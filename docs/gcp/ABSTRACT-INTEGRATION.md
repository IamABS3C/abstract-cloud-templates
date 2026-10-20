<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../brand/abstract-logo-white.svg">
  <img alt="Abstract Security" src="../brand/abstract-logo-black.svg" width="180">
</picture>

# Configuring the integration in Abstract

The GCP side creates the pipeline. This is what you type into Abstract.

---

## GCP Pub/Sub — audit logs

**Integration:** `default.google_cloud_pub_sub` · Event Source · **PULL**

Three fields. With the guided setup, script step 10 prints all three and the line that downloads the key. Run it
from the top folder of the templates repository:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
```

Terraform path only (you deployed `gcp-source-audit-logs-organization` with Terraform, so its state has the values).
Go to the template's folder:

```bash
cd templates/gcp/gcp-source-audit-logs-organization
```

Print the three values (read-only):

```bash
terraform output -json abstract_onboarding
```

| Field | Value | The mistake people make |
|---|---|---|
| **Project ID** | the project holding the **subscription** | **Not** the projects generating logs. With an org sink the logs come from dozens of projects while the subscription lives in one. **This is the field filled in wrong most often** |
| **Subscription ID** | the **short name** only | Not `projects/…/subscriptions/…`. Pasting the full path produces an auth-shaped error, not a validation one |
| **Credentials** | service-account JSON key, **under 1 MB** | Must be the key for the SA that holds `roles/pubsub.subscriber` **on the subscription** |

To print the short name (read-only; LOG_PROJECT is your logging project's ID, from the answers file
`~/.abstract-gcp-setup.env`):

```bash
gcloud pubsub subscriptions list --project="$LOG_PROJECT" --format='value(name.basename())'
```

### Creating the key

With the guided setup, script step 5 makes the key and records its ID, so step 10 never offers it for deletion.

Terraform path only: the key is deliberately **not** created by Terraform, because it would put a private key in
the state. Make it with gcloud, once, in the template's folder. Keep the reader account's email in SA:

```bash
SA="$(terraform output -json abstract_onboarding | jq -r .service_account_email)"
```

Make a folder for the key outside the repository, readable only by you:

```bash
mkdir -m 700 -p ~/abstract-keys
```

Create the key, as a file only you can read. This adds one key to the reader account in your logging project;
anyone holding the file can read the subscription. The last command on this page revokes it:

```bash
(umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-pubsub-key.json --iam-account="$SA" --project="$LOG_PROJECT")
```

In Cloud Shell, download it to the computer you use for Abstract:

```bash
cloudshell download ~/abstract-keys/abstract-pubsub-key.json
```

Upload it to Abstract. Once Abstract has saved the integration, delete every copy: the downloaded
file, and this one:

```bash
rm -f ~/abstract-keys/abstract-pubsub-key.json
```

To revoke the key later (a rotation, or removing the integration), list the reader account's keys (read-only).
The one Abstract holds has the ID in the `private_key_id` of the file you uploaded:

```bash
gcloud iam service-accounts keys list --iam-account="$SA" --project="$LOG_PROJECT" --managed-by=user
```

Then delete it, replacing KEY_ID with that ID. Abstract can no longer read from that moment; nothing else changes:

```bash
gcloud iam service-accounts keys delete KEY_ID --iam-account="$SA" --project="$LOG_PROJECT"
```

> **Abstract PULLS.** It needs `roles/pubsub.subscriber` on the **subscription** — not
> publisher, not project-wide. An existing internal document says publisher, and following
> it gives you `PERMISSION_DENIED` with no obvious cause.

### Verify before you blame the integration

Script step 9 writes a harmless admin event inside your scope (it creates and deletes a log-based metric) and
waits for it on a throwaway subscription on the same topic, never on Abstract's, and deletes that subscription
afterwards. It reads your scope from the answers file script step 1 saved. From the top folder of the repository:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
```

Never pull from `abstract-audit-logs-sub` yourself: Abstract reads that subscription, and an acknowledged pull there deletes events before Abstract sees them.

Events here but not in Abstract → credentials or config. Nothing here → the cloud side, and
the integration is not the problem.

---

## Google Workspace — identity

**Integration:** `default.google_workspace` · Event Source · **PULL**

With the guided setup, script step 10 prints the values (script step 7 made the key). Terraform path only: go to
the template's folder:

```bash
cd templates/gcp/gcp-source-google-workspace-logs
```

Print the values (read-only):

```bash
terraform output -json workspace_onboarding
```

| Field | Value |
|---|---|
| **Admin Email** | a Workspace **admin** the service account impersonates |
| **Credentials** | the delegated SA's JSON key, under 1 MB |
| **Application Name** | multi-select; **each is polled on its own checkpoint** |

`admin_email` is not cosmetic — delegation impersonates a real user, and without a valid
subject the Reports API returns **401**, not an empty result.

**Before this works** a Workspace **super admin** must grant domain-wide delegation in
`admin.google.com`. A GCP Owner cannot. See [WORKSPACE.md](WORKSPACE.md).

### Which applications

Start with `login`, `saml`, `token`, `user_accounts`, `context_aware_access`, `admin`,
`groups`, `groups_enterprise`, `rules` — the module's default.

Add `gmail`/`drive` only after measuring; they dwarf everything else combined.

---

## Network logs, asset changes and Security Command Center findings

Each of these has its own topic and subscription, and each subscription gets **its own GCP Pub/Sub Source
configuration**: one configuration per subscription, never a second subscription on the audit-log configuration.
There is no separate integration for findings or assets; it is the same GCP Pub/Sub Source.

Abstract keeps them only when the configuration runs the **extended GCP Pub/Sub parser**. The managed parser as
shipped keeps Cloud Audit Logs only. Measured on an Abstract test tenant on 19 October 2026, with the managed parser:
9,639 network log entries pulled, 0 stored; Security Command Center findings, 0 stored; asset changes, 0 stored
(and 2 parsing errors, from the feed's plain-text greeting).

The extended parser is YAML only: a dispatcher that recognises each message and hands it to one sub-parser, the
managed audit pipeline unchanged, and network, asset and Security Command Center sub-parsers built from messages
captured in a test organization. Anything else is still dropped. Audit logs come out the same as on the managed
parser: compared with a configuration left on it, the 7 event types both stored had identical field sets.
**It is not in the managed integration yet. Until it is, Abstract applies it to the configuration's parsers**:
ask for it when you add the configuration.

| Source | Template | Subscription | Read with | Stored as |
|---|---|---|---|---|
| Network logs | `gcp-source-network-threat-logs` | `abstract-network-threats-sub` | its own account, `abstract-net-threat-reader` | `gcp.vpc_flows`, `gcp.firewall`, `gcp.nat_flows`, `gcp.dns_queries` |
| Asset changes | `gcp-source-asset-and-iam-changes` | `abstract-asset-changes-sub` | the audit-log reader account | `gcp.asset_inventory`, `action` `iam_policy_grant`, `iam_policy_revoke` or `iam_policy_change` |
| Security Command Center findings | `gcp-source-security-command-center-findings` | `abstract-audit-logs-sub-scc` | the audit-log reader account | `gcp.scc_findings`, as `type` `event` |

Terraform path only: each is deployed with Terraform from its template's tutorial, which ends with **Connect
Abstract**. In the template's folder, print the values (read-only):

```bash
terraform output -json abstract_onboarding
```

Then add the configuration with the same three fields as the audit logs: **Project ID** (your logging project),
**Subscription ID** (the short name in the table) and **Credentials** (a key of the account in the table).

### Network logs

Kept: firewall rule logs, Cloud DNS query logs, VPC Flow Logs and Cloud NAT logs. Not kept, even by the extended
parser: load balancer request logs (where Cloud Armor's decisions are) and Cloud IDS threat logs, so leave them out
of `log_categories` and `platform_log_filters` unless something else reads the topic. Each log is turned on where
the resource lives, by the team that owns it, in the project that owns the network (the host project with Shared
VPC): [FILTERS.md, Where each source is turned on](FILTERS.md#where-each-source-is-turned-on).

### Asset changes

The asset sub-parser is
[`parsers/cloud-asset-inventory.yml`](../../templates/gcp/gcp-source-asset-and-iam-changes/parsers/cloud-asset-inventory.yml).
It diffs the policy before and after, so each change arrives as `action` `iam_policy_grant`,
`iam_policy_revoke` or `iam_policy_change`, with the roles in `user.target.roles`, the members in
`related.user` (the same fields the audit-log parser uses), and each role and member pair in
`ext.iam_granted` / `ext.iam_revoked`. The feed sends one plain-text "You have successfully configured real time
feed" message when it is created or updated; the extended parser drops it.

Worth explaining to a customer, because it sounds redundant and is not: `admin_activity`
says **who called which API**; this says **what the policy now is, and what it was before.**
Three API paths to the same IAM binding give three audit entries and one identical diff.

The feed is set on the organization, and feed names are unique there: a second deployment in the same organization
sets its own `feed_id`.

### Security Command Center findings

Stored as `gcp.scc_findings`, Event Threat Detection findings included: 76 in the first hour of the test. They are
stored as `type` `event`, because a parser record marked `type` `finding` is collected and never stored.

Before you deploy, Security Command Center Standard or Premium must be active at the organization (tested with
Premium): an organization still on legacy Security Command Center gets 400 "Security Command Center Legacy has
been permanently disabled". Whoever applies needs `roles/securitycenter.notificationConfigEditor` at the
organization. Right after activation, the create can answer 400 "Precondition check failed" and still create the
notification config: list the configs, and import it into the Terraform state if it is there (the template's
tutorial has the command).

---

## Bucket notifications — logs already in a bucket

Terraform path only (this template has no guided step). Go to the template's folder:

```bash
cd templates/gcp/gcp-source-cloud-storage-bucket-logs
```

Print its values (read-only):

```bash
terraform output -json abstract_onboarding
```

Same three fields as the Pub/Sub source. The difference is that Abstract must also **fetch
each object** — so the service account needs `roles/storage.objectViewer` on the bucket as
well as `subscriber` on the subscription. Both are granted by the module.

---

## One identity, or several?

The asset and Security Command Center templates **reuse** the service account
`gcp-source-audit-logs-organization` creates, and you should keep that:

- fewer keys to rotate
- one grant to audit
- one thing to revoke if it leaks

Pass `remote_state_bucket` and the identity is read from state rather than retyped. The network and bucket
templates make a reader account of their own (the network one is `abstract-net-threat-reader`).

---

## Troubleshooting, in the order that localises fastest

| Symptom | Almost always |
|---|---|
| `PERMISSION_DENIED` on pull | Granted `publisher` instead of `subscriber`, or granted at project scope instead of on the subscription |
| Zero events, sink healthy | Filter references `data_access` and Data Access logging is not enabled. **Two switches** — see [SETUP.md](SETUP.md) |
| Zero events immediately after deploy | The sink is not live when Terraform returns. Wait 5 minutes and fire a **fresh** event |
| Worked, then stopped after ~a month | Subscription expiry. Everything here sets `expiration_policy` to never — check it was not recreated by hand |
| Events arrive, fields empty | Check the integration version before anything else |
| Workspace returns 401 | Delegation not propagated, or `admin_email` is not actually an admin |
| Notifications with no content | `objectViewer` missing on the bucket. The notification is a **pointer**, not the data |
