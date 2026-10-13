<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Export GCP audit logs to Abstract Security

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

This sets up **one aggregated log sink at organization scope**. It covers every project
you have today and every project created in future, automatically — because the sink's
scope is defined by *containment*, not by a list of projects.

There is nothing to repeat per project, and nothing to re-run when a project is added.

**What gets created:**

* A Pub/Sub topic and a pull subscription in a logging project you choose
* An aggregated Cloud Logging sink at organization scope with `--include-children`
* The `roles/pubsub.publisher` binding for the sink's writer identity — **the step
  that is skipped most often, and the number-one cause of a healthy-looking sink that
  delivers nothing**
* A service account for Abstract with `roles/pubsub.subscriber` on the subscription only

## Before you start

<walkthrough-project-setup></walkthrough-project-setup>

You need three things. **The first is usually the blocker, and it is rarely technical:**

1. **`roles/logging.configWriter` at ORGANIZATION scope.** Whoever owns a project
   almost never holds this. Find that person before you go further.
2. `roles/pubsub.admin` on the logging project.
3. Your organization ID: `gcloud organizations list`

If you are not in an organization, an aggregated sink is not available. Stop here and talk
to whoever owns the GCP hierarchy.

<walkthrough-info-message>Use a **dedicated logging or security project**, not a workload
project. Pub/Sub publish quota is consumed in the destination project, and a security
pipeline living inside a workload project can be read or broken by that workload's
owner.</walkthrough-info-message>

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

## Decide the filter

Script step 4, in [Deploy](#deploy) below, prints the filter (the line that starts `filter:`) before it asks to create
the sink. Read it there: that filter decides both your coverage and your bill. [Verify](#verify) shows how to print the
filter the sink uses at any time.

<walkthrough-info-message>**Routing is evaluated at write time and there is no backfill.**
A filter that was too narrow leaves a permanent hole you cannot fill later. One that was
too wide costs money you can stop spending. Start broad, measure for 7 days, then
tighten.</walkthrough-info-message>

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

<walkthrough-info-message>**A sink is not live the instant the deploy finishes.** Routing is
evaluated at WRITE TIME, so events written during the first couple of minutes after the
sink is created are simply never routed — and no later change recovers
them.</walkthrough-info-message>

Measured against a live organization on 2026-08-26:

| Event written | Result |
|---|---|
| ~30 s after `CreateSink` | **never delivered** |
| ~2 min after | **never delivered** |
| ~3 min after | delivered, ~60 s end to end |

**This is the single most likely reason you conclude a working pipeline is broken.** You
apply, immediately generate a test event, see nothing, and start pulling the deployment
apart. Give it **five minutes**, then generate a *fresh* event — do not keep re-checking
for the one you fired at t+0, because it was never routed and never will be.

In steady state, delivery here took around a minute.

### Verify, cloud side first

Check the cloud before you check Abstract. Each step isolates one layer, so a failure
localises instead of becoming a debate.

These read, and change nothing. They use ORG_ID and LOG_PROJECT from the answers file loaded at the end of Deploy.

The sink exists and is aggregated: the second value printed must be True. Without includeChildren it is a plain
organization sink that carries only the organization's own logs, not the projects', which looks almost identical
until you notice what is missing:

```bash
gcloud logging sinks describe abstract-org-audit-sink --organization="$ORG_ID" --format="value(name,includeChildren,destination)"
```

The filter the sink uses. You should see `logName:` clauses for `cloudaudit.googleapis.com` (activity, system_event and
policy), and a `data_access` clause only if script step 6 added one:

```bash
gcloud logging sinks describe abstract-org-audit-sink --organization="$ORG_ID" --format='value(filter)'
```

The sink's writer identity holds roles/pubsub.publisher on the topic. It is the most-skipped step, and the sink
reports healthy without it. You should see the sink's identity (serviceAccount:…@gcp-sa-logging.iam.gserviceaccount.com)
under roles/pubsub.publisher:

```bash
gcloud pubsub topics get-iam-policy abstract-audit-logs --project="$LOG_PROJECT"
```

Google records a sink's delivery failures as log entries. Nothing printed means no failure was recorded:

```bash
gcloud logging read 'logName:"logging.googleapis.com%2Fsink_error"' --limit=20 --project="$LOG_PROJECT"
```

### The test that actually proves it

Everything above can pass while nothing flows. Script step 9 of the guided setup is the check that does not: it
subscribes a throwaway probe subscription to the topic (never Abstract's), writes a fresh Admin Activity event
inside your scope, and waits up to five minutes for it. It reads your scope and logging project from the answers
file; if you deployed with Terraform and never ran the guided setup, run script steps 1 and 3 first, which record
and check what exists. From the top folder of the repository:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
```

Never pull from `abstract-audit-logs-sub` yourself: Abstract reads that subscription, and `--auto-ack` there deletes events before Abstract sees them. The probe subscription step 9 makes is its own, and is deleted when the test ends.

A ✓ "the test event arrived" within five minutes proves the sink routes and the topic delivers. It does not
prove Abstract stores the events: check that in Abstract once the integration is connected.

<walkthrough-info-message>GCP is the only major cloud with a **first-class health signal
for its own main failure mode**. A sink whose writer identity lacks `pubsub.publisher`
produces `exports/error_count`, a `sink_error` log entry, **and a daily `[ACTION
REQUIRED]` email**.</walkthrough-info-message>

## Connect Abstract

In Abstract, add the **GCP Pub/Sub Source** integration. Script step 10 printed the three things it needs:

* **Project ID** — the project holding the **subscription**, not the projects generating
  logs. With an org-level sink the logs come from dozens of projects while the
  subscription lives in one. This is the field filled in wrong most often.
* **Subscription ID** — `abstract-audit-logs-sub`, the short name only, not the `projects/.../subscriptions/...` path.
* **Credentials** — `abstract-pubsub-key.json`, the key script step 5 made. Script step 10 printed the
  `cloudshell download` line that saves it to your computer. Once Abstract has saved the integration, delete every
  copy: `rm -f ~/abstract-keys/abstract-pubsub-key.json` here, and the downloaded file.

Deployed with [Terraform instead](#terraform-instead)? Its step 4 prints these values and makes the key.

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Your whole organization now exports audit logs to Abstract, and **any project created
from now on is covered the moment it exists**.

**One thing this did not do:** Data Access audit logs are off by default for every service except
BigQuery, which writes its Data Access logs by default. Two switches turn them on, and either alone does nothing:
the audit settings make Google write them, and the sink's filter routes them. Script step 6 of the guided setup
(`./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6`) does both, saves a copy of your audit settings first,
and asks before each change; the Terraform equivalent is `gcp-foundation-data-access-audit-logs`. It is an
organization-wide change and the cost driver of the whole pipeline: each service and log type you add is billed
by Cloud Logging and adds volume, with `DATA_READ` the largest by far, so start with the services script step 6
suggests.

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
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-organization"
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

- `org_id`: your organization ID (ORG_ID; `echo "$ORG_ID"` prints it)
- `log_project`: your logging project ID (LOG_PROJECT; `echo "$LOG_PROJECT"` prints it)

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(LOGGING_PROJECT_ID|ORG_ID)\b' terraform.tfvars
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
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-organization"
```

Take them out of the state (this deletes nothing):

```bash
terraform state rm 'module.log_export.google_pubsub_topic.abstract' 'module.log_export.google_pubsub_subscription.abstract' 'module.log_export.google_logging_organization_sink.abstract[0]'
```

Destroy the rest of what this template built (Terraform lists it and asks first):

```bash
terraform destroy
```

Delete the sink abstract-org-audit-sink, so nothing more is written to the topic:

```bash
gcloud logging sinks delete abstract-org-audit-sink --organization="$ORG_ID" --quiet
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
- [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks)
- [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth)
- [Logging query language](https://docs.cloud.google.com/logging/docs/view/logging-query-language)
- [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)
- [logging_organization_sink](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_organization_sink)
- [pubsub_topic_iam](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam)
- [google_service_account_key](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account_key)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
