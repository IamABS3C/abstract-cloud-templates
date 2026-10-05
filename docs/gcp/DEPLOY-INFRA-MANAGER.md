# Deploying with Infrastructure Manager

Infrastructure Manager ("Infra Manager") is Google's managed Terraform. You hand it a
config; it runs Terraform on Cloud Build and **holds the state for you** in a
Google-managed bucket.

Use it when you want the deployment auditable and repeatable without standing up your own
Terraform backend and CI.

> **Do not reach for Deployment Manager.** It reached **end of support on 31 March 2026**.
> It keeps running until 30 June 2027, but Google will not answer support tickets and
> states that continued use is at your own risk. Infra Manager is the documented successor,
> and it is Terraform underneath — so the modules in this repo work unchanged.

---

## Prerequisites — check these before you start

> ### Billing MUST be enabled on the project
>
> **This is a hard blocker and it is not documented anywhere obvious.** Infra Manager runs
> Terraform on **Cloud Build**, and Cloud Build cannot be enabled on a project without an
> open billing account.
>
> Verified 2026-08-26 against a live organization: `gcloud services enable
> config.googleapis.com cloudbuild.googleapis.com` returned
>
> ```
> reason: UREQ_PROJECT_BILLING_NOT_OPEN
> services: cloudbuild.googleapis.com, artifactregistry.googleapis.com, ...
> ```
>
> Neither `config.googleapis.com` nor `cloudbuild.googleapis.com` enabled. **Note the API
> enable call reports success at the CLI level** — you have to check afterwards.
>
> ```bash
> gcloud billing projects describe YOUR_PROJECT --format='value(billingEnabled)'
> gcloud billing accounts list --format='value(name,displayName,open)'
> ```
>
> Both must be true. A billing account that exists but is **closed** (`open: False`) fails
> exactly the same way as none at all.

**Worth knowing, because it changes which path you recommend:** the plain
Terraform / Cloud Shell path in this repo **works fine on a project with billing
disabled** — verified end to end, sink created and audit events delivered. Pub/Sub and
Cloud Logging both have free tiers that cover it. So for a customer in a sandbox, a trial,
or an unfunded project, **Cloud Shell works and Infra Manager does not.**

| | Needs billing? |
|---|---|
| Cloud Shell button / local Terraform | **No** — verified working without it |
| Infrastructure Manager | **Yes** — Cloud Build dependency |

### The other prerequisites

| | Check |
|---|---|
| Infra Manager API | `gcloud services list --enabled --filter=config.googleapis.com` |
| Cloud Build API | `gcloud services list --enabled --filter=cloudbuild.googleapis.com` |
| A service account to run as | Step 2 below |
| `roles/logging.configWriter` **at the org** | `tools/gcp-guided-setup/preflight.sh` |

---

## The constraint that shapes everything

**An Infra Manager deployment is a project-scoped resource. Our sink is an org-scoped one.**

So the service account running the deployment needs grants *above* the project the
deployment lives in. This is the step that gets missed, and it fails at apply — after
Terraform has already created the topic and subscription.

Run [`tools/gcp-guided-setup/preflight.sh`](../../tools/gcp-guided-setup/preflight.sh) first.

---

## Step 1 — Enable the APIs

```bash
export LOG_PROJECT=acme-security-logging
export ORG_ID=123456789012
export LOCATION=us-central1        # a standard GCP region

# NOTE: `gcloud infra-manager locations list` does NOT exist — an earlier draft of
# this document said to run it. Use a standard region; check the Infra Manager
# locations page if you need the authoritative list.
export SA=infra-manager-abstract

gcloud config set project "$LOG_PROJECT"
gcloud services enable \
  config.googleapis.com \
  cloudbuild.googleapis.com \
  pubsub.googleapis.com \
  logging.googleapis.com
```

`config.googleapis.com` **is** the Infrastructure Manager API — the naming is not obvious,
and it is why the agent role is called `roles/config.agent`.

## Step 2 — Create the service account

```bash
gcloud iam service-accounts create "$SA" \
  --display-name="Infra Manager — Abstract log export"

export SA_EMAIL="$SA@$LOG_PROJECT.iam.gserviceaccount.com"
```

## Step 3 — Grant it, at the project

```bash
# Infra Manager itself
gcloud projects add-iam-policy-binding "$LOG_PROJECT" \
  --member="serviceAccount:$SA_EMAIL" --role="roles/config.agent"

# What the module creates in this project
gcloud projects add-iam-policy-binding "$LOG_PROJECT" \
  --member="serviceAccount:$SA_EMAIL" --role="roles/pubsub.admin"
gcloud projects add-iam-policy-binding "$LOG_PROJECT" \
  --member="serviceAccount:$SA_EMAIL" --role="roles/iam.serviceAccountAdmin"
```

## Step 4 — Grant it at the ORGANIZATION

**This is the step that gets missed.**

```bash
gcloud organizations add-iam-policy-binding "$ORG_ID" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/logging.configWriter"
```

Add `roles/resourcemanager.organizationAdmin` **only** if you are also deploying
`gcp-foundation-data-access-audit-logs`, which changes the org IAM policy.

## Step 5 — Let yourself act as the service account

```bash
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/iam.serviceAccountUser"
```

### If the service account lives in a different project from the resources

Google documents two extra grants for cross-project use:

- the Infra Manager **service agent** needs `roles/iam.serviceAccountUser`
- the **Cloud Build service agent** needs `roles/iam.serviceAccountTokenCreator`
- the org policy `iam.disableCrossProjectServiceAccountUsage` must not be enforced

Simplest avoidance: put the service account in the logging project, as above.

## Step 6 — Preview (this is `terraform plan`)

```bash
gcloud infra-manager previews create \
  "projects/$LOG_PROJECT/locations/$LOCATION/previews/abstract-preview" \
  --service-account="projects/$LOG_PROJECT/serviceAccounts/$SA_EMAIL" \
  --local-source="./templates/gcp/gcp-source-audit-logs-organization" \
  --input-values="org_id=$ORG_ID,log_project=$LOG_PROJECT"
```

**Read it.** Confirm the sink is org-scoped with `include_children = true`, and that
`effective_filter` is what you expect. That filter decides both coverage and bill.

## Step 7 — Apply

```bash
gcloud infra-manager deployments apply \
  "projects/$LOG_PROJECT/locations/$LOCATION/deployments/abstract-log-export" \
  --service-account="projects/$LOG_PROJECT/serviceAccounts/$SA_EMAIL" \
  --local-source="./templates/gcp/gcp-source-audit-logs-organization" \
  --input-values="org_id=$ORG_ID,log_project=$LOG_PROJECT"
```

## Step 8 — Read the outputs

```bash
gcloud infra-manager deployments describe \
  "projects/$LOG_PROJECT/locations/$LOCATION/deployments/abstract-log-export"

gcloud infra-manager revisions list \
  --deployment="projects/$LOG_PROJECT/locations/$LOCATION/deployments/abstract-log-export"
```

`abstract_onboarding` carries the `project_id` / `subscription_id` pair for the Abstract
integration. `sink_writer_identity` confirms the publisher binding landed.

---

## List variables: `--input-values` cannot carry them

**`--input-values` accepts scalars only.** Google's reference: *"It only accepts (key,
value) pairs where value is a scalar value."* There is no `--inputs-file` flag.

So `log_categories`, `data_access_services`, `workspace_app_groups` and `exclusions`
**cannot** be passed on the command line.

**Commit a `terraform.tfvars` into the deployment directory instead.** Terraform
auto-loads it from the working directory, and `--input-values` still overrides scalars on
top. Verified working against these modules.

```hcl
# templates/gcp/gcp-source-audit-logs-organization/terraform.tfvars
log_categories       = ["admin_activity", "system_event", "firewall", "dns_queries"]
data_access_services = ["bigquery.googleapis.com", "storage.googleapis.com"]
```

```bash
gcloud infra-manager deployments apply ... \
  --input-values="org_id=$ORG_ID,log_project=$LOG_PROJECT"
```

Note the repo `.gitignore` excludes `terraform.tfvars` by default — deliberately, so
nobody commits a customer's values by accident. For a git-source deployment you must
either commit it intentionally (`git add -f`) or keep the defaults.

---

## Deploying from git instead of local

`--local-source` uploads whatever is on your laptop, which is a one-shot. Point at the
repo to make it a controlled pipeline:

```bash
gcloud infra-manager deployments apply \
  "projects/$LOG_PROJECT/locations/$LOCATION/deployments/abstract-log-export" \
  --service-account="projects/$LOG_PROJECT/serviceAccounts/$SA_EMAIL" \
  --git-source-repo="https://github.com/IamABS3C/abstract-cloud-templates" \
  --git-source-directory="templates/gcp/gcp-source-audit-logs-organization" \
  --git-source-ref="<tag>" \
  --input-values="org_id=$ORG_ID,log_project=$LOG_PROJECT"
```

> **Pin `--git-source-ref` to a TAG, not a branch.** With a branch, the deployment's
> content changes whenever somebody merges — and the next apply silently deploys code
> nobody reviewed against that environment.

The repo layout is designed for this: `--git-source-directory` points at a deployment
root, and the local `../_modules/...` references resolve inside the clone.

---

## Pinning the Terraform version

```bash
--tf-version-constraint="=1.5.7"
```

Infra Manager runs **Terraform**, not OpenTofu. These modules are validated under OpenTofu
locally and declare `required_version = ">= 1.5"`. Treat the first preview as the real
compatibility test.

---

## Other flags worth knowing

| Flag | Use |
|---|---|
| `--labels` | Labels on the deployment. Existing values are overwritten |
| `--worker-pool` | Run the Cloud Build job in a private pool — needed if your build must sit inside a VPC |
| `--tf-version-constraint` | Pin Terraform |

---

## Teardown

```bash
gcloud infra-manager deployments delete \
  "projects/$LOG_PROJECT/locations/$LOCATION/deployments/abstract-log-export"
```

This destroys the resources it created. It **cannot** touch `gcp-foundation-data-access-audit-logs`, which is a
separate deployment with separate state — that separation exists precisely so that
deleting a collector can never strip an organization's Data Access audit logging.
