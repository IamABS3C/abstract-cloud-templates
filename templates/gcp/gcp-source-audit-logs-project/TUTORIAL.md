<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Single-project pilot

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

<walkthrough-info-message>**This does not cover future projects.** A project sink has no
`include_children`, because nothing exists below a project. This is a pilot — it shows the
pipeline working, from the sink to events in Abstract, before you ask for organization-scope
IAM, which is usually the real blocker.</walkthrough-info-message>

Choosing this directory *is* the acknowledgement — the module normally refuses project
scope without one.

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

## Choose the project

Script step 1 asks which project to pilot: choose the one running the workload, whose logs you want to see. Script
step 3 asks for the logging project, which holds the topic and subscription; for a pilot it may be the same project.

<!-- abstract:deploy -->
## Deploy

Run script steps 3, 4 and 5 of the guided setup: the logging project, then the pipeline, then the account Abstract reads with. Script step 4 prints the sink's filter before it asks to create the sink. Script step 9 then sends a test event and checks it reaches the topic from the sink, and script step 10 prints the values to enter in Abstract and the commands that download the key from this temporary session. Delete every copy of the key once Abstract has it. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing. [Clean up](#clean-up), below, undoes what it made.

Go to the top folder of the templates repository; the guided-setup commands run from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

Script step 3: the logging project, its billing and APIs.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
```

Script step 4: the topic, the subscription and the sink.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
```

Script step 5: the account Abstract reads with, and its key.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
```

Script step 9: a test event, from the sink to the topic.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
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

## Verify

Before you replace the pilot, confirm it delivers. These read, and change nothing; they use SCOPE_ID (the piloted
project) and LOG_PROJECT from the answers file loaded at the end of Deploy.

The sink exists on the piloted project and sends to the topic. You should see abstract-org-audit-sink and the topic
in your logging project:

```bash
gcloud logging sinks describe abstract-org-audit-sink --project="$SCOPE_ID" --format="value(name,destination)"
```

Script step 9, run in Deploy, is the test that proves delivery: a ✓ "the test event arrived" within five minutes.
Then Abstract shows the integration's events, once it is connected with the values script step 10 printed.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

## Then replace it

Once you have proven the pipeline and obtained `roles/logging.configWriter` at the
organization, deploy `gcp-source-audit-logs-organization` and **delete this sink**.

**Do not repeat this per project.** Seventy project sinks is exactly the linear toil the
aggregated sink exists to eliminate — and each one silently decays as projects change.

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
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-project"
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

- `sink_project`: the ID of the workload project whose logs the pilot exports
- `log_project`: your logging project ID (LOG_PROJECT; `echo "$LOG_PROJECT"` prints it)

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

`sink_project` is the project whose logs you are piloting, the one running the workload; it has no default, so a
pilot never exports an empty logging project by accident. `log_project` holds the topic and subscription; for a pilot
it may be the same project.

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(LOGGING_PROJECT_ID|WORKLOAD_PROJECT_ID)\b' terraform.tfvars
```

Download the providers and connect to the state bucket:

```bash
terraform init
```

Preview, and save the plan. It ends with the outputs, `effective_filter` among them: the filter the sink will use, which decides your coverage and your bill:

```bash
terraform plan -out=abstract.tfplan
```

Apply exactly that plan. It creates what the plan listed; **To remove it later**, below, says how to take it away:

```bash
terraform apply abstract.tfplan
```

Print the filter the sink uses (read-only). You should see one Cloud Logging filter, naming the audit logs (`cloudaudit.googleapis.com`) and any other sources you chose; it is the filter that decides your coverage and your bill:

```bash
terraform output -raw effective_filter
```

**4. Connect Abstract.** Terraform makes no key for Abstract, so no key sits in the state; make it with gcloud, once.

Print the values for Abstract (read-only):

```bash
terraform output abstract_onboarding
```

You should see `project_id`, your logging project: enter it as **Project ID** in Abstract's GCP Pub/Sub Source. `subscription_id` is the **Subscription ID**, the short name. `service_account_email` is the account the key below belongs to.

Keep the reader account's email in SA_EMAIL:

```bash
export SA_EMAIL="$(terraform output -json abstract_onboarding | jq -r .service_account_email)"
```

Check it. You should see an address ending in @ and your logging project's ID, then .iam.gserviceaccount.com:

```bash
echo "Reader account: ${SA_EMAIL:?not set: run the apply first}"
```

Make a folder for the key outside the repository clone, readable only by you:

```bash
mkdir -m 700 -p ~/abstract-keys
```

Create the key, as a file only you can read. This adds one key to the reader account in your logging project; anyone holding the file can read the subscription. The last command in this step revokes it:

```bash
(umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-pubsub-key.json --iam-account="$SA_EMAIL" --project="$LOG_PROJECT")
```

In Cloud Shell, save it to your computer:

```bash
cloudshell download ~/abstract-keys/abstract-pubsub-key.json
```

Upload it to Abstract with the two values above. Once Abstract has saved the integration, delete the copy here, and the downloaded file on your computer:

```bash
rm -f ~/abstract-keys/abstract-pubsub-key.json
```

To revoke the key later (a rotation, or removing the integration), list the reader account's keys (read-only). The one Abstract holds has the ID in the `private_key_id` of the file you uploaded:

```bash
gcloud iam service-accounts keys list --iam-account="$SA_EMAIL" --project="$LOG_PROJECT" --managed-by=user
```

Then delete it, replacing KEY_ID with that ID. Abstract can no longer read from that moment; nothing else changes:

```bash
gcloud iam service-accounts keys delete KEY_ID --iam-account="$SA_EMAIL" --project="$LOG_PROJECT"
```
<!-- /abstract:tfapply -->

<!-- abstract:tfremove -->
**To remove it later**, delete the integration in Abstract first. The topic, the subscription and the sink carry `prevent_destroy`, so a stray `terraform destroy`, or a rename that would replace them, cannot drop security logs Abstract has not read yet; `terraform destroy` on its own is refused. Take them out of the state, destroy the rest, then delete them with gcloud, the sink first so nothing is written to a topic that is about to go, then the subscription, then the topic. Use your own names if you changed them in terraform.tfvars.

The commands below use the guided setup's answers (LOG_PROJECT, ORG_ID, SCOPE_ID), saved in `~/.abstract-gcp-setup.env`. Load them in this terminal; without the guided setup, `export` each one instead:

```bash
source ~/.abstract-gcp-setup.env
```

In this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-project"
```

Take them out of the state (this deletes nothing):

```bash
terraform state rm 'module.log_export.google_pubsub_topic.abstract' 'module.log_export.google_pubsub_subscription.abstract' 'module.log_export.google_logging_project_sink.abstract[0]'
```

Destroy the rest of what this template built (Terraform lists it and asks first):

```bash
terraform destroy
```

Delete the sink abstract-org-audit-sink, so nothing more is written to the topic:

```bash
gcloud logging sinks delete abstract-org-audit-sink --project="$SCOPE_ID" --quiet
```

Delete the subscription abstract-audit-logs-sub, and every event in it not yet read:

```bash
gcloud pubsub subscriptions delete abstract-audit-logs-sub --project="$LOG_PROJECT" --quiet
```

Delete the topic abstract-audit-logs:

```bash
gcloud pubsub topics delete abstract-audit-logs --project="$LOG_PROJECT" --quiet
```
<!-- /abstract:tfremove -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)
- [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#creating_sink)
- [Logging query language](https://docs.cloud.google.com/logging/docs/view/logging-query-language)
- [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)
- [logging_project_sink](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_project_sink)
- [pubsub_topic_iam](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam)
- [google_service_account_key](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account_key)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
