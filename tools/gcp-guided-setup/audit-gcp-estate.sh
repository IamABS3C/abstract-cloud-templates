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
banner() {
  printf "%s" "$P"
  cat <<'EOF'
    _   _         _                  _     ___                      _ _         
   /_\ | |__  ___| |_ _ _ __ _  __ _| |_  / __| ___ __ _  _ _ _(_) |_ _  _ 
  / _ \| '_ \(_-<  _| '_/ _` |/ _` |  _| \__ \/ -_) _| || | '_| |  _| || |
 /_/ \_\_.__/__/\__|_| \__,_|\__, |\__| |___/\___\__|\_,_|_| |_|\__|\_, |
                              |___/                                   |__/ 
EOF
  printf "%s" "$O"
  printf "%s   Google Cloud Platform Estate Security & Telemetry Audit%s\n\n" "$D" "$O"
}

heading() { printf "\n%s━━ %s %s━━%s\n" "$P" "$1" "$2" "$O"; }
pass()    { printf "  %s✓%s %s\n" "$G" "$O" "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
warn()    { printf "  %s!%s %s\n" "$Y" "$O" "$*"; WARN_COUNT=$((WARN_COUNT+1)); }
fail()    { printf "  %s✗%s %s\n" "$R" "$O" "$*"; FAIL_COUNT=$((FAIL_COUNT+1)); }
info()    { printf "  %s•%s %s\n" "$C" "$O" "$*"; }
dim()     { printf "%s     %s%s\n" "$D" "$*" "$O"; }

PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0
JSON_OUTPUT=false
TARGET_ORG=""
TARGET_PROJECT=""
REC_LIST=()
add_rec() { REC_LIST+=("$1"); }

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
! $JSON_OUTPUT && heading "1. Identity & Authenticated Context" "━━━━━━━━━━━━━━━━━━━━━━━━"
ACTIVE_ACCOUNT=$(gcloud config get-value account 2>/dev/null | grep -v "^(unset)$" || true)
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1 || true)
fi

if [[ -n "$ACTIVE_ACCOUNT" ]]; then
  ! $JSON_OUTPUT && pass "Authenticated as: ${B}$ACTIVE_ACCOUNT${O}"
else
  ! $JSON_OUTPUT && fail "No active gcloud authentication detected. Run 'gcloud auth login' first."
  exit 1
fi

# A configured account is not a working sign-in: when gcloud needs to sign in again, every later call
# fails quietly and the audit used to report "no organization, 0 projects" as if the estate were empty.
if ! TOKEN=$(gcloud auth print-access-token 2>&1) || [[ -z "$TOKEN" || "$TOKEN" == *ERROR* ]]; then
  ! $JSON_OUTPUT && fail "gcloud is signed in as $ACTIVE_ACCOUNT but cannot get a token: run 'gcloud auth login' (and 'gcloud auth application-default login'), then run this audit again. Nothing was checked."
  exit 2
fi

# 2. Resource Hierarchy Discovery
! $JSON_OUTPUT && heading "2. Resource Hierarchy Discovery" "━━━━━━━━━━━━━━━━━━━━━━━"
DISCOVERED_ORGS=$(gcloud organizations list --format="value(ID,displayName)" 2>/dev/null || true)
ORG_COUNT=$(echo "$DISCOVERED_ORGS" | grep -c . || true)

if [[ -z "$TARGET_ORG" && "$ORG_COUNT" -gt 0 ]]; then
  TARGET_ORG=$(echo "$DISCOVERED_ORGS" | head -n1 | awk '{print $1}')
fi

if [[ -n "$TARGET_ORG" ]]; then
  ORG_NAME=$(echo "$DISCOVERED_ORGS" | grep "^$TARGET_ORG" | awk '{print $2}' || echo "Org $TARGET_ORG")
  ! $JSON_OUTPUT && pass "Google Cloud Organization: ${B}$TARGET_ORG${O} (${ORG_NAME:-Primary Organization})"
else
  ! $JSON_OUTPUT && warn "No Google Cloud Organization detected. Operating at Folder or Project scope."
  add_rec "Organization scope provides centralized coverage. If you have an Org ID, specify via --org-id."
fi

# Discover Folders
if [[ -n "$TARGET_ORG" ]]; then
  FOLDERS=$(gcloud resource-manager folders list --organization="$TARGET_ORG" --format="value(ID,displayName)" 2>/dev/null || true)
  FOLDER_COUNT=$(echo "$FOLDERS" | grep -c . || true)
  if [[ "$FOLDER_COUNT" -gt 0 ]]; then
    ! $JSON_OUTPUT && info "Discovered $FOLDER_COUNT top-level folder(s) under Organization $TARGET_ORG"
  fi
fi

# Discover Projects
ALL_PROJECTS=$(gcloud projects list --format="value(projectId,name)" 2>/dev/null || true)
PROJECT_COUNT=$(echo "$ALL_PROJECTS" | grep -c . || true)
! $JSON_OUTPUT && info "Discovered $PROJECT_COUNT accessible GCP project(s)"

CANDIDATE_LOG_PROJECTS=()
while IFS=$'\t' read -r pid pname; do
  [[ -z "$pid" ]] && continue
  if [[ "$pid" =~ (log|audit|security|sec|siem|abstract) ]] || [[ "$pname" =~ (log|audit|security|sec|siem|abstract) ]]; then
    CANDIDATE_LOG_PROJECTS+=("$pid")
  fi
done <<< "$ALL_PROJECTS"

if [[ ${#CANDIDATE_LOG_PROJECTS[@]} -gt 0 ]]; then
  ! $JSON_OUTPUT && pass "Candidate Centralized Logging Project(s): ${B}${CANDIDATE_LOG_PROJECTS[*]}${O}"
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
  pubsub_sinks=$(gcloud logging sinks list --organization="$TARGET_ORG" --format="value(name,destination)" 2>/dev/null \
    | awk -F'\t' '$2 ~ /^pubsub\.googleapis\.com\/projects\//')
  sink_line=$(echo "$pubsub_sinks" | awk -F'\t' '$1 == "abstract-org-audit-sink" || $2 ~ /\/topics\/abstract-audit-logs$/ {print; exit}')
  if [[ -z "$sink_line" && $(echo "$pubsub_sinks" | grep -c .) -eq 1 ]]; then sink_line="$pubsub_sinks"; fi
  if [[ -n "$sink_line" ]]; then
    TARGET_PROJECT=$(echo "$sink_line" | sed -E 's|.*pubsub\.googleapis\.com/projects/([^/]+)/.*|\1|')
    TARGET_REASON="the organization sink $(echo "$sink_line" | cut -f1) sends there"
  elif [[ -n "$pubsub_sinks" ]]; then
    ! $JSON_OUTPUT && warn "Several organization sinks send to Pub/Sub and none is the audit sink; pass --project to choose: $(echo "$pubsub_sinks" | cut -f1 | tr '\n' ' ')"
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
! $JSON_OUTPUT && info "Active audit inspection target project: ${B}${TARGET_PROJECT:-none}${O} (${TARGET_REASON:-none found})"

# 3. Permissions & Policy Governance
! $JSON_OUTPUT && heading "3. Permissions & Policy Governance" "━━━━━━━━━━━━━━━━━━━━━━"
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
    ! $JSON_OUTPUT && warn "Could not check organization permissions: $ORG_PERMS_ERROR"
  else
    if granted "$ORG_PERMS_TEST" logging.sinks.create; then
      ! $JSON_OUTPUT && pass "Organization Sink Creator (roles/logging.configWriter) is HELD"
    else
      ! $JSON_OUTPUT && fail "Organization Sink Creator (roles/logging.configWriter) is MISSING on Organization $TARGET_ORG"
      add_rec "Request 'roles/logging.configWriter' on Organization $TARGET_ORG to create aggregated organization-wide sinks."
    fi

    if granted "$ORG_PERMS_TEST" resourcemanager.organizations.setIamPolicy; then
      ! $JSON_OUTPUT && pass "Organization IAM Admin (resourcemanager.organizations.setIamPolicy) is HELD"
    else
      ! $JSON_OUTPUT && warn "Organization IAM Admin is MISSING. Needed for templates/gcp/gcp-foundation-data-access-audit-logs (Data Access Audit Configs)."
    fi

    if granted "$ORG_PERMS_TEST" cloudasset.feeds.create; then
      ! $JSON_OUTPUT && pass "Cloud Asset Owner (cloudasset.feeds.create) is HELD"
    else
      ! $JSON_OUTPUT && warn "Cloud Asset Owner is MISSING. Needed for templates/gcp/gcp-source-asset-and-iam-changes."
    fi
  fi

  # Security Command Center permissions cannot be tested on an organization ahead of time.
  ! $JSON_OUTPUT && info "SCC notifications cannot be checked in advance: templates/gcp/gcp-source-security-command-center-findings needs roles/securitycenter.notificationConfigEditor on the organization."
fi

# Check Target Project permissions
if [[ -n "$TARGET_PROJECT" && -n "$TOKEN" ]]; then
  PROJ_PERMS_TEST=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    "https://cloudresourcemanager.googleapis.com/v1/projects/${TARGET_PROJECT}:testIamPermissions" \
    -d '{"permissions":["pubsub.topics.create","pubsub.subscriptions.create","iam.serviceAccounts.create","iam.serviceAccountKeys.create","serviceusage.services.enable"]}' 2>/dev/null || true)

  PROJ_PERMS_ERROR=$(perm_error "$PROJ_PERMS_TEST")
  if [[ -n "$PROJ_PERMS_ERROR" ]]; then
    ! $JSON_OUTPUT && warn "Could not check permissions on '$TARGET_PROJECT': $PROJ_PERMS_ERROR"
  elif granted "$PROJ_PERMS_TEST" pubsub.topics.create && granted "$PROJ_PERMS_TEST" pubsub.subscriptions.create; then
    ! $JSON_OUTPUT && pass "Pub/Sub Admin on project '$TARGET_PROJECT' is HELD"
  else
    ! $JSON_OUTPUT && fail "Pub/Sub topic/subscription creation is MISSING on '$TARGET_PROJECT'"
  fi

  KEY_POLICY=$(gcloud resource-manager org-policies describe iam.disableServiceAccountKeyCreation \
    --project="$TARGET_PROJECT" --effective --format="value(booleanPolicy.enforced)" 2>/dev/null || true)
  if [[ "$KEY_POLICY" == "True" ]]; then
    ! $JSON_OUTPUT && warn "Org Policy 'iam.disableServiceAccountKeyCreation' is ENFORCED on $TARGET_PROJECT"
    dim "Abstract connector requires a Service Account Key."
    add_rec "Request an Org Policy exemption for 'iam.disableServiceAccountKeyCreation' on project $TARGET_PROJECT."
  else
    ! $JSON_OUTPUT && pass "Org Policy allows Service Account key creation on $TARGET_PROJECT"
  fi
fi

# 4. Existing Log Sinks & Pub/Sub Pipelines
! $JSON_OUTPUT && heading "4. Existing Log Sinks & Telemetry Streams" "━━━━━━━━━━━━━━━━━━━━"
if [[ -n "$TARGET_ORG" ]]; then
  # Google's own _Required and _Default sinks exist in every organization; they export nothing.
  ORG_SINKS=$(gcloud logging sinks list --organization="$TARGET_ORG" --format="value(name,destination)" 2>/dev/null \
    | grep -v -E '^_(Required|Default)\b' || true)
  ORG_SINK_COUNT=$(echo "$ORG_SINKS" | grep -c . || true)
  if [[ "$ORG_SINK_COUNT" -gt 0 ]]; then
    ! $JSON_OUTPUT && pass "Found $ORG_SINK_COUNT Organization-level log sink(s)"
  else
    ! $JSON_OUTPUT && warn "No Organization-level log sinks configured. Org audit logs are not routed to central SIEM."
    add_rec "Deploy templates/gcp/gcp-source-audit-logs-organization to stream org-wide audit logs to Abstract Security."
  fi
fi

if [[ -n "$TARGET_PROJECT" ]]; then
  PUBSUB_TOPICS=$(gcloud pubsub topics list --project="$TARGET_PROJECT" --format="value(name)" 2>/dev/null || true)
  if echo "$PUBSUB_TOPICS" | grep -q "abstract-audit-logs"; then
    ! $JSON_OUTPUT && pass "Dedicated topic 'abstract-audit-logs' exists in '$TARGET_PROJECT'"
  fi
  PUBSUB_SUBS=$(gcloud pubsub subscriptions list --project="$TARGET_PROJECT" --format="value(name)" 2>/dev/null || true)
  if echo "$PUBSUB_SUBS" | grep -q "abstract-audit-logs-sub"; then
    ! $JSON_OUTPUT && pass "Dedicated subscription 'abstract-audit-logs-sub' exists in '$TARGET_PROJECT'"
  fi
fi

# 5. Data Access Audit Logging Assessment
! $JSON_OUTPUT && heading "5. Data Access Audit Logging Assessment" "━━━━━━━━━━━━━━━━━━━━"
if [[ -n "$TARGET_ORG" ]]; then
  ORG_AUDIT_CONFIG=$(gcloud organizations get-iam-policy "$TARGET_ORG" --format=json 2>/dev/null || true)
  AUDIT_SERVICES=$(echo "$ORG_AUDIT_CONFIG" | python3 -c '
import json, sys
data = json.load(sys.stdin)
configs = data.get("auditConfigs", [])
svcs = [c.get("service") for c in configs]
print(",".join(svcs))
' 2>/dev/null || true)

  if echo "$AUDIT_SERVICES" | grep -q "allServices"; then
    ! $JSON_OUTPUT && warn "allServices is enabled for Data Access at Organization scope! (High volume & cost hazard)"
    add_rec "Scope Data Access logs to specific high-signal services via templates/gcp/gcp-foundation-data-access-audit-logs to optimize cost."
  elif [[ -n "$AUDIT_SERVICES" ]]; then
    ! $JSON_OUTPUT && pass "Scoped Data Access logging is active for: ${B}$AUDIT_SERVICES${O}"
  else
    ! $JSON_OUTPUT && warn "Data Access audit logging is DISABLED at Organization scope."
    dim "Admin Activity logs are on by default, but Data Access (BigQuery, GCS, IAM token minting) is off."
    add_rec "Deploy templates/gcp/gcp-foundation-data-access-audit-logs to enable Data Access logging for BigQuery, Storage, KMS, and IAM."
  fi

  # Identity telemetry. Google records token minting (GenerateAccessToken, SignBlob, SignJwt) and STS
  # ExchangeToken as ADMIN_READ Data Access logs, and enables token minting ONLY through the IAM API
  # (iam.googleapis.com) or allServices: an audit config naming iamcredentials.googleapis.com alone does
  # nothing. https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds
  AUDIT_TYPES=$(echo "$ORG_AUDIT_CONFIG" | python3 -c '
import json, sys
for c in json.load(sys.stdin).get("auditConfigs", []):
    print(c.get("service", ""), ",".join(l.get("logType", "") for l in c.get("auditLogConfigs", [])))
' 2>/dev/null || true)
  logs_admin_read() { echo "$AUDIT_TYPES" | awk -v s="$1" '($1 == s || $1 == "allServices") && $2 ~ /ADMIN_READ/ {f=1} END {exit !f}'; }

  # The Abstract audit sink's filter decides which of those events ever leave Cloud Logging.
  # SINK_STATE: found (with its filter) | none (the list was read; no Abstract sink) | unread.
  SINK_STATE=unread; AUDIT_SINK_NAME=""; AUDIT_SINK_FILTER=""
  if SINKS_JSON=$(gcloud logging sinks list --organization="$TARGET_ORG" --format=json 2>/dev/null); then
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
        $SINK_REPORTED || { ! $JSON_OUTPUT && warn "Could not read the organization's sinks, so whether identity events reach Abstract is unknown."; }
        SINK_REPORTED=true; return ;;
      none)
        $SINK_REPORTED || { ! $JSON_OUTPUT && warn "No Abstract audit sink was found at the organization, so identity events are not sent to Abstract."
                            add_rec "Deploy templates/gcp/gcp-source-audit-logs-organization with data_access_all and these services in data_access_services."; }
        SINK_REPORTED=true; return ;;
    esac
    # One shared reader (sink_routes.py) checks each OR alternative; an empty filter routes everything.
    [[ -z $(python3 "$HERE/sink_routes.py" "$AUDIT_SINK_FILTER" "$1") ]] && return 0
    ! $JSON_OUTPUT && warn "The Abstract sink $AUDIT_SINK_NAME does not forward $1 Data Access events: they stay in Cloud Logging and never reach Abstract."
    add_rec "Add '$1' to data_access_services in templates/gcp/gcp-source-audit-logs-organization and apply, so the sink forwards those events."
  }

  if logs_admin_read iam.googleapis.com; then
    ! $JSON_OUTPUT && pass "Service account token minting and impersonation is AUDITED (iam.googleapis.com, ADMIN_READ)"
    check_forwarded iamcredentials.googleapis.com
  else
    ! $JSON_OUTPUT && warn "Service account token minting and impersonation is NOT audited"
    dim "GenerateAccessToken, SignBlob and SignJwt (e.g. gcloud --impersonate-service-account) produce no audit events."
    dim "Google enables them only through the IAM API or allServices; listing iamcredentials.googleapis.com alone does nothing."
    add_rec "Add 'iam.googleapis.com' with ADMIN_READ to Data Access audit configs (templates/gcp/gcp-foundation-data-access-audit-logs) to record service account token minting and impersonation."
  fi

  if logs_admin_read sts.googleapis.com; then
    ! $JSON_OUTPUT && pass "Workload Identity Federation (sts.googleapis.com) token exchange is AUDITED (ADMIN_READ)"
    check_forwarded sts.googleapis.com
  else
    ! $JSON_OUTPUT && warn "Workload Identity Federation (sts.googleapis.com) token exchange is NOT audited"
    dim "External identity token exchanges (GitHub Actions OIDC, AWS/Azure federation) will not produce audit events."
    add_rec "Add 'sts.googleapis.com' with ADMIN_READ to Data Access audit configs (templates/gcp/gcp-foundation-data-access-audit-logs) to record Workload Identity Federation exchanges."
  fi
fi

# 6. Network Threat Telemetry Assessment
! $JSON_OUTPUT && heading "6. Network Threat Telemetry Assessment" "━━━━━━━━━━━━━━━━━━━━━"
BACKEND_SERVICES=$(gcloud compute backend-services list --format="value(name,logConfig.enable)" 2>/dev/null || true)
BS_COUNT=$(echo "$BACKEND_SERVICES" | grep -c . || true)
if [[ "$BS_COUNT" -gt 0 ]]; then
  LOGGED_BS=$(echo "$BACKEND_SERVICES" | grep "True" | wc -l | tr -d " " || true)
  if [[ "$LOGGED_BS" -gt 0 ]]; then
    ! $JSON_OUTPUT && pass "Discovered $LOGGED_BS Backend Service(s) with request/Cloud Armor logging enabled"
  else
    ! $JSON_OUTPUT && warn "Backend services exist but none have request logging enabled (Cloud Armor WAF decisions not logged)."
    add_rec "Enable 'logConfig { enable = true }' on Backend Services to capture Cloud Armor WAF events."
  fi
fi

DNS_POLICIES=$(gcloud dns policies list --format="value(name,enableLogging)" 2>/dev/null || true)
DNS_LOG_COUNT=$(echo "$DNS_POLICIES" | grep "True" | wc -l | tr -d " " || true)
if [[ "$DNS_LOG_COUNT" -gt 0 ]]; then
  ! $JSON_OUTPUT && pass "Discovered $DNS_LOG_COUNT Cloud DNS server policy/policies with query logging ENABLED"
else
  ! $JSON_OUTPUT && warn "No Cloud DNS Server Policies with query logging enabled. DNS query telemetry (C2/exfil detection) is OFF."
  add_rec "Enable DNS Query Logging on VPC networks to capture high-value C2 beaconing and data exfiltration telemetry."
fi

FIREWALL_LOGS=$(gcloud compute firewall-rules list --format="value(name,logConfig.enable)" 2>/dev/null || true)
FW_LOGGED=$(echo "$FIREWALL_LOGS" | grep "True" | wc -l | tr -d " " || true)
if [[ "$FW_LOGGED" -gt 0 ]]; then
  ! $JSON_OUTPUT && pass "$FW_LOGGED Firewall rule(s) have logging enabled"
else
  ! $JSON_OUTPUT && warn "Zero firewall rules have rule logging enabled. Ingress/egress allow/deny decisions are not recorded."
  add_rec "Enable logging on critical ingress/deny firewall rules, then deploy templates/gcp/gcp-source-network-threat-logs."
fi

# 7. Out-of-Hierarchy Billing Account Audit
! $JSON_OUTPUT && heading "7. Billing Account Telemetry Assessment" "━━━━━━━━━━━━━━━━━━━━"
BILLING_ACCOUNTS=$(gcloud billing accounts list --filter="open=true" --format="value(name,displayName)" 2>/dev/null || true)
BA_COUNT=$(echo "$BILLING_ACCOUNTS" | grep -c . || true)
if [[ "$BA_COUNT" -gt 0 ]]; then
  while IFS=$'\t' read -r ba_id ba_name; do
    [[ -z "$ba_id" ]] && continue
    BA_RAW_ID=$(basename "$ba_id")
    ! $JSON_OUTPUT && pass "Active Billing Account: ${B}$BA_RAW_ID${O} ('$ba_name')"
    BA_SINKS=$(gcloud logging sinks list --billing-account="$BA_RAW_ID" --format="value(name)" 2>/dev/null || true)
    if [[ -n "$BA_SINKS" ]]; then
      ! $JSON_OUTPUT && pass "Billing Account $BA_RAW_ID has active log sink(s): $(echo "$BA_SINKS" | head -n1)"
    else
      ! $JSON_OUTPUT && warn "Billing Account $BA_RAW_ID has NO log sink. Billing changes & project linkings are invisible to Org sinks."
      add_rec "Deploy templates/gcp/gcp-source-billing-account-logs to capture out-of-hierarchy billing IAM and project association changes."
    fi
  done <<< "$BILLING_ACCOUNTS"
fi

# 8. Security Command Center & Cloud Asset Inventory
! $JSON_OUTPUT && heading "8. SCC Findings & Asset Feeds Assessment" "━━━━━━━━━━━━━━━━━━"
if [[ -n "$TARGET_ORG" ]]; then
  SCC_NOTIFS=$(gcloud scc notifications list "organizations/$TARGET_ORG" --format="value(name)" 2>/dev/null || true)
  if [[ -n "$SCC_NOTIFS" ]]; then
    ! $JSON_OUTPUT && pass "Security Command Center Notification Config found"
  else
    ! $JSON_OUTPUT && warn "No Security Command Center Notification Configs discovered at Organization scope."
    add_rec "Deploy templates/gcp/gcp-source-security-command-center-findings to stream real-time threat, vulnerability, and posture findings to Abstract."
  fi

  ASSET_FEEDS=$(gcloud asset feeds list --organization="$TARGET_ORG" --format="value(name)" 2>/dev/null || true)
  if [[ -n "$ASSET_FEEDS" ]]; then
    ! $JSON_OUTPUT && pass "Cloud Asset Inventory real-time feed(s) discovered"
  else
    ! $JSON_OUTPUT && info "No Cloud Asset Inventory organization feeds configured."
    add_rec "Deploy templates/gcp/gcp-source-asset-and-iam-changes for real-time drift detection and IAM policy diff tracking."
  fi
fi

# Final Summary
! $JSON_OUTPUT && heading "Audit Summary & Prioritized Action Plan" "━━━━━━━━━━━━━━━━━━━━━"
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
