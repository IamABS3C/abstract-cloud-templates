<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Alert on the pipeline itself

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

Every other deployment here documents a silent failure. **This is the one that catches
them.** Deploy it alongside `gcp-source-audit-logs-organization`, not later.

## Why this exists, in one line

Every other deployment in this repo gets data flowing. **This one tells you when it
stops** — and on this pipeline, stopping is silent by default. A stalled consumer, a
missing IAM grant and a deleted sink all look identical from the outside: everything is
green and there is simply no data.

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

## You need a notification channel

```bash
gcloud beta monitoring channels list --project="$LOG_PROJECT" --format='table(name,type,displayName)'
```

None? Create one:

```bash
gcloud beta monitoring channels create \
  --project="$LOG_PROJECT" --type=email \
  --display-name="Security on-call" \
  --channel-labels=email_address=soc@yourcompany.com
```

<walkthrough-info-message>**If `gcloud beta` is not installed** it will prompt to install
it, and in a non-interactive shell that fails outright. The Monitoring API needs no beta
component:</walkthrough-info-message>

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/notificationChannels" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"email","displayName":"Security on-call",
       "labels":{"email_address":"soc@yourcompany.com"},"enabled":true}'
```

The response `name` is what goes in `notification_channels`. Set it in terraform.tfvars as
`projects/YOUR_LOG_PROJECT/notificationChannels/CHANNEL_ID`.

<walkthrough-info-message>The module **refuses to deploy without a channel** unless you
explicitly acknowledge it. Alert policies with no channel fire into the void — the same
failure as a dead webhook, and indistinguishable from having no alerting at all until the
day it matters.</walkthrough-info-message>

<!-- abstract:deploy -->
## Deploy

Run script step 8 of the guided setup. It needs the log pipeline from script steps 3 to 5; run those first. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
```

Your team requires infrastructure as code? Use [Terraform instead](#terraform-instead) at the end of this page. Use one or the other, not both.
<!-- /abstract:deploy -->

## What you get, and why each one exists

| Alert | Catches | Severity |
|---|---|---|
| **Sink failing to export** | Missing `pubsub.publisher` grant, or publish quota exhausted. Failed entries are **dropped** — no retry, no backfill | CRITICAL |
| **Abstract not consuming** | The countdown to permanent data loss. Fires at 1 hour against a 7-day window | CRITICAL |
| **Feed went dark** | Sink deleted, disabled, or filter narrowed to match nothing. Uses a *metric-absence* condition, because a threshold cannot detect "nothing arrived" | ERROR |
| **Dead-letter receiving** | Abstract repeatedly failing on a message shape. A DLQ nobody reads is worse than none | WARNING |

## Verify

Deployment is not proof. Check the policy is enabled, wired to a channel, and that **its
own filter matches live data** — a policy whose filter matches nothing is enabled, green,
and useless.

```bash
TOKEN=$(gcloud auth print-access-token)
P="$LOG_PROJECT"

# every policy, with its channel count
curl -s "https://monitoring.googleapis.com/v3/projects/$P/alertPolicies" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c '
import json,sys
for p in json.load(sys.stdin).get("alertPolicies",[]):
    print(p["displayName"], "| enabled:", p.get("enabled"),
          "| channels:", len(p.get("notificationChannels",[])))'
```

**Then confirm the metric actually exists.** Pub/Sub metrics only appear once a
subscription has traffic — on a brand-new pipeline they are legitimately absent, and an
alert on an absent metric cannot fire:

```bash
curl -s -G "https://monitoring.googleapis.com/v3/projects/$P/timeSeries" \
  -H "Authorization: Bearer $TOKEN" \
  --data-urlencode 'filter=metric.type="pubsub.googleapis.com/subscription/oldest_unacked_message_age"' \
  --data-urlencode "interval.startTime=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)" \
  --data-urlencode "interval.endTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

## Expect the stall alert to fire before Abstract is connected

<walkthrough-info-message>**This is not a false positive.** Until Abstract is pulling,
nothing consumes the subscription, so `oldest_unacked_message_age` climbs past the 1-hour
threshold and the alert fires correctly. Measured on a live deployment: **9,391 seconds
unacked** within a few hours of standing the pipeline up.</walkthrough-info-message>

Deploy the pipeline and connect Abstract **in the same working session** if you can. If
there will be a gap, either expect the alert or raise
`unacked_age_threshold_seconds` temporarily — and put it back, because a threshold above
the retention window tells you about data you have already lost. The module refuses that
outright.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

**The one that matters most is "Abstract not consuming."** Pub/Sub retention is your entire
recovery window — when the oldest message reaches it, the data is deleted permanently with
no error. The alert fires at a small fraction of that window on purpose, so there is time
to act rather than a post-mortem.

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
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-monitoring-pipeline-health-alerts"
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
