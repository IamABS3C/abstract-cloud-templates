# Setting up from nothing

Everything needed before the first deployment: which scope, whether to create a project,
billing, quota, and every permission — for both the gcloud/Cloud Shell path and
Infrastructure Manager.

**To set up, follow [the setup guide](GUIDE.md).** This page is the background behind its steps.
The guided setup's steps 1 and 2 check most of what follows against your real environment.

---

## 1. Decide the scope — this drives everything else

| | Covers future projects | Needs | Use when |
|---|---|---|---|
| **Organization** | ✅ by containment | `roles/logging.configWriter` **at the org** | Almost always |
| **Folder** | ✅ within the subtree | `roles/logging.configWriter` **at the folder** | Org IAM not granted, or a real trust boundary |
| **Project** | ❌ | `roles/logging.configWriter` on the project | Pilot only |
| **Billing account** | n/a | `roles/logging.configWriter` on the billing account | Billing logs, which sit outside the hierarchy |

### What actually differs, in practice

**Organization.** One deployment, permanently. The only real obstacle is *who holds
`logging.configWriter` at org scope* — and that is frequently nobody, because it is not
granted by default even to an Organization Admin. **Verified on a live org 2026-08-26:** an
account holding `roles/resourcemanager.organizationAdmin` did **not** hold
`logging.configWriter`, and could not create the sink until it granted itself the role.

```bash
# Are you actually able to do this?
gcloud organizations get-iam-policy $ORG_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/logging.configWriter" \
  --format="table(bindings.members)"

# Organization Admin? You can grant it to yourself.
gcloud organizations add-iam-policy-binding $ORG_ID \
  --member="user:you@example.com" --role="roles/logging.configWriter"
```

**Folder.** Identical mechanics, narrower container — and it **silently misses everything
outside that folder**, including new projects, which land in the org root by default.
Choose it because org IAM is genuinely unavailable, not because it feels safer. Write down
which folder, and schedule the org conversation.

**Project.** No `include_children` exists below a project, so it cannot cover future
projects. It proves the pipeline end to end before you ask for org rights — which is
genuinely useful, because "it works, here is the data" is a better ask than "please grant
me org IAM." Replace it; never repeat it per project.

> **Do not deploy a project sink per project.** Seventy project sinks is the linear toil
> the aggregated sink exists to eliminate, each one decaying independently as projects
> change. The 200-sinks-per-container quota also starts to matter.

---

## 2. The logging project

### Use an existing one if there is a sensible candidate

Requirements: **not a workload project.** Pub/Sub publish quota is consumed in the
destination project, and a security pipeline living inside a workload project can be read
or broken by that workload's owner.

### Create one if there is not

```bash
cd templates/gcp/gcp-foundation-logging-project
cat > terraform.tfvars <<EOF
create_project     = true
project_id         = "acme-security-logging"     # globally unique
org_id             = "123456789012"
billing_account_id = "XXXXXX-XXXXXX-XXXXXX"
EOF
terraform init && terraform apply
```

Or by hand:

```bash
gcloud projects create acme-security-logging --organization=$ORG_ID
gcloud billing projects link acme-security-logging --billing-account=$BILLING_ACCOUNT
gcloud services enable pubsub.googleapis.com logging.googleapis.com \
  --project=acme-security-logging
```

**You need:**

| Permission | Where |
|---|---|
| `roles/resourcemanager.projectCreator` | organization or folder |
| `roles/billing.user` | the billing account |

`deletion_policy` defaults to **PREVENT**, which is right for a project holding an audit
pipeline — it refuses to let Terraform delete it.

---

## 3. Billing — and when you genuinely do not need it

**Verified on a live organization 2026-08-26.**

| Path | Billing required |
|---|---|
| Cloud Shell button / local Terraform / gcloud | **No** |
| **Infrastructure Manager** | **Yes** |

The Cloud Shell path deployed and delivered real audit events on a project with
`billingEnabled=False` — Pub/Sub and Cloud Logging both have free tiers that cover a
control-plane feed.

**Infra Manager does not work without billing.** It runs Terraform on Cloud Build, and
Cloud Build cannot be enabled on an unfunded project:

```
gcloud services enable config.googleapis.com cloudbuild.googleapis.com
→ reason: UREQ_PROJECT_BILLING_NOT_OPEN
```

**The enable call reports success at the CLI level.** Check afterwards:

```bash
gcloud billing projects describe $LOG_PROJECT --format='value(billingEnabled)'
gcloud billing accounts list --format='value(name,displayName,open)'
gcloud services list --enabled --project=$LOG_PROJECT \
  --filter="config.name:(config.googleapis.com OR cloudbuild.googleapis.com)"
```

A billing account that **exists but is closed** (`open: False`) fails identically to none.

> For a sandbox, a trial, or an unfunded project: **recommend Cloud Shell.** It is not a
> lesser path — it is the only one that works there.

---

## 4. Quota

Publish quota is consumed in the **destination** project, not in the source projects. Size
the logging project, not the estate.

| Limit | Consequence |
|---|---|
| **200 sinks** per container, raisable to 4,000 | Never reached with an aggregated sink. Reached quickly with per-project sinks |
| **50 exclusion filters** per sink | Prefer narrowing the inclusion filter over stacking exclusions |
| **20,000-character filter** | Prefer `allServices` + exclusions over a long explicit service list |
| Pub/Sub publish quota, **per project per region** | Admin Activity across 70+ projects is small. `DATA_READ` and `vpc_flows` are what threaten it |

```bash
gcloud alpha services quota list --service=pubsub.googleapis.com \
  --consumer=projects/$LOG_PROJECT 2>/dev/null | head -20
```

If a sink cannot publish, **Cloud Logging drops the entry.** No retry, no backfill — only
`logging.googleapis.com/exports/error_count`, which `gcp-monitoring-pipeline-health-alerts` alerts on.

---

## 5. Every permission, by task

### Deploying the pipeline

| Principal | Role | Scope | Notes |
|---|---|---|---|
| you | `roles/logging.configWriter` | **org / folder / project** | **THE blocker.** Not granted by default, even to Org Admin |
| you | `roles/pubsub.admin` | logging project | Topic, subscription, IAM |
| you | `roles/iam.serviceAccountAdmin` | logging project | Abstract's identity |
| you | `roles/serviceusage.serviceUsageAdmin` | logging project | Enable APIs |
| **sink writer identity** | `roles/pubsub.publisher` | the **topic** | Automated here. **The #1 skipped step when done by hand** |
| abstract | `roles/pubsub.subscriber` | the **subscription** | Abstract pulls; never publisher, never project-wide |

### Enabling Data Access

| Principal | Role | Scope |
|---|---|---|
| you | **Organization Admin** (`resourcemanager.organizations.setIamPolicy`) | organization |

Usually a different person again from the `logging.configWriter` holder.

### Infrastructure Manager, additionally

| Principal | Role | Scope |
|---|---|---|
| the IM service account | `roles/config.agent` | logging project |
| the IM service account | `roles/pubsub.admin`, `roles/iam.serviceAccountAdmin` | logging project |
| the IM service account | **`roles/logging.configWriter`** | **the organization** |
| you | `roles/iam.serviceAccountUser` | on that service account |

> **The deployment is project-scoped; the sink is org-scoped.** So the service account needs
> a grant *above* the project it lives in. That is the step people miss, and it fails at
> apply — after some resources already exist.

### If you cannot read every project

**You do not need to.** An aggregated sink covers projects by **containment**, not by
per-project permission. `preflight.sh` reports which projects you cannot read and says so
explicitly, because the instinct is to go and get access to all of them — which is weeks of
work that buys nothing.

You only need per-project visibility to **size** the deployment and predict cost.

---

## 6. Two switches, both required

**Verified live:** enabling Data Access audit logging routes **nothing** on its own.

```
Switch 1  IAM audit config     — is the log GENERATED?      templates/gcp/gcp-foundation-data-access-audit-logs
Switch 2  the sink filter      — is the log ROUTED?         log_categories
```

Flip only switch 1 and you pay to generate logs nobody receives. Flip only switch 2 and the
filter matches **nothing, with no error** — indistinguishable from a broken sink.

```hcl
# Switch 1 — gcp-foundation-data-access-audit-logs
services  = ["bigquery.googleapis.com", "storage.googleapis.com", "cloudkms.googleapis.com"]
log_types = ["ADMIN_READ", "DATA_WRITE"]

# Switch 2 — gcp-source-audit-logs-organization
log_categories       = [..., "data_access_all"]
data_access_services = ["bigquery.googleapis.com", "storage.googleapis.com", "cloudkms.googleapis.com"]
```

Keep the service lists **identical**, or you generate logs you never route, or route for
services that generate nothing.

---

## 7. Order of operations

```
1. audit-gcp-estate.sh, then --step 1 and 2   read-only: what exists, and every permission
2. --step 3   logging project                 create or pick it, enable APIs
3. --step 4   the pipeline                    topic, subscription, sink, publisher grant
4. --step 5   Abstract's access               service account and key
5. --step 6   Data Access (optional)          both switches
6. --step 8   health alerts                   do NOT defer this
7. --step 9   verify with a FRESH event       wait 5 minutes: the sink is not live at once
8. --step 10  connect Abstract
```

Audit config before the pipeline, so the logs exist by the time the filter looks for them.
The reverse order works too — it just collects nothing until you catch up.
