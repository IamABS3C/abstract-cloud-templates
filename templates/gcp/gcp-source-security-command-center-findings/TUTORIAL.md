<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Security Command Center findings

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

<walkthrough-info-message>**SCC does not flow through the Log Router.** It publishes to
Pub/Sub through its own NotificationConfig. No sink filter, at any scope, will ever collect
it — which is why this is a separate deployment rather than a checkbox on the log
export.</walkthrough-info-message>

## Before you start

Needs **SCC Premium or Enterprise**, and
`roles/securitycenter.notificationConfigEditor` at the organization.

<!-- abstract:signin -->
## Sign in first

Cloud Shell opened the public templates repository in a **temporary** session. Google gives a repository it does not own none of your credentials, and deletes the session's files when it ends. Sign in, then give the scripts and Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```
<!-- /abstract:signin -->

<!-- abstract:check -->
## Check first

Read-only: nothing changes. The estate audit lists your organization, folders, projects, and the log sinks and topics you already have. Script steps 1 and 2 of the guided setup record your scope and check the rights the sink needs; script step 3 checks the logging project, and the organization policy that can block the service-account key.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/audit-gcp-estate.sh
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
```

If a permission row shows ✗, find the person who holds that role before you go on.

The guided setup saves your answers (organization, scope, logging project, topic, subscription). Load them for the commands on this page:

```bash
source ~/.abstract-gcp-setup.env
```
<!-- /abstract:check -->

## Reuse Abstract's existing identity

If you already deployed `gcp-source-audit-logs-organization`, take the service-account email from its output
rather than making a second identity to rotate:

```bash
cd ../gcp-source-audit-logs-organization
terraform output -json abstract_onboarding | jq -r .service_account_email
cd ../gcp-source-security-command-center-findings
```

`-json | jq`, not `-raw`: **`-raw` errors on an object output.**

Set it as `subscriber_service_account_email` in terraform.tfvars, for example
`abstract-pubsub-reader@YOUR_LOG_PROJECT.iam.gserviceaccount.com`.

Better still, skip the copy entirely — set `remote_state_bucket` and it is read from
`gcp-source-audit-logs-organization`'s state:

```hcl
remote_state_bucket = "acme-abstract-tfstate"
remote_state_prefix = "01-organization"  # its state key keeps the original folder name
```

## Decide the filter

The default is **active, unmuted** findings:

```
state="ACTIVE" AND NOT mute="MUTED"
```

On a mature SCC deployment muted and resolved findings are the bulk of the volume and
none of the signal. Widen this deliberately, not by default.

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

```bash
gcloud scc notifications list --organization="$ORG_ID"
gcloud pubsub subscriptions describe abstract-audit-logs-sub-scc --project="$LOG_PROJECT"
```

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Findings arrive on their **own** topic and subscription. They are a different shape from
audit logs, so configure them as a separate source in Abstract rather than expecting the
audit-log parser to handle them.

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, if this piece feeds one. Then, with the same `backend.tf`:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-security-command-center-findings"
terraform destroy
```
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Deploy with Terraform

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-security-command-center-findings"
source ~/.abstract-gcp-setup.env 2>/dev/null   # the guided setup's saved answers, if you ran it
echo "Logging project: ${LOG_PROJECT:?not set: run export LOG_PROJECT=<your-logging-project-id> first}"
export STATE_PROJECT="${STATE_PROJECT:-$LOG_PROJECT}" STATE_BUCKET="$LOG_PROJECT-abstract-tfstate"
gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$STATE_BUCKET" --project="$STATE_PROJECT" --location=US --uniform-bucket-level-access
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
sed "s/acme-abstract-tfstate/$STATE_BUCKET/" backend.tf.example > backend.tf
```

**2. Fill in your values.** Every value is explained in the file and in this template's README:

```bash
cp terraform.tfvars.example terraform.tfvars
cloudshell edit terraform.tfvars
```

**3. Preview, then apply exactly what you previewed:**

```bash
terraform init
terraform plan -out=abstract.tfplan
terraform apply abstract.tfplan
```

**To remove it later**, run `terraform destroy` in this folder with the same `backend.tf`.
<!-- /abstract:terraform -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
