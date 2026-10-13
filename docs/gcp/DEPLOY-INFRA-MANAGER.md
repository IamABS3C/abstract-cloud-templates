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

## Who needs which role

Two principals need roles, and they are not the same set. Every row below comes from
[`tools/gcp-guided-setup/permissions.json`](../../tools/gcp-guided-setup/permissions.json), the list the guided script's
`--grant` and the app's step-by-step guide read too.

| Principal | Role | Where | For |
|---|---|---|---|
| you | `roles/serviceusage.serviceUsageAdmin` | logging project | turn on the Infrastructure Manager and Cloud Build APIs |
| you | `roles/iam.serviceAccountAdmin` | logging project | create the service account Infrastructure Manager runs as |
| you | `roles/config.admin` | logging project | create previews and deployments |
| you | `roles/iam.serviceAccountUser` | the Infrastructure Manager service account | start a deployment that runs as it |
| the service account | `roles/config.agent` | logging project | run deployments for Infrastructure Manager |
| the service account | `roles/pubsub.admin` | logging project | create the topic and subscription, and grant on them |
| the service account | `roles/iam.serviceAccountAdmin` | logging project | create Abstract's service account |
| the service account | `roles/serviceusage.serviceUsageAdmin` | logging project | turn on the APIs each template names in `apis.tf` |
| the service account | **`roles/logging.configWriter`** | **the organization, folder or project the sink is at** | create the log sink |
| the service account | `roles/iam.securityAdmin` (optional) | the same scope | only to deploy `gcp-foundation-data-access-audit-logs` |
| the service account | `roles/monitoring.editor` (optional) | logging project | only to deploy `gcp-monitoring-pipeline-health-alerts` |

`roles/iam.serviceAccountKeyAdmin` is not on the list: the templates make no key unless you set
`create_service_account_key = true`, which puts the private key in Terraform state. Make the key with
gcloud instead (script step 5).

### Check them, then grant them

The guided script checks and grants both sets, one binding per role, never a write of a whole policy. Run these
from the top folder of the templates repository. Replace YOUR_EMAIL with your account and LOGGING_PROJECT_ID with
the logging project's ID.

Check what you hold, changing nothing. For your own email it asks Google which permissions you hold by any
route, a group or an inherited role included:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL --for infra-manager --check
```

Grant what is missing. Someone who can set IAM policy on the logging project runs it; anyone else is handed the
commands to pass on:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL --for infra-manager
```

Then the service account's roles, once it exists (Step 2):

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant serviceAccount:infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --for infra-manager-sa
```

The commands below do the same by hand.

## Step 1 — Enable the APIs

Replace LOGGING_PROJECT_ID with your logging project's ID, ORG_ID with your organization's ID, YOUR_EMAIL with
your account, and INFRA_MANAGER_REGION with a Google Cloud region your organization allows.
`gcloud infra-manager locations list` does not exist; check the Infra Manager locations page if you need the
authoritative list.

```bash
gcloud services enable config.googleapis.com cloudbuild.googleapis.com pubsub.googleapis.com logging.googleapis.com --project=LOGGING_PROJECT_ID
```

Then confirm both took. A project without open billing reports success here and enables nothing:

```bash
gcloud services list --enabled --project=LOGGING_PROJECT_ID --filter="config.googleapis.com OR cloudbuild.googleapis.com" --format="value(config.name)"
```

`config.googleapis.com` **is** the Infrastructure Manager API — the naming is not obvious,
and it is why the agent role is called `roles/config.agent`.

## Step 2 — Create the service account

```bash
gcloud iam service-accounts create infra-manager-abstract --display-name="Infra Manager - Abstract" --project=LOGGING_PROJECT_ID
```

## Step 3 — Grant it, in the logging project

The first grant is for Infrastructure Manager itself; the rest cover what the template creates in this project.
One command per role:

```bash
gcloud projects add-iam-policy-binding LOGGING_PROJECT_ID --member=serviceAccount:infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --role=roles/config.agent --condition=None
```

```bash
gcloud projects add-iam-policy-binding LOGGING_PROJECT_ID --member=serviceAccount:infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --role=roles/pubsub.admin --condition=None
```

```bash
gcloud projects add-iam-policy-binding LOGGING_PROJECT_ID --member=serviceAccount:infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --role=roles/iam.serviceAccountAdmin --condition=None
```

```bash
gcloud projects add-iam-policy-binding LOGGING_PROJECT_ID --member=serviceAccount:infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --role=roles/serviceusage.serviceUsageAdmin --condition=None
```

## Step 4 — Grant it where the sink goes

**This is the step that gets missed.** For an organization sink:

```bash
gcloud organizations add-iam-policy-binding ORG_ID --member=serviceAccount:infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --role=roles/logging.configWriter --condition=None
```

For a folder sink, `gcloud resource-manager folders add-iam-policy-binding FOLDER_ID` with the same flags; for a
project sink, `gcloud projects add-iam-policy-binding` on the project the logs come from.

Add `roles/iam.securityAdmin` at the same scope **only** if you are also deploying
`gcp-foundation-data-access-audit-logs`, which changes the audit settings in the IAM policy there. It is powerful:
it can change IAM anywhere at that scope, so take it back once the deployment is done.

## Step 5 — Let yourself act as the service account

```bash
gcloud iam service-accounts add-iam-policy-binding infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --project=LOGGING_PROJECT_ID --member=user:YOUR_EMAIL --role=roles/iam.serviceAccountUser --condition=None
```

You also need `roles/config.admin` on the logging project to create previews and deployments:

```bash
gcloud projects add-iam-policy-binding LOGGING_PROJECT_ID --member=user:YOUR_EMAIL --role=roles/config.admin --condition=None
```

### If the service account lives in a different project from the resources

Google documents two extra grants for cross-project use:

- the Infra Manager **service agent** needs `roles/iam.serviceAccountUser`
- the **Cloud Build service agent** needs `roles/iam.serviceAccountTokenCreator`
- the org policy `iam.disableCrossProjectServiceAccountUsage` must not be enforced

Simplest avoidance: put the service account in the logging project, as above.

## Step 6 — Choose the source: the public repository at a release tag

> **Not yet run end to end.** Every command on this page was checked against gcloud's own help (SDK 588.0.0) and
> Google's Infrastructure Manager pages, but the test organization has no open billing account, so no preview or
> deployment has run (see [VERIFIED.md](VERIFIED.md)). Treat your first preview as the test, and read it before you
> apply.

Deploy from the public repository, not from a folder on your computer. Each template reads the shared modules
from `../_modules`, and `--local-source` uploads only the folder you name: gcloud's own help says Terraform
references outside that path are not supported (`gcloud infra-manager deployments apply --help`, SDK 588.0.0). A
git source fetches the whole repository, so the modules resolve.

Pin `--git-source-ref` to a release tag, never a branch: with a branch, the next apply deploys whatever was merged
since, unreviewed. Every publish of the public repository is tagged `release-<UTC time>-<commit>`, so the tags
sort in publish order. List them, newest last,
and use the last one wherever RELEASE_TAG appears below:

```bash
git ls-remote --tags --sort=v:refname https://github.com/IamABS3C/abstract-cloud-templates
```

## Step 7 — Write your values in a .tfvars file

`--input-values` takes scalars only (`gcloud infra-manager deployments apply --help`), so lists such as
`log_categories` go in a `.tfvars` file passed with `--inputs-file`. Copy the template's example, then edit the copy:

```bash
cp templates/gcp/gcp-source-audit-logs-organization/terraform.tfvars.example abstract.tfvars
```

Set at least `org_id` and `log_project`. For the default three Cloud Audit Logs plus service-account token minting
and Workload Identity Federation:

```hcl
org_id         = "ORG_ID"
log_project    = "LOGGING_PROJECT_ID"
log_categories = ["admin_activity", "system_event", "policy_denied", "identity_access"]
```

To route BigQuery, Cloud Storage and Cloud KMS Data Access logs as well, add `data_access_all`:

```hcl
log_categories = ["admin_activity", "system_event", "policy_denied", "identity_access", "data_access_all"]
```

Leave `data_access_services` out: its default already names `bigquery.googleapis.com`,
`storage.googleapis.com` and `cloudkms.googleapis.com` (with the identity services), the same
services `gcp-foundation-data-access-audit-logs` recommends turning on. If you set it, keep it matched to the
foundation's `services`, or Google writes and bills Data Access logs this sink never routes. It is
read only with `data_access_all`, and on its own routes nothing.

Either way, turn the Data Access logs on at the source too, with
`gcp-foundation-data-access-audit-logs`. Firewall and DNS logs do not belong in this root:
Abstract's managed GCP parser keeps only Cloud Audit Log records, so they would be pulled and
discarded. `gcp-source-network-threat-logs` routes them to a topic of their own, but Abstract does not keep
them there either today: deploying it costs money in Google Cloud and adds nothing in Abstract.

`abstract.tfvars` stays on your computer: gcloud reads it and sends the values, and the repository's `.gitignore`
keeps `*.tfvars` out of git so nobody commits a customer's values by accident.

## Step 8 — Preview (this is `terraform plan`)

```bash
gcloud infra-manager previews create projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-organization --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
```

Wait for the state to read `SUCCEEDED`:

```bash
gcloud infra-manager previews describe projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --format="value(state,errorCode)"
```

Then download the result. Google exports it twice, as a binary plan and as JSON; read the JSON in any editor or
with `jq`:

```bash
gcloud infra-manager previews export projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --file=abstract-preview
```

**Read it.** Confirm the sink is at the scope you chose with `include_children = true`, and that the filter is
what you expect. That filter decides both coverage and bill.

## Step 9 — Apply

```bash
gcloud infra-manager deployments apply projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-organization --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
```

In the console the same deployment is under **Infra Manager** (console.cloud.google.com/infra-manager): **Create**,
then on **Deployment details** the deployment ID, region, Terraform version, service account and a Git source
(repository, directory, tag), **Continue**, the input values on **Terraform details** (one key and value per
variable, so lists are easier from gcloud), **Continue**, then **Create deployment**.

## Step 10 — Read the result

```bash
gcloud infra-manager deployments describe projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --format="yaml(state,stateDetail,errorCode,tfErrors,latestRevision)"
```

`ACTIVE` is done. `FAILED` names why in `stateDetail`, `errorCode` and `tfErrors` (Terraform's own errors, up to
ten, each with the resource and Google's HTTP status). A `403` there is a role the service account is missing:
check it with `--grant serviceAccount:… --for infra-manager-sa --check` above. For `REVISION_FAILED`, the
revision names the Cloud Build run that holds the full log:

```bash
gcloud infra-manager revisions list --deployment=projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export
```

The template's outputs carry the values Abstract needs: `abstract_onboarding` holds the `project_id` /
`subscription_id` pair for the integration, and `sink_writer_identity` names the account the publisher grant went
to. Make Abstract's key with script step 5, never in Terraform: a key made by Terraform lives in its state.

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

Delete the integration in Abstract first, so it stops reading the subscription.

A plain `gcloud infra-manager deployments delete` asks Infra Manager to delete what the
deployment made, which is a Terraform destroy. The topic, the subscription and the sink carry
`prevent_destroy` in `_modules/log-export`, so that destroy is refused, and the sink keeps
exporting. This is inferred, not run against Infra Manager: [VERIFIED.md](VERIFIED.md)
measured the same refusal for a plain `terraform destroy`. The guard is deliberate: a stray
destroy cannot drop security logs Abstract has not read yet.

So delete the deployment with `--delete-policy=abandon`, which removes only Infra Manager's
record and leaves every resource in place, then delete the resources with gcloud: the sink
first, so nothing is written to a topic that is about to go, then the subscription, then the
topic, then Abstract's service account. Use your own names if you changed them:

```bash
gcloud infra-manager deployments delete projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --delete-policy=abandon
```

```bash
gcloud logging sinks delete abstract-org-audit-sink --organization=ORG_ID
```

```bash
gcloud pubsub subscriptions delete abstract-audit-logs-sub --project=LOGGING_PROJECT_ID
```

```bash
gcloud pubsub topics delete abstract-audit-logs --project=LOGGING_PROJECT_ID
```

```bash
gcloud iam service-accounts delete abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com --project=LOGGING_PROJECT_ID
```

The guided script's `--teardown` finds all of these across the organization and lists them before it deletes
anything (`./tools/gcp-guided-setup/abstract-gcp-setup.sh --teardown`). The Infrastructure Manager service account
`infra-manager-abstract` and its grants stay until you remove them; the roles `--grant` added are taken back with
`--teardown --include-grants`.

If you turned on `enable_dead_letter`, delete the dead-letter topic too. The topic's
publisher grant to the sink goes with the topic.

None of this touches `gcp-foundation-data-access-audit-logs`, which is a separate deployment
with separate state. That separation exists precisely so that deleting a collector can never
strip an organization's Data Access audit logging.
