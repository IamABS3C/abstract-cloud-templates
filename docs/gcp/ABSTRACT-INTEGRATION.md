<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../brand/abstract-logo-white.svg">
  <img alt="Abstract Security" src="../brand/abstract-logo-black.svg" width="180">
</picture>

# Configuring the integration in Abstract

The GCP side creates the pipeline. This is what you type into Abstract.

---

## GCP Pub/Sub — audit logs

**Integration:** `default.google_cloud_pub_sub` · Event Source · **PULL**

Three fields. Get all of them from one command:

```bash
cd templates/gcp/gcp-source-audit-logs-organization
terraform output -json abstract_onboarding
```

| Field | Value | The mistake people make |
|---|---|---|
| **Project ID** | the project holding the **subscription** | **Not** the projects generating logs. With an org sink the logs come from dozens of projects while the subscription lives in one. **This is the field filled in wrong most often** |
| **Subscription ID** | the **short name** only | Not `projects/…/subscriptions/…`. Pasting the full path produces an auth-shaped error, not a validation one |
| **Credentials** | service-account JSON key, **under 1 MB** | Must be the key for the SA that holds `roles/pubsub.subscriber` **on the subscription** |

```bash
# The short name, explicitly
gcloud pubsub subscriptions list --project="$LOG_PROJECT" \
  --format='value(name.basename())'
```

### Creating the key

Deliberately **not** created by Terraform — it would put a private key in state, and on the
Cloud Shell path that state is a file in a home directory.

```bash
SA=$(terraform output -json abstract_onboarding | jq -r .service_account_email)
gcloud iam service-accounts keys create abstract-key.json --iam-account="$SA"
# upload to Abstract, then:
rm abstract-key.json
```

> **Abstract PULLS.** It needs `roles/pubsub.subscriber` on the **subscription** — not
> publisher, not project-wide. An existing internal document says publisher, and following
> it gives you `PERMISSION_DENIED` with no obvious cause.

### Verify before you blame the integration

```bash
PROBE=abstract-probe-$(date +%s)
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-audit-logs \
  --project="$LOG_PROJECT" --expiration-period=1d
gcloud pubsub topics create abstract-probe-topic --project="$LOG_PROJECT" --quiet
gcloud pubsub topics delete abstract-probe-topic --project="$LOG_PROJECT" --quiet
sleep 75
gcloud pubsub subscriptions pull "$PROBE" --project="$LOG_PROJECT" --limit=5 --auto-ack
gcloud pubsub subscriptions delete "$PROBE" --project="$LOG_PROJECT" --quiet
```

Never pull from `abstract-audit-logs-sub`: Abstract reads that subscription, and `--auto-ack` there deletes events before Abstract sees them. The probe subscription above is yours and expires in a day.

Events here but not in Abstract → credentials or config. Nothing here → the cloud side, and
the integration is not the problem.

---

## Google Workspace — identity

**Integration:** `default.google_workspace` · Event Source · **PULL**

```bash
cd templates/gcp/gcp-source-google-workspace-logs
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

## Security Command Center — findings

**Its own topic and subscription**, because findings are a different shape from audit logs.

```bash
cd templates/gcp/gcp-source-security-command-center-findings && terraform output
```

Configure as a **separate source** in Abstract. Do not expect the audit-log parser to handle
the finding shape: the managed **GCP Pub/Sub Source** parser drops every message that is not a
Cloud Audit Log, after counting it as collected. Findings are collected and never stored.

---

## Asset inventory — resource and IAM-policy changes

```bash
cd templates/gcp/gcp-source-asset-and-iam-changes && terraform output -json abstract_onboarding
```

Also a separate source, and it needs its own parser. The managed **GCP Pub/Sub Source** parser
drops every message that is not a Cloud Audit Log: the configuration counts asset changes as
collected, and none is stored. Create a GCP Pub/Sub Source configuration on
`abstract-asset-changes-sub`, then replace its parser with
[`parsers/cloud-asset-inventory.yml`](../../templates/gcp/gcp-source-asset-and-iam-changes/parsers/cloud-asset-inventory.yml)
(`PATCH /v3/configurations/{id}/parsers` with `{"parsers": {"default.yml": <file>}, "mapper": null}`).

It diffs the policy before and after, so each change arrives as `action` `iam_policy_grant`,
`iam_policy_revoke` or `iam_policy_change`, with the roles in `user.target.roles`, the members in
`related.user` (the same fields the audit-log parser uses), and each role and member pair in
`ext.iam_granted` / `ext.iam_revoked`. The feed's first message is a plain-text greeting; the
parser drops it.

Worth explaining to a customer, because it sounds redundant and is not: `admin_activity`
says **who called which API**; this says **what the policy now is, and what it was before.**
Three API paths to the same IAM binding give three audit entries and one identical diff.

---

## Bucket notifications — logs already in a bucket

```bash
cd templates/gcp/gcp-source-cloud-storage-bucket-logs && terraform output -json abstract_onboarding
```

Same three fields as the Pub/Sub source. The difference is that Abstract must also **fetch
each object** — so the service account needs `roles/storage.objectViewer` on the bucket as
well as `subscriber` on the subscription. Both are granted by the module.

---

## One identity, or several?

The modules default to **reusing** the service account `gcp-source-audit-logs-organization` creates, and you
should keep that:

- one key to rotate instead of four
- one grant to audit
- one thing to revoke if it leaks

Pass `remote_state_bucket` and the identity is read from state rather than retyped.

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
