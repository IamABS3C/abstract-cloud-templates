<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Security Command Center findings

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

<walkthrough-info-message>**SCC does not flow through the Log Router.** It publishes to
Pub/Sub through its own NotificationConfig. No sink filter, at any scope, will ever collect
it — which is why this is a separate deployment rather than a checkbox on the log
export.</walkthrough-info-message>

Needs **SCC Premium or Enterprise**, and
`roles/securitycenter.notificationConfigEditor` at the organization.

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Step 1 — Reuse Abstract's existing identity

If you already deployed `gcp-source-audit-logs-organization`, take the service-account email from its output
rather than making a second identity to rotate:

```bash
cd ../gcp-source-audit-logs-organization
terraform output -json abstract_onboarding | jq -r .service_account_email
cd ../gcp-source-security-command-center-findings
```

`-json | jq`, not `-raw`: **`-raw` errors on an object output.**

Better still, skip the copy entirely — set `remote_state_bucket` and it is read from
`gcp-source-audit-logs-organization`'s state:

```hcl
remote_state_bucket = "acme-abstract-tfstate"
remote_state_prefix = "01-organization"  # its state key keeps the original folder name
```

## Step 2 — Decide the filter

The default is **active, unmuted** findings:

```
state="ACTIVE" AND NOT mute="MUTED"
```

On a mature SCC deployment muted and resolved findings are the bulk of the volume and
none of the signal. Widen this deliberately, not by default.

## Step 3 — Plan, then apply

```bash
cat > terraform.tfvars <<EOF
org_id                           = "YOUR_ORG_ID"
log_project                      = "YOUR_LOG_PROJECT"
subscriber_service_account_email = "abstract-pubsub-reader@YOUR_LOG_PROJECT.iam.gserviceaccount.com"
EOF
terraform init && terraform plan
```

## Step 4 — Verify

```bash
gcloud scc notifications list --organization=YOUR_ORG_ID
gcloud pubsub subscriptions describe abstract-audit-logs-sub-scc --project=YOUR_LOG_PROJECT
```

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Findings arrive on their **own** topic and subscription. They are a different shape from
audit logs, so configure them as a separate source in Abstract rather than expecting the
audit-log parser to handle them.

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
