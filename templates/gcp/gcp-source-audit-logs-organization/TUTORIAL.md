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

## Decide the filter

Read the filter the deploy assembles. That filter decides both your coverage and your bill.

<walkthrough-info-message>**Routing is evaluated at write time and there is no backfill.**
A filter that was too narrow leaves a permanent hole you cannot fill later. One that was
too wide costs money you can stop spending. Start broad, measure for 7 days, then
tighten.</walkthrough-info-message>

<!-- abstract:deploy -->
## Deploy

Run script steps 3, 4 and 5 of the guided setup: the logging project, then the pipeline, then the account Abstract reads with. Script step 9 then sends a test event end to end, and script step 10 prints the values to enter in Abstract and the commands that download the key from this temporary session. Delete every copy of the key once Abstract has it. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
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

Microsoft-style "allow 90 minutes" is the conservative published figure. In practice
steady-state delivery here was around a minute.

### Verify, cloud side first

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

## Connect Abstract

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
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-organization"
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
