<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Export GCP billing account audit logs to Abstract Security

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

<!-- abstract:needs -->
**This page uses Terraform, because a billing account is not inside your organization, so the guided script's sink cannot reach it: the template puts a sink on the billing account itself.**

Needs: Terraform (Cloud Shell has it), a Cloud Storage bucket for its state (the Terraform section creates it), and the roles under [Check first](#check-first). [Deploy with Terraform](#deploy-with-terraform), at the end of this page, deploys it.
<!-- /abstract:needs -->

This sets up a **dedicated Cloud Logging sink on your GCP Cloud Billing Account**.

**An organization sink routes the organization and the folders and projects under it; a billing account is a separate resource, so its logs are collected with a sink created on the billing account itself.**

**What gets created:**

* A Pub/Sub topic and a pull subscription in a logging project you choose
* A Cloud Logging sink bound directly to the Billing Account
* The `roles/pubsub.publisher` binding for the sink's writer identity — **the step that is skipped most often, and the number-one cause of a healthy-looking sink that delivers nothing**
* A service account for Abstract with `roles/pubsub.subscriber` on the subscription only

## Before you start

<walkthrough-project-setup></walkthrough-project-setup>

You need three things. **The first is usually the blocker, and it is rarely technical:**

1. **`roles/logging.configWriter` on the BILLING ACCOUNT.** Organization Administrator (`roles/resourcemanager.organizationAdmin`) or Project Owner does not grant this. Find your Billing Account Administrator before you go further.
2. `roles/pubsub.admin` on the logging project.
3. Your billing account ID: `gcloud billing accounts list`

If the list is empty you do not have access to any billing accounts. Stop here and request access from your billing administrator.

<walkthrough-info-message>Use a **dedicated logging or security project**, not a workload project. Pub/Sub publish quota is consumed in the destination project, and a security pipeline living inside a workload project can be read or broken by that workload's owner.</walkthrough-info-message>

<!-- abstract:signin -->
## Sign in first

Cloud Shell opened the public templates repository in a **temporary** session. Google gives a repository it does not own none of your credentials, and deletes the session's files when it ends. Sign in; `--update-adc` gives the scripts and Terraform the same sign-in:

```bash
gcloud auth login --update-adc
```
<!-- /abstract:signin -->

<!-- abstract:check -->
## Check first

Read-only, except the role grants at the end, which say what they add. The estate audit lists your organization, folders, projects, and the log sinks and topics you already have. Script step 1 of the guided setup records your organization and scope (ORG_ID, SCOPE_ID) in its answers file, `~/.abstract-gcp-setup.env`.

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

Load the answers into this terminal. It sets ORG_ID, and LOG_PROJECT if you ran the guided setup's script step 3 before:

```bash
source ~/.abstract-gcp-setup.env
```

This page also needs your logging project, the project that holds the topic and subscription. Check both are set. You should see your organization's number and your logging project's ID; "not set" names what to do:

```bash
echo "Organization: ${ORG_ID:?not set: run script step 1} Logging project: ${LOG_PROJECT:?not set: export LOG_PROJECT=LOGGING_PROJECT_ID}"
```

Only if it said the logging project is not set (you have not run script step 3): set it yourself, replacing LOGGING_PROJECT_ID with its ID, then run the check above again:

```bash
export LOG_PROJECT=LOGGING_PROJECT_ID
```

### The roles this page needs

The guided setup's own grant option covers only the roles its script steps need, not these. The person who deploys this template needs:

- `roles/logging.configWriter` on the billing account: Create the billing-account sink.
- `roles/pubsub.admin` on the logging project: Create the topic, subscription and IAM bindings.
- `roles/iam.serviceAccountAdmin` on the logging project: Create Abstract's service account.
- `roles/serviceusage.serviceUsageAdmin` on the logging project: Turn on the APIs this template uses. Terraform reads which are on and turns on only those still off.

Someone who can set IAM policy there adds each as one binding; nothing else in the policy changes. Replace PRINCIPAL with the person who deploys: `user:` and their email, `group:` and a group's email, or `serviceAccount:` and a service account's email.

Add `roles/logging.configWriter` for PRINCIPAL on the billing account (replace BILLING_ACCOUNT_ID with its ID, from `gcloud billing accounts list`):

```bash
gcloud billing accounts add-iam-policy-binding BILLING_ACCOUNT_ID --member="PRINCIPAL" --role="roles/logging.configWriter"
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud billing accounts remove-iam-policy-binding BILLING_ACCOUNT_ID --member="PRINCIPAL" --role="roles/logging.configWriter"
```

Add `roles/pubsub.admin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/pubsub.admin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/pubsub.admin" --condition=None
```

Add `roles/iam.serviceAccountAdmin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/iam.serviceAccountAdmin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/iam.serviceAccountAdmin" --condition=None
```

Add `roles/serviceusage.serviceUsageAdmin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/serviceusage.serviceUsageAdmin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/serviceusage.serviceUsageAdmin" --condition=None
```

Removing this template later (**To remove it later**, at the end of the page) needs these roles again: add them back with the same commands first.
<!-- /abstract:check -->

## Choose the billing account

Pick the billing account explicitly: an organization often has several, and taking the first one listed can export the wrong account. List the open ones you can see (read-only):

```bash
gcloud billing accounts list --filter=open=true --format='table(name.basename():label=ID,displayName)'
```

Keep the ID you chose in BILLING_ACCOUNT_ID for the commands below: it is the same ID the role commands under Check
first name as BILLING_ACCOUNT_ID. Replace XXXXXX-XXXXXX-XXXXXX with it (that is
its format):

```bash
BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX
```

Check the permissions on it (read-only). The check that matters is **`roles/logging.configWriter` on the BILLING
ACCOUNT**: look for your account under that role:

```bash
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT_ID"
```

If you lack it, a Billing Account Administrator adds it for you: [The roles this page needs](#the-roles-this-page-needs),
under Check first, gives the command that adds it for the person who deploys, and the one that takes it back.

Turn on the Pub/Sub and Cloud Logging APIs in your logging project. Script step 3 does the same. An API already on
stays on, and nothing else changes; to undo it, `gcloud services disable` with the same API names and `--project`,
only if nothing else in the project uses them:

```bash
gcloud services enable pubsub.googleapis.com logging.googleapis.com --project="$LOG_PROJECT"
```

## Inspect the configuration and filter

Cloud Billing writes Admin Activity audit logs (IAM policy changes, project billing links and unlinks, account create, close, reopen, rename and move) and Data Access audit logs, and no System Event logs ([Cloud Billing audit logging](https://docs.cloud.google.com/billing/docs/audit-logging)). This template's default `log_categories` routes the billing account's Admin Activity logs (`cloudaudit.googleapis.com%2Factivity`) only.

Read the filter before applying: routing is evaluated at write time and there is no backfill.

<walkthrough-info-message>**Routing is evaluated at write time and there is no backfill.**
A filter that was too narrow leaves a permanent hole you cannot fill later. The default configuration routes all Admin Activity audit logs from the billing account.</walkthrough-info-message>

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

<walkthrough-info-message>**A sink is not live the instant the deploy finishes.** Routing is
evaluated at WRITE TIME, so events written during the first couple of minutes after the
sink is created are simply never routed — and no later change recovers
them.</walkthrough-info-message>

Measured against a live GCP environment:

| Event written | Result |
|---|---|
| ~30 s after `CreateSink` | **never delivered** |
| ~2 min after | **never delivered** |
| ~3 min after | delivered, ~60 s end to end |

**This is the single most likely reason you conclude a working pipeline is broken.** You apply, immediately check for events, see nothing, and start pulling the deployment apart. Give it **five minutes**, then check for new events.

### Verify, cloud side first

Check the cloud before you check Abstract. Each step isolates one layer, so a failure localizes instead of becoming a debate.

These read, and change nothing. In this template's folder, print the sink's writer identity:

```bash
terraform output -raw sink_writer_identity
```

and the topic it publishes to:

```bash
terraform output -raw topic_id
```

The billing sink exists and points to Pub/Sub. You should see abstract-billing-audit-sink, the topic and the same
writer identity:

```bash
gcloud logging sinks describe abstract-billing-audit-sink --billing-account="$BILLING_ACCOUNT_ID" --format="value(name,destination,writerIdentity)"
```

The writer identity holds roles/pubsub.publisher on the topic. It is the most-skipped step, and the sink reports
healthy without it. You should see the writer identity under roles/pubsub.publisher:

```bash
gcloud pubsub topics get-iam-policy abstract-billing-audit-logs --project="$LOG_PROJECT"
```

Google records a sink's delivery failures as log entries. Nothing printed means no failure was recorded:

```bash
gcloud logging read 'logName:"logging.googleapis.com%2Fsink_error"' --limit=20 --project="$LOG_PROJECT"
```

### Pull test messages

Check delivery on a probe subscription of your own, never on Abstract's: pulling from
abstract-billing-audit-logs-sub with `--auto-ack` deletes events before Abstract reads them, and without it hides
them from Abstract for the ack deadline. A new subscription only receives messages published after it exists, so
create it before the test event.

Name the probe subscription:

```bash
PROBE="abstract-probe-$(date +%s)"
```

Create it on the billing topic, in the logging project. It keeps messages for 10 minutes and deletes itself after
a day; the last command below deletes it sooner:

```bash
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-billing-audit-logs --project="$LOG_PROJECT" --expiration-period=1d --message-retention-duration=10m
```

Billing events are rare, and the three checks above already prove the sink, its destination and the grant without
one. A live event is optional. The only harmless one is the billing account's owner renaming it and then renaming it
back: it is the Billing Account Administrator's decision, not yours, because everyone who uses the account sees the
name ([Modify your Cloud Billing account](https://docs.cloud.google.com/billing/docs/how-to/modify-billing-account#rename_account)).
Each rename writes an UpdateBillingAccountDisplayName Admin Activity entry. If they agree, they rename it in the
console (Billing, Account management), then rename it back to exactly the old name, and you pull from the probe every
minute or so, for up to five minutes. A line with an ackId means a message reached the topic; nothing yet means wait
and pull again:

```bash
gcloud pubsub subscriptions pull "$PROBE" --project="$LOG_PROJECT" --limit=1000 --auto-ack --format="value(ackId)"
```

Delete the probe subscription:

```bash
gcloud pubsub subscriptions delete "$PROBE" --project="$LOG_PROJECT" --quiet
```

<walkthrough-info-message>GCP has a **first-class health signal for its own main failure mode**. A sink whose writer identity lacks `pubsub.publisher` produces `exports/error_count`, a `sink_error` log entry, **and a daily `[ACTION REQUIRED]` email**.</walkthrough-info-message>

## Connect Abstract

[Deploy with Terraform](#deploy-with-terraform), step 4, prints the values and makes the key. In Abstract's GCP
Pub/Sub Source:

* **Project ID** — the project holding the **subscription** (your logging project), not the billing account.
* **Subscription ID** — `abstract-billing-audit-logs-sub`.
* **Credentials** — `abstract-billing-key.json`, the key step 4 makes. Delete every copy once Abstract has it.

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Your Cloud Billing Account now exports audit logs to Abstract Security via Pub/Sub.

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, if this piece feeds one. Then follow **To remove it later** at the end of [Deploy with Terraform](#deploy-with-terraform), with the same `backend.tf`.
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Deploy with Terraform

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=PROJECT_ID_WITH_BILLING`, with your own project ID, to put the bucket in a project that has it.

Go to this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-billing-account-logs"
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

- `billing_account_id`: the billing account's ID, from `gcloud billing accounts list`
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
grep -nE '^[^#]*\b(BILLING_ACCOUNT_ID|LOGGING_PROJECT_ID)\b' terraform.tfvars
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
(umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-billing-key.json --iam-account="$SA_EMAIL" --project="$LOG_PROJECT")
```

In Cloud Shell, save it to your computer:

```bash
cloudshell download ~/abstract-keys/abstract-billing-key.json
```

Upload it to Abstract with the two values above. Once Abstract has saved the integration, delete the copy here, and the downloaded file on your computer:

```bash
rm -f ~/abstract-keys/abstract-billing-key.json
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
**To remove it later**, delete the integration in Abstract first. The topic, the subscription and the sink carry `prevent_destroy`, so a stray `terraform destroy`, or a rename that would replace them, cannot drop security logs Abstract has not read yet; `terraform destroy` on its own is refused. Take them out of the state, destroy the rest, then delete them with gcloud, the sink first so nothing is written to a topic that is about to go, then the subscription, then the topic. Use your own names if you changed them in terraform.tfvars. Replace BILLING_ACCOUNT_ID with the billing account the sink is on.

The commands below use the guided setup's answers (LOG_PROJECT, ORG_ID, SCOPE_ID), saved in `~/.abstract-gcp-setup.env`. Load them in this terminal; without the guided setup, `export` each one instead:

```bash
source ~/.abstract-gcp-setup.env
```

In this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-billing-account-logs"
```

Take them out of the state (this deletes nothing):

```bash
terraform state rm 'module.log_export.google_pubsub_topic.abstract' 'module.log_export.google_pubsub_subscription.abstract' 'module.log_export.google_logging_billing_account_sink.abstract[0]'
```

Destroy the rest of what this template built (Terraform lists it and asks first):

```bash
terraform destroy
```

Delete the sink abstract-billing-audit-sink, so nothing more is written to the topic:

```bash
gcloud logging sinks delete abstract-billing-audit-sink --billing-account=BILLING_ACCOUNT_ID --quiet
```

Delete the subscription abstract-billing-audit-logs-sub, and every event in it not yet read:

```bash
gcloud pubsub subscriptions delete abstract-billing-audit-logs-sub --project="$LOG_PROJECT" --quiet
```

Delete the topic abstract-billing-audit-logs:

```bash
gcloud pubsub topics delete abstract-billing-audit-logs --project="$LOG_PROJECT" --quiet
```
<!-- /abstract:tfremove -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up:

- [gcloud logging sinks create](https://docs.cloud.google.com/sdk/gcloud/reference/logging/sinks/create#--billing-account)
- [Cloud Billing audit logging](https://docs.cloud.google.com/billing/docs/audit-logging)
- [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth)
- [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)
- [Cloud Billing access control and permissions](https://docs.cloud.google.com/billing/docs/how-to/billing-access)
- [Modify your Cloud Billing account](https://docs.cloud.google.com/billing/docs/how-to/modify-billing-account#rename_account)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
