# Troubleshooting

Use this when the feed is quiet, short or stopped. Work the checks in order. Each one rules out a
hop in [the data flow](DATAFLOW.md), so the first one that fails is where the fault is.

Examples use `acme-security-logging` for the logging project and `123456789012` for the
organization. Replace them with yours. Run `./tools/gcp-guided-setup/abstract-gcp-setup.sh --check`
first: it runs most of these checks for you and changes nothing.

```bash
export LOG_PROJECT=acme-security-logging
export ORG_ID=123456789012
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

Use `--folder=<folder-id>` or `--project=$LOG_PROJECT` for those scopes.

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

A backlog that only grows means the sink works and Abstract is not reading. Go to check 6. A flat
zero with no traffic means nothing is arriving. Go back to checks 1 to 3.

If the oldest message approaches seven days, messages are about to be lost. Fix the reader first.

## 5. Probe the path with a subscription of your own

This proves the whole path to Pub/Sub without touching Abstract's subscription.

The subscription lives in the logging project. The test event must be written in a project the
sink covers. For an organization sink the logging project is fine. For a project sink it must be
the sink's own project. For a folder sink it must be a project inside that folder, and the logging
project may not be one. Set `PROBE_PROJECT` to that project.

```bash
PROBE_PROJECT="replace-with-a-project-inside-the-sink-scope"
PROBE=abstract-probe-$(date +%s)
TOPIC=abstract-probe-topic-$(date +%s)
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-audit-logs \
  --project=$LOG_PROJECT --expiration-period=1d --message-retention-duration=10m
# write a harmless admin event: create and delete a topic
gcloud pubsub topics create "$TOPIC" --project=$PROBE_PROJECT --quiet
gcloud pubsub topics delete "$TOPIC" --project=$PROBE_PROJECT --quiet
for i in $(seq 1 10); do   # every 30 s, up to 5 minutes
  sleep 30
  gcloud pubsub subscriptions pull "$PROBE" --project=$LOG_PROJECT --limit=50 --format=json 2>/dev/null \
    | python3 -c '
import base64, json, sys
for m in json.load(sys.stdin) or []:
    d = base64.b64decode(m.get("message", {}).get("data", "")).decode("utf-8", "replace")
    if sys.argv[1] in d: print("FOUND", sys.argv[1]); sys.exit(0)
sys.exit(1)' "$TOPIC" && break
done
gcloud pubsub subscriptions delete "$PROBE" --project=$LOG_PROJECT --quiet
```

Pub/Sub returns each message with its body base64-encoded in `message.data`, so the loop decodes
it before matching. `FOUND` means the path works up to Pub/Sub. Nothing after ten tries means one
of checks 1 to 3 is failing, or the sink is under three minutes old. The probe subscription expires
in a day, so a forgotten one cleans itself up. Guided setup step 9 does the same test for you.

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
| Data Access events missing | Data Access logs are off, or the filter does not name them | Turn them on with `gcp-foundation-data-access-audit-logs` or guided step 6, then add `identity_access` (impersonation and federation) or `data_access_all` with `data_access_services` to `log_categories`. A filter that names a log that does not exist matches nothing and raises no error |
| Cost jumps after enabling Data Access | `DATA_READ` on all services | Scope `data_access_services`, and exempt chatty service accounts |
| Billing account changes missing | Billing accounts sit outside the hierarchy. An organization sink never sees them | Deploy `gcp-source-billing-account-logs` |
| `PERMISSION_DENIED` creating the sink | You lack `roles/logging.configWriter` at that scope | Find who holds it. Project Owner is not enough. `preflight.sh` shows it |
| Cannot turn on Data Access | You lack permission to change the organization IAM policy | Ask an Organization Admin. This is usually a different person from the sink owner |
| Security Command Center findings never arrive | Security Command Center Premium or Enterprise is not on, or the service agent cannot publish to the topic | Check the tier, then the topic's publisher grants |
| Security Command Center, asset or network threat events collected but not stored | The managed parser keeps only audit logs | Create each as its own source, with its own parser |
| Asset feed refused with 403, topic and subscription exist | Deployer lacks `roles/cloudasset.owner` at the organization | Grant it. It is not part of Organization Admin |
| Asset feed created, nothing published | Cloud Asset service agent of the logging project lacks publisher on the topic | Grant `roles/pubsub.publisher` on the topic to `service-<project number>@gcp-sa-cloudasset.iam.gserviceaccount.com` |
| Bucket notifications arrive, no content | Abstract lacks `roles/storage.objectViewer` on the bucket | Grant it on the bucket, scoped to the prefix if you set one |
| Only some buckets deliver | Buckets in other projects have their own Cloud Storage service agent | Each agent needs publisher on the topic. Use `bucket_map` |
| Firewall, DNS or load balancer logs missing | Logging is off on the rule, the network policy or the backend service | Turn it on at the source. The sink only routes it. [Filters](FILTERS.md) lists where |
| Cloud IDS alerts missing | The IDS endpoint is not `READY`, or traffic is not mirrored | `gcloud ids endpoints list --project=<project>` |
| Workspace returns 401 or 403 | Delegation not yet propagated, wrong admin email, or scopes not an exact match | [Google Workspace](WORKSPACE.md) |
| Publish quota errors (`RESOURCE_EXHAUSTED`) | Pub/Sub quota is spent in the logging project | Request more quota, or move the heaviest source to its own topic. [Architecture](ARCHITECTURE.md) |
| Everything stopped inside a VPC Service Controls perimeter | The perimeter blocks Abstract's pull | [VPC Service Controls](VPC-SC.md) |
| Worked for a month, then stopped | The subscription expired | Recreate it with no expiry. The templates set it to never expire |
| Messages piling up in a dead-letter topic | Dead-letter delivery is on and Abstract is failing to acknowledge | It is off by default, because nobody reads it. Fix the reader, then drain it |
| Nothing alerts you when it stops | Health alerts are not deployed | `gcp-monitoring-pipeline-health-alerts` or guided step 8 |

---

## If you must change a permission by hand

Grant the one role that is missing, on the one resource that needs it, with
`add-iam-policy-binding`. Do not replace a whole policy. A replacement that is built from a stale
copy removes every binding added since, and on an organization that can lock people out. If you
must edit a full policy, read it with `get-iam-policy`, edit that copy, and write it back with its
`etag` so a concurrent change is refused instead of overwritten.

Data Access audit settings are the sharpest case: they are set per service, and a change that lists
fewer services than exist removes the rest. Run `preflight.sh` first, and let the template or
guided step 6 make the change. Step 6 saves a backup of your earlier settings.

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
