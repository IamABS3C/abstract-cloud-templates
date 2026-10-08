<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Google Workspace identity logs

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

A **separate pipeline**. Workspace audit data comes from the Admin SDK Reports API and never
touches Cloud Logging — no sink, topic or filter at any scope will collect it.

## Before you start

<walkthrough-info-message>You need a Workspace **SUPER ADMIN** for the delegation step. A Google Cloud
Owner cannot grant domain-wide delegation — there is no API for it and no Terraform
provider.</walkthrough-info-message>

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

Run script step 7 of the guided setup. It needs the logging project from script step 3; run that first. Script step 10 then prints the commands that download its key from this temporary session. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
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

Paste the `client_id` — the **numeric** ID, not the service-account email — and the two
scopes exactly as printed, comma-separated with no spaces.

## Key, then Abstract

```bash
SA=$(terraform output -json workspace_onboarding | jq -r .service_account_email)
echo "$SA"
gcloud iam service-accounts keys create ws-key.json --iam-account="$SA"
```

`-json | jq` rather than `-raw`: **`-raw` only works on a string output and errors on an
object**, which `workspace_onboarding` is.

Upload it to Abstract with the admin email and application list, then **delete the local
copy**.

## Verify

If the Reports API returns **401**, the delegation has not propagated or `admin_email` is
not actually an admin. Delegation impersonates a real user — without a valid subject you
get 401, not an empty result.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, so it stops reading. The clean-up needs the answers file the guided setup saved; in a new Cloud Shell session, upload the copy you downloaded at the end of the setup. Then list what the clean-up would remove, and remove it:

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
```

It removes only what the guided setup recorded creating, and never the logging project. Lost the answers file? `--remove --project <logging-project-id>` lists everything that carries the setup's names, with the command to remove each, and deletes nothing itself. If you deployed with Terraform instead, run `terraform destroy` in this folder with the same `backend.tf`.
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Terraform instead

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it.

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

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
