#!/usr/bin/env bash
# =============================================================================
#  Abstract Security — Google Cloud guided setup
#
#  Walks you through every piece, in order, and checks each one:
#
#    1  Sign-in and organization        who you are, which org, which scope
#    2  What you can change             the roles each later step needs, checked live
#    3  Logging project                 create or pick it, billing, APIs
#    4  Log pipeline                    topic, subscription, sink, publisher grant
#    5  Abstract's access               service account, subscriber grant, key
#    6  Data Access logs     (optional) generate them AND route them — both switches
#    7  Google Workspace     (optional) identity logs: service account + delegation
#    8  Health alerts        (optional) tell you when the pipeline stops
#    9  Test and verify                 a fresh event, end to end
#   10  Connect Abstract                the exact values to enter
#
#  Usage
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh              guided: every step, asks before each change
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6     one step
#    ./tools/gcp-guided-setup/abstract-gcp-setup.sh --check      verify everything, change nothing
#
#  Nothing changes without a "y". Every command is printed before it runs. Answers are
#  kept in ~/.abstract-gcp-setup.env so you can stop and resume. No secret is printed;
#  the only secret made (a service-account key) is written to a 0600 file you upload
#  to Abstract and then delete.
# =============================================================================
set -uo pipefail

STATE="${ABSTRACT_GCP_STATE:-$HOME/.abstract-gcp-setup.env}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"   # the repository root: this script lives in tools/gcp-guided-setup

# Defaults; anything in the state file wins.
TOPIC="abstract-audit-logs"; SUB="abstract-audit-logs-sub"; SINK="abstract-org-audit-sink"  # the Terraform and deploy-script default
SA="abstract-pubsub-reader"; WS_SA="abstract-workspace-reader"; RETENTION_DAYS=7
DA_SERVICES="bigquery.googleapis.com,storage.googleapis.com,cloudkms.googleapis.com"; DA_TYPES="ADMIN_READ,DATA_WRITE"
DATA_ACCESS=no; WORKSPACE=no; ALERTS=no
ORG_ID=""; SCOPE=""; SCOPE_ID=""; LOG_PROJECT=""; BILLING=""; WS_ADMIN=""; ALERT_EMAIL=""
# Keys go outside any checkout, in a folder only you can read, so they cannot be committed by accident.
KEY_DIR="${ABSTRACT_KEY_DIR:-$HOME/abstract-keys}"
KEY_FILE="$KEY_DIR/abstract-pubsub-key.json"; WS_KEY_FILE="$KEY_DIR/abstract-workspace-key.json"
SINK_CREATED_AT=0
# shellcheck disable=SC1090
[[ -f "$STATE" ]] && source "$STATE"

B=$'\033[1m'; P=$'\033[38;5;198m'; G=$'\033[0;32m'; Y=$'\033[0;33m'; R=$'\033[0;31m'; D=$'\033[2m'; O=$'\033[0m'
title() { printf '\n%s━━ %s %s━━%s\n' "$P" "$1" "$2" "$O"; }
say()   { printf '%s\n' "$*"; }
why()   { printf '%s   %s%s\n' "$D" "$*" "$O"; }
pass()  { printf '  %s✓%s %s\n' "$G" "$O" "$*"; PASSES=$((PASSES+1)); }
warn()  { printf '  %s!%s %s\n' "$Y" "$O" "$*"; WARNS=$((WARNS+1)); }
bad()   { printf '  %s✗%s %s\n' "$R" "$O" "$*"; FAILS=$((FAILS+1)); }
PASSES=0; WARNS=0; FAILS=0
CHECK_ONLY=false; ONLY_STEP=""

save() {
  $CHECK_ONLY && return 0
  umask 077
  # %q escapes every value, so an answer containing shell syntax is stored as text, never run.
  { echo "# Abstract GCP guided setup — your answers. Safe to delete; nothing secret is kept here."
    local v; for v in ORG_ID SCOPE SCOPE_ID LOG_PROJECT BILLING TOPIC SUB SINK SA RETENTION_DAYS DATA_ACCESS DA_SERVICES DA_TYPES \
      WORKSPACE WS_SA WS_ADMIN ALERTS ALERT_EMAIL SINK_CREATED_AT; do printf '%s=%q\n' "$v" "${!v}"; done; } > "$STATE"
}

# Ask with a default. In --check mode nothing is asked.
ask() { local q="$1" def="${2:-}" a; if $CHECK_ONLY; then printf '%s' "$def"; return; fi
  read -r -p "  $q${def:+ [$def]}: " a </dev/tty; printf '%s' "${a:-$def}"; }
yes_no() { $CHECK_ONLY && return 1; local a; read -r -p "  $1 [y/N] " a </dev/tty; [[ "$a" == y || "$a" == Y ]]; }

# Show the command, ask, run it. Returns the command's status; "no" is not a failure.
run() { printf '%s   $' "$D"; printf ' %q' "$@"; printf '%s\n' "$O"; if $CHECK_ONLY; then return 3; fi
  if yes_no "Run it?"; then "$@"; return $?; fi; say "  skipped"; return 3; }

need() { command -v "$1" >/dev/null || { bad "$1 is not installed. Cloud Shell has everything this needs."; exit 1; }; }
token() { gcloud auth print-access-token 2>/dev/null; }

# Which of these permissions does the signed-in principal hold on a resource?
# (the resource's own answer, from testIamPermissions — no guessing from role names)
held() {  # held <resource-url> perm...
  local url="$1"; shift
  local body; body=$(python3 -c 'import json,sys;print(json.dumps({"permissions":sys.argv[1:]}))' "$@")
  curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d "$body" "$url:testIamPermissions" \
    | python3 -c 'import json,sys
try: print(" ".join(json.load(sys.stdin).get("permissions",[])))
except Exception: print("")'
}
scope_url() { case "$SCOPE" in
  organization) echo "https://cloudresourcemanager.googleapis.com/v3/organizations/$SCOPE_ID" ;;
  folder)       echo "https://cloudresourcemanager.googleapis.com/v3/folders/$SCOPE_ID" ;;
  project)      echo "https://cloudresourcemanager.googleapis.com/v3/projects/$SCOPE_ID" ;; esac; }
scope_flag() { case "$SCOPE" in organization) echo "--organization=$SCOPE_ID" ;; folder) echo "--folder=$SCOPE_ID" ;; project) echo "--project=$SCOPE_ID" ;; esac; }
has() { [[ " $1 " == *" $2 "* ]]; }

# ─────────────────────────────────────────────────────────────────────────────
step1() {
  title 1 "Sign-in and organization"
  why "Everything below is checked for the account you are signed in as."
  local acct; acct=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
  [[ -n "$acct" ]] && pass "signed in as $acct" || { bad "not signed in. Run: gcloud auth login"; return; }

  local orgs; orgs=$(gcloud organizations list --format='value(ID,displayName)' 2>/dev/null)
  if [[ -z "$orgs" ]]; then bad "no organization visible to $acct. An organization is needed for org or folder scope; a project pilot still works."
  else
    [[ -z "$ORG_ID" && $(wc -l <<<"$orgs") -eq 1 ]] && ORG_ID=$(cut -f1 <<<"$orgs")
    if [[ -z "$ORG_ID" ]]; then say "  Organizations you can see:"; sed 's/^/    /' <<<"$orgs"; ORG_ID=$(ask "Organization ID"); fi
    gcloud organizations describe "$ORG_ID" >/dev/null 2>&1 && pass "organization $ORG_ID ($(gcloud organizations describe "$ORG_ID" --format='value(displayName)'))" || bad "cannot read organization $ORG_ID"
  fi

  if [[ -z "$SCOPE" ]] && ! $CHECK_ONLY; then
    say ""
    say "  ${B}Which part of Google Cloud should send logs?${O}"
    say "    1) the whole organization   — every project, including ones created later (recommended)"
    say "    2) one folder               — every project in it; anything outside is missed"
    say "    3) one project              — a pilot; does not cover other or future projects"
    case "$(ask "Choose 1, 2 or 3" 1)" in 2) SCOPE=folder ;; 3) SCOPE=project ;; *) SCOPE=organization ;; esac
  fi
  case "$SCOPE" in
    organization) SCOPE_ID="$ORG_ID" ;;
    folder) if [[ -z "$SCOPE_ID" || "$SCOPE_ID" == "$ORG_ID" ]]; then
              gcloud resource-manager folders list --organization="$ORG_ID" --format='table(ID,displayName)' 2>/dev/null | sed 's/^/    /'
              SCOPE_ID=$(ask "Folder ID"); fi ;;
    project) [[ -z "$SCOPE_ID" || "$SCOPE_ID" == "$ORG_ID" ]] && SCOPE_ID=$(ask "Project ID to pilot" "$(gcloud config get-value project 2>/dev/null)") ;;
  esac
  [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] && pass "scope: $SCOPE $SCOPE_ID" || bad "no scope chosen yet"
  save
}

# ─────────────────────────────────────────────────────────────────────────────
step2() {
  title 2 "What you can change"
  why "Each later step needs a specific permission. This asks Google directly which ones you hold."
  [[ -n "$SCOPE" && -n "$SCOPE_ID" ]] || { bad "choose a scope first (step 1)"; return; }
  local h; h=$(held "$(scope_url)" logging.sinks.create "resourcemanager.$( [[ $SCOPE == organization ]] && echo organizations || echo "${SCOPE}s" ).setIamPolicy")
  has "$h" logging.sinks.create && pass "create the log sink at the $SCOPE (step 4)" \
    || { bad "you cannot create a sink at the $SCOPE. You need roles/logging.configWriter there — not included in Organization Admin."
         why "An Organization Admin can grant it:  gcloud organizations add-iam-policy-binding $ORG_ID --member=user:$(gcloud config get-value account 2>/dev/null) --role=roles/logging.configWriter"; }
  has "$h" "resourcemanager.$( [[ $SCOPE == organization ]] && echo organizations || echo "${SCOPE}s" ).setIamPolicy" \
    && pass "turn on Data Access logs at the $SCOPE (step 6, optional)" \
    || warn "you cannot turn on Data Access logs at the $SCOPE (needs Organization Admin or Security Admin). Skip step 6 or ask them."
  if [[ -n "$ORG_ID" ]]; then
    local o; o=$(held "https://cloudresourcemanager.googleapis.com/v3/organizations/$ORG_ID" resourcemanager.projects.create)
    has "$o" resourcemanager.projects.create && pass "create a new logging project (step 3)" || warn "you cannot create projects in the organization; pick an existing logging project in step 3"
  fi
  if [[ -n "$LOG_PROJECT" ]]; then
    local p; p=$(held "https://cloudresourcemanager.googleapis.com/v3/projects/$LOG_PROJECT" pubsub.topics.create pubsub.subscriptions.create iam.serviceAccounts.create iam.serviceAccountKeys.create serviceusage.services.enable pubsub.topics.setIamPolicy)
    local miss=""; for x in pubsub.topics.create pubsub.subscriptions.create pubsub.topics.setIamPolicy iam.serviceAccounts.create iam.serviceAccountKeys.create serviceusage.services.enable; do
      has "$p" "$x" || miss+=" $x"; done
    [[ -z "$miss" ]] && pass "build the pipeline in $LOG_PROJECT (steps 3-5)" \
      || bad "missing in $LOG_PROJECT:$miss — Owner, or Pub/Sub Admin + Service Account Admin + Service Account Key Admin + Service Usage Admin"
    # The org policy that most often blocks the key in step 5.
    local kp; kp=$(gcloud resource-manager org-policies describe iam.disableServiceAccountKeyCreation --project="$LOG_PROJECT" --effective --format='value(booleanPolicy.enforced)' 2>/dev/null)
    [[ "$kp" == "True" ]] && bad "org policy iam.disableServiceAccountKeyCreation is enforced on $LOG_PROJECT: step 5 cannot create a key. Ask for an exception on this project." \
      || pass "service-account keys are allowed on $LOG_PROJECT"
  else
    warn "project checks run once the logging project is chosen (step 3)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
step3() {
  title 3 "Logging project"
  why "One dedicated project holds the topic, subscription and Abstract's service account."
  why "Not a workload project: whoever owns that project could read or break the pipeline."
  if [[ -z "$LOG_PROJECT" ]] && ! $CHECK_ONLY; then
    say "    1) use an existing project"
    say "    2) create a new one"
    if [[ "$(ask "Choose 1 or 2" 1)" == 2 ]]; then
      LOG_PROJECT=$(ask "New project ID (globally unique, e.g. <company>-security-logging)")
      local parent="--organization=$ORG_ID"; [[ "$SCOPE" == folder ]] && parent="--folder=$SCOPE_ID"
      run gcloud projects create "$LOG_PROJECT" "$parent" --name="Abstract security logging"
    else
      gcloud projects list --format='table(projectId,name)' --limit=30 2>/dev/null | sed 's/^/    /'
      LOG_PROJECT=$(ask "Logging project ID")
    fi
    save
  fi
  [[ -n "$LOG_PROJECT" ]] || { bad "no logging project chosen"; return; }
  local st; st=$(gcloud projects describe "$LOG_PROJECT" --format='value(lifecycleState)' 2>/dev/null)
  [[ "$st" == ACTIVE ]] && pass "project $LOG_PROJECT is active" || { bad "project $LOG_PROJECT not found or not active"; return; }

  local be; be=$(gcloud billing projects describe "$LOG_PROJECT" --format='value(billingEnabled)' 2>/dev/null)
  if [[ "$be" == True ]]; then pass "billing is linked"
  else
    warn "no billing linked. That is fine for this path: Pub/Sub and Logging free tiers cover an audit feed."
    why "Link billing only if you will use Infrastructure Manager or high-volume logs."
    if ! $CHECK_ONLY && yes_no "Link a billing account now?"; then
      gcloud billing accounts list --filter=open=true --format='table(name.basename(),displayName)' 2>/dev/null | sed 's/^/    /'
      BILLING=$(ask "Billing account ID"); save
      run gcloud billing projects link "$LOG_PROJECT" --billing-account="$BILLING"
    fi
  fi

  local apis="pubsub.googleapis.com logging.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com"
  [[ "$WORKSPACE" == yes ]] && apis+=" admin.googleapis.com"
  [[ "$ALERTS" == yes ]] && apis+=" monitoring.googleapis.com"
  local on; on=$(gcloud services list --enabled --project="$LOG_PROJECT" --format='value(config.name)' 2>/dev/null)
  local missing=""; for a in $apis; do grep -qx "$a" <<<"$on" || missing+=" $a"; done
  if [[ -z "$missing" ]]; then pass "APIs enabled: ${apis// /, }"
  else
    warn "APIs not enabled:$missing"
    # shellcheck disable=SC2086
    run gcloud services enable $missing --project="$LOG_PROJECT" && pass "APIs enabled"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
filter() {
  local f='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy"'
  if [[ "$DATA_ACCESS" == yes ]]; then
    local c=""; IFS=',' read -ra S <<<"$DA_SERVICES"; for s in "${S[@]}"; do c+="${c:+ OR }\"$s\""; done
    f+=" OR (logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND protoPayload.serviceName=($c))"
  fi
  printf '%s' "$f"
}

step4() {
  title 4 "Log pipeline"
  why "A sink at the ${SCOPE:-chosen scope} copies matching audit logs, as they are written, to a Pub/Sub topic."
  why "Abstract reads them from a subscription on that topic. There is no backfill: what the"
  why "filter misses while it is not in place is gone."
  [[ -n "$LOG_PROJECT" && -n "$SCOPE" ]] || { bad "finish steps 1 and 3 first"; return; }

  if gcloud pubsub topics describe "$TOPIC" --project="$LOG_PROJECT" >/dev/null 2>&1; then pass "topic $TOPIC"
  else warn "topic $TOPIC does not exist"; run gcloud pubsub topics create "$TOPIC" --project="$LOG_PROJECT" && pass "topic created"; fi

  if gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" >/dev/null 2>&1; then
    local ttl on; ttl=$(gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" --format='value(expirationPolicy.ttl)')
    on=$(gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" --format='value(topic)')
    [[ "$on" == "projects/$LOG_PROJECT/topics/$TOPIC" ]] && pass "subscription $SUB reads $TOPIC" \
      || bad "subscription $SUB reads $on, not $TOPIC: Abstract would read the wrong feed. Choose another subscription name (SUB) and re-run."
    [[ -z "$ttl" ]] && pass "subscription $SUB, never expires" || bad "subscription $SUB expires after $ttl idle — a quiet week deletes it. Fix: gcloud pubsub subscriptions update $SUB --project=$LOG_PROJECT --expiration-period=never"
  else
    warn "subscription $SUB does not exist"
    why "--expiration-period=never matters: by default an idle subscription is deleted after 31 days."
    run gcloud pubsub subscriptions create "$SUB" --topic="$TOPIC" --project="$LOG_PROJECT" \
      --ack-deadline=60 --message-retention-duration="${RETENTION_DAYS}d" --expiration-period=never && pass "subscription created"
  fi

  local sf; sf=$(scope_flag); local want; want=$(filter)
  local dest="pubsub.googleapis.com/projects/$LOG_PROJECT/topics/$TOPIC"
  # A sink already sending to this topic under another name is adopted, never duplicated:
  # two sinks to one topic deliver every event twice.
  if ! gcloud logging sinks describe "$SINK" "$sf" >/dev/null 2>&1; then
    local other; other=$(gcloud logging sinks list "$sf" --format='value(name,destination)' 2>/dev/null | awk -v d="$dest" '$2==d{print $1; exit}')
    [[ -n "$other" ]] && { say "  found sink $other already sending to $TOPIC; using it"; SINK="$other"; save; }
  fi
  if gcloud logging sinks describe "$SINK" "$sf" >/dev/null 2>&1; then
    local d f ic; d=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(destination)'); f=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(filter)')
    ic=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(includeChildren)')
    [[ "$d" == "$dest" ]] && pass "sink $SINK sends to $TOPIC" || bad "sink $SINK sends to $d, not $dest"
    if [[ "$SCOPE" != project ]]; then
      [[ "$ic" == True ]] && pass "sink covers every project under the $SCOPE (includeChildren)" \
        || bad "sink $SINK does not include child projects: logs from projects under the $SCOPE never reach Abstract. Recreate it with --include-children (or set include_children in Terraform)."
    fi
    # Only ever ADD what is missing. An existing sink may route more (firewall, DNS…); that is kept.
    local missing_clauses; missing_clauses=$(python3 - "$f" "$want" <<'PY'
import re, sys
have, want = sys.argv[1], sys.argv[2]
parts = [p.strip() for p in re.split(r"\s+OR\s+(?![^()]*\))", want) if p.strip()]
norm = lambda x: re.sub(r"\s+", " ", x)
print(" OR ".join(p for p in parts if norm(p) not in norm(have)))
PY
)
    if [[ -z "$missing_clauses" ]]; then pass "sink filter routes everything these answers need"
    else warn "the sink does not yet route: $missing_clauses"
         why "Its existing filter is kept; only the missing part is added. If Terraform manages this sink, add it there and answer no."
         run gcloud logging sinks update "$SINK" "$sf" --log-filter="($f) OR $missing_clauses" && pass "sink filter extended"; fi
  else
    warn "sink $SINK does not exist at the $SCOPE"
    say "   filter: $want"
    local ic=""; [[ "$SCOPE" != project ]] && ic="--include-children"
    # shellcheck disable=SC2086
    run gcloud logging sinks create "$SINK" "$dest" "$sf" $ic --log-filter="$want" && { pass "sink created"; SINK_CREATED_AT=$(date +%s); save; }
  fi

  local w; w=$(gcloud logging sinks describe "$SINK" "$sf" --format='value(writerIdentity)' 2>/dev/null)
  if [[ -n "$w" ]]; then
    if gcloud pubsub topics get-iam-policy "$TOPIC" --project="$LOG_PROJECT" --format=json 2>/dev/null | grep -q "\"$w\""; then
      pass "the sink's own identity can publish to $TOPIC"
    else
      bad "the sink's identity cannot publish yet — the #1 missed step. The sink looks healthy and sends nothing."
      run gcloud pubsub topics add-iam-policy-binding "$TOPIC" --project="$LOG_PROJECT" --member="$w" --role=roles/pubsub.publisher >/dev/null && pass "publisher granted to the sink identity"
    fi
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
step5() {
  title 5 "Abstract's access"
  why "Abstract signs in as its own service account and may only read the one subscription."
  why "Subscriber, never publisher, never project-wide."
  [[ -n "$LOG_PROJECT" ]] || { bad "finish step 3 first"; return; }
  local email="$SA@$LOG_PROJECT.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$email" --project="$LOG_PROJECT" >/dev/null 2>&1; then pass "service account $email"
  else warn "service account $email does not exist"
       run gcloud iam service-accounts create "$SA" --project="$LOG_PROJECT" --display-name="Abstract Security log reader" && pass "service account created"; fi

  if gcloud pubsub subscriptions get-iam-policy "$SUB" --project="$LOG_PROJECT" --format=json 2>/dev/null | grep -q "serviceAccount:$email"; then
    pass "it can read $SUB (roles/pubsub.subscriber on the subscription)"
  else
    bad "it cannot read $SUB yet"
    run gcloud pubsub subscriptions add-iam-policy-binding "$SUB" --project="$LOG_PROJECT" --member="serviceAccount:$email" --role=roles/pubsub.subscriber >/dev/null && pass "subscriber granted"
  fi
  # Anything broader than that one subscription is a finding, not a convenience.
  if gcloud projects get-iam-policy "$LOG_PROJECT" --flatten='bindings[].members' --filter="bindings.members:serviceAccount:$email" --format='value(bindings.role)' 2>/dev/null | grep -q .; then
    warn "$email also holds project-wide roles on $LOG_PROJECT. It needs none; remove them."
  else pass "no project-wide roles (least privilege)"; fi

  local n; n=$(gcloud iam service-accounts keys list --iam-account="$email" --managed-by=user --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')
  if [[ -f "$KEY_FILE" ]]; then pass "key file ready to upload: $KEY_FILE"
  elif [[ "${n:-0}" -gt 0 ]]; then pass "$n key(s) already exist; Abstract uses the one you uploaded. Make another only if it was lost."
    ! $CHECK_ONLY && yes_no "Create a new key anyway?" && make_key "$email" "$KEY_FILE"
  else warn "no key yet. Abstract needs one to sign in."; ! $CHECK_ONLY && make_key "$email" "$KEY_FILE"; fi
}

make_key() {
  why "The key is written to a file only you can read. Upload it to Abstract, then delete it."
  mkdir -p "$KEY_DIR" && chmod 700 "$KEY_DIR"
  run gcloud iam service-accounts keys create "$2" --iam-account="$1" && { chmod 600 "$2"; pass "key written to $2 (not printed)"; }
}

# ─────────────────────────────────────────────────────────────────────────────
audit_config_json() {  # the current auditConfigs at the scope, as JSON
  curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d '{}' "$(scope_url):getIamPolicy" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"etag":d.get("etag"),"auditConfigs":d.get("auditConfigs",[])}))'
}

step6() {
  title 6 "Data Access logs (optional)"
  why "Admin Activity logs are always on. Data Access logs (who read or changed data in BigQuery,"
  why "Cloud Storage, KMS…) are OFF until you turn them on. It takes TWO switches:"
  why "  switch 1 — generate them: the audit config at the ${SCOPE:-chosen scope}"
  why "  switch 2 — route them:    the sink filter (step 4 adds them when this is on)"
  why "Either alone does nothing, silently. DATA_READ is high volume; it is off by default here."
  if [[ "$DATA_ACCESS" != yes ]] && ! $CHECK_ONLY; then
    yes_no "Turn on Data Access logs?" || { say "  skipped — Admin Activity still flows"; return; }
    DATA_ACCESS=yes
    DA_SERVICES=$(ask "Services (comma-separated)" "$DA_SERVICES")
    DA_TYPES=$(ask "Log types (ADMIN_READ, DATA_WRITE, DATA_READ)" "$DA_TYPES")
    save
  fi
  [[ "$DATA_ACCESS" == yes ]] || { say "  off (your choice)"; return; }

  local cur; cur=$(audit_config_json)
  local missing; missing=$(python3 - "$cur" "$DA_SERVICES" "$DA_TYPES" <<'PY'
import json, sys
cur = json.loads(sys.argv[1]); svcs = sys.argv[2].split(","); types = sys.argv[3].split(",")
have = {}
for c in cur.get("auditConfigs", []):
    have.setdefault(c["service"], set()).update(l["logType"] for l in c.get("auditLogConfigs", []))
allsvc = have.get("allServices", set())
print(" ".join(f"{s}:{t}" for s in svcs for t in types if t not in have.get(s, set()) and t not in allsvc))
PY
)
  if [[ -z "$missing" ]]; then pass "switch 1: Data Access is generated for ${DA_SERVICES//,/, } ($DA_TYPES)"
  else
    bad "switch 1 is off for: $missing"
    why "This changes ONLY the audit settings at the ${SCOPE:-chosen scope} (updateMask=auditConfigs); role bindings are untouched."
    why "A copy of the current settings is saved first."
    if ! $CHECK_ONLY && yes_no "Turn switch 1 on now?"; then
      local backup; backup="$PWD/abstract-audit-config-backup-$(date +%Y%m%d%H%M%S).json"
      printf '%s\n' "$cur" > "$backup"; say "  saved current settings to $backup"
      local body; body=$(python3 - "$cur" "$DA_SERVICES" "$DA_TYPES" <<'PY'
import json, sys
cur = json.loads(sys.argv[1]); svcs = sys.argv[2].split(","); types = sys.argv[3].split(",")
cfgs = {c["service"]: c for c in cur.get("auditConfigs", [])}
for s in svcs:
    c = cfgs.setdefault(s, {"service": s, "auditLogConfigs": []})
    have = {l["logType"] for l in c["auditLogConfigs"]}
    c["auditLogConfigs"] += [{"logType": t} for t in types if t not in have]
print(json.dumps({"policy": {"etag": cur["etag"], "auditConfigs": list(cfgs.values())}, "updateMask": "auditConfigs"}))
PY
)
      local out; out=$(curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d "$body" "$(scope_url):setIamPolicy")
      grep -q '"error"' <<<"$out" && bad "Google refused: $(python3 -c 'import json,sys;print(json.load(sys.stdin)["error"]["message"])' <<<"$out")" || pass "switch 1 on"
    fi
  fi
  local sf; sf=$(scope_flag)
  gcloud logging sinks describe "$SINK" "$sf" --format='value(filter)' 2>/dev/null | grep -q 'data_access' \
    && pass "switch 2: the sink routes Data Access logs" || { bad "switch 2 is off: the sink filter does not include Data Access"; $CHECK_ONLY || { why "Step 4 updates the filter; running it now."; step4; }; }
}

# ─────────────────────────────────────────────────────────────────────────────
step7() {
  title 7 "Google Workspace logs (optional)"
  why "Sign-ins, admin changes and token grants in Google Workspace do NOT go through Cloud"
  why "Logging. Abstract reads them from the Workspace Reports API with a separate service"
  why "account that a Workspace SUPER ADMIN allows through domain-wide delegation."
  why "A Google Cloud Owner cannot do that last part; plan for the super admin."
  if [[ "$WORKSPACE" != yes ]] && ! $CHECK_ONLY; then
    yes_no "Set up Google Workspace logs?" || { say "  skipped"; return; }
    WORKSPACE=yes; WS_ADMIN=$(ask "Workspace admin email Abstract should act as" "$WS_ADMIN"); save
  fi
  [[ "$WORKSPACE" == yes ]] || { say "  off (your choice)"; return; }
  [[ -n "$LOG_PROJECT" ]] || { bad "finish step 3 first"; return; }

  gcloud services list --enabled --project="$LOG_PROJECT" --format='value(config.name)' 2>/dev/null | grep -qx admin.googleapis.com \
    && pass "Admin SDK API enabled" || { warn "Admin SDK API is off"; run gcloud services enable admin.googleapis.com --project="$LOG_PROJECT" && pass "Admin SDK API enabled"; }

  local email="$WS_SA@$LOG_PROJECT.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$email" --project="$LOG_PROJECT" >/dev/null 2>&1; then pass "service account $email"
  else warn "service account $email does not exist"
       run gcloud iam service-accounts create "$WS_SA" --project="$LOG_PROJECT" --display-name="Abstract Security Workspace reader" && pass "created"; fi
  # A new service account can take a few seconds to become readable.
  local cid="" i
  for i in 1 2 3 4 5 6; do
    cid=$(gcloud iam service-accounts describe "$email" --project="$LOG_PROJECT" --format='value(uniqueId)' 2>/dev/null)
    [[ -n "$cid" ]] && break; $CHECK_ONLY && break; sleep 5
  done
  [[ -n "$cid" ]] || { bad "cannot read $email yet. Run this step again in a minute."; return; }
  cat <<EOF

  ${B}Hand this to a Workspace super admin:${O}
    admin.google.com → Security → Access and data control → API controls
      → Domain-wide delegation → Add new
    Client ID     $cid
    OAuth scopes  https://www.googleapis.com/auth/admin.reports.audit.readonly,https://www.googleapis.com/auth/admin.reports.usage.readonly
    (one line, comma-separated, no spaces; both are read-only)

EOF
  [[ -f "$WS_KEY_FILE" ]] && pass "key file ready: $WS_KEY_FILE" || { ! $CHECK_ONLY && make_key "$email" "$WS_KEY_FILE"; }
  if [[ -f "$WS_KEY_FILE" && -n "$WS_ADMIN" ]]; then
    verify_workspace "$WS_KEY_FILE" "$WS_ADMIN"
  fi
}

# Prove delegation works: sign a JWT as the service account for the admin, call the Reports API.
verify_workspace() {
  local r; r=$(python3 - "$1" "$2" <<'PY' 2>&1
import json, sys, time, base64, urllib.request, urllib.parse, subprocess, tempfile, os
key = json.load(open(sys.argv[1])); sub = sys.argv[2]
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
now = int(time.time())
head = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
claim = b64(json.dumps({"iss": key["client_email"], "sub": sub, "aud": "https://oauth2.googleapis.com/token",
    "scope": "https://www.googleapis.com/auth/admin.reports.audit.readonly", "iat": now, "exp": now + 600}).encode())
with tempfile.NamedTemporaryFile("w", delete=False) as f:
    f.write(key["private_key"]); pem = f.name
try:
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", pem], input=head + b"." + claim, capture_output=True, check=True).stdout
finally:
    os.unlink(pem)
jwt = head + b"." + claim + b"." + b64(sig)
data = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": jwt.decode()}).encode()
try:
    tok = json.load(urllib.request.urlopen("https://oauth2.googleapis.com/token", data))["access_token"]
except urllib.error.HTTPError as e:
    desc = json.load(e).get("error_description", str(e))
    # A brand-new key is rejected as "Invalid signature" for about a minute. Never echo the token.
    print("NEWKEY" if "Invalid signature" in desc else "DELEGATION " + desc.split(": ey")[0][:200]); sys.exit()
req = urllib.request.Request("https://admin.googleapis.com/admin/reports/v1/activity/users/all/applications/login?maxResults=1", headers={"Authorization": "Bearer " + tok})
try:
    urllib.request.urlopen(req); print("OK")
except urllib.error.HTTPError as e:
    print(f"REPORTS {e.code}")
PY
)
  case "$r" in
    OK) pass "delegation works: the Reports API answered as $2" ;;
    NEWKEY) warn "the new key is not active yet (Google takes about a minute). Check again shortly: $0 --step 7 --check" ;;
    DELEGATION*) bad "delegation is not in place yet (${r#DELEGATION }). The super admin step above is still needed; it can take a few minutes after saving." ;;
    *) bad "the Reports API refused ($r). Check that $2 is a Workspace admin." ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
step8() {
  title 8 "Health alerts (optional)"
  why "A stopped pipeline is silent. These alerts tell you: sink export errors, no messages,"
  why "and Abstract not consuming. This runs the repo's gcp-monitoring-pipeline-health-alerts template."
  if [[ "$ALERTS" != yes ]] && ! $CHECK_ONLY; then
    yes_no "Set up health alerts?" || { say "  skipped"; return; }
    ALERTS=yes; save
  fi
  [[ "$ALERTS" == yes ]] || { say "  off (your choice)"; return; }
  # REST, not "gcloud alpha": the alpha component may not be installed, and installing it prompts.
  local have; have=$(curl -s -H "Authorization: Bearer $(token)" "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/alertPolicies?pageSize=200" \
    | python3 -c 'import json,sys;print(sum(1 for p in json.load(sys.stdin).get("alertPolicies",[]) if p.get("displayName","").startswith("Abstract log pipeline")))' 2>/dev/null)
  # gcp-monitoring-pipeline-health-alerts makes three policies without a dead-letter topic (this setup uses none).
  if [[ "${have:-0}" -ge 3 ]]; then pass "$have Abstract alert policies exist"; return; fi
  [[ "${have:-0}" -gt 0 ]] && warn "only ${have} of 3 alert policies exist" || warn "no Abstract alert policies yet"
  $CHECK_ONLY && return
  need terraform
  while [[ -z "$ALERT_EMAIL" ]]; do
    ALERT_EMAIL=$(ask "Email that receives the alerts")
    [[ -n "$ALERT_EMAIL" ]] || { yes_no "Create the alerts with nobody to tell?" && break; }
  done; save
  local dir="$ROOT/templates/gcp/gcp-monitoring-pipeline-health-alerts" ch="[]"
  if [[ -n "$ALERT_EMAIL" ]]; then
    local body; body=$(python3 -c 'import json,sys;print(json.dumps({"type":"email","displayName":"Abstract log pipeline","labels":{"email_address":sys.argv[1]}}))' "$ALERT_EMAIL")
    local cname; cname=$(curl -s -X POST -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" -d "$body" \
      "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/notificationChannels" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("name",""))')
    [[ -n "$cname" ]] || { bad "could not create the email channel for $ALERT_EMAIL; alerts not created, so none are silent. Check that the Monitoring API is on (step 3)."; return; }
    pass "email channel for $ALERT_EMAIL"; ch="[\"$cname\"]"
  fi
  python3 -c 'import json,sys;print(json.dumps({"log_project":sys.argv[1],"topic_id":sys.argv[2],"subscription_id":sys.argv[3],"notification_channels":json.loads(sys.argv[4]),"acknowledge_no_channel":sys.argv[4]=="[]"}, indent=2))' \
    "$LOG_PROJECT" "$TOPIC" "$SUB" "$ch" > "$dir/abstract.auto.tfvars.json"
  terraform -chdir="$dir" init -input=false >/dev/null || { bad "terraform init failed in $dir"; return; }
  terraform -chdir="$dir" plan -input=false -out=abstract.tfplan || { bad "terraform plan failed"; return; }
  # The plan above is the preview; approving it here is the only confirmation.
  run terraform -chdir="$dir" apply -input=false abstract.tfplan && pass "alerts created"
}

# Where the probe must be written: somewhere the sink can see, with an API that is on.
probe_project() {
  case "$SCOPE" in
    project) echo "$SCOPE_ID" ;;
    organization) echo "$LOG_PROJECT" ;;
    folder) if gcloud projects get-ancestors "$LOG_PROJECT" --format='value(id)' 2>/dev/null | grep -qx "$SCOPE_ID"; then echo "$LOG_PROJECT"
            else gcloud projects list --filter="parent.type=folder AND parent.id=$SCOPE_ID" --format='value(projectId)' --limit=1 2>/dev/null; fi ;;
  esac
}

step9() {
  title 9 "Test and verify"
  why "Writes a harmless admin event inside the ${SCOPE:-chosen scope} (creates and deletes a log-based metric),"
  why "then waits for it on a throwaway subscription on the same topic, never on Abstract's."
  why "A new sink routes nothing for about 3 minutes."
  [[ -n "$LOG_PROJECT" ]] || { bad "finish step 3 first"; return; }
  if $CHECK_ONLY; then
    gcloud pubsub subscriptions describe "$SUB" --project="$LOG_PROJECT" >/dev/null 2>&1 && pass "subscription is readable" || bad "subscription not found"
    return
  fi
  local pp; pp=$(probe_project)
  [[ -n "$pp" ]] || { bad "found no project inside folder $SCOPE_ID to write the test event in"; return; }
  yes_no "Send a test event from $pp now?" || return
  local age=$(( $(date +%s) - ${SINK_CREATED_AT:-0} ))
  if (( SINK_CREATED_AT > 0 && age < 240 )); then
    say "  the sink is $age seconds old; waiting $(( 240 - age ))s so it is routing before the test (an earlier event would be lost for good)"
    sleep $(( 240 - age ))
  fi
  local probe got="" i
  send_probe() {
    probe="abstract-probe-$(date +%s)"
    printf '%s   $ gcloud logging metrics create %s --project=%s … && gcloud logging metrics delete %s%s\n' "$D" "$probe" "$pp" "$probe" "$O"
    if gcloud logging metrics create "$probe" --project="$pp" --description="Abstract pipeline test; deleted at once" --log-filter='logName:"abstract-probe"' --quiet >/dev/null 2>&1; then
      gcloud logging metrics delete "$probe" --project="$pp" --quiet >/dev/null 2>&1
    # A log-based metric needs billing on the project. Without it, a Pub/Sub topic create and
    # delete writes the same kind of Admin Activity event.
    elif gcloud pubsub topics create "$probe" --project="$pp" --quiet >/dev/null 2>&1; then
      printf '%s   (no billing on %s, so the test event is a Pub/Sub topic create and delete instead)%s\n' "$D" "$pp" "$O"
      gcloud pubsub topics delete "$probe" --project="$pp" --quiet >/dev/null 2>&1
    else
      bad "could not write the test event in $pp (needs logging.logMetrics.create, or pubsub.topics.create, there)"; return 1
    fi
    say "  test event written ($probe)"
  }
  # Never pull from $SUB: with --auto-ack that deletes events before Abstract reads them, and
  # without it hides them from Abstract for the ack deadline. Read a throwaway subscription on
  # the same topic instead, created BEFORE the test event (it only receives later messages).
  local probe_sub; probe_sub="abstract-probe-sub-$(date +%s)"
  printf '%s   $ gcloud pubsub subscriptions create %s --topic=%s --project=%s --expiration-period=1d --message-retention-duration=10m%s\n' "$D" "$probe_sub" "$TOPIC" "$LOG_PROJECT" "$O"
  if ! gcloud pubsub subscriptions create "$probe_sub" --topic="$TOPIC" --project="$LOG_PROJECT" \
       --expiration-period=1d --message-retention-duration=10m --quiet >/dev/null 2>&1; then
    bad "could not create the probe subscription $probe_sub on $TOPIC (needs pubsub.subscriptions.create in $LOG_PROJECT)"; return
  fi
  send_probe || { gcloud pubsub subscriptions delete "$probe_sub" --project="$LOG_PROJECT" --quiet >/dev/null 2>&1; return; }
  say "  watching the probe subscription $probe_sub (on $TOPIC) for up to 5 minutes…"
  for i in $(seq 1 20); do
    sleep 15
    # Only this script reads the probe subscription, so acknowledging there is safe.
    got=$(gcloud pubsub subscriptions pull "$probe_sub" --project="$LOG_PROJECT" --limit=50 --auto-ack --format=json 2>/dev/null | python3 -c '
import base64, json, sys
for m in json.load(sys.stdin) or []:
    d = m.get("message", {}).get("data", "")
    try: d = base64.b64decode(d).decode("utf-8", "replace")
    except Exception: pass
    if sys.argv[1] in d: print(sys.argv[1]); break' "$probe")
    [[ -n "$got" ]] && break
    # One more event half way, in case the first was written before routing began.
    [[ $i -eq 10 ]] && { echo; send_probe || true; }
    printf '.'
  done; echo
  gcloud pubsub subscriptions delete "$probe_sub" --project="$LOG_PROJECT" --quiet >/dev/null 2>&1 \
    || warn "could not delete the probe subscription $probe_sub; it expires by itself after 1 day"
  [[ -n "$got" ]] && pass "the test event arrived on $TOPIC — the pipeline works end to end" \
    || bad "no test event after 5 minutes. Check sink errors: gcloud logging read 'logName:\"logging.googleapis.com%2Fsink_error\"' --project=$LOG_PROJECT --limit=5"
}

# ─────────────────────────────────────────────────────────────────────────────
step10() {
  title 10 "Connect Abstract"
  cat <<EOF
  In Abstract: Integrations → ${B}GCP Pub/Sub${O} (pull)
    Project ID        ${B}$LOG_PROJECT${O}     ← the project with the SUBSCRIPTION, not the ones sending logs
    Subscription ID   ${B}$SUB${O}      ← the short name only
    Credentials       ${B}$KEY_FILE${O}
EOF
  [[ "$WORKSPACE" == yes ]] && cat <<EOF

  In Abstract: Integrations → ${B}Google Workspace${O}
    Admin Email       ${B}$WS_ADMIN${O}
    Credentials       ${B}$WS_KEY_FILE${O}
    Applications      login, admin, token, saml, user_accounts, groups (start here)
EOF
  cat <<EOF

  After uploading, delete the key files:  rm -f "$KEY_FILE" "$WS_KEY_FILE"
  Re-check everything any time:           $0 --check
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC1090  # the state file is chosen at run time
while [[ $# -gt 0 ]]; do case "$1" in
  --check) CHECK_ONLY=true; shift ;;
  --step) ONLY_STEP="$2"; shift 2 ;;
  --state) STATE="$2"; shift 2; [[ -f "$STATE" ]] && source "$STATE" ;;
  -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option $1 (try --help)"; exit 2 ;; esac; done

need gcloud; need python3; need curl
printf '%sAbstract Security — Google Cloud guided setup%s%s\n' "$P" "$O" "$($CHECK_ONLY && echo '  (check only: nothing will change)')"
if [[ -n "$ONLY_STEP" ]]; then "step$ONLY_STEP"; else for s in 1 2 3 4 5 6 7 8 9 10; do "step$s"; done; fi
printf '\n%s%d passed%s · %s%d to look at%s · %s%d to fix%s\n' "$G" "$PASSES" "$O" "$Y" "$WARNS" "$O" "$R" "$FAILS" "$O"
[[ $FAILS -eq 0 ]]
