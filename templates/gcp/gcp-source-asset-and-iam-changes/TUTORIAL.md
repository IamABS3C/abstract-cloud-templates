<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Cloud Asset Inventory — resource and IAM-policy changes

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

<walkthrough-info-message>**The third thing a log sink cannot carry.** Cloud Asset
Inventory publishes to Pub/Sub through its own feed. Not a sink, not a filter — no
widening of `log_categories` reaches it.</walkthrough-info-message>

Deploy this **alongside** `gcp-source-audit-logs-organization`, not instead of it. They answer different
questions:

| | Answers |
|---|---|
| `admin_activity` | **who called which API** |
| CAI `IAM_POLICY` | **what the policy now IS**, and what it was before |

Three different API paths to the same IAM binding produce three different audit entries and
**one identical policy diff**. The diff is what a detection actually wants — and it is also
the natural feed for an asset and identity model, because it carries inventory rather than
only events.

## Before you start

You need `roles/cloudasset.owner` at the organization.

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

## Reuse Abstract's identity

If `gcp-source-audit-logs-organization` used a GCS backend, read it rather than retyping it.
Set these in terraform.tfvars:

```hcl
remote_state_bucket = "acme-abstract-tfstate"
remote_state_prefix = "01-organization"  # its state key keeps the original folder name
```

No shared backend? Paste it instead — and know you now own keeping it in sync:

```bash
cd ../gcp-source-audit-logs-organization && terraform output -json abstract_onboarding | jq -r .service_account_email
```

## Choose the content type

`IAM_POLICY` is the default and the highest security value.

| Type | What it gives you |
|---|---|
| `IAM_POLICY` | Policy changes **with the prior state** |
| `RESOURCE` | Full resource metadata on change — inventory for an asset model |
| `ORG_POLICY` | Organization policy constraint changes |
| `ACCESS_POLICY` | **VPC Service Controls and Access Context Manager changes** |
| `OS_INVENTORY` | Installed packages and patches, where the Ops Agent runs |

## Scope the asset types

The default is a security-first set: projects, folders, service accounts, **service-account
keys**, buckets and firewalls.

<walkthrough-info-message>An **empty** `asset_types` feeds every asset type in the
organization. On a large estate that is a very large stream with a low signal ratio — the
module refuses it without `acknowledge_all_asset_types`.</walkthrough-info-message>

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

If nothing arrives:

```bash
terraform output cai_service_agent
```

CAI publishes as its **own service agent**, not as you — the same shape as the Log Router
writer identity and the GCS service agent. Without `roles/pubsub.publisher` on the topic
the feed is created successfully and delivers nothing. Terraform grants it here; that
output is where to look if it ever gets removed.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Asset changes arrive on their **own** topic and subscription. Configure them as a separate
source in Abstract — the shape is nothing like an audit log.

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, if this piece feeds one. Then, with the same `backend.tf`:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-asset-and-iam-changes"
terraform destroy
```
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Deploy with Terraform

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-asset-and-iam-changes"
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
