<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Export GCP billing account audit logs to Abstract Security

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

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

## Choose the billing account

Pick the billing account explicitly: an organization often has several, and taking the first one listed can export the wrong account.

```bash
gcloud billing accounts list --filter=open=true --format='table(name.basename():label=ID,displayName)'
```

Set the ID you chose (the format is `XXXXXX-XXXXXX-XXXXXX`). The commands below use it:

```bash
BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX
```

Check the permissions on it. The check that matters is **`roles/logging.configWriter` on the BILLING ACCOUNT**. If you lack this role, a Billing Account Administrator must grant it:

```bash
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT_ID"
gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT_ID" \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/logging.configWriter"
```

Ensure the required APIs are enabled in your logging project:

```bash
gcloud services enable pubsub.googleapis.com logging.googleapis.com --project="$LOG_PROJECT"
```

## Inspect the configuration and filter

Cloud Billing writes Admin Activity audit logs (IAM policy changes, project billing links and unlinks, account create, close, reopen, rename and move) and Data Access audit logs, and no System Event logs ([Cloud Billing audit logging](https://docs.cloud.google.com/billing/docs/audit-logging)). This deployment routes Admin Activity (`admin_activity`).

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

Inspect output identities:

```bash
terraform output -raw sink_writer_identity
terraform output -raw topic_id
```

```bash
# 1. The billing sink exists and points to Pub/Sub
gcloud logging sinks describe abstract-billing-audit-sink \
  --billing-account="$BILLING_ACCOUNT_ID" \
  --format="value(name,destination,writerIdentity)"

# 2. The writer identity actually holds publisher on the topic. THE most-skipped
#    step, and the sink reports healthy without it.
gcloud pubsub topics get-iam-policy abstract-billing-audit-logs --project="$LOG_PROJECT"

# 3. GCP tells you about this failure directly — check for sink errors
gcloud logging read 'logName:"logging.googleapis.com%2Fsink_error"' \
  --limit=20 --project="$LOG_PROJECT"
```

### Pull test messages

Check delivery on a probe subscription, never on Abstract's:

```bash
# Never pull from abstract-billing-audit-logs-sub: with --auto-ack that deletes events before Abstract
# reads them, and without it hides them from Abstract for the ack deadline.
# Pull from a throwaway subscription on the same topic instead. Create it BEFORE the
# test event: a new subscription only receives messages published after it exists.
PROBE="abstract-probe-$(date +%s)"
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-billing-audit-logs \
  --project="$LOG_PROJECT" --expiration-period=1d --message-retention-duration=10m
# Billing events are rare: make one on the billing account (for example rename it in
# the console, which writes an UpdateBillingAccountDisplayName Admin Activity entry),
# then wait.
for i in $(seq 1 20); do
  sleep 15
  N=$(gcloud pubsub subscriptions pull "$PROBE" --project="$LOG_PROJECT" --limit=1000 --auto-ack --format="value(ackId)" 2>/dev/null | grep -c .)
  [ "${N:-0}" -gt 0 ] && { echo "FOUND: $N message(s) reached the topic"; break; }
done
gcloud pubsub subscriptions delete "$PROBE" --project="$LOG_PROJECT" --quiet
```

<walkthrough-info-message>GCP has a **first-class health signal for its own main failure mode**. A sink whose writer identity lacks `pubsub.publisher` produces `exports/error_count`, a `sink_error` log entry, **and a daily `[ACTION REQUIRED]` email**.</walkthrough-info-message>

## Connect Abstract

Retrieve the onboarding output:

```bash
terraform output abstract_onboarding
```

You need two values, plus a key:

* **Project ID** — the project holding the **subscription** (`$LOG_PROJECT`), not the billing account.
* **Subscription ID** — `abstract-billing-audit-logs-sub`.
* **Service-account key** — create it, upload it to Abstract, then delete the local copy:

```bash
export SA_EMAIL=$(terraform output -raw service_account_email)
mkdir -p ~/abstract-keys && chmod 700 ~/abstract-keys   # outside the repo clone
gcloud iam service-accounts keys create ~/abstract-keys/abstract-billing-key.json \
  --iam-account="$SA_EMAIL" \
  --project="$LOG_PROJECT"
chmod 600 ~/abstract-keys/abstract-billing-key.json
```

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

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=<project-id-with-billing>` to put the bucket in a project that has it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-billing-account-logs"
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

**To remove it later**, delete the integration in Abstract first. The topic, the subscription and the sink carry `prevent_destroy`, so a stray `terraform destroy`, or a rename that would replace them, cannot drop security logs Abstract has not read yet; `terraform destroy` on its own is refused. Take them out of the state, destroy the rest, then delete them with gcloud, the sink first so nothing is written to a topic that is about to go, then the subscription, then the topic. Use your own names if you changed them in terraform.tfvars:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-billing-account-logs"
terraform state rm 'module.log_export.google_pubsub_topic.abstract' 'module.log_export.google_pubsub_subscription.abstract' 'module.log_export.google_logging_billing_account_sink.abstract[0]'
terraform destroy
gcloud logging sinks delete abstract-billing-audit-sink --billing-account=<billing-account-id>
gcloud pubsub subscriptions delete abstract-billing-audit-logs-sub --project=<log-project-id>
gcloud pubsub topics delete abstract-billing-audit-logs --project=<log-project-id>
```
<!-- /abstract:terraform -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up:

- [gcloud logging sinks create](https://docs.cloud.google.com/sdk/gcloud/reference/logging/sinks/create#--billing-account)
- [Cloud Billing audit logging](https://docs.cloud.google.com/billing/docs/audit-logging)
- [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth)
- [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
