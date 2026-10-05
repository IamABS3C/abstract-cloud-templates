#!/usr/bin/env bash
# Check what is already true before deploying anything.
#
# Terraform fails at APPLY when a permission is missing — after it has created
# some resources. This checks first, so a missing organization-level grant is a
# message rather than a half-built pipeline.
#
# READ-ONLY. Every command here is a get or a list. It changes nothing.
set -uo pipefail

ORG_ID=""; FOLDER_ID=""; PROJECT=""; SCOPE="organization"; REPORT=""
TMP=$(mktemp -t abspf.XXXXXX); trap 'rm -f "$TMP"' EXIT
REC=()   # recommendations, printed as a plan at the end
rec() { REC+=("$1"); }
ok=0; warn=0; fail=0
g() { printf "  \033[32m✓\033[0m %s\n" "$1"; ok=$((ok+1)); }
w() { printf "  \033[33m!\033[0m %s\n" "$1"; warn=$((warn+1)); }
b() { printf "  \033[31m✗\033[0m %s\n" "$1"; fail=$((fail+1)); }
h() { printf "\n\033[1m%s\033[0m\n" "$1"; }

usage() {
  cat <<'EOF'
Usage: preflight.sh --project <id> [--org-id <id>] [--folder-id <id>] [--scope organization|folder|project]

Checks, all read-only:
  * who you are authenticated as
  * the APIs the pipeline needs
  * roles/logging.configWriter at the chosen scope  (THE usual blocker)
  * whether Data Access audit logging is already enabled, and for what
  * existing sinks that may already be exporting these logs
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org-id) ORG_ID="$2"; shift 2 ;;
    --folder-id) FOLDER_ID="$2"; SCOPE="folder"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --report) REPORT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1"; usage; exit 2 ;;
  esac
done
[[ -z "$PROJECT" ]] && { usage; exit 2; }

h "Identity"
# Three sources, because they fail in different environments:
#   config account   — unset under token auth (ADC, and Cloud Shell service accounts)
#   auth list        — empty when only ADC is present
#   token userinfo   — works whenever a token can be minted at all
ACCT=$(gcloud config get-value account 2>/dev/null | grep -v '^(unset)$' || true)
if [[ -z "$ACCT" ]]; then
  ACCT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
fi
if [[ -z "$ACCT" ]]; then
  _tok=$(gcloud auth application-default print-access-token 2>/dev/null || true)
  if [[ -n "$_tok" ]]; then
    ACCT=$(curl -s -H "Authorization: Bearer $_tok" \
             https://www.googleapis.com/oauth2/v3/userinfo 2>/dev/null \
           | python3 -c 'import json,sys; print(json.load(sys.stdin).get("email",""))' 2>/dev/null || true)
    [[ -n "$ACCT" ]] && ACCT="$ACCT (application-default credentials)"
  fi
fi
if [[ -n "$ACCT" ]]; then
  g "authenticated as $ACCT"
else
  b "not authenticated — run: gcloud auth login, or gcloud auth application-default login"
  rec "Authenticate first: gcloud auth application-default login"
fi

h "APIs on $PROJECT"
for api in pubsub.googleapis.com logging.googleapis.com; do
  if gcloud services list --enabled --project="$PROJECT" --filter="config.name=$api" --format="value(config.name)" 2>/dev/null | grep -q .; then
    g "$api enabled"
  else
    w "$api NOT enabled"
    rec "Enable $api — gcloud services enable $api --project=$PROJECT   (or deploy gcp-foundation-logging-project)"
  fi
done

h "Permission at $SCOPE scope"
case "$SCOPE" in
  organization)
    if [[ -z "$ORG_ID" ]]; then
      w "no --org-id given; skipping the organization checks"
    elif gcloud organizations get-iam-policy "$ORG_ID" --format=json >"$TMP" 2>/dev/null; then
      g "can read the organization IAM policy"
      # The policy file path is passed as argv[2]: the heredoc is quoted so the
      # shell does NOT expand $TMP inside it, and an earlier version tried to
      # interpolate it anyway — producing a FileNotFoundError that was swallowed,
      # so the "you do NOT hold configWriter" branch ran unconditionally.
      if python3 - "${ACCT%% (*}" "$TMP" <<'PY'
import json,sys
acct=sys.argv[1]
p=json.load(open(sys.argv[2]))
want={"roles/logging.configWriter","roles/logging.admin","roles/owner"}
hit=[b["role"] for b in p.get("bindings",[]) if b["role"] in want
     and any(acct in m for m in b.get("members",[]))]
sys.exit(0 if hit else 1)
PY
      then g "you hold logging.configWriter (or equivalent) at the ORGANIZATION"
      else
        b "you do NOT hold roles/logging.configWriter at the ORGANIZATION.
      This is THE blocking prerequisite and it is rarely held by the project owner.
      It is the single most common reason a GCP onboarding produces a decision
      list instead of a working feed."
        # Distinguish "you cannot get it" from "you can grant it to yourself".
        # An Organization Admin holds setIamPolicy and can self-grant; anyone else
        # has to go and find a human. Those are very different next steps, and
        # telling both groups the same thing wastes the admin's time.
        if python3 - "${ACCT%% (*}" "$TMP" <<'PY2'
import json,sys
acct=sys.argv[1]; p=json.load(open(sys.argv[2]))
can={"roles/resourcemanager.organizationAdmin","roles/owner"}
sys.exit(0 if [b for b in p.get("bindings",[]) if b["role"] in can
               and any(acct in m for m in b.get("members",[]))] else 1)
PY2
        then
          w "BUT you hold Organization Admin — you can grant it to yourself:"
          printf "      gcloud organizations add-iam-policy-binding %s --member='user:%s' --role='roles/logging.configWriter'\n" "$ORG_ID" "${ACCT%% (*}"
          rec "Self-grant (you are an Organization Admin): gcloud organizations add-iam-policy-binding $ORG_ID --member='user:${ACCT%% (*}' --role='roles/logging.configWriter'"
        else
          rec "BLOCKER: obtain roles/logging.configWriter at the ORGANIZATION from whoever holds Organization Admin. Nothing else can proceed without it."
        fi
      fi
    else
      b "cannot read the organization IAM policy — you likely lack organization access entirely"
    fi
    ;;
  folder|project)
    # Check ROLE MEMBERSHIP, not just whether the policy is readable. Reading it
    # proves nothing about whether you can create a sink, and a green tick that
    # means "I could read a file" is worse than no check.
    if [[ "$SCOPE" == "folder" ]]; then
      gcloud resource-manager folders get-iam-policy "$FOLDER_ID" --format=json >"$TMP" 2>/dev/null
    else
      gcloud projects get-iam-policy "$PROJECT" --format=json >"$TMP" 2>/dev/null
    fi
    if [[ -s "$TMP" ]]; then
      g "can read the $SCOPE IAM policy"
      if python3 - "${ACCT%% (*}" "$TMP" <<'PY2'
import json,sys
acct=sys.argv[1]; p=json.load(open(sys.argv[2]))
want={"roles/logging.configWriter","roles/logging.admin","roles/owner","roles/editor"}
hit=[b["role"] for b in p.get("bindings",[]) if b["role"] in want and any(acct in m for m in b.get("members",[]))]
sys.exit(0 if hit else 1)
PY2
      then g "you hold logging.configWriter (or equivalent) at the $SCOPE"
      else b "you do NOT hold roles/logging.configWriter at the $SCOPE"
           rec "Grant roles/logging.configWriter at the $SCOPE, or find who holds it."
      fi
    else
      b "cannot read the $SCOPE IAM policy"
    fi ;;
esac

h "Data Access audit logging"
printf "  Admin Activity is ALWAYS ON and cannot be disabled — nothing to check.\n"
printf "  Only Data Access is off by default. Current state:\n\n"
AUDIT=""
case "$SCOPE" in
  organization) [[ -n "$ORG_ID" ]] && AUDIT=$(gcloud organizations get-iam-policy "$ORG_ID" --format="json(auditConfigs)" 2>/dev/null) ;;
  folder)       [[ -n "$FOLDER_ID" ]] && AUDIT=$(gcloud resource-manager folders get-iam-policy "$FOLDER_ID" --format="json(auditConfigs)" 2>/dev/null) ;;
  project)      AUDIT=$(gcloud projects get-iam-policy "$PROJECT" --format="json(auditConfigs)" 2>/dev/null) ;;
esac
if [[ -n "$AUDIT" ]]; then
  echo "$AUDIT" | python3 -c '
import json,sys
d = json.load(sys.stdin) or {}
cfgs = d.get("auditConfigs") or []
if not cfgs:
    print("  !  Data Access is NOT enabled anywhere at this scope.")
    print("     A sink filter referencing data_access will match NOTHING, with no error,")
    print("     which is indistinguishable from a broken sink. Deploy gcp-foundation-data-access-audit-logs.")
else:
    for c in cfgs:
        svc = c.get("service", "?")
        types = ", ".join(l.get("logType", "?") for l in c.get("auditLogConfigs", []))
        ex = [m for l in c.get("auditLogConfigs", []) for m in l.get("exemptedMembers", [])]
        suffix = "  (exempt: %d)" % len(ex) if ex else ""
        print("  v  %s: %s%s" % (svc, types, suffix))
'
else
  w "could not read the audit config at $SCOPE scope"
  rec "Could not read the audit config at $SCOPE scope — check you can run get-iam-policy there."
fi
if echo "$AUDIT" | grep -q '"auditConfigs"'; then
  # If something already enabled DATA_READ, warn LOUDLY that gcp-foundation-data-access-audit-logs is
  # authoritative and its narrower default would REMOVE it. A security tool
  # silently switching off audit logging is the worst failure on this path.
  if echo "$AUDIT" | grep -q 'DATA_READ'; then
    printf "\n"
    w "DATA_READ is ALREADY enabled here — by a landing zone, a CIS benchmark, or a platform team."
    rec "DO NOT apply gcp-foundation-data-access-audit-logs with its default log_types. google_*_iam_audit_config is AUTHORITATIVE: applying [ADMIN_READ, DATA_WRITE] would REMOVE the existing DATA_READ. List every type you intend to keep, or target named services."
  fi
else
  rec "Data Access audit logging is not enabled. Deploy gcp-foundation-data-access-audit-logs BEFORE using any data_access log category — until then such a filter matches nothing, with no error."
fi

h "Project coverage — can you actually see the estate?"
if [[ -n "$ORG_ID" && "$SCOPE" == "organization" ]]; then
  # An aggregated sink covers projects by CONTAINMENT, so it does not need
  # per-project permission. But if you cannot even LIST the projects, you cannot
  # size the deployment, cannot tell the customer what is in scope, and cannot
  # spot the projects that will dominate the bill. Worth knowing before the call.
  TOTAL=$(gcloud projects list --filter="parent.id=$ORG_ID" --format="value(projectId)" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${TOTAL:-0}" -gt 0 ]]; then
    g "$TOTAL project(s) visible under the organization"
    printf "     %s\n" "$(gcloud projects list --filter="parent.id=$ORG_ID" --format='value(projectId)' 2>/dev/null | head -8 | tr '\n' ' ')"
    [[ "$TOTAL" -gt 8 ]] && printf "     ... and %d more\n" "$((TOTAL - 8))"

    # Projects you cannot READ are still covered by the sink. Say so explicitly,
    # because the instinct on seeing a permission error is to go get access to
    # every project — which is weeks of work that buys nothing here.
    NOACCESS=0
    for pj in $(gcloud projects list --filter="parent.id=$ORG_ID" --format="value(projectId)" 2>/dev/null | head -25); do
      gcloud projects describe "$pj" --format="value(projectId)" >/dev/null 2>&1 || NOACCESS=$((NOACCESS+1))
    done
    if [[ "$NOACCESS" -gt 0 ]]; then
      w "$NOACCESS project(s) you cannot read individually"
      printf "     This does NOT block the deployment. An aggregated sink covers projects by\n"
      printf "     CONTAINMENT, not by per-project permission — you need rights at the ORG,\n"
      printf "     not in each project. Do not go chasing per-project access.\n"
    else
      g "you can read every project you can see"
    fi
  else
    w "could not list projects under the organization"
    rec "You cannot enumerate projects. The sink will still work (containment), but you cannot size the deployment or predict cost. Ask for roles/resourcemanager.organizationViewer."
  fi
else
  printf "  Skipped — project coverage is only meaningful at organization scope.\n"
fi

h "Existing sinks (are these logs already going somewhere?)"
if [[ -n "$ORG_ID" && "$SCOPE" == "organization" ]]; then
  # _Required and _Default are GCP's built-in sinks. They exist in EVERY
  # organization, they write to the org's own log buckets, and they are not an
  # export anyone chose. Counting them as "someone may already be exporting
  # this" is noise that teaches people to ignore the check.
  CUSTOM=$(gcloud logging sinks list --organization="$ORG_ID" --format="value(name)" 2>/dev/null \
           | grep -vE '^_(Required|Default)$' | wc -l | tr -d ' ')
  if [[ "$CUSTOM" == "0" ]]; then
    g "no custom organization sinks (only GCP's built-in _Required/_Default)"
  else
    w "$CUSTOM custom organization sink(s) already exist"
    rec "Review the $CUSTOM existing custom organization sink(s) — confirm you are not about to duplicate an export and pay for both."
  fi
  gcloud logging sinks list --organization="$ORG_ID" --format="table(name,destination)" 2>/dev/null | sed 's/^/     /'
fi

h "Recommended next steps"
if [[ ${#REC[@]} -eq 0 ]]; then
  printf "  Nothing outstanding. Deploy gcp-source-audit-logs-organization.\n"
else
  i=1
  for r in "${REC[@]}"; do printf "  %d. %s\n" "$i" "$r"; i=$((i+1)); done
fi

h "Summary"
printf "  %d passed, %d warning(s), %d blocker(s)\n" "$ok" "$warn" "$fail"
if [[ "$fail" -gt 0 ]]; then
  printf "  \033[31mDo not deploy yet.\033[0m Resolve the blockers above first.\n\n"
else
  printf "  \033[32mReady to deploy.\033[0m\n\n"
fi

# ---- optional markdown report, for handing to a customer -------------------
if [[ -n "$REPORT" ]]; then
  {
    echo "# GCP log-export readiness assessment"
    echo
    echo "Generated by \`tools/gcp-guided-setup/preflight.sh\` — **read-only**, nothing was changed."
    echo
    echo "| | |"
    echo "|---|---|"
    echo "| Run by | \`$ACCT\` |"
    echo "| Logging project | \`$PROJECT\` |"
    echo "| Scope | \`$SCOPE\` |"
    [[ -n "$ORG_ID" ]] && echo "| Organization | \`$ORG_ID\` |"
    [[ -n "$FOLDER_ID" ]] && echo "| Folder | \`$FOLDER_ID\` |"
    echo "| Result | **$ok passed · $warn warning(s) · $fail blocker(s)** |"
    echo
    if [[ "$fail" -gt 0 ]]; then
      echo "> **Not ready to deploy.** Resolve the blockers below first."
    else
      echo "> **Ready to deploy.** Proceed with \`templates/gcp/gcp-source-audit-logs-organization\`."
    fi
    echo
    echo "## Actions required"
    echo
    if [[ ${#REC[@]} -eq 0 ]]; then
      echo "None."
    else
      i=1
      for r in "${REC[@]}"; do echo "$i. $r"; i=$((i+1)); done
    fi
    echo
    echo "## Notes that apply regardless of the result"
    echo
    echo "- **Admin Activity is always on and cannot be disabled.** Only Data Access needs enabling."
    echo "- **Routing is evaluated at write time. There is no backfill.** A filter that is too narrow leaves a permanent hole; one that is too wide costs money you can stop spending. Start broad, measure for 7 days, then tighten."
    echo "- **Pub/Sub publish quota is consumed in the destination project**, not in the source projects. Size \`$PROJECT\`, not the estate."
    echo "- Deploy \`gcp-monitoring-pipeline-health-alerts\` alongside the pipeline. Every failure mode on this path is silent by default."
  } > "$REPORT"
  printf "  Report written to %s\n\n" "$REPORT"
fi

[[ "$fail" -gt 0 ]] && exit 1 || exit 0
