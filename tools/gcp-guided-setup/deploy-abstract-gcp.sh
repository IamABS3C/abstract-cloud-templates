#!/usr/bin/env bash
# =============================================================================
#  Abstract Security — GCP log onboarding, one command
#
#  Hand this to a customer's cloud engineer. It is deliberately readable: every
#  step prints what it is about to do and why, so the person running it can
#  explain it to their security team afterwards.
#
#  Dry-run by default. Nothing is created until you pass --confirm.
#
#  What it builds:
#    topic + subscription (never-expiring) -> aggregated sink at org/folder scope
#    -> publisher grant to the sink's writer identity -> service account with
#    subscriber on ONE subscription.
#
#  The two steps people skip, both of which fail silently:
#    * the writer-identity publisher grant — sink looks healthy, publishes nothing
#    * --expiration-period=never — subscription deleted after 31 days idle
# =============================================================================
set -euo pipefail

SCOPE=""            # organization | folder
SCOPE_ID=""
LOG_PROJECT=""
TOPIC="abstract-audit-logs"
SUB="abstract-audit-logs-sub"
SINK="abstract-org-audit-sink"
SA="abstract-pubsub-reader"
RETENTION_DAYS=7
DATA_ACCESS=false
DATA_ACCESS_SERVICES="bigquery.googleapis.com,storage.googleapis.com"
PLATFORM_LOGS=""
CONFIRM=false; ROTATE_KEY=false
KEY_OUT="abstract-sa-key.json"

C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'
C_BRAND=$'\033[38;5;198m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'

say()  { printf '%s==>%s %s\n' "$C_BRAND" "$C_OFF" "$1"; }
ok()   { printf '%s  ok%s %s\n' "$C_OK" "$C_OFF" "$1"; }
warn() { printf '%s  !!%s %s\n' "$C_WARN" "$C_OFF" "$1"; }
die()  { printf '%s ERR%s %s\n' "$C_ERR" "$C_OFF" "$1" >&2; exit 1; }
note() { printf '%s     %s%s\n' "$C_DIM" "$1" "$C_OFF"; }

usage() {
  cat <<'USAGE'
Abstract Security — GCP log onboarding

REQUIRED
  --scope <organization|folder>   Where the aggregated sink binds. Only these two
                                 cover projects created LATER.
  --scope-id <id>                 Organization or folder ID.
  --log-project <id>              DEDICATED logging project for the topic and
                                 subscription. Not a workload project.

OPTIONAL
  --data-access                   Include Data Access audit logs. OFF by default:
                                 dominated by DATA_READ and can move total volume
                                 by 1-2 orders of magnitude on a BigQuery estate.
  --data-access-services a,b      Restrict Data Access to these services.
                                 Default: bigquery + storage.
  --platform-logs a,b             Extra platform log IDs, e.g.
                                 compute.googleapis.com%2Ffirewall
  --retention-days N              Pub/Sub retention, 1-31. Default 7 — this is
                                 your entire recovery window.
  --topic / --subscription / --sink / --service-account   Override names.
  --rotate-key                    Mint a new service-account key even if one
                                 exists. GCP caps user-managed keys at 10.
  --confirm                       Actually create things. Without it, dry run.
  -h, --help

EXAMPLES
  # See what would happen — safe, changes nothing
  ./deploy-abstract-gcp.sh --scope organization --scope-id 123456789012 \
      --log-project acme-security-logging

  # Production shape: audit + BigQuery/GCS data access + firewall and DNS
  ./deploy-abstract-gcp.sh --scope organization --scope-id 123456789012 \
      --log-project acme-security-logging --data-access \
      --platform-logs 'compute.googleapis.com%2Ffirewall,dns.googleapis.com%2Fdns_queries' \
      --confirm
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope) SCOPE="$2"; shift 2 ;;
    --scope-id) SCOPE_ID="$2"; shift 2 ;;
    --log-project) LOG_PROJECT="$2"; shift 2 ;;
    --topic) TOPIC="$2"; shift 2 ;;
    --subscription) SUB="$2"; shift 2 ;;
    --sink) SINK="$2"; shift 2 ;;
    --service-account) SA="$2"; shift 2 ;;
    --retention-days) RETENTION_DAYS="$2"; shift 2 ;;
    --data-access) DATA_ACCESS=true; shift ;;
    --data-access-services) DATA_ACCESS_SERVICES="$2"; shift 2 ;;
    --platform-logs) PLATFORM_LOGS="$2"; shift 2 ;;
    --confirm) CONFIRM=true; shift ;;
    --rotate-key) ROTATE_KEY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1  (try --help)" ;;
  esac
done

command -v gcloud >/dev/null || die "gcloud not found. Install the Google Cloud CLI."
[[ -n "$SCOPE" ]] || { usage; die "--scope is required"; }
[[ "$SCOPE" == "organization" || "$SCOPE" == "folder" ]] || \
  die "--scope must be organization or folder. A project-level sink does not cover future projects, which defeats the purpose."
[[ -n "$SCOPE_ID" ]]    || die "--scope-id is required"
[[ -n "$LOG_PROJECT" ]] || die "--log-project is required"
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] && (( RETENTION_DAYS >= 1 && RETENTION_DAYS <= 31 )) || \
  die "--retention-days must be 1-31 (Pub/Sub limit)"

# ---------------------------------------------------------------------------
# Build the filter. Assembled rather than hand-written, because routing is
# evaluated at WRITE TIME with no backfill — anything this filter misses is
# permanently unrecoverable, so it deserves to be printed and read.
# ---------------------------------------------------------------------------
FILTER='logName:"cloudaudit.googleapis.com%2Factivity"
  OR logName:"cloudaudit.googleapis.com%2Fsystem_event"'

if $DATA_ACCESS; then
  svc_clause=""
  IFS=',' read -ra SVCS <<< "$DATA_ACCESS_SERVICES"
  for s in "${SVCS[@]}"; do
    [[ -n "$svc_clause" ]] && svc_clause+=" OR "
    svc_clause+="\"$s\""
  done
  FILTER+='
  OR (logName:"cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName=('"$svc_clause"'))'
fi

if [[ -n "$PLATFORM_LOGS" ]]; then
  IFS=',' read -ra PLOGS <<< "$PLATFORM_LOGS"
  for p in "${PLOGS[@]}"; do
    FILTER+='
  OR logName:"'"$p"'"'
  done
fi

printf '\n%s  Abstract Security — GCP log onboarding%s\n' "$C_BRAND" "$C_OFF"
printf '%s  ────────────────────────────────────────%s\n\n' "$C_BRAND" "$C_OFF"
echo "  Sink scope        : $SCOPE $SCOPE_ID  (covers projects created later, by containment)"
echo "  Logging project   : $LOG_PROJECT"
echo "  Topic / sub       : $TOPIC / $SUB"
echo "  Retention         : ${RETENTION_DAYS}d, never-expiring subscription"
echo "  Data Access logs  : $($DATA_ACCESS && echo "YES — restricted to $DATA_ACCESS_SERVICES" || echo 'no (recommended default)')"
echo
echo "  Filter:"
printf '    %s\n' "$FILTER" | sed 's/^/  /'
echo

if ! $CONFIRM; then
  warn "DRY RUN — nothing will be created. Re-run with --confirm to apply."
  note "Read the filter above first. Routing is write-time and there is NO backfill,"
  note "so start broader than you think you need and tighten after a 7-day baseline."
  exit 0
fi

run() { note "\$ $*"; "$@"; }

say "Enabling APIs on $LOG_PROJECT"
run gcloud services enable pubsub.googleapis.com logging.googleapis.com --project="$LOG_PROJECT"
ok "APIs enabled"

say "Creating topic $TOPIC"
gcloud pubsub topics describe "$TOPIC" --project="$LOG_PROJECT" >/dev/null 2>&1 \
  && warn "topic already exists — leaving it alone" \
  || { run gcloud pubsub topics create "$TOPIC" --project="$LOG_PROJECT"; ok "topic created"; }

say "Creating subscription $SUB"
note "--expiration-period=never is NOT cosmetic: the default deletes a subscription"
note "after 31 days idle, so a quiet pilot silently destroys the feed."
gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" >/dev/null 2>&1 \
  && warn "subscription already exists — leaving it alone" \
  || { run gcloud pubsub subscriptions create "$SUB" \
        --topic="$TOPIC" --project="$LOG_PROJECT" \
        --ack-deadline=60 \
        --message-retention-duration="${RETENTION_DAYS}d" \
        --expiration-period=never
       ok "subscription created, never-expiring"; }

say "Creating aggregated sink $SINK at $SCOPE scope"
note "--include-children is what makes it AGGREGATED. Scope is containment, not a"
note "project list — so there is nothing to go stale as projects are added."
SCOPE_FLAG="--organization=$SCOPE_ID"
[[ "$SCOPE" == "folder" ]] && SCOPE_FLAG="--folder=$SCOPE_ID"

if gcloud logging sinks describe "$SINK" $SCOPE_FLAG >/dev/null 2>&1; then
  warn "sink already exists — updating its filter"
  run gcloud logging sinks update "$SINK" $SCOPE_FLAG --log-filter="$FILTER"
else
  run gcloud logging sinks create "$SINK" \
    "pubsub.googleapis.com/projects/$LOG_PROJECT/topics/$TOPIC" \
    $SCOPE_FLAG --include-children --log-filter="$FILTER"
fi
ok "sink configured"

say "Granting the sink's writer identity publish rights"
note "THE step people skip. The sink runs as its own identity, created with the"
note "sink, holding NO permissions until this grant exists. It then reports"
note "healthy and publishes nothing."
WRITER=$(gcloud logging sinks describe "$SINK" $SCOPE_FLAG --format='value(writerIdentity)')
[[ -n "$WRITER" ]] || die "could not read the sink's writerIdentity — cannot grant publish"
echo "  writer identity: $WRITER"
run gcloud pubsub topics add-iam-policy-binding "$TOPIC" \
  --project="$LOG_PROJECT" --member="$WRITER" --role="roles/pubsub.publisher"
ok "publisher granted"

say "Creating the service account Abstract authenticates as"
SA_EMAIL="$SA@$LOG_PROJECT.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$SA_EMAIL" --project="$LOG_PROJECT" >/dev/null 2>&1 \
  && warn "service account already exists" \
  || { run gcloud iam service-accounts create "$SA" --project="$LOG_PROJECT" \
        --display-name="Abstract Security log reader"; ok "service account created"; }

say "Granting subscriber on the subscription only"
note "SUBSCRIBER, not publisher — Abstract PULLS. And bound on the one"
note "subscription, never project-wide."
run gcloud pubsub subscriptions add-iam-policy-binding "$SUB" \
  --project="$LOG_PROJECT" --member="serviceAccount:$SA_EMAIL" --role="roles/pubsub.subscriber"
ok "subscriber granted"

# Every other resource here is existence-checked. Key creation was not, so
# re-running to change a filter minted ANOTHER key. GCP caps user-managed keys
# at 10 per service account — run it eleven times and the script hard-fails,
# and nothing ever deleted the earlier ones.
EXISTING_KEYS=$(gcloud iam service-accounts keys list --iam-account="$SA_EMAIL" \
  --managed-by=user --format="value(name)" 2>/dev/null | wc -l | tr -d " ")
if [[ "${EXISTING_KEYS:-0}" -gt 0 && "$ROTATE_KEY" != "true" ]]; then
  warn "$EXISTING_KEYS user-managed key(s) already exist on $SA_EMAIL — not creating another."
  warn "GCP caps these at 10. Pass --rotate-key to mint a new one deliberately."
else
  say "Creating the service-account key"
  run gcloud iam service-accounts keys create "$KEY_OUT" --iam-account="$SA_EMAIL"
fi
ok "key written to $KEY_OUT"
warn "Upload it to Abstract, then DELETE the local copy. Do not email it, do not commit it."
note "There is no Workload Identity Federation option on this integration today."

cat <<SUMMARY

$C_BRAND  Configure the Abstract integration$C_OFF
  ────────────────────────────────────────
  Integration      GCP Pub/Sub Source
  Project ID       $LOG_PROJECT
                   ^ the project holding the SUBSCRIPTION, not the projects
                     generating logs. This is the field people fill in wrong.
  Subscription ID  $SUB
  Credentials      $KEY_OUT

$C_BRAND  Verify — cloud side first, Abstract last$C_OFF
  ────────────────────────────────────────
  1. Logs reaching the topic
       Pub/Sub -> $TOPIC -> Metrics -> topic/send_request_count
       Zero here is the SINK or the publisher grant, not Abstract.

  2. No sink errors  (GCP is the only cloud that tells you this directly)
       gcloud logging read 'logName:"logging.googleapis.com%2Fsink_error"' \\
         --limit=20 --project=$LOG_PROJECT
       Also watch logging.googleapis.com/exports/error_count, and check for a
       daily [ACTION REQUIRED] email.

  3. Consumer keeping up
       Subscription metric num_undelivered_messages near zero while traffic flows.

  4. Events in Abstract — search vendor GCP over the last 15 minutes.

  5. The fields that matter — spot-check user_name, related.user,
     cloud.project_id. This proves value, not just plumbing. Do it on the call.

  Generate a guaranteed test event with a trivial IAM change: Admin Activity is
  always on, so it flows even if Data Access is still off.
SUMMARY

if $DATA_ACCESS; then
  echo
  warn "Data Access was requested. It is NOT enabled by this script."
  note "It is an org-level IAM audit-config change — read-modify-write, and the one"
  note "genuinely risky action here, so it is deliberately left to a human:"
  note "  gcloud organizations get-iam-policy $SCOPE_ID --format=json > policy.json"
  note "  # add auditConfigs, KEEP A COPY of the original and its etag, then:"
  note "  gcloud organizations set-iam-policy $SCOPE_ID policy.json   (the file keeps the etag)"
  note "Until then the data_access clause in the filter matches NOTHING — which"
  note "reads exactly like a broken sink."
fi
