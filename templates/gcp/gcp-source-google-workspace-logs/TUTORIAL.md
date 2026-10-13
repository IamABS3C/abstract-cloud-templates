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

## Choose the applications

Which Workspace applications Abstract reads is chosen in Abstract's integration form (Application Name), not in
Google Cloud. Start with Login, Admin, Token, SAML, User Accounts and Groups: the answer to "who signed in", which is
usually the whole ask. Add Drive and Gmail only after measuring; they dwarf everything else. Script step 7 asks for
the email of the Workspace admin Abstract acts as.

<!-- abstract:deploy -->
## Deploy

Run script steps 1, 3, 7 and 10 of the guided setup: your scope, the logging project, then the Workspace account. Script step 7 prints the Client ID and the scope a Workspace super admin enters, and script step 10 prints the values to enter in Abstract and the commands that download its key from this temporary session. Delete every copy of the key once Abstract has it. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing. [Clean up](#clean-up), below, undoes what it made.

Go to the top folder of the templates repository; the guided-setup commands run from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

Script step 1: your organization and scope.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
```

Script step 3: the logging project, its billing and APIs.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
```

Script step 7: the Workspace account and its key.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
```

Script step 10: the values to enter in Abstract.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
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

## Grant delegation (Workspace super admin)

Script step 7 printed a Client ID and one OAuth scope under "Hand this to a Workspace super admin". The super admin
opens **admin.google.com → Security → Access and data control → API controls → Domain-wide delegation → Add new**,
and pastes the Client ID — the **numeric** ID, not the service-account email — and the scope exactly as printed
(`https://www.googleapis.com/auth/admin.reports.audit.readonly`, the only one Abstract requests). This lets the new
account read your Workspace audit reports as the admin you named, read-only, until a super admin removes the entry.

## Verify delegation

Do this before you upload or delete the key: the check signs in with the key file. Run script step 7 again in check
mode from the top folder of the repository. It changes nothing, and shows a ✓ "delegation works: the Reports API
answered as" your admin once the super admin's entry has taken effect, which can take a few minutes:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7 --check
```

If the Reports API returns **401**, the delegation has not propagated or the admin email is
not actually an admin. Delegation impersonates a real user — without a valid subject you
get 401, not an empty result.

## Connect Abstract

In Abstract, add the **Google Workspace Audit Log Integration** with the values script step 10 printed: the admin
email, and `abstract-workspace-key.json`, the key script step 7 made. Script step 10 also printed the
`cloudshell download` line that saves the key to your computer. Google Workspace login events appear in Abstract's
event search; Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

The key carries domain-wide delegation. Once Abstract has saved the integration, **delete every copy**: this one
here, and the downloaded file on your computer.

```bash
rm -f ~/abstract-keys/abstract-workspace-key.json
```

With the file gone, script step 7 says the key made for Abstract still exists in Google and makes no other. It
makes a second key only when you ask for one with `--step 7 --new-key` (a lost key, or a rotation), and then names
the old key to revoke.

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

Go to this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-google-workspace-logs"
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

- `log_project`: your logging project ID (LOG_PROJECT; `echo "$LOG_PROJECT"` prints it)
- `workspace_admin_email`: the email of a Workspace admin Abstract acts as

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

`workspace_admin_email` is the Workspace admin Abstract acts as, for example ADMIN_EMAIL, an admin's address in your
domain. `workspace_app_groups` chooses which application groups the outputs list; `identity` (`login`, `saml`,
`token`, `user_accounts`, `context_aware_access`) is usually the whole ask:

```hcl
workspace_admin_email = "ADMIN_EMAIL"
workspace_app_groups  = ["identity", "admin"]
```

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(ADMIN_EMAIL|LOGGING_PROJECT_ID|WORKSPACE_ADMIN_EMAIL)\b' terraform.tfvars
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

**4. Delegation, key, then Abstract.** Print the service account, its numeric client ID and the scope (read-only):

```bash
terraform output workspace_onboarding
```

A Workspace super admin enters the `client_id` and the scope as [Grant delegation](#grant-delegation-workspace-super-admin)
describes. With `include_directory_enrichment_scopes = true` the scopes are printed comma-separated with no spaces;
paste them as printed.

Keep the service account's email in SA (`-json | jq`, because `-raw` errors on an object output):

```bash
export SA="$(terraform output -json workspace_onboarding | jq -r .service_account_email)"
```

Check it. You should see abstract-workspace-reader@ and your logging project's ID:

```bash
echo "Workspace reader: ${SA:?not set: run the apply first}"
```

Make a folder for the key outside the repository clone, readable only by you:

```bash
mkdir -m 700 -p ~/abstract-keys
```

Create the key, as a file only you can read. This adds one key to the Workspace reader account in your logging
project; with the delegation, anyone holding the file can read your Workspace audit reports. The last command here
revokes it:

```bash
(umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-workspace-key.json --iam-account="$SA" --project="$LOG_PROJECT")
```

In Cloud Shell, save it to your computer:

```bash
cloudshell download ~/abstract-keys/abstract-workspace-key.json
```

Upload it to Abstract with the admin email. Once Abstract has saved the integration, delete the copy here, and the
downloaded file on your computer:

```bash
rm -f ~/abstract-keys/abstract-workspace-key.json
```

To revoke the key later, list the account's keys (read-only); the one Abstract holds has the ID in the
`private_key_id` of the file you uploaded:

```bash
gcloud iam service-accounts keys list --iam-account="$SA" --project="$LOG_PROJECT" --managed-by=user
```

Then delete it, replacing KEY_ID with that ID:

```bash
gcloud iam service-accounts keys delete KEY_ID --iam-account="$SA" --project="$LOG_PROJECT"
```

<!-- abstract:tfremove -->
**To remove it later**, run `terraform destroy` in this folder with the same `backend.tf`.
<!-- /abstract:tfremove -->

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
