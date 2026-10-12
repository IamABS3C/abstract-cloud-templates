<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Google Workspace identity logs

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

A **separate pipeline**. Abstract's Workspace integration reads Workspace audit data from the
Admin SDK Reports API and does not depend on Cloud Logging. If [Workspace data sharing with
Google Cloud](https://docs.cloud.google.com/logging/docs/audit/configure-gsuite-audit-logs#share_audit_logs) is on, Google also writes the shared Workspace logs to Cloud Logging, and
an organization sink with `identity_access` routes the login entries too; this repo has not
verified that path, so rely on the Reports API.

## Before you start

<walkthrough-info-message>You need a Workspace **SUPER ADMIN** for the delegation step. A Google Cloud
Owner cannot grant domain-wide delegation — there is no API for it and no Terraform
provider.</walkthrough-info-message>

<!-- abstract:signin -->
## Sign in first

Cloud Shell opened the public templates repository in a **temporary** session. Google gives a repository it does not own none of your credentials, and deletes the session's files when it ends. Sign in; `--update-adc` gives the scripts and Terraform the same sign-in:

```bash
gcloud auth login --update-adc
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

## Choose the application groups

Set these in terraform.tfvars:

```hcl
workspace_admin_email = "admin@yourdomain.com"
workspace_app_groups  = ["identity", "admin"]
```

`identity` is `login`, `saml`, `token`, `user_accounts`, `context_aware_access` — the answer
to "who signed in", which is usually the whole ask. Add `data` for gmail and drive only
after measuring; they dwarf everything else.

<!-- abstract:deploy -->
## Deploy

Run script steps 1, 3, 7 and 10 of the guided setup: your scope, the logging project, then the Workspace account. Script step 10 then prints the values to enter in Abstract and the commands that download its key from this temporary session. Delete every copy of the key once Abstract has it. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
```

Your team requires infrastructure as code? Use [Terraform instead](#terraform-instead) at the end of this page. Use one or the other, not both.
<!-- /abstract:deploy -->

## Read the values you need

```bash
terraform output workspace_onboarding
```

## Grant delegation (Workspace super admin)

**admin.google.com → Security → Access and data control → API controls →
Domain-wide delegation → Add new**

Paste the `client_id` — the **numeric** ID, not the service-account email — and the scope
exactly as printed (`https://www.googleapis.com/auth/admin.reports.audit.readonly`, the only one Abstract
requests). With `include_directory_enrichment_scopes = true` the scopes are printed comma-separated with
no spaces; paste them as printed.

## Key, then Abstract

```bash
SA=$(terraform output -json workspace_onboarding | jq -r .service_account_email)
echo "$SA"
mkdir -p ~/abstract-keys && chmod 700 ~/abstract-keys   # outside the repo clone
(umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-workspace-key.json --iam-account="$SA")
cloudshell download ~/abstract-keys/abstract-workspace-key.json   # in Cloud Shell: save it to your computer
```

`-json | jq` rather than `-raw`: **`-raw` only works on a string output and errors on an
object**, which `workspace_onboarding` is.

The key carries domain-wide delegation, so it is written outside the repository clone, readable only by
you. Upload it to Abstract with the admin email and application list, then **delete every copy**:
`rm -f ~/abstract-keys/abstract-workspace-key.json` here, and the downloaded file on your computer.

## Verify

If the Reports API returns **401**, the delegation has not propagated or `admin_email` is
not actually an admin. Delegation impersonates a real user — without a valid subject you
get 401, not an empty result.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, so it stops reading. The clean-up needs the answers file the guided setup saved, `~/.abstract-gcp-setup.env`; in a new Cloud Shell session, upload the copy you downloaded at the end of the setup to your home folder. First list what the clean-up would remove. This deletes nothing:

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
```

When the list is right, remove it:

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
```

It removes only what the guided setup recorded creating, and never the logging project. Lost the answers file? `--remove --project <logging-project-id>` lists everything that carries the setup's names, with the command to remove each, and deletes nothing itself. If you deployed with Terraform instead, follow **To remove it later** at the end of [Terraform instead](#terraform-instead).
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Terraform instead

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=<project-id-with-billing>` to put the bucket in a project that has it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-google-workspace-logs"
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

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating)
- [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation)
- [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)
- [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)
- [google_service_account](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account)
- [google_project_service](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_service)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
