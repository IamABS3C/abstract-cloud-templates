<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Alert on the pipeline itself

<!-- guided-step -->
> **This is step 8 of the guided setup (Health alerts).** The guided setup does it for you and checks it: from the repository root run `./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8`, or follow `tools/gcp-guided-setup/WALKTHROUGH.md`. This page is the Terraform way to do the same step.
<!-- /guided-step -->

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

Every other deployment here documents a silent failure. **This is the one that catches
them.** Deploy it alongside `gcp-source-audit-logs-organization`, not later.

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Why this exists, in one line

Every other deployment in this repo gets data flowing. **This one tells you when it
stops** — and on this pipeline, stopping is silent by default. A stalled consumer, a
missing IAM grant and a deleted sink all look identical from the outside: everything is
green and there is simply no data.

## Step 1 — You need a notification channel

```bash
gcloud beta monitoring channels list --project=YOUR_LOG_PROJECT --format='table(name,type,displayName)'
```

None? Create one:

```bash
gcloud beta monitoring channels create \
  --project=YOUR_LOG_PROJECT --type=email \
  --display-name="Security on-call" \
  --channel-labels=email_address=soc@yourcompany.com
```

<walkthrough-info-message>**If `gcloud beta` is not installed** it will prompt to install
it, and in a non-interactive shell that fails outright. The Monitoring API needs no beta
component:</walkthrough-info-message>

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -X POST \
  "https://monitoring.googleapis.com/v3/projects/YOUR_LOG_PROJECT/notificationChannels" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"email","displayName":"Security on-call",
       "labels":{"email_address":"soc@yourcompany.com"},"enabled":true}'
```

The response `name` is what goes in `notification_channels`.

<walkthrough-info-message>The module **refuses to deploy without a channel** unless you
explicitly acknowledge it. Alert policies with no channel fire into the void — the same
failure as a dead webhook, and indistinguishable from having no alerting at all until the
day it matters.</walkthrough-info-message>

## Step 2 — Apply

```bash
cat > terraform.tfvars <<EOF
log_project           = "YOUR_LOG_PROJECT"
notification_channels = ["projects/YOUR_LOG_PROJECT/notificationChannels/CHANNEL_ID"]
EOF
terraform init && terraform apply
```

## What you get, and why each one exists

| Alert | Catches | Severity |
|---|---|---|
| **Sink failing to export** | Missing `pubsub.publisher` grant, or publish quota exhausted. Failed entries are **dropped** — no retry, no backfill | CRITICAL |
| **Abstract not consuming** | The countdown to permanent data loss. Fires at 1 hour against a 7-day window | CRITICAL |
| **Feed went dark** | Sink deleted, disabled, or filter narrowed to match nothing. Uses a *metric-absence* condition, because a threshold cannot detect "nothing arrived" | ERROR |
| **Dead-letter receiving** | Abstract repeatedly failing on a message shape. A DLQ nobody reads is worse than none | WARNING |

## Step 3 — Confirm the policies are real

Deployment is not proof. Check the policy is enabled, wired to a channel, and that **its
own filter matches live data** — a policy whose filter matches nothing is enabled, green,
and useless.

```bash
TOKEN=$(gcloud auth print-access-token)
P=YOUR_LOG_PROJECT

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

## Step 4 — Expect the stall alert to fire before Abstract is connected

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

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
