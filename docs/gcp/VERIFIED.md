# What has actually been proven, and what has not

This repo uses provenance tiers rather than a blanket claim, because "it validates" and
"it deploys" are different things and blurring them is how customers get surprised.

**Last live runs: 18 to 20 October 2026, against a test Google Cloud organization and an Abstract test tenant**
(the section below). The sections after it are the earlier runs, kept for their evidence.

---

## Proven 18 to 20 October 2026: four methods, and what Abstract stored

Every method below reached the topic, and Abstract stored and parsed the audit logs it sent. Which projects the
events came from was read from each event's project ID in Abstract.

| Method | Scope | What happened |
|---|---|---|
| Guided script, option A: one organization sink filtered to the ticked projects | two projects | Script step 9's test event arrived; Abstract stored audit logs only from the two ticked projects |
| Guided script, option B: one sink in each ticked project | two projects | The test event arrived in both projects; Abstract stored logs from both |
| Local Terraform, `gcp-source-audit-logs-folder` | one folder | Abstract stored logs only from the project in that folder |
| Infrastructure Manager, `gcp-source-audit-logs-folder` from the public repository at a release tag | one folder | Preview first: 11 to create, 0 to destroy. Then apply: deployment `ACTIVE`. Abstract stored the audit logs. The first full run of this path. The service account's roles were granted with `--grant serviceAccount:EMAIL --for infra-manager-sa` |

The read-only `--check` of the two script setups passed 42 and 60 checks. Script step 6 turned on the IAM and
identity logs by default; with option A it set the audit settings in each ticked project. Script step 7 (Google
Workspace) reported "delegation works: the Reports API answered" once a super admin added the delegation, and
Abstract's Google Workspace integration stored and parsed the Workspace events.

### What Abstract stored, by parser

| Feed | Managed GCP Pub/Sub Source parser, as shipped | Extended GCP Pub/Sub parser |
|---|---|---|
| Cloud Audit Logs | stored | stored, the same: 7 event types stored by both had identical field sets |
| Network logs (VPC Flow, firewall, Cloud NAT, Cloud DNS) | 9,639 pulled, 0 stored | stored as `gcp.vpc_flows`, `gcp.firewall`, `gcp.nat_flows`, `gcp.dns_queries` |
| Cloud Asset changes | 0 stored, 2 parsing errors (the feed's plain-text greeting) | stored; the greeting dropped |
| Security Command Center findings | 0 stored | stored as `gcp.scc_findings`: 76 in the first hour, Event Threat Detection findings included |

The extended parser is YAML only, a dispatcher with audit, network, asset and Security Command Center
sub-parsers, and was applied to each configuration's parsers: it is not in the managed integration yet.

In this run the asset sub-parser of the day stored asset changes as `gcp.asset_changes`. It has since been replaced
by this repository's policy-diffing parser,
[`parsers/cloud-asset-inventory.yml`](../../templates/gcp/gcp-source-asset-and-iam-changes/parsers/cloud-asset-inventory.yml),
which stores them as `gcp.asset_inventory` with `action` `iam_policy_grant`, `iam_policy_revoke` or
`iam_policy_change`. Measured on the tenant on 20 October: one role granted and then removed arrived as two
events, `iam_policy_grant` and `iam_policy_revoke`, each with the role in `user.target.roles` and the member in
`related.user`.

### Found live, and fixed

| Found | Fix |
|---|---|
| A sink whose filter spans several lines (the Terraform module writes them) was read as several sinks | The script reads existing sinks as JSON: one sink, whatever its filter |
| The subscriber grant right after creating a service account failed silently: a new account is not grantable for a few seconds | The script retries the grant |
| The use-existing questions for topic, subscription and account had no default | Enter creates the new one |
| `gcp-source-asset-and-iam-changes`: the first apply failed with "does not exist", granting the Cloud Asset service agent | The template waits 60 seconds for the agent before granting it |
| `gcp-source-asset-and-iam-changes`: a second deployment in one organization failed with 409, because feed names are unique per organization | A `feed_id` variable, default `abstract-asset-feed` |
| `gcp-source-security-command-center-findings`: 403 creating the notification config | Whoever applies needs `roles/securitycenter.notificationConfigEditor` at the organization; the template says so |
| `gcp-source-security-command-center-findings`: 400 "Security Command Center Legacy has been permanently disabled" | Security Command Center Standard or Premium must be active at the organization first (tested with Premium) |
| `gcp-source-security-command-center-findings`: right after activation, 400 "Precondition check failed", yet the config was created | List the configs and import it into the state; the next plan shows no changes |

---

## 🟢 Deployed — executed against a live organization

| | Evidence |
|---|---|
| `templates/gcp/gcp-source-audit-logs-organization` **applies cleanly** | `Plan: 9 to add` → applied, no errors |
| Aggregated sink at org scope | `includeChildren=True`, destination is the topic |
| Writer identity granted publisher | `roles/pubsub.publisher: service-org-<ORG>@gcp-sa-logging` |
| Subscription config | 60 s ack, `604800s` (7-day) retention, expiration never |
| No sink errors | `logging.googleapis.com/sink_error` empty throughout |
| **Audit events delivered end to end** | 3 messages pulled, with `methodName`, `principalEmail`, `resourceName`, `callerIp` |
| `tools/gcp-guided-setup/preflight.sh` | Run against the live org; found a real blocker and was verified against the org IAM policy independently |
| **Works with billing DISABLED** | The whole path deployed and delivered on a project with `billingEnabled=False` |
| `templates/gcp/gcp-foundation-data-access-audit-logs` **applies** | 3 scoped services enabled at org scope; preflight reads them back |
| The **authoritative-overwrite guard** fires against real state | With 3 configs present, `allServices` is refused |
| `prevent_destroy` **actually refuses** | `terraform destroy` rejected on sink and subscription; everything survived |
| `templates/gcp/gcp-monitoring-pipeline-health-alerts` **applies** | 3 alert policies created, enabled, wired to a channel, documentation attached |
| The stall alert's **filter matches live data** | Policy filter returned 1 series at **9,391 s** against a 3,600 s threshold |

## 🟡 Validated — compiler and linters, never executed

Everything else. All 13 roots and 9 modules pass `terraform validate` (Terraform 1.15.8) at the declared provider floor
and at latest; `tflint` (Google ruleset), `trivy config` and `shellcheck` are clean; 24
guard tests pass with positive controls.

That proves structure. It does not prove runtime.

| Not yet executed | Why it matters |
|---|---|
| `gcp-archive-log-bucket`, `gcp-source-cloud-storage-bucket-logs` | Not applied |
| `gcp-source-billing-account-logs` | Validated only; needs `billing.admin` on the billing account. Billing-account audit logs are AuditLog records, so the managed parser keeps them |
| Load balancer (Cloud Armor) and Cloud IDS logs from `gcp-source-network-threat-logs` | No sub-parser handles them: the extended parser's dispatcher drops what it does not recognise (read from its YAML, not measured) |

Since October, `gcp-source-network-threat-logs`, `gcp-source-asset-and-iam-changes`,
`gcp-source-security-command-center-findings` and the Workspace path have run against a live organization, and
Infrastructure Manager too (the section above).

## Infrastructure Manager requires billing

`gcloud services enable config.googleapis.com cloudbuild.googleapis.com` returned:

```
reason: UREQ_PROJECT_BILLING_NOT_OPEN
```

Neither API enabled. Infra Manager runs Terraform on **Cloud Build**, and Cloud Build
requires an open billing account. In August the test organization's billing account was in `open:
False` state across all five projects, so the Infra Manager path could not be exercised. With open billing it
ran in October (the section above).

**This is a genuinely useful finding rather than just a gap.** It means:

| | Needs billing |
|---|---|
| Cloud Shell button / local Terraform | **No** — proven working without it |
| Infrastructure Manager | **Yes** |

So for a sandbox, a trial, or an unfunded project, recommend Cloud Shell. See
[DEPLOY-INFRA-MANAGER.md](DEPLOY-INFRA-MANAGER.md).

---

## Behaviours found only by running it

Neither of these is in Google's documentation in a form you would find before hitting them.

### Data Access needs TWO switches, and one alone does nothing

Google documents one exception this run did not exercise: BigQuery writes its Data Access logs by
default, so BigQuery needs only the routing switch.

Enabling Data Access in the IAM audit config makes the log **generated**. It does not make
it **routed** — the sink filter must also include it.

Verified: after enabling Data Access on three services, the deployed sink's filter
contained no `data_access` clause, so those logs were generated (and billed) and reached
nothing. Flip only the filter instead and it matches **nothing, with no error**.

Keep the service lists identical on both sides.

### The stall alert fires before Abstract is connected — correctly

Nothing consumes the subscription until Abstract is wired up, so
`oldest_unacked_message_age` climbs. Measured **9,391 seconds** within hours of standing the
pipeline up, against a 3,600 s threshold.

That is the alert working, not a false positive. Connect Abstract in the same session, or
expect it.

### `gcloud beta` may not be installed

`gcloud beta monitoring channels create` prompts to install the beta component, which fails
outright in a non-interactive shell — including CI and some Cloud Shell configurations. The
Monitoring REST API needs no component and is in the tutorial as the fallback.

### A sink is not live when Terraform returns

| Event written | Delivered? |
|---|---|
| ~30 s after `CreateSink` | **No — never** |
| ~2 min after | **No — never** |
| ~3 min after | Yes, ~60 s end to end |

Routing is evaluated at **write time**, so events during the propagation window were never
routed and cannot be recovered. **This is the most likely reason someone concludes a
working pipeline is broken** — they apply, test immediately, see nothing, and start pulling
it apart.

Wait five minutes, then fire a **fresh** event.

### `pull` without `--auto-ack` makes the next pull look empty

The first pull delivers but does not acknowledge, so the message sits inside the 60-second
ack deadline and a second pull returns nothing. That reads as "it stopped working."

Use `--auto-ack` only on your own probe subscription (`abstract-probe-*`), never on the subscription Abstract reads: there it deletes events before Abstract sees them.

---

## Bugs the live run found that no amount of local validation would have

All three were in `tools/gcp-guided-setup/preflight.sh`, all fixed.

1. **`gcloud config get-value account` is unset under token auth** — reported "not
   authenticated" while fully authenticated. Cloud Shell service accounts behave the same
   way, so this would have hit customers.
2. **The org-role check was a Python `SyntaxError`** whose output was swallowed, so the
   *"you do NOT hold `logging.configWriter`"* branch fired **unconditionally**. A false
   blocker that would have stopped valid deployments.
3. **GCP's built-in `_Required`/`_Default` sinks were counted as existing exports**, warning
   about duplication that was not there — noise that teaches people to ignore the check.

---

## Proven 2026-08-27: Abstract pulls from the subscription

The largest gap on this list is now closed. An Abstract configuration was created against
a live tenant and **pulled real events from the org sink's Pub/Sub subscription**.

| Measure | Result |
|---|---|
| Events collected | **90** |
| Bytes ingested | **205,537** |
| Audit events generated to drive it | 63, across 5 services |
| Integration | `default.google_cloud_pub_sub.0_0_11` |

**`pubsub.subscriptions.get` is settled:** `roles/pubsub.subscriber` alone is sufficient.
No additional grant was needed.

**The credential field shape.** `credentials` is a file-type field. It takes a nested
object — not a raw string, not base64, and not a parsed object:

```json
"credentials": { "content": "<the service-account JSON, as a string>", "name": "key.json" }
```

**Always call `/validate` before `create`.** `POST /v2/configurations/validate` reports
precisely which field is wrong, so you can correct the payload before creating anything.

### Confirming events landed, and which query surface to use

Both integrations parse into ACS correctly. Confirmed by retrieving actual documents.

**GCP Audit Logs** — 25 populated fields:

```
vendor          GCP                                     <-- not "google"
product         GCP Audit Logs
action          google.iam.admin.v1.CreateServiceAccountKey
user_name       admin@example.com
user_id         user:admin@example.com
source_address  203.0.113.10
@timestamp      2026-08-27T06:57:38.878Z
```

**Google Workspace** — 18 populated fields:

```
vendor          Google
product         Google Workspace Logs
action          AUTHORIZE_API_CLIENT_ACCESS
event           {category: configuration, code: DOMAIN_SETTINGS...}
cloud           {provider: Google}
organization    {id: C01abcdef}
data_stream     {dataset: Google Workspace Audit Logs (...)}
user_name       admin@example.com
source_ipv4     203.0.113.10
```

**Use `POST /v2/streamviewer/raw-search` with `query_string` to confirm events landed.**
It is the surface that returns whole documents, which is what you want when verifying a
new deployment:

| Surface | Behaviour |
|---|---|
| `POST /v2/streamviewer/raw-search` + `query_string` | **Correct.** The only surface that returned the documents |
| `POST /v1/streamviewer/field-analytics` | Returns the **top values** per field. A low-volume new source will not appear beside a high-volume existing one — use raw-search instead when verifying |

**Three things to know about `raw-search`:**

1. **Fields come back nested, not flat.** `event.category` as a top-level key is `null`;
   the value lives in `event: {category: ...}`. A flat-key check reports a populated
   document as empty.
2. **Leading wildcards are rejected**, not ignored:
   `query_string contains a leading-wildcard or regex token ('product:*workspace*');
   not allowed (full-scan risk)`. Trailing wildcards (`vendor:google*`) are fine.
3. **`vendor` is `GCP`, not `google`.** A query of `vendor:google AND NOT
   product:"Google Workspace Logs"` returns **0** and looks like a parse failure. It is a
   wrong-value query. Confirm the actual `vendor` string before concluding absence.

> When verifying a brand-new source, a free-text search for your project ID is the
> quickest way to confirm documents arrived.


## Audit-log generation: what actually produces an event

Established by direct probe, not inference. This governs any attempt to generate test
telemetry.

| Call outcome | Audit entry written? |
|---|---|
| Succeeds | **Yes** |
| Reaches the service and fails on billing (`FAILED_PRECONDITION`) | **Yes** — proven via `cloudkms.CreateKeyRing`, `logging.CreateSink` |
| Reaches the service and fails on permission (`PERMISSION_DENIED`) | **Yes** |
| Rejected because the API is not enabled (`SERVICE_DISABLED`) | **No** — nothing is logged |
| Denied against a resource in another organization | **No** — logged in *that* org, not yours |

**The practical rule: enabling an API is the unlock.** Once enabled, a call audits even
when it fails. But an API that *requires billing to enable* cannot be enabled at all —
`compute`, `dns`, `container` and `secretmanager` all reject enablement with
`FAILED_PRECONDITION: Billing account...`.

### Four log types cannot exist without running VMs

Not a bug, and not a filter error. If these come back empty, this is why:

- **VPC Flow Logs** — requires VMs generating traffic
- **Firewall hit logs** (`compute.googleapis.com/firewall`) — requires a rule with
  `--enable-logging` *and traffic hitting it*
- **DNS query logs** (`dns.googleapis.com/dns_queries`) — requires a DNS policy *and*
  resolvers issuing queries
- **GKE control plane** — requires a cluster

The catalog clauses for these are correct. They will simply never fire in an environment
with no compute.

---

## Workspace: verified 2026-08-27

- **The Reports API exposes 41 `applicationName` streams**, not the 23 an earlier revision
  of `WORKSPACE.md` claimed. Source of truth is the discovery document:
  `curl -s 'https://admin.googleapis.com/$discovery/rest?version=reports_v1'`
- **Scopes do not overlap with GCP.** A token carrying
  `https://www.googleapis.com/auth/cloud-platform` gets **403 insufficient authentication
  scopes** on both the Reports API and Alert Center. Reports needs
  `admin.reports.audit.readonly`; Alert Center needs `apps.alerts`. This is why Workspace
  **must** be a separate integration — its data never transits Cloud Logging or Pub/Sub
- **Directory API is the exception** — it returned **200** under `cloud-platform`
- **Alert Center** exposes 7 methods: `list`, `get`, `getMetadata`, `batchDelete`,
  `batchUndelete`, `delete`, `undelete`
- **A service account's `oauth2ClientId` equals its `uniqueId`** — that is the value
  Workspace domain-wide delegation asks for
- **Three parameters** configure it: `admin_email`, `credentials`, `application_name`
- **Domain-wide delegation has no API.** It is configured only in the Workspace Admin
  console, at **admin.google.com → Security → Access and data control → API controls →
  Domain-wide delegation**. Plan for a manual step by a Workspace super admin

---

## The role list and the checks, run against a live organization (2026-10-13)

- `python3 tools/gcp-guided-setup/permissions.py verify`: 16 of 16 roles exist with the title written in
  `permissions.json` and include every permission listed for them. Its first run caught two wrong rows: Google titles
  the Infrastructure Manager roles "Cloud Infrastructure Manager Admin" and "... Agent", and the agent role holds the
  deployment-state permissions (`config.deployments.getState`, `updateState`, `getLock`), not `config.deployments.get`.
- `--grant <own email> --check` at the organization: every role answered by Google's testIamPermissions, 11 passed.
  `--step 2 --check`: the full role check ran inside step 2, 16 passed.
- `--grant <own email> --for infra-manager --check`: 4 passed. On a service account that does not exist, Google
  answers 404 "Unknown service account", which the script reports as could not check, never as held.
- The proof step's pull, `--format="value(message.data.decode(base64))" | grep -c`, counted the test event on the
  first pull. The same event pulled with `--format=json` and grepped undecoded counted 0: message data is base64.

## The console click paths, read from the live console (2026-10-13)

The step-by-step guide ([STEP-BY-STEP.md](STEP-BY-STEP.md)) and the app give a console click path for every step. Each
label in them was read from the live Google Cloud console's own accessibility tree on 13 October 2026, in a test
organization, by opening each form and filling it in without ever pressing the final Create, Save or Enable. The
screenshots in the app were taken the same way. Before each capture the page's text was rewritten in the browser so
the organization, its domain, project IDs, account emails and numeric IDs read as example values; every image was
then checked by eye. No form was submitted; afterwards the organization's sinks were listed (only the existing one) and the project ID typed into the new-project form was looked up (it does not exist).

Where the live console differed from Google's documentation, the guide follows the console:

| Step | Google's documentation says | The console showed |
|---|---|---|
| Sink destination, organization sink | choose **Pub/Sub topic** and enter the path | **Cloud Pub/Sub topic**, then **Use a Cloud Pub/Sub topic in a project**, which switches the service to **Other resource** with a template path in **Sink destination** |
| Sink, include children | (not stated) | the default is **Include only logs ingested by this organization**, which misses every project; **Include logs ingested by this organization and all child resources** must be chosen |
| Sink panels | **Choose logs to exclude from the sink** | **Choose logs to filter out of sink (optional)** |
| Create subscription, topic field | **Pub/Sub topic** | **Select a Cloud Pub/Sub topic** |
| Grant a role | **Grant Access** | **Grant access**, a panel with **New principals** and **Role** |
| Audit logs | **Set Default Configuration**, **Log Types** tab | **Set default configuration**, **Permission types** tab with **Admin read**, **Data read**, **Data write** |
| Policy Troubleshooter | **Add Another Pair** | **Add another pair**, up to five pairs a query |
| Organization policies | (not stated) | an **Enforcement state** column reading Inactive or Active |

Not captured: the Infrastructure Manager create form (on 13 October the test project had no open billing account,
so the API could not be turned on there), the alerting policy form, and the Pub/Sub **Messages** tab, which would show real audit
events.

## To raise the tier further

One apply each, in a project with billing:

1. **One deployment through a GCS backend**, recorded here, so the documented practice has been done once
2. `gcp-archive-log-bucket` and `gcp-source-cloud-storage-bucket-logs`
3. The extended GCP Pub/Sub parser with the policy-diffing asset sub-parser, measured on the tenant
