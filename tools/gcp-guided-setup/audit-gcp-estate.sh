#!/usr/bin/env bash
# =============================================================================
#   Abstract Security — Google Cloud Estate Security & Telemetry Audit
#
#   READ-ONLY assessment script that inspects your GCP resource hierarchy,
#   existing log sinks, Pub/Sub pipelines, Data Access configs, network security
#   logging (Armor, IDS, DNS, Firewalls), Billing, SCC, Asset Feeds, and
#   Infrastructure Manager readiness.
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Read-only: gcloud must never stop to ask (for example "enable the Compute API and retry?"). A prompt
# here once left the audit waiting for hours on a project without the Compute API.
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

B=$'\033[1m'; P=$'\033[38;5;198m'; G=$'\033[0;32m'; Y=$'\033[0;33m'; R=$'\033[0;31m'; C=$'\033[0;36m'; D=$'\033[2m'; O=$'\033[0m'
# The Abstract header (brand.py: the official lockup, as in the Search & Export kit).
banner() { python3 "$HERE/brand.py" header "Google Cloud estate audit" "read-only - nothing will change"; }

# Every printer is silent in --json mode on its own, so no call site can leak text into it.
JSON_OUTPUT=false
heading() { $JSON_OUTPUT || printf "\n%s━━ %s %s━━%s\n" "$P" "$1" "$2" "$O"; }
pass()    { PASS_COUNT=$((PASS_COUNT+1)); $JSON_OUTPUT || printf "  %s✓%s %s\n" "$G" "$O" "$*"; }
warn()    { WARN_COUNT=$((WARN_COUNT+1)); $JSON_OUTPUT || printf "  %s!%s %s\n" "$Y" "$O" "$*"; }
fail()    { FAIL_COUNT=$((FAIL_COUNT+1)); $JSON_OUTPUT || printf "  %s✗%s %s\n" "$R" "$O" "$*"; }
info()    { $JSON_OUTPUT || printf "  %s•%s %s\n" "$C" "$O" "$*"; }
dim()     { $JSON_OUTPUT || printf "%s     %s%s\n" "$D" "$*" "$O"; }

PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0
TARGET_ORG=""
TARGET_PROJECT=""
REC_LIST=()
add_rec() { REC_LIST+=("$1"); }

# A read that fails is not an answer. Every lookup goes through rd, which keeps the command's status
# and the first line of what it said on stderr, so a denied or broken read is reported as "could not
# check" and never as an absence (a hidden failure once read as "Data Access logging is DISABLED").
#   rd <command...>   -> status of the command; stdout in $OUT, first error line in $ERR
# Call it directly, never inside $(...): a subshell would lose OUT and ERR.
RD_ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/abs-audit.XXXXXX") || exit 1
trap 'rm -f "$RD_ERR_FILE"' EXIT
OUT=""; ERR=""
rd() {
  local rc
  OUT=$("$@" 2>"$RD_ERR_FILE"); rc=$?
  ERR=$(grep -m1 '^ERROR' "$RD_ERR_FILE" || grep -m1 . "$RD_ERR_FILE" || true)
  ERR=${ERR:0:240}
  return $rc
}
# cant <what> [reason when Google said nothing]: the one way a failed read is reported.
cant() { warn "Could not check $1: ${ERR:-${2:-the answer could not be read}}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org-id) TARGET_ORG="$2"; shift 2 ;;
    --project) TARGET_PROJECT="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    -h|--help)
      echo "Usage: ./tools/gcp-guided-setup/audit-gcp-estate.sh [--org-id <ORG_ID>] [--project <PROJECT_ID>] [--json]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

! $JSON_OUTPUT && banner

# 1. Identity & Active Context
heading "1. Identity & Authenticated Context" "━━━━━━━━━━━━━━━━━━━━━━━━"
ACTIVE_ACCOUNT=$(gcloud config get-value account 2>/dev/null | grep -v "^(unset)$" || true)
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1 || true)
fi

if [[ -n "$ACTIVE_ACCOUNT" ]]; then
  : # reported once the token is proven to be this account, below
else
  fail "No active gcloud authentication detected. Run 'gcloud auth login' first."
  exit 1
fi

# A configured account is not a working sign-in: when gcloud needs to sign in again, every later call
# fails quietly and the audit used to report "no organization, 0 projects" as if the estate were empty.
# stderr stays out of TOKEN: gcloud writes WARNING lines there (impersonation prints one on every call), and a
# token with a warning in it reads as nobody to tokeninfo, which skipped the identity check below unseen.
if ! TOKEN=$(gcloud auth print-access-token 2>/dev/null) || [[ -z "$TOKEN" ]]; then
  fail "gcloud is signed in as $ACTIVE_ACCOUNT but cannot get a token: run 'gcloud auth login' (and 'gcloud auth application-default login'), then run this audit again. Nothing was checked."
  exit 2
fi

# The token, not the configured account, decides what this audit can see (gcloud-identity.sh, shared with
# abstract-gcp-setup.sh and preflight.sh).
# shellcheck source=gcloud-identity.sh
source "$HERE/gcloud-identity.sh"
TOKEN_EMAIL=$(gid_token_email "$TOKEN")
if ! gid_check "$ACTIVE_ACCOUNT" "$TOKEN_EMAIL"; then
  fail "$GID_LINE. Every result would be $TOKEN_EMAIL's view, so nothing was checked."
  exit 2
fi
if [[ "$GID_LINE" == "signed in as "* ]]; then pass "Authenticated as: ${B}$ACTIVE_ACCOUNT${O}"
else pass "Authenticated: ${B}$GID_LINE${O}"; fi

# 2. Resource Hierarchy Discovery
heading "2. Resource Hierarchy Discovery" "━━━━━━━━━━━━━━━━━━━━━━━"
ORGS_READ=true
if rd gcloud organizations list --format="value(ID,displayName)"; then DISCOVERED_ORGS="$OUT"
else DISCOVERED_ORGS=""; ORGS_READ=false; ORGS_ERR="$ERR"; fi
ORG_COUNT=$(echo "$DISCOVERED_ORGS" | grep -c . || true)

if [[ -z "$TARGET_ORG" && "$ORG_COUNT" -gt 0 ]]; then
  TARGET_ORG=$(echo "$DISCOVERED_ORGS" | head -n1 | awk '{print $1}')
fi

if [[ -n "$TARGET_ORG" ]]; then
  ORG_NAME=$(echo "$DISCOVERED_ORGS" | grep "^$TARGET_ORG" | awk '{print $2}' || echo "Org $TARGET_ORG")
  pass "Google Cloud Organization: ${B}$TARGET_ORG${O} (${ORG_NAME:-Primary Organization})"
elif ! $ORGS_READ; then
  ERR="$ORGS_ERR"; warn "Could not list organizations: ${ERR:-no answer}. Pass --org-id to audit one; the organization checks below are skipped."
else
  warn "No Google Cloud Organization detected. Operating at Folder or Project scope."
  add_rec "Organization scope provides centralized coverage. If you have an Org ID, specify via --org-id."
fi

# Discover Folders
if [[ -n "$TARGET_ORG" ]]; then
  if rd gcloud resource-manager folders list --organization="$TARGET_ORG" --format="value(ID,displayName)"; then
    FOLDER_COUNT=$(echo "$OUT" | grep -c . || true)
    if [[ "$FOLDER_COUNT" -gt 0 ]]; then
      info "Discovered $FOLDER_COUNT top-level folder(s) under Organization $TARGET_ORG"
    fi
  else
    cant "the folders under Organization $TARGET_ORG"
  fi
fi

# Discover Projects
if rd gcloud projects list --format="value(projectId,name)"; then
  ALL_PROJECTS="$OUT"
  PROJECT_COUNT=$(echo "$ALL_PROJECTS" | grep -c . || true)
  info "Discovered $PROJECT_COUNT accessible GCP project(s)"
else
  ALL_PROJECTS=""
  warn "Could not list projects: ${ERR:-no answer}. Pass --project to name the logging project."
fi

# The organization's sinks, read ONCE as JSON: a filter can span several lines, which a value() list
# would split into rows. SINK_ROWS has one line per sink other than Google's own _Required/_Default:
#   name <TAB> destination <TAB> disabled 0|1 <TAB> exports audit logs 0|1 <TAB> includeChildren 0|1 <TAB> filter summary
# SINKS_READ: true when Google answered with a sink list, false when the read failed (and nothing is inferred).
SINKS_READ=false; SINKS_JSON=""; SINK_ROWS=""; SINKS_ERR=""
if [[ -n "$TARGET_ORG" ]]; then
  if rd gcloud logging sinks list --organization="$TARGET_ORG" --format=json; then
    SINKS_JSON="$OUT"
    if SINK_ROWS=$(python3 -c '
import json, sys
sinks = json.loads(sys.argv[1] or "[]")
if not isinstance(sinks, list): sys.exit(3)
for s in sinks:
    name = s.get("name", "")
    if name in ("_Required", "_Default"): continue        # Google'"'"'s own; they export nothing
    flt = " ".join(str(s.get("filter", "")).split())
    audit = (not flt) or "cloudaudit.googleapis.com" in flt  # an empty filter exports every entry
    summary = (flt if len(flt) <= 110 else flt[:107] + "...") if flt else "(no filter: exports every log entry)"
    print("	".join([name or "?", s.get("destination") or "?", "1" if s.get("disabled") else "0",
                     "1" if audit else "0", "1" if s.get("includeChildren") else "0", summary]))
' "$SINKS_JSON" 2>/dev/null); then SINKS_READ=true
    else SINKS_ERR="the sink list was not JSON"; SINK_ROWS=""; fi
  else
    SINKS_ERR="$ERR"
  fi
fi

CANDIDATE_LOG_PROJECTS=()
while IFS=$'\t' read -r pid pname; do
  [[ -z "$pid" ]] && continue
  if [[ "$pid" =~ (log|audit|security|sec|siem|abstract) ]] || [[ "$pname" =~ (log|audit|security|sec|siem|abstract) ]]; then
    CANDIDATE_LOG_PROJECTS+=("$pid")
  fi
done <<< "$ALL_PROJECTS"

if [[ ${#CANDIDATE_LOG_PROJECTS[@]} -gt 0 ]]; then
  pass "Candidate Centralized Logging Project(s): ${B}${CANDIDATE_LOG_PROJECTS[*]}${O}"
fi
# Which project to inspect, most certain first: --project; the guided setup's saved answers; the project
# an organization sink already sends to over Pub/Sub; then the first log-like name. Picking the first
# name alone once inspected a leftover duplicate and said nothing about the project Abstract reads.
TARGET_REASON="--project"
if [[ -z "$TARGET_PROJECT" ]]; then
  saved="${ABSTRACT_GCP_STATE:-$HOME/.abstract-gcp-setup.env}"
  if [[ -f "$saved" ]]; then
    saved_org=$(sed -n 's/^ORG_ID=//p' "$saved" | head -n1 | tr -d "'\"")
    # Answers saved for another organization describe another estate: never mix the two.
    if [[ -z "$TARGET_ORG" || -z "$saved_org" || "$saved_org" == "$TARGET_ORG" ]]; then
      TARGET_PROJECT=$(sed -n 's/^LOG_PROJECT=//p' "$saved" | head -n1 | tr -d "'\"")
      TARGET_REASON="the guided setup's saved answers name it"
    fi
  fi
fi
if [[ -z "$TARGET_PROJECT" && -n "$TARGET_ORG" ]]; then
  # The AUDIT sink, not merely the first Pub/Sub one: the network-threat sink also sends to Pub/Sub.
  # A disabled sink sends nothing, so it never names the project Abstract reads.
  pubsub_sinks=$(echo "$SINK_ROWS" | awk -F'\t' '$3 == "0" && $2 ~ /^pubsub\.googleapis\.com\/projects\// {print $1 "\t" $2}')
  sink_line=$(echo "$pubsub_sinks" | awk -F'\t' '$1 == "abstract-org-audit-sink" || $2 ~ /\/topics\/abstract-audit-logs$/ {print; exit}')
  if [[ -z "$sink_line" && $(echo "$pubsub_sinks" | grep -c .) -eq 1 ]]; then sink_line="$pubsub_sinks"; fi
  if [[ -n "$sink_line" ]]; then
    TARGET_PROJECT=$(echo "$sink_line" | cut -f2 | sed -E 's|^pubsub\.googleapis\.com/projects/([^/]+)/.*|\1|')
    TARGET_REASON="the organization sink $(echo "$sink_line" | cut -f1) sends there"
  elif [[ -n "$pubsub_sinks" ]]; then
    warn "Several organization sinks send to Pub/Sub and none is the audit sink; pass --project to choose: $(echo "$pubsub_sinks" | cut -f1 | tr '\n' ' ')"
  fi
fi
if [[ -z "$TARGET_PROJECT" && ${#CANDIDATE_LOG_PROJECTS[@]} -gt 0 ]]; then
  TARGET_PROJECT="${CANDIDATE_LOG_PROJECTS[0]}"
  TARGET_REASON="first project with a logging-like name; pass --project to choose another"
fi

CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null | grep -v "^(unset)$" || true)
if [[ -z "$TARGET_PROJECT" ]]; then
  TARGET_PROJECT="$CURRENT_PROJECT"; TARGET_REASON="gcloud's current project"
fi
info "Active audit inspection target project: ${B}${TARGET_PROJECT:-none}${O} (${TARGET_REASON:-none found})"

# 3. Permissions & Policy Governance
heading "3. Permissions & Policy Governance" "━━━━━━━━━━━━━━━━━━━━━━"
# testIamPermissions answers with the subset of permissions the caller holds ({} when none), or with an
# error. An error names permissions too, so only the "permissions" list is ever read as an answer, and
# anything that is not a clean answer - no body, not JSON, any error - leaves the check unanswered.
granted()    { python3 -c 'import json,sys; d=json.loads(sys.argv[1] or "{}"); sys.exit(0 if sys.argv[2] in d.get("permissions",[]) else 1)' "$1" "$2" 2>/dev/null; }
perm_error() { python3 -c '
import json, sys
body = sys.argv[1].strip()
if not body: sys.exit(print("no answer from Google (network or sign-in problem)"))
try: d = json.loads(body)
except ValueError: sys.exit(print("the answer was not JSON"))
if not isinstance(d, dict): sys.exit(print("the answer was not a permissions list"))
e = d.get("error")
if e is not None: print((e.get("message") if isinstance(e, dict) else "") or "Google returned an error")
' "$1" 2>/dev/null || echo "the answer could not be read"; }

if [[ -n "$TARGET_ORG" && -n "$TOKEN" ]]; then
  # Only permissions an organization can answer for: Google rejects the whole call if one is not.
  ORG_PERMS_TEST=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "https://cloudresourcemanager.googleapis.com/v1/organizations/${TARGET_ORG}:testIamPermissions" \
    -d '{"permissions":["logging.sinks.create","resourcemanager.organizations.setIamPolicy","cloudasset.feeds.create"]}' 2>/dev/null || true)
  ORG_PERMS_ERROR=$(perm_error "$ORG_PERMS_TEST")

  if [[ -n "$ORG_PERMS_ERROR" ]]; then
    warn "Could not check organization permissions: $ORG_PERMS_ERROR"
  else
    if granted "$ORG_PERMS_TEST" logging.sinks.create; then
      pass "Organization Sink Creator (roles/logging.configWriter) is HELD"
    else
      fail "Organization Sink Creator (roles/logging.configWriter) is MISSING on Organization $TARGET_ORG"
      add_rec "Request 'roles/logging.configWriter' on Organization $TARGET_ORG to create aggregated organization-wide sinks."
    fi

    if granted "$ORG_PERMS_TEST" resourcemanager.organizations.setIamPolicy; then
      pass "Organization IAM Admin (resourcemanager.organizations.setIamPolicy) is HELD"
    else
      warn "Organization IAM Admin is MISSING. Needed for templates/gcp/gcp-foundation-data-access-audit-logs (Data Access Audit Configs)."
    fi

    if granted "$ORG_PERMS_TEST" cloudasset.feeds.create; then
      pass "Cloud Asset Owner (cloudasset.feeds.create) is HELD"
    else
      warn "Cloud Asset Owner is MISSING. Needed for templates/gcp/gcp-source-asset-and-iam-changes."
    fi
  fi

  # Google refuses securitycenter.* in an organization testIamPermissions call, so the right to CREATE
  # a notification config is never tested here. Which configs already exist is read in section 8.
  info "The permission to create SCC notification configs is not tested in advance: templates/gcp/gcp-source-security-command-center-findings needs roles/securitycenter.notificationConfigEditor on the organization."
fi

# Check Target Project permissions
if [[ -n "$TARGET_PROJECT" && -n "$TOKEN" ]]; then
  PROJ_PERMS_TEST=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "https://cloudresourcemanager.googleapis.com/v1/projects/${TARGET_PROJECT}:testIamPermissions" \
    -d '{"permissions":["pubsub.topics.create","pubsub.subscriptions.create","iam.serviceAccounts.create","iam.serviceAccountKeys.create","serviceusage.services.enable"]}' 2>/dev/null || true)

  PROJ_PERMS_ERROR=$(perm_error "$PROJ_PERMS_TEST")
  if [[ -n "$PROJ_PERMS_ERROR" ]]; then
    warn "Could not check permissions on '$TARGET_PROJECT': $PROJ_PERMS_ERROR"
  elif granted "$PROJ_PERMS_TEST" pubsub.topics.create && granted "$PROJ_PERMS_TEST" pubsub.subscriptions.create; then
    pass "Pub/Sub Admin on project '$TARGET_PROJECT' is HELD"
  else
    fail "Pub/Sub topic/subscription creation is MISSING on '$TARGET_PROJECT'"
  fi

  # Two constraints block the key Abstract's connector needs: the legacy boolean one and its managed
  # successor. An org that enforces only the managed one used to pass here as "keys are allowed".
  # Each lookup is on | off | unknown; keys are allowed only when BOTH answered and neither is on.
  KEY_LEGACY=unknown; KEY_LEGACY_ERR=""; KEY_MANAGED=unknown; KEY_MANAGED_ERR=""
  if rd gcloud resource-manager org-policies describe iam.disableServiceAccountKeyCreation \
      --project="$TARGET_PROJECT" --effective --format="value(booleanPolicy.enforced)"; then
    if [[ "$OUT" == "True" ]]; then KEY_LEGACY=on; else KEY_LEGACY=off; fi
  else KEY_LEGACY_ERR="${ERR:-no answer}"; fi
  if rd gcloud org-policies describe iam.managed.disableServiceAccountKeyCreation \
      --project="$TARGET_PROJECT" --effective --format=json; then
    # Enforced when any rule says enforce: true (conditional rules included); unreadable is unknown.
    KEY_MANAGED=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
if not isinstance(d, dict): raise ValueError
rules = (d.get("spec") or {}).get("rules") or []
print("on" if any(isinstance(r, dict) and r.get("enforce") is True for r in rules) else "off")
' "$OUT" 2>/dev/null) || { KEY_MANAGED=unknown; KEY_MANAGED_ERR="the answer was not a policy"; }
  else KEY_MANAGED_ERR="${ERR:-no answer}"; fi

  for c in iam.disableServiceAccountKeyCreation iam.managed.disableServiceAccountKeyCreation; do
    if [[ "$c" == iam.managed.* ]]; then st=$KEY_MANAGED; else st=$KEY_LEGACY; fi
    [[ "$st" == on ]] || continue
    fail "Org Policy blocks Service Account key creation on $TARGET_PROJECT: $c is ENFORCED"
    add_rec "Request an Org Policy exception for '$c' on project $TARGET_PROJECT: Abstract's connector needs a Service Account key."
  done
  if [[ "$KEY_LEGACY" == on || "$KEY_MANAGED" == on ]]; then
    dim "Abstract's connector needs a Service Account key; the guided setup's step 5 cannot create one."
  elif [[ "$KEY_LEGACY" == unknown || "$KEY_MANAGED" == unknown ]]; then
    why=""
    [[ "$KEY_LEGACY" == unknown ]] && why="iam.disableServiceAccountKeyCreation: $KEY_LEGACY_ERR"
    [[ "$KEY_MANAGED" == unknown ]] && why="${why:+$why; }iam.managed.disableServiceAccountKeyCreation: $KEY_MANAGED_ERR"
    warn "Could not check whether an org policy blocks Service Account key creation on $TARGET_PROJECT ($why). If one is enforced, the key Abstract's connector needs cannot be created; reading it needs Organization Policy Viewer."
  else
    pass "Org Policy allows Service Account key creation on $TARGET_PROJECT (iam.disableServiceAccountKeyCreation and iam.managed.disableServiceAccountKeyCreation are not enforced)"
  fi
fi

# 4. Existing Log Sinks & Pub/Sub Pipelines
heading "4. Existing Log Sinks & Telemetry Streams" "━━━━━━━━━━━━━━━━━━━━"
if [[ -n "$TARGET_ORG" ]]; then
  # Each sink is listed, so the existing exports can be judged here and not only counted. Google's own
  # _Required and _Default sinks exist in every organization and export nothing; they are left out.
  if ! $SINKS_READ; then
    ERR="$SINKS_ERR"; cant "organization sinks"
  else
    ORG_SINK_COUNT=$(echo "$SINK_ROWS" | grep -c . || true)
    if [[ "$ORG_SINK_COUNT" -gt 0 ]]; then
      AUDIT_EXPORTERS=$(echo "$SINK_ROWS" | awk -F'\t' '$3 == "0" && $4 == "1"' | grep -c . || true)
      pass "Found $ORG_SINK_COUNT Organization-level log sink(s), $AUDIT_EXPORTERS of them exporting audit logs"
      while IFS=$'\t' read -r s_name s_dest s_off s_audit s_children s_filter; do
        [[ -z "$s_name" ]] && continue
        flags=""
        [[ "$s_audit" == 1 ]] && flags=" [exports audit logs]"
        [[ "$s_children" == 0 ]] && flags="$flags [organization's own logs only: includeChildren is off]"
        [[ "$s_off" == 1 ]] && flags=" [disabled: exports nothing]"
        info "${B}$s_name${O} -> $s_dest$flags"
        dim "filter: $s_filter"
      done <<< "$SINK_ROWS"
      [[ "$AUDIT_EXPORTERS" -gt 0 ]] && dim "A sink already exporting audit logs may duplicate Abstract's: confirm you are not about to pay for the same export twice."
    else
      warn "No Organization-level log sinks configured. Org audit logs are not routed to central SIEM."
      add_rec "Deploy templates/gcp/gcp-source-audit-logs-organization to stream org-wide audit logs to Abstract Security."
    fi
  fi
fi

if [[ -n "$TARGET_PROJECT" ]]; then
  if rd gcloud pubsub topics list --project="$TARGET_PROJECT" --format="value(name)"; then
    if echo "$OUT" | grep -q "abstract-audit-logs"; then
      pass "Dedicated topic 'abstract-audit-logs' exists in '$TARGET_PROJECT'"
    fi
  else
    cant "Pub/Sub topics in $TARGET_PROJECT"
  fi
  if rd gcloud pubsub subscriptions list --project="$TARGET_PROJECT" --format="value(name)"; then
    if echo "$OUT" | grep -q "abstract-audit-logs-sub"; then
      pass "Dedicated subscription 'abstract-audit-logs-sub' exists in '$TARGET_PROJECT'"
    fi
  else
    cant "Pub/Sub subscriptions in $TARGET_PROJECT"
  fi
fi

# 5. Data Access Audit Logging Assessment
heading "5. Data Access Audit Logging Assessment" "━━━━━━━━━━━━━━━━━━━━"
# A policy that could not be read says nothing about Data Access: it is reported as unchecked and
# recommends nothing (a denied read once came out as "DISABLED" plus a template recommendation).
# AUDIT_TYPES: one line per audit config, "<service> <LOG_TYPE,LOG_TYPE>".
POLICY_READ=false
if [[ -n "$TARGET_ORG" ]]; then
  if rd gcloud organizations get-iam-policy "$TARGET_ORG" --format=json; then
    AUDIT_TYPES=$(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
if not isinstance(d, dict): sys.exit(3)
for c in d.get("auditConfigs", []):
    print(c.get("service", ""), ",".join(l.get("logType", "") for l in c.get("auditLogConfigs", [])))
' "$OUT" 2>/dev/null) && POLICY_READ=true
    $POLICY_READ || ERR="the IAM policy answer was not JSON"
  fi
  $POLICY_READ || cant "Data Access audit logging at Organization $TARGET_ORG"
fi
if $POLICY_READ; then
  AUDIT_SERVICES=$(echo "$AUDIT_TYPES" | awk 'NF {print $1}' | paste -sd, -)

  if echo "$AUDIT_SERVICES" | grep -q "allServices"; then
    warn "allServices is enabled for Data Access at Organization scope! (High volume & cost hazard)"
    add_rec "Scope Data Access logs to specific high-signal services via templates/gcp/gcp-foundation-data-access-audit-logs to optimize cost."
  elif [[ -n "$AUDIT_SERVICES" ]]; then
    pass "Scoped Data Access logging is active for: ${B}$AUDIT_SERVICES${O}"
  else
    warn "Data Access audit logging is DISABLED at Organization scope."
    dim "Admin Activity logs are on by default, but Data Access (BigQuery, GCS, IAM token minting) is off."
    add_rec "Deploy templates/gcp/gcp-foundation-data-access-audit-logs to enable Data Access logging for BigQuery, Storage, KMS, and IAM."
  fi

  # Identity telemetry. Google records GenerateAccessToken (impersonation) and STS ExchangeToken as
  # ADMIN_READ Data Access logs. For the other token methods Google's page disagrees with itself (read
  # 2026-10-12): Google's table of methods by permission type lists GenerateAccessToken and SignJwt under
  # ADMIN_READ, and GenerateIdToken, SignBlob and SignJwt under DATA_READ, while its per-method entries give
  # SignBlob, SignJwt and GenerateIdToken one ADMIN_READ and one DATA_READ permission each. So add DATA_READ
  # on iam.googleapis.com to be sure of SignBlob and GenerateIdToken (docs/public/gcp/IDENTITY.md), and the
  # pass below says exactly what ADMIN_READ alone covers. It enables token minting ONLY through the IAM API
  # (iam.googleapis.com) or allServices: an audit config naming iamcredentials.googleapis.com alone does
  # nothing. https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds
  logs_data_read() { echo "$AUDIT_TYPES" | awk -v s="$1" '($1 == s || $1 == "allServices") && $2 ~ /DATA_READ/ {f=1} END {exit !f}'; }
  logs_admin_read() { echo "$AUDIT_TYPES" | awk -v s="$1" '($1 == s || $1 == "allServices") && $2 ~ /ADMIN_READ/ {f=1} END {exit !f}'; }

  # The Abstract audit sink's filter decides which of those events ever leave Cloud Logging.
  # SINK_STATE: found (with its filter) | none (the list was read; no Abstract sink) | unread.
  SINK_STATE=unread; AUDIT_SINK_NAME=""; AUDIT_SINK_FILTER=""
  if $SINKS_READ; then
    AUDIT_SINK=$(python3 -c '
import json, sys
for s in json.loads(sys.argv[1] or "[]"):
    if s.get("name") == "abstract-org-audit-sink" or s.get("destination", "").endswith("/topics/abstract-audit-logs"):
        print(s.get("name", "")); print(s.get("filter", "")); break
' "$SINKS_JSON" 2>/dev/null) && SINK_STATE=none
    if [[ -n "$AUDIT_SINK" ]]; then
      SINK_STATE=found; AUDIT_SINK_NAME=$(head -n1 <<<"$AUDIT_SINK"); AUDIT_SINK_FILTER=$(tail -n +2 <<<"$AUDIT_SINK")
    fi
  fi
  SINK_REPORTED=false
  check_forwarded() {  # check_forwarded <serviceName the events carry>
    case "$SINK_STATE" in
      unread)
        $SINK_REPORTED || { warn "Could not read the organization's sinks, so whether identity events reach Abstract is unknown."; }
        SINK_REPORTED=true; return ;;
      none)
        $SINK_REPORTED || { warn "No Abstract audit sink was found at the organization, so identity events are not sent to Abstract."
                            add_rec "Deploy templates/gcp/gcp-source-audit-logs-organization with identity_access in log_categories (it routes iamcredentials.googleapis.com and sts.googleapis.com), or run guided script step 4."; }
        SINK_REPORTED=true; return ;;
    esac
    # One shared reader (sink_routes.py) checks each OR alternative; an empty filter routes everything.
    [[ -z $(python3 "$HERE/sink_routes.py" "$AUDIT_SINK_FILTER" "$1") ]] && return 0
    warn "The Abstract sink $AUDIT_SINK_NAME does not forward $1 Data Access events: they stay in Cloud Logging and never reach Abstract."
    # The same advice the guided setup prints for a Terraform-managed sink (sink_routes.py --tfvars), for
    # exactly the clause that is missing: identity services are routed by identity_access, never by
    # data_access_services, which the sink reads only with data_access_all.
    local tf; tf=$(python3 "$HERE/sink_routes.py" --tfvars "$AUDIT_SINK_FILTER" \
      "(logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND protoPayload.serviceName=(\"$1\"))" | paste -sd';' - | sed 's/;/; /g')
    add_rec "So the sink forwards $1: in templates/gcp/gcp-source-audit-logs-organization (its tfvars), ${tf:-add identity_access to log_categories}, then apply. A sink not managed by Terraform: run guided script step 4, which adds only the missing clause."
  }

  if logs_admin_read iam.googleapis.com && logs_data_read iam.googleapis.com; then
    pass "Service account token minting and impersonation is AUDITED (iam.googleapis.com, ADMIN_READ and DATA_READ)"
    check_forwarded iamcredentials.googleapis.com
  elif logs_admin_read iam.googleapis.com; then
    pass "Service account token minting and impersonation is AUDITED for GenerateAccessToken and SignJwt only (iam.googleapis.com, ADMIN_READ)"
    dim "Google's table of methods by permission type lists GenerateAccessToken and SignJwt under ADMIN_READ, and GenerateIdToken, SignBlob and SignJwt under DATA_READ; its per-method entries give SignBlob, SignJwt and GenerateIdToken one ADMIN_READ and one DATA_READ permission each. So add DATA_READ on iam.googleapis.com to be sure of SignBlob and GenerateIdToken, and measure the volume."
    check_forwarded iamcredentials.googleapis.com
  else
    warn "Service account token minting and impersonation is NOT audited"
    dim "GenerateAccessToken (e.g. gcloud --impersonate-service-account), SignBlob and SignJwt produce no audit events."
    dim "Google enables them only through the IAM API or allServices; listing iamcredentials.googleapis.com alone does nothing."
    add_rec "Add 'iam.googleapis.com' with ADMIN_READ to Data Access audit configs (templates/gcp/gcp-foundation-data-access-audit-logs) to record service account impersonation (GenerateAccessToken) and SignJwt, with DATA_READ too to be sure of SignBlob and GenerateIdToken, and add identity_access to log_categories in your gcp-source-audit-logs-* sink so it forwards them (or run guided script step 6, which does both)."
  fi

  if logs_admin_read sts.googleapis.com; then
    pass "Workload Identity Federation (sts.googleapis.com) token exchange is AUDITED (ADMIN_READ)"
    check_forwarded sts.googleapis.com
  else
    warn "Workload Identity Federation (sts.googleapis.com) token exchange is NOT audited"
    dim "External identity token exchanges (GitHub Actions OIDC, AWS/Azure federation) will not produce audit events."
    add_rec "Add 'sts.googleapis.com' with ADMIN_READ to Data Access audit configs (templates/gcp/gcp-foundation-data-access-audit-logs) to record Workload Identity Federation exchanges, and add identity_access to log_categories in your gcp-source-audit-logs-* sink so it forwards them (or run guided script step 6, which does both)."
  fi
fi

# 6. Network Threat Telemetry Assessment
heading "6. Network Threat Telemetry Assessment" "━━━━━━━━━━━━━━━━━━━━━"
# These logs are not Cloud Audit Log records. Abstract's managed GCP parser keeps only audit logs, so
# turning them on is worth it only together with a parser on their own Abstract configuration.
NOT_STORED="Abstract's managed GCP parser keeps only Cloud Audit Log records, so these logs are collected but not stored until a parser for them is attached to their own Abstract configuration (see templates/gcp/gcp-source-network-threat-logs)."
# Read in ONE project, named in every line: an unscoped list reads gcloud's current project and used to
# state its answer as a fact about the whole estate.
NP="$TARGET_PROJECT"
if [[ -z "$NP" ]]; then
  info "No project to inspect, so network logging was not checked: pass --project <id>."
else
  info "Network logging is read in $NP only; other projects were not checked (pass --project <id> to check another)."

  if rd gcloud compute backend-services list --project="$NP" --format="value(name,logConfig.enable)"; then
    BS_COUNT=$(echo "$OUT" | grep -c . || true)
    LOGGED_BS=$(echo "$OUT" | grep -c $'\tTrue$' || true)
    if [[ "$BS_COUNT" -eq 0 ]]; then
      info "No backend services in $NP"
    elif [[ "$LOGGED_BS" -gt 0 ]]; then
      pass "$LOGGED_BS of $BS_COUNT backend service(s) in $NP have request/Cloud Armor logging enabled"
    else
      warn "$BS_COUNT backend service(s) in $NP, none with request logging (Cloud Armor WAF decisions not logged)."
      add_rec "Enable 'logConfig { enable = true }' on the backend services in $NP to capture Cloud Armor WAF events. $NOT_STORED"
    fi
  else
    cant "backend service logging in $NP"
  fi

  if rd gcloud dns policies list --project="$NP" --format="value(name,enableLogging)"; then
    DNS_LOG_COUNT=$(echo "$OUT" | grep -c $'\tTrue$' || true)
    if [[ "$DNS_LOG_COUNT" -gt 0 ]]; then
      pass "$DNS_LOG_COUNT Cloud DNS server policy/policies in $NP have query logging ENABLED"
    else
      warn "No Cloud DNS server policy in $NP has query logging enabled. DNS query telemetry (C2/exfil detection) is OFF there."
      add_rec "Enable DNS Query Logging on the VPC networks in $NP to capture C2 beaconing and data exfiltration telemetry. $NOT_STORED"
    fi
  else
    cant "Cloud DNS query logging in $NP"
  fi

  if rd gcloud compute firewall-rules list --project="$NP" --format="value(name,logConfig.enable)"; then
    FW_COUNT=$(echo "$OUT" | grep -c . || true)
    FW_LOGGED=$(echo "$OUT" | grep -c $'\tTrue$' || true)
    if [[ "$FW_COUNT" -eq 0 ]]; then
      info "No firewall rules in $NP"
    elif [[ "$FW_LOGGED" -gt 0 ]]; then
      pass "$FW_LOGGED of $FW_COUNT firewall rule(s) in $NP have logging enabled"
    else
      warn "$FW_COUNT firewall rule(s) in $NP, none logged. Ingress/egress allow/deny decisions are not recorded."
      add_rec "Enable logging on critical ingress/deny firewall rules in $NP, then deploy templates/gcp/gcp-source-network-threat-logs. $NOT_STORED"
    fi
  else
    cant "firewall rule logging in $NP"
  fi
fi

# 7. Billing account audit: a billing account is a separate resource, with its own sinks
heading "7. Billing Account Telemetry Assessment" "━━━━━━━━━━━━━━━━━━━━"
if rd gcloud billing accounts list --filter="open=true" --format="value(name,displayName)"; then
  BILLING_ACCOUNTS="$OUT"
  while IFS=$'\t' read -r ba_id ba_name; do
    [[ -z "$ba_id" ]] && continue
    BA_RAW_ID=$(basename "$ba_id")
    pass "Active Billing Account: ${B}$BA_RAW_ID${O} ('$ba_name')"
    if rd gcloud logging sinks list --billing-account="$BA_RAW_ID" --format="value(name)"; then
      if [[ -n "$OUT" ]]; then
        pass "Billing Account $BA_RAW_ID has active log sink(s): $(echo "$OUT" | head -n1)"
      else
        warn "Billing Account $BA_RAW_ID has NO log sink. An organization sink routes the organization and the folders and projects under it; a billing account is a separate resource, so its logs are collected with a sink created on the billing account itself."
        add_rec "Deploy templates/gcp/gcp-source-billing-account-logs to collect billing account $BA_RAW_ID's audit logs (its IAM changes and project billing links)."
      fi
    else
      cant "sinks on billing account $BA_RAW_ID"
    fi
  done <<< "$BILLING_ACCOUNTS"
  # A listing that worked and returned nothing is not "billing is fine": nothing was looked at.
  [[ -z "$(tr -d '[:space:]' <<<"$BILLING_ACCOUNTS")" ]] && \
    info "No open billing account is visible to $(gcloud config get-value account 2>/dev/null || echo 'you'), so billing account logs were not assessed (needs roles/billing.viewer on the billing account)."
else
  cant "billing accounts"
fi

# 8. Security Command Center & Cloud Asset Inventory
heading "8. SCC Findings & Asset Feeds Assessment" "━━━━━━━━━━━━━━━━━━"
if [[ -n "$TARGET_ORG" ]]; then
  if rd gcloud scc notifications list "organizations/$TARGET_ORG" --format="value(name)"; then
    if [[ -n "$OUT" ]]; then
      pass "Security Command Center Notification Config found"
    else
      warn "No Security Command Center Notification Configs discovered at Organization scope."
      add_rec "Deploy templates/gcp/gcp-source-security-command-center-findings to stream real-time threat, vulnerability, and posture findings. Abstract's managed GCP parser keeps only Cloud Audit Log records, so findings are collected but not stored until a parser built from a captured finding is attached to the subscription's own Abstract configuration."
    fi
  else
    cant "Security Command Center notification configs at Organization $TARGET_ORG" \
      "the answer could not be read (SCC may not be activated, or you lack Security Center viewer rights)"
  fi

  if rd gcloud asset feeds list --organization="$TARGET_ORG" --format="value(name)"; then
    if [[ -n "$OUT" ]]; then
      pass "Cloud Asset Inventory real-time feed(s) discovered"
    else
      info "No Cloud Asset Inventory organization feeds configured."
      add_rec "Deploy templates/gcp/gcp-source-asset-and-iam-changes for real-time drift detection and IAM policy diff tracking. Asset changes are not stored by the audit-log configuration: attach the template's parsers/cloud-asset-inventory.yml to the subscription's own Abstract configuration."
    fi
  else
    cant "Cloud Asset Inventory feeds at Organization $TARGET_ORG"
  fi
fi

# Final Summary
heading "Audit Summary & Prioritized Action Plan" "━━━━━━━━━━━━━━━━━━━━━"
if ! $JSON_OUTPUT; then
  printf "\n  Audit Score: %s%d checks passed%s, %s%d warnings%s, %s%d critical blockers%s\n\n" \
    "$G" "$PASS_COUNT" "$O" "$Y" "$WARN_COUNT" "$O" "$R" "$FAIL_COUNT" "$O"

  if [[ ${#REC_LIST[@]} -gt 0 ]]; then
    printf "%sRecommended Actions in Priority Order:%s\n" "$B" "$O"
    idx=1
    for r in "${REC_LIST[@]}"; do
      printf "  %s%d.%s %s\n" "$P" "$idx" "$O" "$r"
      idx=$((idx+1))
    done
  else
    printf "  %sAll security, audit, and telemetry controls are optimal!%s\n" "$G" "$O"
  fi

  printf "\n%sOnboarding & Standalone Setup Options:%s\n" "$B" "$O"
  printf "  • Guided interactive walkthrough:  %scloudshell launch-tutorial tools/gcp-guided-setup/WALKTHROUGH.md%s\n" "$C" "$O"
  printf "  • Guided setup:                     %s./tools/gcp-guided-setup/abstract-gcp-setup.sh%s\n" "$C" "$O"
  printf "  • One template per source:          %stemplates/gcp/<template-id>/ (README.md and TUTORIAL.md)%s\n\n" "$C" "$O"
fi
