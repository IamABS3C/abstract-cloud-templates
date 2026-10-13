# Troubleshooting

Use this when the feed is quiet, short or stopped. Work the checks in order. Each one rules out a
hop in [the data flow](DATAFLOW.md), so the first one that fails is where the fault is.

The checks use LOG_PROJECT and ORG_ID. Load them from the guided setup's answers with
`source ~/.abstract-gcp-setup.env`, or set them below, replacing LOGGING_PROJECT_ID and YOUR_ORG_ID with yours. Run `./tools/gcp-guided-setup/abstract-gcp-setup.sh --check`
first: it runs most of these checks for you and changes nothing.

```bash
export LOG_PROJECT=LOGGING_PROJECT_ID
export ORG_ID=YOUR_ORG_ID
```

---

## Rules that save time

- **A new sink needs about three minutes** before it routes anything. Events written before then
  are not routed and cannot be recovered. Wait, then write a fresh test event.
- **There is no backfill.** Routing happens when the entry is written. A filter change fixes the
  future, not the past.
- **Never read Abstract's subscription to test.** A pull from it hides messages from Abstract for the
  length of the acknowledgement deadline, and acknowledging them deletes them before Abstract sees
  them. Test on a probe subscription of your own (check 5).
- **Zero events is not proof of a fault.** A source that is switched off and a sink that is broken
  look the same from outside. Check 1 tells them apart.

---

## 1. Is anything writing the logs?

Set `SOURCE_PROJECT` to a project inside the sink's scope that should be producing logs.

```bash
SOURCE_PROJECT="replace-with-a-source-project-id"
gcloud logging read 'logName:"cloudaudit.googleapis.com%2Factivity"' \
  --project="$SOURCE_PROJECT" --limit=3 \
  --format="table(timestamp,protoPayload.methodName,protoPayload.authenticationInfo.principalEmail)"
```

Rows come back: the source works, go to check 2. No rows:

- The project is idle, or the service API is disabled. Make a harmless change and read again.
- You are looking for Data Access, firewall, DNS or load balancer logs. Those are off until you turn
  them on at the source. A sink cannot create them. See [Filters](FILTERS.md).

## 2. Does the sink match, and does it see child projects?

```bash
gcloud logging sinks describe abstract-org-audit-sink --organization=$ORG_ID \
  --format="yaml(name,destination,filter,includeChildren,writerIdentity,disabled)"
```

Healthy output has a `destination` ending in your topic, `includeChildren: true` for an
organization or folder sink, a `writerIdentity`, and no `disabled: true`.

Without child inclusion, an organization sink sees only entries written on the organization
resource itself. Every folder and project is silent. Turn it on:

```bash
gcloud logging sinks update abstract-org-audit-sink --organization=$ORG_ID --include-children
```

Use `--folder=FOLDER_ID` or `--project=$LOG_PROJECT` for those scopes.

## 3. Can the sink write to the topic?

This is the most common silent fault. Google creates a service account for each sink. It holds no
permissions until you grant them, and a sink that cannot publish raises no warning.

```bash
WRITER=$(gcloud logging sinks describe abstract-org-audit-sink --organization=$ORG_ID \
  --format="value(writerIdentity)")
gcloud pubsub topics get-iam-policy abstract-audit-logs --project=$LOG_PROJECT \
  --flatten="bindings[].members" --filter="bindings.role:roles/pubsub.publisher" \
  --format="table(bindings.members)"
```

If `$WRITER` is not in the list, add it to the topic only:

```bash
gcloud pubsub topics add-iam-policy-binding abstract-audit-logs --project=$LOG_PROJECT \
  --member="$WRITER" --role="roles/pubsub.publisher"
```

The templates and the guided script make this grant. You meet the fault when a sink was made by
hand, or recreated, which gives it a new identity.

Also check for sink errors. The metric `logging.googleapis.com/exports/error_count` should be flat
at zero.

## 4. Is the subscription filling up?

In Cloud Monitoring, chart these for the subscription:

| Metric | Reads as |
|---|---|
| `pubsub.googleapis.com/subscription/num_undelivered_messages` | Messages waiting. Near zero means Abstract keeps up |
| `pubsub.googleapis.com/subscription/oldest_unacked_message_age` | How far behind. It must stay well under the seven-day retention |

Google's backlog page recommends the regional versions (`num_unacked_messages_by_region`, `oldest_unacked_message_age_by_region`). The alerts here use the two above because they were measured reporting every minute on a live subscription (2026-10-11), while the regional ones wrote only 8 points in 24 hours. Either works for a chart; alert on the ones that report.

A backlog that only grows means the sink works and Abstract is not reading. Go to check 6. A flat
zero with no traffic means nothing is arriving. Go back to checks 1 to 3.

If the oldest message approaches seven days, messages are about to be lost. Fix the reader first.

## 5. Probe the path with a subscription of your own

This proves the whole path to Pub/Sub without touching Abstract's subscription.

The subscription lives in the logging project. The test event must be written in a project the
sink covers. For an organization sink the logging project is fine. For a project sink it must be
the sink's own project. For a folder sink it must be a project inside that folder, and the logging
project may not be one. Set `PROBE_PROJECT` to that project. The test event is a topic created and
deleted at once; the loop then checks every 30 seconds, for up to 5 minutes.

```bash
PROBE_PROJECT="replace-with-a-project-inside-the-sink-scope"
PROBE=abstract-probe-$(date +%s)
TOPIC=abstract-probe-topic-$(date +%s)
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-audit-logs \
  --project=$LOG_PROJECT --expiration-period=1d --message-retention-duration=10m
gcloud pubsub topics create "$TOPIC" --project=$PROBE_PROJECT --quiet
gcloud pubsub topics delete "$TOPIC" --project=$PROBE_PROJECT --quiet
END=$(( $(date +%s) + 330 )); FOUND=
for i in $(seq 1 10); do
  sleep 30
  while [ -z "$FOUND" ] && [ "$(date +%s)" -lt "$END" ]; do
    N=$(gcloud pubsub subscriptions pull "$PROBE" --project=$LOG_PROJECT --limit=1000 --auto-ack --format=json 2>/dev/null \
      | python3 -c '
import base64, json, sys
m = json.load(sys.stdin) or []
for x in m:
    d = base64.b64decode(x.get("message", {}).get("data", "")).decode("utf-8", "replace")
    if sys.argv[1] in d: print("FOUND"); sys.exit(0)
print(len(m))' "$TOPIC" 2>/dev/null)
    case "$N" in FOUND) FOUND=1 ;; ""|0) break ;; esac
  done
  [ -n "$FOUND" ] && { echo "FOUND $TOPIC"; break; }
done
gcloud pubsub subscriptions delete "$PROBE" --project=$LOG_PROJECT --quiet
```

Pub/Sub returns each message with its body base64-encoded in `message.data`, so the loop decodes
it before matching. Each round keeps pulling until a pull comes back empty, because Pub/Sub may
return short batches while a backlog remains and the probe event can sit behind it. `FOUND` means the path works up to Pub/Sub. Nothing after ten tries means one
of checks 1 to 3 is failing, or the sink is under three minutes old. The probe subscription expires
in a day, so a forgotten one cleans itself up. Script step 9 of the guided setup does the same test for you.

## 6. Is Abstract reading?

If check 5 shows messages and Abstract shows none, the fault is in the integration. Check these in
order. [Abstract integration](ABSTRACT-INTEGRATION.md) has the details.

| Check | Right answer |
|---|---|
| Project ID field | The project that holds the subscription, not a source project |
| Subscription ID field | The short name, such as `abstract-audit-logs-sub`, not `projects/.../subscriptions/...` |
| Key | The key for the service account that holds `roles/pubsub.subscriber` on the subscription, under 1 MB |
| Role | Subscriber on the subscription. Publisher gives `PERMISSION_DENIED` |
| Subscription | Still exists. A subscription recreated by hand may expire after 31 days of inactivity |
| Events found | Search vendor GCP in Abstract. Events with empty fields point to the integration version |

---

## By symptom

| Symptom | Likely cause | What to do |
|---|---|---|
| Healthy sink, no events, ever | Writer identity lacks publisher on the topic | Check 3 |
| New projects send nothing | Sink has no child inclusion, or it is a folder sink and the project sits outside the folder | Check 2. For a folder sink, deploy at organization scope, or one sink per folder |
| Data Access events missing | Data Access logs are off, or the sink filter does not route them | Turn them on with `gcp-foundation-data-access-audit-logs` or script step 6 of the guided setup. For identity, switch on `iam.googleapis.com` and `sts.googleapis.com`; the events arrive as `iamcredentials.googleapis.com` and `sts.googleapis.com`. Then route them: add `identity_access` to `log_categories` for impersonation and federation, or `data_access_all` for other services. `data_access_services` is read only when `data_access_all` is set. A filter that names a log that does not exist matches nothing and raises no error |
| Cost jumps after enabling Data Access | `DATA_READ` on all services | Scope `data_access_services`, and exempt chatty service accounts |
| Billing account changes missing | An organization sink routes the organization and the folders and projects under it; a billing account is a separate resource, so its logs are collected with a sink created on the billing account itself. | Deploy `gcp-source-billing-account-logs` |
| A script stops: "gcloud is set to A, but its stored sign-in acts as B" (or "its token acts as B") | The token gcloud mints is not A's: an old stored sign-in, a service account set in `auth/impersonate_service_account`, or a token file in `CLOUDSDK_AUTH_ACCESS_TOKEN_FILE` | The message names the cause. A stale sign-in: `gcloud auth login A`. Impersonating a service account on purpose is accepted, and the scripts say "acting as <service account> (impersonated by A)"; when the token is someone else's, correct the setting or clear it with `gcloud config unset auth/impersonate_service_account`. A token file decides the identity by itself: point the variable at a token for A, or `unset CLOUDSDK_AUTH_ACCESS_TOKEN_FILE`. Signing in again changes neither setting |
| `PERMISSION_DENIED` creating the sink | You lack `roles/logging.configWriter` at that scope | Find who holds it. Project Owner is not enough. `preflight.sh` shows it |
| Cannot turn on Data Access | You lack permission to change the organization IAM policy | Ask an Organization Admin. This is usually a different person from the sink owner |
| Security Command Center findings never arrive | Security Command Center Premium or Enterprise is not on, or the service agent cannot publish to the topic | Check the tier, then the topic's publisher grants |
| Security Command Center, asset or network threat events collected but not stored | The managed parser keeps only audit logs | Create each as its own source, with its own parser |
| Asset feed refused with 403, topic and subscription exist | Deployer lacks `roles/cloudasset.owner` at the organization | Grant it. It is not part of Organization Admin |
| Asset feed created, nothing published | Cloud Asset service agent of the logging project lacks publisher on the topic | Grant `roles/pubsub.publisher` on the topic to `service-PROJECT_NUMBER@gcp-sa-cloudasset.iam.gserviceaccount.com`, PROJECT_NUMBER being the logging project's number |
| Bucket notifications arrive, no content | Abstract lacks `roles/storage.objectViewer` on the bucket | Grant it on the bucket, scoped to the prefix if you set one |
| Only some buckets deliver | Buckets in other projects have their own Cloud Storage service agent | Each agent needs publisher on the topic. Use `bucket_map` |
| Firewall, DNS or load balancer logs missing | Logging is off on the rule, the network policy or the backend service | Turn it on at the source. The sink only routes it. [Filters](FILTERS.md) lists where |
| Cloud IDS alerts missing | The IDS endpoint is not `READY`, or traffic is not mirrored | `gcloud ids endpoints list --project=WORKLOAD_PROJECT_ID`, for the project the endpoint is in |
| Workspace returns 401 or 403 | Delegation not yet propagated, wrong admin email, or scopes not an exact match | [Google Workspace](WORKSPACE.md) |
| Publish quota errors (`RESOURCE_EXHAUSTED`) | Pub/Sub quota is spent in the logging project | Request more quota, or move the heaviest source to its own topic. [Architecture](ARCHITECTURE.md) |
| Everything stopped inside a VPC Service Controls perimeter | The perimeter blocks Abstract's pull | [VPC Service Controls](VPC-SC.md) |
| Worked for a month, then stopped | The subscription expired | Recreate it with no expiry. The templates set it to never expire |
| Messages piling up in a dead-letter topic | Dead-letter delivery is on and Abstract is failing to acknowledge | It is off by default, because nobody reads it. Fix the reader, then drain it |
| Nothing alerts you when it stops | Health alerts are not deployed | `gcp-monitoring-pipeline-health-alerts` or script step 8 of the guided setup |

---

## If you must change a permission by hand

Grant the one role that is missing, on the one resource that needs it, with
`add-iam-policy-binding`. Do not replace a whole policy. A replacement that is built from a stale
copy removes every binding added since, and on an organization that can lock people out. If you
must edit a full policy, read it with `get-iam-policy`, edit that copy, and write it back with its
`etag` so a concurrent change is refused instead of overwritten.

Data Access audit settings are the sharpest case: they are set per service, and the Terraform
template replaces the settings of every service it names. It applies ONE log_types list and ONE
exempted_members list to every service it names, so copying one service's `DATA_READ` into
`log_types` turns it on for every named service. Run `preflight.sh` first: it marks each service
whose settings differ from what the template sets. Name only services whose settings you accept
being replaced, and leave out any service that already has DATA_READ or exempted members, or manage
it only from a separate root with its own backend prefix, after removing it from this root's
services. Script step 6 of the guided setup only adds to your settings, and saves a backup of the
earlier ones first.

---

## When it still does not add up

Collect these and send them to Abstract support:

```bash
gcloud logging sinks describe abstract-org-audit-sink --organization=$ORG_ID
gcloud pubsub subscriptions describe abstract-audit-logs-sub --project=$LOG_PROJECT
gcloud pubsub topics get-iam-policy abstract-audit-logs --project=$LOG_PROJECT
./tools/gcp-guided-setup/abstract-gcp-setup.sh --check
```

Remove anything you do not want to share before sending. None of these commands print key
material.
