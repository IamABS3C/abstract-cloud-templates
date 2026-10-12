#!/usr/bin/env bash
# Check what is already true before deploying anything.
#
# Terraform fails at APPLY when a permission is missing — after it has created
# some resources. This checks first, so a missing organization-level grant is a
# message rather than a half-built pipeline.
#
# READ-ONLY. Every command here is a get or a list. It changes nothing.
set -uo pipefail
# gcloud must never stop to ask a question: its questions go to stderr, which these lookups hide, so a hidden
# "enable this API and retry? (y/N)" would freeze the check (measured 2026-10-08 in the estate audit).
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

python3 "$HERE/brand.py" header "Google Cloud preflight" "read-only - nothing will change"
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
# The token, not the configured account, decides what every check below can see (gcloud-identity.sh, shared
# with abstract-gcp-setup.sh and audit-gcp-estate.sh): stop when it is someone else's, instead of reporting
# another account's view. Impersonating a service account on purpose is accepted, and named.
# shellcheck source=gcloud-identity.sh
source "$HERE/gcloud-identity.sh"
WHO_LINE=""
if [[ -n "$ACCT" && "$ACCT" != *"(application-default credentials)" ]]; then
  _who=$(gid_token_email "$(gcloud auth print-access-token 2>/dev/null)")
  if ! gid_check "$ACCT" "$_who"; then
    b "$GID_LINE. Every check would be $_who's view, so nothing was checked."
    exit 1
  fi
  [[ "$GID_LINE" == "signed in as "* ]] || WHO_LINE="$GID_LINE"
fi
if [[ -n "$WHO_LINE" ]]; then
  g "$WHO_LINE"
elif [[ -n "$ACCT" ]]; then
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
# Ask the scope itself, with testIamPermissions: Google answers for every route to a permission (a
# group, a custom role, an inherited grant), which a scan of the direct bindings cannot - that scan
# blocked people who held the right through a group, and matched bob@x.com inside jimbob@x.com.
# Only the "permissions" list is an answer. An error names permissions too, so an error object, an
# empty body or a non-JSON body is "could not check", and a check that could not run never blocks.
ME="${ACCT%% (*}"
case "$ME" in *.gserviceaccount.com) MEMBER="serviceAccount:$ME" ;; *) MEMBER="user:$ME" ;; esac
SCOPE_ID=""; SCOPE_URL=""; SETIAM=""; GRANT_CMD=""
case "$SCOPE" in
  organization)
    if [[ -z "$ORG_ID" ]]; then
      b "no --org-id given, so nothing at the organization was checked. Pass --org-id <id> (gcloud organizations list), or --scope project / --folder-id for a narrower deployment."
      rec "Run preflight again with --org-id: an organization deployment cannot be checked without it."
    else
      SCOPE_ID="$ORG_ID"; SCOPE_URL="https://cloudresourcemanager.googleapis.com/v3/organizations/$ORG_ID"
      SETIAM=resourcemanager.organizations.setIamPolicy
      GRANT_CMD="gcloud organizations add-iam-policy-binding $ORG_ID"
    fi ;;
  folder)
    if [[ -z "$FOLDER_ID" ]]; then
      b "no --folder-id given, so nothing at the folder was checked. Pass --folder-id <id>."
      rec "Run preflight again with --folder-id: a folder deployment cannot be checked without it."
    else
      SCOPE_ID="$FOLDER_ID"; SCOPE_URL="https://cloudresourcemanager.googleapis.com/v3/folders/$FOLDER_ID"
      SETIAM=resourcemanager.folders.setIamPolicy
      GRANT_CMD="gcloud resource-manager folders add-iam-policy-binding $FOLDER_ID"
    fi ;;
  project)
    SCOPE_ID="$PROJECT"; SCOPE_URL="https://cloudresourcemanager.googleapis.com/v3/projects/$PROJECT"
    SETIAM=resourcemanager.projects.setIamPolicy
    GRANT_CMD="gcloud projects add-iam-policy-binding $PROJECT" ;;
  *)
    b "unknown --scope '$SCOPE': use organization, folder or project" ;;
esac
if [[ -n "$SCOPE_URL" ]]; then
  TOKEN=$(gcloud auth print-access-token 2>/dev/null) || TOKEN=""
  [[ -z "$TOKEN" ]] && { TOKEN=$(gcloud auth application-default print-access-token 2>/dev/null) || TOKEN=""; }
  ANSWER=""
  if [[ -n "$TOKEN" ]]; then
    ANSWER=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"permissions\":[\"logging.sinks.create\",\"$SETIAM\"]}" "$SCOPE_URL:testIamPermissions" 2>/dev/null) || ANSWER=""
  fi
  # Prints the permissions held, one per line; exits 1 (printing why) when the answer is not a clean list.
  HELD=$(python3 -c '
import json, sys
def no(why): print(why); sys.exit(1)
body = sys.argv[1].strip()
if not sys.argv[2]: no("no access token (run: gcloud auth login)")
if not body: no("no answer from Google (network or sign-in problem)")
try: d = json.loads(body)
except ValueError: no("the answer was not JSON")
if not isinstance(d, dict): no("the answer was not a permissions list")
e = d.get("error")
if e is not None: no((e.get("message") if isinstance(e, dict) else "") or "Google returned an error")
p = d.get("permissions", [])
if not isinstance(p, list): no("the answer was not a permissions list")
print("\n".join(p))
' "$ANSWER" "${TOKEN:+y}" 2>/dev/null)
  HELD_RC=$?
  if [[ "$HELD_RC" -ne 0 ]]; then
    w "could not check whether you can create sinks at the $SCOPE ($SCOPE_ID): ${HELD:-the answer could not be read}"
    rec "Could not confirm you can create sinks at the $SCOPE. Check before deploying: gcloud logging sinks list --$SCOPE=$SCOPE_ID works for viewers too, so ask whoever manages IAM whether $ME holds logging.sinks.create (roles/logging.configWriter) there."
  elif grep -qx 'logging.sinks.create' <<<"$HELD"; then
    g "you can create sinks at the $SCOPE ($SCOPE_ID): Google confirms logging.sinks.create, through whichever role or group grants it"
  else
    b "you cannot create sinks at the $SCOPE ($SCOPE_ID): logging.sinks.create (roles/logging.configWriter) is not held.
      This is THE blocking prerequisite and it is rarely held by the project owner.
      It is the single most common reason a GCP onboarding produces a decision
      list instead of a working feed."
    # Someone who can change the policy can grant it to themselves; anyone else has to find a human.
    if grep -qx "$SETIAM" <<<"$HELD"; then
      w "BUT you can change the $SCOPE IAM policy ($SETIAM) — you can grant it to yourself:"
      printf "      %s --member='%s' --role='roles/logging.configWriter'\n" "$GRANT_CMD" "$MEMBER"
      rec "Self-grant (you can change the $SCOPE IAM policy): $GRANT_CMD --member='$MEMBER' --role='roles/logging.configWriter'"
    else
      rec "BLOCKER: obtain roles/logging.configWriter at the $SCOPE ($SCOPE_ID) from whoever administers its IAM policy. Nothing else can proceed without it."
    fi
  fi
fi

h "Data Access audit logging"
printf "  Admin Activity is ALWAYS ON and cannot be disabled — nothing to check.\n"
printf "  Data Access is off by default for every service except BigQuery, which writes its Data Access logs by default. Current state:\n\n"
AUDIT=""
case "$SCOPE" in
  organization) [[ -n "$ORG_ID" ]] && AUDIT=$(gcloud organizations get-iam-policy "$ORG_ID" --format="json(auditConfigs)" 2>/dev/null) ;;
  folder)       [[ -n "$FOLDER_ID" ]] && AUDIT=$(gcloud resource-manager folders get-iam-policy "$FOLDER_ID" --format="json(auditConfigs)" 2>/dev/null) ;;
  project)      AUDIT=$(gcloud projects get-iam-policy "$PROJECT" --format="json(auditConfigs)" 2>/dev/null) ;;
esac
# What gcp-foundation-data-access-audit-logs sets on EVERY service it names, with its defaults: one
# log_types list and one exempted_members list. A service whose settings today differ from that is
# changed by an apply that names it, so each one is marked.
TEMPLATE_TYPES="ADMIN_READ,DATA_WRITE"
if [[ -n "$AUDIT" ]]; then
  echo "$AUDIT" | python3 -c '
import json,sys
d = json.load(sys.stdin) or {}
cfgs = d.get("auditConfigs") or []
want = set(sys.argv[1].split(","))
if not cfgs:
    print("  !  Data Access is NOT enabled anywhere at this scope.")
    print("     A sink filter referencing data_access will match NOTHING, with no error,")
    print("     which is indistinguishable from a broken sink. Deploy gcp-foundation-data-access-audit-logs.")
else:
    print("  Compared with what gcp-foundation-data-access-audit-logs sets, with its defaults, on every service")
    print("  it names: log types %s, and no exempted members.\n" % ", ".join(sorted(want)))
    for c in cfgs:
        svc = c.get("service", "?")
        types = [l.get("logType", "?") for l in c.get("auditLogConfigs", [])]
        ex = sorted({m for l in c.get("auditLogConfigs", []) for m in l.get("exemptedMembers", [])})
        print("  v  %s: %s" % (svc, ", ".join(types)))
        if ex:
            print("       exempted: %s" % ", ".join(ex))
        why = []
        if set(types) - want: why.append("has " + ", ".join(sorted(set(types) - want)))
        if want - set(types): why.append("lacks " + ", ".join(sorted(want - set(types))))
        if ex: why.append("has exempted members")
        if why:
            print("       differs from what the template sets (%s): naming it replaces that" % "; ".join(why))
        else:
            print("       same as what the template sets")
' "$TEMPLATE_TYPES"
else
  w "could not read the audit config at $SCOPE scope"
  rec "Could not read the audit config at $SCOPE scope — check you can run get-iam-policy there."
fi
if [[ -z "$AUDIT" ]]; then
  :   # unread: reported above, and an unread config says nothing about what is enabled
elif echo "$AUDIT" | grep -q '"auditConfigs"'; then
  # google_*_iam_audit_config is AUTHORITATIVE PER NAMED SERVICE: for each service it names (allServices
  # when services is empty) apply replaces that service's whole audit config - every log type and every
  # exempted member - and destroy removes it. Naming services narrows WHICH configs are replaced; it
  # does not make replacing them safe. So the inputs must carry what is already there.
  TODAY=$(echo "$AUDIT" | python3 -c '
import json, sys
out = []
for c in (json.load(sys.stdin) or {}).get("auditConfigs") or []:
    types = [l.get("logType", "?") for l in c.get("auditLogConfigs", [])]
    ex = sorted({m for l in c.get("auditLogConfigs", []) for m in l.get("exemptedMembers", [])})
    out.append("%s [%s%s]" % (c.get("service", "?"), ", ".join(types), "; exempted " + ", ".join(ex) if ex else ""))
print("; ".join(out))
' 2>/dev/null)
  if echo "$AUDIT" | grep -q 'DATA_READ'; then
    # A security tool silently switching off audit logging is the worst failure on this path.
    printf "\n"
    w "DATA_READ is ALREADY enabled here — by a landing zone, a CIS benchmark, or a platform team."
  fi
  # The services an apply would change: those with DATA_READ, exempted members, or other log types.
  DIFFER=$(echo "$AUDIT" | python3 -c '
import json, sys
want = set(sys.argv[1].split(","))
out = []
for c in (json.load(sys.stdin) or {}).get("auditConfigs") or []:
    types = {l.get("logType", "?") for l in c.get("auditLogConfigs", [])}
    if types != want or any(l.get("exemptedMembers") for l in c.get("auditLogConfigs", [])):
        out.append(c.get("service", "?"))
print(", ".join(out))
' "$TEMPLATE_TYPES" 2>/dev/null)
  rec "Data Access audit logging is already configured at this $SCOPE. gcp-foundation-data-access-audit-logs is authoritative per named service, and applies ONE log_types list and ONE exempted_members list to every service it names (allServices when services is empty): apply REPLACES each named service's audit config with those two lists, and terraform destroy removes it. So name only services whose settings today you accept being replaced by those lists. A service that already has DATA_READ or exempted members: leave it out of services (its settings stay as they are), or manage it only from a separate root with its own backend prefix, after removing it from this root's services. Copying its DATA_READ into log_types, or its exemptions into exempted_members, applies them to every named service. ${DIFFER:+Differ from the template defaults today: $DIFFER. }Today: ${TODAY:-see the list above}."
else
  rec "Data Access audit logging is not enabled. Deploy gcp-foundation-data-access-audit-logs BEFORE using any data_access log category — until then such a filter matches nothing for any service but BigQuery (whose Data Access logs Google writes by default), with no error."
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
  # A listing that failed is not an empty one: that read as "no sinks" and hid an export already paid for.
  if ! SINKS=$(gcloud logging sinks list --organization="$ORG_ID" --format="value(name)" 2>"$TMP"); then
    w "could not list the organization's sinks: $(grep -v '^[[:space:]]*$' "$TMP" | head -n1)"
    rec "Could not list the organization's sinks, so an existing export was not ruled out. Check by hand before deploying: gcloud logging sinks list --organization=$ORG_ID"
  else
    CUSTOM=$(grep -vE '^_(Required|Default)$' <<<"$SINKS" | grep -c . || true)
    if [[ "$CUSTOM" == "0" ]]; then
      g "no custom organization sinks (only GCP's built-in _Required/_Default)"
    else
      w "$CUSTOM custom organization sink(s) already exist"
      rec "Review the $CUSTOM existing custom organization sink(s) — confirm you are not about to duplicate an export and pay for both."
    fi
    gcloud logging sinks list --organization="$ORG_ID" --format="table(name,destination)" 2>/dev/null | sed 's/^/     /'
  fi
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
