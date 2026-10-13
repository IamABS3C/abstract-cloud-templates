<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Bootstrap the logging project

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

**Optional.** Most customers already have a security or logging project — point
`gcp-source-audit-logs-organization` at it and skip this.

Run this for greenfield, or when the only candidate is a **workload** project. That is the
wrong answer: Pub/Sub publish quota is consumed in the destination project, and a security
pipeline inside a workload project can be read or broken by that workload's owner.

## Before you start

To create the project too, you need project-creator rights. Billing is optional for the log pipeline: it was
measured delivering on a project with billing disabled ([VERIFIED.md](../../../docs/gcp/VERIFIED.md)), but an API that
requires billing cannot be enabled on a project without it. Script step 3 asks whether to link a billing account.

<!-- abstract:signin -->
## Sign in first

Cloud Shell opened the public templates repository in a **temporary** session. Google gives a repository it does not own none of your credentials, and deletes the session's files when it ends. Sign in; `--update-adc` gives the scripts and Terraform the same sign-in:

```bash
gcloud auth login --update-adc
```
<!-- /abstract:signin -->

<!-- abstract:check -->
## Check first

Read-only: nothing changes. The estate audit lists your organization, folders, projects, and the log sinks and topics you already have. Script steps 1 and 2 of the guided setup record your scope in the answers file, `~/.abstract-gcp-setup.env`, and check the rights the sink needs; script step 3, in [Deploy](#deploy), checks the logging project and the organization policy that can block the service-account key.

Go to the top folder of the templates repository; the guided-setup commands run from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

List what you already have (read-only):

```bash
./tools/gcp-guided-setup/audit-gcp-estate.sh
```

Script step 1: your organization and scope.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
```

Script step 2: the rights each step needs, asked of Google.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
```

If a permission row shows ✗, find the person who holds that role before you go on. Someone who can set IAM policy at your scope can grant exactly the roles the setup needs with `./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant` and your email address. It records each role it adds; once the pipeline works, the clean-up lists the command that takes each one back.
<!-- /abstract:check -->

## Existing project or new project

Script step 3 asks whether to use a project you already have or create one, then turns on its APIs. It asks before
each change, and checks your rights in the project and whether an organization policy blocks the service-account key.

<!-- abstract:deploy -->
## Deploy

Run script step 3 of the guided setup. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing. [Clean up](#clean-up), below, undoes what it made.

Go to the top folder of the templates repository; the guided-setup commands run from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

Script step 3: the logging project, its billing and APIs.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
```

Load the answers the script saved into this terminal; the checks below use them (LOG_PROJECT, ORG_ID, SCOPE_ID):

```bash
source ~/.abstract-gcp-setup.env
```

Check the logging project is set. You should see its ID; "not set" means script step 3 has not run yet:

```bash
echo "Logging project: ${LOG_PROJECT:?not set: run script step 3, or export LOG_PROJECT=LOGGING_PROJECT_ID}"
```

Your team requires infrastructure as code? Use [Terraform instead](#terraform-instead) at the end of this page. Use one or the other, not both.
<!-- /abstract:deploy -->

## Verify

Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the
pipeline in the project, and "service-account keys are allowed". A ✗ on the key policy means: ask for an exception on
this project before you go on. To check again at any time, changing nothing, run this from the top folder of the
repository:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --check
```

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, so it stops reading. The clean-up needs the answers file the guided setup saved, `~/.abstract-gcp-setup.env`; in a new Cloud Shell session, upload the copy you downloaded at the end of the setup to your home folder.

Go to the top folder of the templates repository; the guided-setup commands run from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

List what the clean-up would remove. This deletes nothing:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
```

When the list is right, remove it:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
```

It removes only what the guided setup recorded creating, and never the logging project. Roles that `--grant` added are listed by hand, each with the `remove-iam-policy-binding` command that takes it back. Lost the answers file? `--remove --project LOGGING_PROJECT_ID` lists everything that carries the setup's names, with the command to remove each, and deletes nothing itself. To start again from scratch, `--teardown` lists everything the setup and the templates make across the organization, and deletes it only with `--teardown --confirm`. If you deployed with Terraform instead, follow **To remove it later** at the end of [Terraform instead](#terraform-instead).
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Terraform instead

Use this instead of the guided script, not as well. Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=PROJECT_ID_WITH_BILLING`, with your own project ID, to put the bucket in a project that has it.

Creating the logging project with Terraform (`create_project = true`)? It does not exist yet, so keep the state in a project that does. Replace EXISTING_PROJECT_ID with its ID:

```bash
export STATE_PROJECT=EXISTING_PROJECT_ID
```

Go to this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-foundation-logging-project"
```

Load the guided setup's answers, if you ran it (it sets LOG_PROJECT and ORG_ID):

```bash
source ~/.abstract-gcp-setup.env
```

Check the logging project is set. If it says not set, run `export LOG_PROJECT=` and your logging project ID first:

```bash
echo "Logging project: ${LOG_PROJECT:?not set}"
```

Name the state bucket, in the logging project unless STATE_PROJECT is set:

```bash
export STATE_PROJECT="${STATE_PROJECT:-$LOG_PROJECT}" STATE_BUCKET="$LOG_PROJECT-abstract-tfstate"
```

Choose where the state bucket lives. Replace LOCATION with a Cloud Storage location your organization allows ([Bucket locations](https://docs.cloud.google.com/storage/docs/locations) lists them): the multi-region or region your data-residency rules name. An organization policy on resource locations refuses any other. A state bucket you created before stays where it is; this does not move it:

```bash
export STATE_LOCATION=LOCATION
```

Create the bucket, in STATE_PROJECT at STATE_LOCATION (to undo it once nothing uses the state, delete the bucket). If you made it before, Google answers that it already exists; go on:

```bash
gcloud storage buckets create "gs://$STATE_BUCKET" --project="$STATE_PROJECT" --location="$STATE_LOCATION" --uniform-bucket-level-access
```

Keep every version of the state:

```bash
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
```

Point `backend.tf` at the bucket:

```bash
sed "s/acme-abstract-tfstate/$STATE_BUCKET/" backend.tf.example > backend.tf
```

**2. Fill in your values.**

Copy the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Each value is described in the file. The required ones are not commented out, and hold an UPPERCASE placeholder until you replace it. Terraform does not notice one left behind, so **3. Preview** below checks for them before the plan.

Replace:

- `project_id`: the logging project's ID: an existing one, or the one to create

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

To use a project you already have, set `project_id` to its ID and leave `create_project` out. To create the project
too, set:

```hcl
create_project = true
project_id     = "LOGGING_PROJECT_ID"
org_id         = "ORG_ID"
```

with LOGGING_PROJECT_ID the new project's ID (6 to 30 characters, lowercase, unique across Google Cloud) and ORG_ID
your organization's. Add `billing_account_id = "BILLING_ACCOUNT_ID"` only if the project should be billed: the
pipeline delivers without billing, but an API that requires billing cannot be enabled without it.
`deletion_policy` defaults to **PREVENT**, which is right for a project holding an audit pipeline.

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(LOGGING_PROJECT_ID|ORG_ID|PROJECT_ID)\b' terraform.tfvars
```

Download the providers and connect to the state bucket:

```bash
terraform init
```

Preview, and save the plan:

```bash
terraform plan -out=abstract.tfplan
```

Apply exactly that plan. It creates what the plan listed; **To remove it later**, below, says how to take it away:

```bash
terraform apply abstract.tfplan
```
<!-- /abstract:tfapply -->

Print what Terraform could not check for you (read-only). You should see the grants it cannot verify, including
`roles/logging.configWriter` at the organization, the one that actually blocks people:

```bash
terraform output preflight
```

<!-- abstract:tfremove -->
**To remove it later**, run `terraform destroy` in this folder with the same `backend.tf`.

terraform destroy never deletes the logging project: a project it created has deletion_policy PREVENT, and the APIs stay on (disable_on_destroy = false). Delete the project yourself in the console only when nothing else uses it; Google keeps it recoverable for 30 days.
<!-- /abstract:tfremove -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects)
- [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project)
- [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling)
- [google_project_service](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_service)
- [Overview of Terraform on Google Cloud](https://docs.cloud.google.com/docs/terraform/terraform-overview)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
