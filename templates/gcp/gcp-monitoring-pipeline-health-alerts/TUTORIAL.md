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

## Where the alerts go

Script step 8 asks for the email that receives the alerts, and creates one email channel for it in the logging
project, named "Abstract log pipeline", before it creates the alerts. You make nothing by hand; the clean-up removes
the channel with the alerts.

<walkthrough-info-message>An alert with no channel fires into the void — the same failure as a dead webhook, and
indistinguishable from having no alerting at all until the day it matters. Answering with no email leaves the alerts
visible only in the console.</walkthrough-info-message>

<!-- abstract:deploy -->
## Deploy

Run script step 8 of the guided setup. It needs the log pipeline from script steps 3 to 5; run those first. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing. [Clean up](#clean-up), below, undoes what it made.

Go to the top folder of the templates repository; the guided-setup commands run from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

Script step 8: the health alerts.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
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

## What you get, and why each one exists

| Alert | Catches | Severity |
|---|---|---|
| **Sink failing to export** | Missing `pubsub.publisher` grant, or publish quota exhausted. Failed entries are **dropped** — no retry, no backfill | CRITICAL |
| **Abstract not consuming** | The countdown to permanent data loss. Fires at 1 hour against a 7-day window | CRITICAL |
| **Feed went dark** | Sink deleted, disabled, or filter narrowed to match nothing. Uses a *metric-absence* condition, because a threshold cannot detect "nothing arrived" | ERROR |
| **Dead-letter receiving** | Abstract repeatedly failing on a message shape. A DLQ nobody reads is worse than none. Terraform only, when `dead_letter_topic_id` is set; script step 8 makes the other three | WARNING |

## Verify

Deployment is not proof. Check the policy is enabled, wired to a channel, and that **its
own filter matches live data** — a policy whose filter matches nothing is enabled, green,
and useless.

Keep a short-lived access token in TOKEN (it is not printed):

```bash
TOKEN=$(gcloud auth print-access-token)
```

List every alert policy in the logging project with its channel count (read-only). You should see three "Abstract
log pipeline" policies (four with Terraform and a dead-letter topic), each enabled, each with at least one channel:

```bash
curl -s "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/alertPolicies" -H "Authorization: Bearer $TOKEN" | python3 -c 'import json, sys; [print(p["displayName"], "| enabled:", p.get("enabled"), "| channels:", len(p.get("notificationChannels", []))) for p in json.load(sys.stdin).get("alertPolicies", [])]'
```

**Then confirm the metric actually exists.** Pub/Sub metrics only appear once a
subscription has traffic — on a brand-new pipeline they are legitimately absent, and an
alert on an absent metric cannot fire. Read the last 30 minutes of the backlog metric (read-only; `date -d` is
the Linux form Cloud Shell uses). Data points in the answer mean the metric exists; `{}` means none yet:

```bash
curl -s -G "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/timeSeries" -H "Authorization: Bearer $TOKEN" --data-urlencode 'filter=metric.type="pubsub.googleapis.com/subscription/oldest_unacked_message_age"' --data-urlencode "interval.startTime=$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" --data-urlencode "interval.endTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

## Expect the stall alert to fire before Abstract is connected

<walkthrough-info-message>**This is not a false positive.** Until Abstract is pulling,
nothing consumes the subscription, so `oldest_unacked_message_age` climbs past the 1-hour
threshold and the alert fires correctly. Measured on a live deployment: **9,391 seconds
unacked** within a few hours of standing the pipeline up.</walkthrough-info-message>

Deploy the pipeline and connect Abstract **in the same working session** if you can. If
there will be a gap, expect the alert: it clears once Abstract reads the subscription.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

**The one that matters most is "Abstract not consuming."** Pub/Sub retention is your entire
recovery window — when the oldest message reaches it, the data is deleted permanently with
no error. The alert fires at a small fraction of that window on purpose, so there is time
to act rather than a post-mortem.

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
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-monitoring-pipeline-health-alerts"
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

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

The template sends its alerts to notification channels that already exist, and refuses to deploy without one unless
you set `acknowledge_no_channel = true`. List the channels in the logging project (read-only):

```bash
gcloud beta monitoring channels list --project="$LOG_PROJECT" --format='table(name,type,displayName)'
```

If `gcloud beta` is not installed, it offers to install it; the request below needs no beta component. None that
should get these alerts? Create one email channel in the logging project, named "Abstract log pipeline" so the guided
clean-up (`--teardown`) finds it too. First keep a short-lived access token in TOKEN (it is not printed):

```bash
TOKEN=$(gcloud auth print-access-token)
```

Create the channel. Replace SOC_EMAIL with the address that should be told. It adds one notification channel to the
logging project and changes nothing else; the answer's `name` is the channel, and the last command here deletes it:

```bash
curl -s -X POST "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/notificationChannels" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"type":"email","displayName":"Abstract log pipeline","labels":{"email_address":"SOC_EMAIL"},"enabled":true}'
```

Set `notification_channels` in terraform.tfvars to a list holding that `name`, for example
`["projects/LOGGING_PROJECT_ID/notificationChannels/CHANNEL_ID"]`. To delete the channel later, once no alert uses it,
replace CHANNEL_NAME with that whole `name` (`force=true` also detaches it from any alert still using it):

```bash
curl -s -X DELETE "https://monitoring.googleapis.com/v3/CHANNEL_NAME?force=true" -H "Authorization: Bearer $TOKEN"
```

Connecting Abstract some time after the apply? The stall alert fires until Abstract reads the subscription. You can
raise `unacked_age_threshold_seconds` in terraform.tfvars for that gap; put it back afterwards, because a threshold
above the retention window tells you about data you have already lost. The module refuses one that high.

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(LOGGING_PROJECT_ID)\b' terraform.tfvars
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

<!-- abstract:tfremove -->
**To remove it later**, run `terraform destroy` in this folder with the same `backend.tf`.
<!-- /abstract:tfremove -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up:

- [Alerting overview](https://docs.cloud.google.com/monitoring/alerts)
- [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui)
- [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).
- [Google Cloud metrics: P through Z](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z#gcp-pubsub)
- [Create and manage notification channels](https://docs.cloud.google.com/monitoring/support/notification-options)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
