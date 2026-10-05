<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Export GCP audit logs to Abstract Security

<!-- guided-step -->
> **This is step 4 of the guided setup (Log pipeline).** The guided setup does it for you and checks it: from the repository root run `./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4`, or follow `tools/gcp-guided-setup/WALKTHROUGH.md`. This page is the Terraform way to do the same step.
<!-- /guided-step -->

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

1. **`roles/logging.configWriter` at ORGANIZATION scope.** Whoever owns a project
   almost never holds this. Find that person before you go further.
2. `roles/pubsub.admin` on the logging project.
3. Your organization ID: `gcloud organizations list`

<walkthrough-info-message>Use a **dedicated logging or security project**, not a workload
project. Pub/Sub publish quota is consumed in the destination project, and a security
pipeline living inside a workload project can be read or broken by that workload's
owner.</walkthrough-info-message>

## Step 1 — Set your variables

```bash
export ORG_ID=$(gcloud organizations list --format='value(ID)' --limit=1)
export LOG_PROJECT=<walkthrough-project-id/>
echo "Organization: $ORG_ID"
echo "Log project : $LOG_PROJECT"
```

If `ORG_ID` is empty you are not in an organization, and an aggregated sink is not
available. Stop here and talk to whoever owns the GCP hierarchy.

## Step 2 — Check what is already true

Read-only. Nothing changes.

```bash
../../../tools/gcp-guided-setup/preflight.sh --project "$LOG_PROJECT" --org-id "$ORG_ID"
```

The check that matters is **`roles/logging.configWriter` at the ORGANIZATION**. It is the
blocking prerequisite and it is rarely held by whoever owns the project. If that line is
red, stop and find the person who holds it.

## Step 3 — See exactly what will happen

The script is **dry-run by default**. It prints every command it would run and changes
nothing:

```bash
../../../tools/gcp-guided-setup/deploy-abstract-gcp.sh --scope organization --scope-id "$ORG_ID" --log-project "$LOG_PROJECT"
```

Read the filter it assembles. That filter decides both your coverage and your bill.

<walkthrough-info-message>**Routing is evaluated at write time and there is no backfill.**
A filter that was too narrow leaves a permanent hole you cannot fill later. One that was
too wide costs money you can stop spending. Start broad, measure for 7 days, then
tighten.</walkthrough-info-message>

## Step 4 — Deploy

Once the dry run looks right, add `--confirm`:

```bash
../../../tools/gcp-guided-setup/deploy-abstract-gcp.sh --scope organization --scope-id "$ORG_ID" --log-project "$LOG_PROJECT" --confirm
```

### Or with Terraform

```bash
cat > terraform.tfvars <<EOF
org_id      = "$ORG_ID"
log_project = "$LOG_PROJECT"
EOF
terraform init && terraform plan
```

You are already in `templates/gcp/gcp-source-audit-logs-organization` — the button put you here.

## Step 5 — Wait before you verify

<walkthrough-info-message>**A sink is not live the instant Terraform returns.** Routing is
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

Microsoft-style "allow 90 minutes" is the conservative published figure. In practice
steady-state delivery here was around a minute.

## Step 6 — Verify, cloud side first

Check the cloud before you check Abstract. Each step isolates one layer, so a failure
localises instead of becoming a debate.

```bash
# 1. The sink exists and is AGGREGATED. includeChildren MUST be True — without it
#    you have a plain org sink that carries only the org's own logs, not the
#    projects', which looks almost identical until you notice what is missing.
gcloud logging sinks describe abstract-org-audit-sink --organization="$ORG_ID" \
  --format="value(name,includeChildren,destination)"

# 2. The writer identity actually holds publisher on the topic. THE most-skipped
#    step, and the sink reports healthy without it.
gcloud pubsub topics get-iam-policy abstract-audit-logs --project="$LOG_PROJECT"

# 3. GCP tells you about this failure directly — most people never look.
gcloud logging read 'logName:"logging.googleapis.com%2Fsink_error"' \
  --limit=20 --project="$LOG_PROJECT"
```

### The test that actually proves it

Everything above can pass while nothing flows. This is the only check that does not.

```bash
# Subscribe a throwaway probe to the same topic first, so Abstract's own
# subscription is never touched. Then fire a fresh event: creating and deleting a
# topic is guaranteed Admin Activity and leaves nothing behind.
PROBE=abstract-probe-$(date +%s)
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-audit-logs \
  --project="$LOG_PROJECT" --expiration-period=1d
gcloud pubsub topics create abstract-probe-topic --project="$LOG_PROJECT" --quiet
gcloud pubsub topics delete abstract-probe-topic --project="$LOG_PROJECT" --quiet
sleep 75
gcloud pubsub subscriptions pull "$PROBE" --project="$LOG_PROJECT" --limit=5 --auto-ack
gcloud pubsub subscriptions delete "$PROBE" --project="$LOG_PROJECT" --quiet
```

Never pull from `abstract-audit-logs-sub`: Abstract reads that subscription, and `--auto-ack` there deletes events before Abstract sees them. The probe subscription above is yours and expires in a day.

You should see your own `CreateTopic` and `DeleteTopic`, with `principalEmail`,
`resourceName` and `callerIp` populated. That is the whole pipeline proven.

<walkthrough-info-message>GCP is the only major cloud with a **first-class health signal
for its own main failure mode**. A sink whose writer identity lacks `pubsub.publisher`
produces `exports/error_count`, a `sink_error` log entry, **and a daily `[ACTION
REQUIRED]` email**.</walkthrough-info-message>

## Step 7 — Connect Abstract

You need two values, plus a key:

```bash
gcloud pubsub subscriptions list --project="$LOG_PROJECT" --format='value(name.basename())'
```

* **Project ID** — the project holding the **subscription**, not the projects generating
  logs. With an org-level sink the logs come from dozens of projects while the
  subscription lives in one. This is the field filled in wrong most often.
* **Subscription ID** — the short name only, not the `projects/.../subscriptions/...` path.
* **Service-account key** — create it, upload it to Abstract, then delete the local copy.

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Your whole organization now exports audit logs to Abstract, and **any project created
from now on is covered the moment it exists**.

**One thing this did not do:** Data Access audit logs are off by default and must be
enabled separately in **IAM & Admin → Audit Logs** at the organization. Until then, a
filter referencing `data_access` matches nothing — which looks exactly like a broken sink.

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
