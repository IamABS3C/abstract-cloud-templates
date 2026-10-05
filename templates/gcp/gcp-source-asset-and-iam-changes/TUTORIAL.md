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

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Step 1 — Reuse Abstract's identity

If `gcp-source-audit-logs-organization` used a GCS backend, read it rather than retyping it:

```bash
cat > terraform.tfvars <<EOF
org_id              = "YOUR_ORG_ID"
log_project         = "YOUR_LOG_PROJECT"
remote_state_bucket = "acme-abstract-tfstate"
remote_state_prefix = "01-organization"  # its state key keeps the original folder name
EOF
```

No shared backend? Paste it instead — and know you now own keeping it in sync:

```bash
cd ../gcp-source-audit-logs-organization && terraform output -json abstract_onboarding | jq -r .service_account_email
```

## Step 2 — Choose the content type

`IAM_POLICY` is the default and the highest security value.

| Type | What it gives you |
|---|---|
| `IAM_POLICY` | Policy changes **with the prior state** |
| `RESOURCE` | Full resource metadata on change — inventory for an asset model |
| `ORG_POLICY` | Organization policy constraint changes |
| `ACCESS_POLICY` | **VPC Service Controls and Access Context Manager changes** |
| `OS_INVENTORY` | Installed packages and patches, where the Ops Agent runs |

## Step 3 — Scope the asset types

The default is a security-first set: projects, folders, service accounts, **service-account
keys**, buckets and firewalls.

<walkthrough-info-message>An **empty** `asset_types` feeds every asset type in the
organization. On a large estate that is a very large stream with a low signal ratio — the
module refuses it without `acknowledge_all_asset_types`.</walkthrough-info-message>

## Step 4 — Plan, then apply

```bash
terraform init && terraform plan
```

You need `roles/cloudasset.owner` at the organization.

## Step 5 — If nothing arrives

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

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
