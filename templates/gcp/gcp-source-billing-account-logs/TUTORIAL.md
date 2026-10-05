<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Export GCP billing account audit logs to Abstract Security

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

This sets up a **dedicated Cloud Logging sink on your GCP Cloud Billing Account**.

**GCP Billing Account audit logs sit outside the resource hierarchy entirely.** Organization, folder, and project sinks do **NOT** capture them. If you only deploy an organization sink, you will completely miss billing IAM changes and project billing associations.

**What gets created:**

* A Pub/Sub topic and a pull subscription in a logging project you choose
* A Cloud Logging sink bound directly to the Billing Account
* The `roles/pubsub.publisher` binding for the sink's writer identity — **the step that is skipped most often, and the number-one cause of a healthy-looking sink that delivers nothing**
* A service account for Abstract with `roles/pubsub.subscriber` on the subscription only

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Before you start

<walkthrough-project-setup></walkthrough-project-setup>

You need three things. **The first is usually the blocker, and it is rarely technical:**

1. **`roles/logging.configWriter` on the BILLING ACCOUNT.** Organization Administrator (`roles/resourcemanager.organizationAdmin`) or Project Owner does not grant this. Find your Billing Account Administrator before you go further.
2. `roles/pubsub.admin` on the logging project.
3. Your billing account ID: `gcloud billing accounts list`

<walkthrough-info-message>Use a **dedicated logging or security project**, not a workload project. Pub/Sub publish quota is consumed in the destination project, and a security pipeline living inside a workload project can be read or broken by that workload's owner.</walkthrough-info-message>

## Step 1 — Set your variables

List available billing accounts:

```bash
gcloud billing accounts list
```

Set the billing account ID and destination logging project. Pick the billing account explicitly: an organization often has several, and taking the first one listed can export the wrong account.

```bash
gcloud billing accounts list --filter=open=true --format='table(name.basename():label=ID,displayName)'
export BILLING_ACCOUNT_ID=""   # paste one ID from the list above
: "${BILLING_ACCOUNT_ID:?set BILLING_ACCOUNT_ID to one ID from the list above}"
gcloud billing accounts describe "$BILLING_ACCOUNT_ID" --format='value(displayName,open)'
export LOG_PROJECT=<walkthrough-project-id/>
echo "Billing Account: $BILLING_ACCOUNT_ID"
echo "Log project    : $LOG_PROJECT"
```

If the list is empty you do not have access to any billing accounts. Stop here and request access from your billing administrator.

## Step 2 — Check what is already true (Permissions preflight)

Read-only. Nothing changes.

Inspect the IAM policy on the billing account:

```bash
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT_ID"
```

The check that matters is **`roles/logging.configWriter` on the BILLING ACCOUNT**. It is the blocking prerequisite and is rarely held by whoever owns the project. If you lack this role, a Billing Account Administrator must grant it:

```bash
gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT_ID" \
  --member="user:$(gcloud config get-value account)" \
  --role="roles/logging.configWriter"
```

<walkthrough-info-message>**Verify Logging Project APIs:** Ensure required APIs are enabled in your logging project before applying:</walkthrough-info-message>

```bash
gcloud services enable pubsub.googleapis.com logging.googleapis.com --project="$LOG_PROJECT"
```

## Step 3 — Inspect the configuration and filter

Cloud Billing writes Admin Activity audit logs (IAM policy changes, project billing links and unlinks, account create, close, reopen, rename and move) and Data Access audit logs, and no System Event logs ([Cloud Billing audit logging](https://docs.cloud.google.com/billing/docs/audit-logging)). This deployment routes Admin Activity (`admin_activity`).

Read the filter before applying: routing is evaluated at write time and there is no backfill.

<walkthrough-info-message>**Routing is evaluated at write time and there is no backfill.**
A filter that was too narrow leaves a permanent hole you cannot fill later. The default configuration routes all Admin Activity audit logs from the billing account.</walkthrough-info-message>

## Step 4 — Deploy

```bash
cat > terraform.tfvars <<EOF
billing_account_id = "$BILLING_ACCOUNT_ID"
log_project        = "$LOG_PROJECT"
EOF
terraform init && terraform plan
```

You are already in `templates/gcp/gcp-source-billing-account-logs` — Cloud Shell opened you here.

When the plan looks right, apply the changes:

```bash
terraform apply
```

Inspect output identities:

```bash
terraform output -raw sink_writer_identity
terraform output -raw topic_id
```

## Step 5 — Wait before you verify

<walkthrough-info-message>**A sink is not live the instant Terraform returns.** Routing is
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

## Step 6 — Verify, cloud side first

Check the cloud before you check Abstract. Each step isolates one layer, so a failure localizes instead of becoming a debate.

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
sleep 120
gcloud pubsub subscriptions pull "$PROBE" --project="$LOG_PROJECT" --limit=5 --auto-ack
gcloud pubsub subscriptions delete "$PROBE" --project="$LOG_PROJECT" --quiet
```

<walkthrough-info-message>GCP has a **first-class health signal for its own main failure mode**. A sink whose writer identity lacks `pubsub.publisher` produces `exports/error_count`, a `sink_error` log entry, **and a daily `[ACTION REQUIRED]` email**.</walkthrough-info-message>

## Step 7 — Connect Abstract

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

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
