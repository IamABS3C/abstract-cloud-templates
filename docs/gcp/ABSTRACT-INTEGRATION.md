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

## Security Command Center — findings

**Not collected by Abstract yet.** Abstract's Google Cloud integration keeps only Cloud Audit Logs, which
Security Command Center findings are not, so deploying this template costs money in Google Cloud and adds
nothing in Abstract today.

**Its own topic and subscription**, because findings are a different shape from audit logs.

Terraform path only (this template has no guided step). Go to the template's folder:

```bash
cd templates/gcp/gcp-source-security-command-center-findings
```

Print its values (read-only):

```bash
terraform output
```

Configure as a **separate source** in Abstract. Do not expect the audit-log parser to handle
the finding shape: the managed **GCP Pub/Sub Source** parser drops every message that is not a
Cloud Audit Log, after counting it as collected. Findings are collected and never stored.

---

## Asset inventory — resource and IAM-policy changes

**Not collected by Abstract yet.** Abstract's Google Cloud integration keeps only Cloud Audit Logs, which
asset and IAM-policy change records are not, so deploying this template costs money in Google Cloud and adds
nothing in Abstract today. The guided setup no longer offers it.

Terraform path only (this template has no guided step). Go to the template's folder:

```bash
cd templates/gcp/gcp-source-asset-and-iam-changes
```

Print its values (read-only):

```bash
terraform output -json abstract_onboarding
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
