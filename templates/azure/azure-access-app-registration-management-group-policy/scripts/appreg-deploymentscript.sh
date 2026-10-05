#!/usr/bin/env bash
# =============================================================================
#  Abstract Security - per-subscription Entra app registration
#  Runs inside a Microsoft.Resources/deploymentScripts AzureCLI container, AS a
#  user-assigned managed identity that already holds Graph
#  Application.ReadWrite.All + AppRoleAssignment.ReadWrite.All.
#
#  Loaded into BOTH delivery paths by loadTextContent() so there is exactly one
#  copy of this logic:
#    azure-access-app-registration-management-group-policy/main.bicep  (Path A - Azure Policy)
#    azure-access-app-registration-logic-app/main.bicep                 (Path B - event-driven)
#
#  Environment (set by the template):
#    TARGET_SUB      subscription this app is being created for
#    MI_CLIENT_ID    client ID of the managed identity to log in as
#    KV_NAME         central Key Vault that receives the client secret
#    APP_NAME        app display name - ALSO the idempotency key
#    GRAPH_PERMS     space-separated Graph application permission names
#    SECRET_MONTHS   client-secret lifetime
#    RBAC_ROLES      space-separated role definition GUIDs for the target sub
#
#  DESIGN RULES
#    * Idempotent. Re-running reuses the app, reuses a still-valid secret, and
#      skips grants already in place. Safe for a policy that re-evaluates.
#    * Consent is VERIFIED, never assumed. We read appRoleAssignments back from
#      Graph and fail loudly on a shortfall - the failure mode we are explicitly
#      designing against is "consent looked fine, Abstract gets 403s".
#    * The secret NEVER reaches deployment outputs, logs or stdout. Key Vault only.
# =============================================================================
set -euo pipefail

GRAPH="https://graph.microsoft.com/v1.0"
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"

log()  { printf '==> %s\n' "$*"; }
ok()   { printf '    + %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*"; }
die()  { printf '    X %s\n' "$*" >&2; exit 1; }

# --- Sign in as the pre-consented managed identity -------------------------
log "Signing in as managed identity $MI_CLIENT_ID"
az login --identity --username "$MI_CLIENT_ID" --allow-no-subscriptions -o none
TENANT_ID=$(az account show --query tenantId -o tsv)
ok "tenant $TENANT_ID"

# --- Resolve the Graph service principal and its appRole map ---------------
log "Resolving Microsoft Graph appRoles"
GRAPH_SP=$(az rest --method GET \
  --url "${GRAPH}/servicePrincipals(appId='${GRAPH_APP_ID}')?\$select=id,appRoles" \
  --headers "Content-Type=application/json")
GRAPH_SP_ID=$(echo "$GRAPH_SP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

# name -> appRoleId, application-type roles only. An unresolved name is a HARD
# failure: silently skipping it is how a permission gap reaches production.
# The Graph role catalogue is hundreds of KB: it goes to Python on stdin, with the program
# passed as an argument. An environment variable is capped at 128 KiB on Linux ("Argument
# list too long"), and a pipe into `python3 - <<'PY'` loses to the heredoc, which becomes stdin.
ROLE_IDS=$(printf '%s' "$GRAPH_SP" | GRAPH_PERMS="$GRAPH_PERMS" python3 -c "$(cat <<'PY'
import json, os, sys
sp = json.load(sys.stdin)
roles = {r['value']: r['id'] for r in sp.get('appRoles', [])
         if 'Application' in r.get('allowedMemberTypes', [])}
want = os.environ['GRAPH_PERMS'].split()
missing = [w for w in want if w not in roles]
if missing:
    sys.stderr.write("UNRESOLVED Graph application permission(s): %s\n" % ', '.join(missing))
    sys.stderr.write("These do not exist as APPLICATION permissions in this tenant. "
                     "Note 'Security.Read.All' is a common mistake - it exists as neither "
                     "an application nor a delegated permission.\n")
    sys.exit(1)
print(' '.join('%s=%s' % (w, roles[w]) for w in want))
PY
)") || die "could not resolve every requested Graph permission - nothing was created"
ok "resolved $(echo "$ROLE_IDS" | wc -w | tr -d ' ') permission(s)"

# --- App registration (idempotent by display name) ------------------------
log "Ensuring app registration '$APP_NAME'"
# The display name is predictable (Abstract-<subscription id>) and any user who may
# register apps could pre-create one, so an app is reused only when exactly one has
# the name AND it carries the marker tag this script writes on the apps it creates.
# Otherwise this identity would consent tenant-wide Graph permissions to an app
# someone else owns.
MARKER="abstract:appreg"
MATCHES=$(az ad app list --filter "displayName eq '${APP_NAME}'" --query "[].{appId:appId, tags:tags}" -o json) \
  || die "cannot list app registrations"
read -r MATCH_COUNT APP_ID MARKED <<<"$(printf '%s' "$MATCHES" | python3 -c "
import json, sys
apps = json.load(sys.stdin) or []
first = apps[0] if apps else {}
print(len(apps), first.get('appId') or '-', 'yes' if '$MARKER' in (first.get('tags') or []) else 'no')")"
if [ "$MATCH_COUNT" -gt 1 ]; then
  die "$MATCH_COUNT app registrations are named '$APP_NAME' - refusing to choose one"
elif [ "$MATCH_COUNT" -eq 1 ]; then
  [ "$MARKED" = yes ] || die "an app named '$APP_NAME' ($APP_ID) exists but was not created by this automation, so it gets no permissions or credential. Delete it, or if an earlier version of this automation created it, tag it: az rest --method PATCH --url \"${GRAPH}/applications(appId='$APP_ID')\" --body '{\"tags\":[\"$MARKER\"]}'"
  ok "reusing existing app $APP_ID"
else
  APP_ID=$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)
  ok "created app $APP_ID"
  sleep 15   # directory replication before the tag and the SP create
  az rest --method PATCH --url "${GRAPH}/applications(appId='${APP_ID}')" \
    --headers "Content-Type=application/json" --body "{\"tags\":[\"${MARKER}\"]}" -o none \
    || die "could not tag app $APP_ID as created by this automation"
fi
APP_OBJ_ID=$(az ad app show --id "$APP_ID" --query id -o tsv)

# --- requiredResourceAccess: what the app ASKS for ------------------------
# Declared for portal visibility and audit. On its own this grants nothing;
# the appRoleAssignments below are what actually authorise the app.
log "Declaring requiredResourceAccess"
RRA=$(ROLE_IDS="$ROLE_IDS" GRAPH_APP_ID="$GRAPH_APP_ID" python3 - <<'PY'
import json, os, sys
pairs = os.environ['ROLE_IDS'].split()
access = [{"id": p.split('=')[1], "type": "Role"} for p in pairs]
print(json.dumps([{"resourceAppId": os.environ['GRAPH_APP_ID'], "resourceAccess": access}]))
PY
)
echo "$RRA" > /tmp/rra.json
az rest --method PATCH --url "${GRAPH}/applications/${APP_OBJ_ID}" \
  --headers "Content-Type=application/json" \
  --body "{\"requiredResourceAccess\": $(cat /tmp/rra.json)}" -o none
ok "declared"

# --- Service principal ----------------------------------------------------
log "Ensuring service principal"
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)
if [ -z "$SP_ID" ] || [ "$SP_ID" = "None" ]; then
  SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
  ok "created SP $SP_ID"
  sleep 20   # replication before RBAC + consent
else
  ok "reusing SP $SP_ID"
fi

# --- Admin consent, then PROVE it ----------------------------------------
log "Granting admin consent (app-role assignments)"
EXISTING=$(az rest --method GET --url "${GRAPH}/servicePrincipals/${SP_ID}/appRoleAssignments" \
  --headers "Content-Type=application/json" 2>/dev/null || echo '{"value":[]}')

GRANTED=0; SKIPPED=0; FAILED=0
for pair in $ROLE_IDS; do
  pname="${pair%%=*}"; rid="${pair##*=}"
  if echo "$EXISTING" | grep -q "$rid"; then
    SKIPPED=$((SKIPPED+1)); continue
  fi
  if az rest --method POST --url "${GRAPH}/servicePrincipals/${SP_ID}/appRoleAssignments" \
      --headers "Content-Type=application/json" \
      --body "{\"principalId\":\"${SP_ID}\",\"resourceId\":\"${GRAPH_SP_ID}\",\"appRoleId\":\"${rid}\"}" \
      -o none 2>/tmp/consent-err; then
    GRANTED=$((GRANTED+1))
  else
    if grep -qiE 'already exists|Conflict' /tmp/consent-err; then
      SKIPPED=$((SKIPPED+1))
    else
      FAILED=$((FAILED+1)); warn "$pname: $(tr -d '\n' < /tmp/consent-err | head -c 300)"
    fi
  fi
done
ok "granted $GRANTED, already present $SKIPPED, failed $FAILED"

# Independent read-back. This is the check that matters - not our POST results.
sleep 10
ASSIGNED=$(az rest --method GET --url "${GRAPH}/servicePrincipals/${SP_ID}/appRoleAssignments" \
  --headers "Content-Type=application/json")
VERIFIED=$(ASSIGNED="$ASSIGNED" ROLE_IDS="$ROLE_IDS" python3 - <<'PY'
import json, os, sys
have = {a['appRoleId'] for a in json.loads(os.environ['ASSIGNED']).get('value', [])}
want = [p.split('=')[1] for p in os.environ['ROLE_IDS'].split()]
print(sum(1 for w in want if w in have))
PY
)
EXPECTED=$(echo "$ROLE_IDS" | wc -w | tr -d ' ')
if [ "$VERIFIED" -ne "$EXPECTED" ]; then
  warn "CONSENT INCOMPLETE: Graph confirms ${VERIFIED}/${EXPECTED} permission(s)."
  warn "Most likely the managed identity lacks AppRoleAssignment.ReadWrite.All admin consent."
  warn "Abstract will receive 403s for the missing permissions until this is fixed."
  CONSENT_OK=false
else
  ok "consent VERIFIED against Graph: ${VERIFIED}/${EXPECTED}"
  CONSENT_OK=true
fi

# --- Client secret -> central Key Vault only ------------------------------
# Only mint a new secret when the vault holds none with >30 days left. Without
# this, a re-evaluating policy would churn a fresh secret on every pass and break
# whatever is already authenticating with the old one.
log "Checking for a usable secret in $KV_NAME"
SECRET_NAME="abstract-${TARGET_SUB}"
NEED_SECRET=true
SECRET_EXPIRES=""
if EXP=$(az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET_NAME" --query 'attributes.expires' -o tsv 2>/dev/null); then
  if [ -n "$EXP" ] && [ "$EXP" != "None" ]; then
    if python3 -c "
import sys,datetime
exp=datetime.datetime.fromisoformat('$EXP'.replace('Z','+00:00'))
now=datetime.datetime.now(datetime.timezone.utc)
sys.exit(0 if (exp-now).days > 30 else 1)"; then
      NEED_SECRET=false
      SECRET_EXPIRES="$EXP"
      ok "existing secret is valid for >30 days - not rotating"
    fi
  fi
fi

if [ "$NEED_SECRET" = true ]; then
  log "Generating a client secret (${SECRET_MONTHS} month(s))"
  END=$(python3 -c "
import datetime
print((datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=30*int('$SECRET_MONTHS'))).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  SECRET=$(az rest --method POST --url "${GRAPH}/applications/${APP_OBJ_ID}/addPassword" \
    --headers "Content-Type=application/json" \
    --body "{\"passwordCredential\":{\"displayName\":\"Abstract ${TARGET_SUB}\",\"endDateTime\":\"${END}\"}}" \
    --query secretText -o tsv)
  [ -z "$SECRET" ] && die "secret generation returned empty"
  az keyvault secret set --vault-name "$KV_NAME" --name "$SECRET_NAME" \
    --value "$SECRET" --expires "$END" -o none
  unset SECRET
  SECRET_EXPIRES="$END"
  ok "secret stored at ${KV_NAME}/${SECRET_NAME} (never emitted to outputs or logs)"
fi

# --- Azure RBAC on the TARGET subscription -------------------------------
# This is what actually makes the app per-subscription. Graph application
# permissions are inherently tenant-wide and cannot be scoped to a subscription.
log "Assigning Azure RBAC on subscription $TARGET_SUB"
for role in $RBAC_ROLES; do
  if az role assignment create --assignee-object-id "$SP_ID" \
      --assignee-principal-type ServicePrincipal \
      --role "$role" --scope "/subscriptions/${TARGET_SUB}" -o none 2>/tmp/rbac-err; then
    ok "granted role $role"
  else
    if grep -qi 'already exists\|RoleAssignmentExists' /tmp/rbac-err; then
      ok "role $role already assigned"
    else
      warn "role $role FAILED: $(tr -d '\n' < /tmp/rbac-err | head -c 300)"
      RBAC_FAILED=true
    fi
  fi
done

: "${RBAC_FAILED:=false}"

# --- Outputs (no secret, by design) --------------------------------------
cat > "$AZ_SCRIPTS_OUTPUT_PATH" <<JSON
{
  "appId": "${APP_ID}",
  "appObjectId": "${APP_OBJ_ID}",
  "servicePrincipalObjectId": "${SP_ID}",
  "tenantId": "${TENANT_ID}",
  "subscriptionId": "${TARGET_SUB}",
  "keyVaultName": "${KV_NAME}",
  "secretName": "${SECRET_NAME}",
  "consentVerified": ${CONSENT_OK},
  "permissionsVerified": "${VERIFIED}/${EXPECTED}"
}
JSON

if [ "$CONSENT_OK" != true ]; then
  die "app created but admin consent is incomplete (${VERIFIED}/${EXPECTED}) - failing so the deployment does not report success"
fi
if [ "$RBAC_FAILED" = true ]; then
  die "app and consent are in place but a subscription role assignment failed - failing so the policy retries"
fi
# The policy's existence check reads these tags, so they are written only after everything
# above is verified. Without them the subscription stays non-compliant and is retried.
# abstract-appreg-secret-expires is what renews the secret: 30 days before that date the
# subscription turns non-compliant again, and a remediation task re-runs this script,
# which then mints a new secret.
SECRET_EXPIRES=$(python3 -c "
import datetime
d=datetime.datetime.fromisoformat('$SECRET_EXPIRES'.replace('Z','+00:00'))
print(d.astimezone(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))") \
  || die "could not read the secret's expiry ('$SECRET_EXPIRES')"
if [ -n "${MARKER_RG:-}" ]; then
  az group update --name "$MARKER_RG" --subscription "$TARGET_SUB" \
    --set tags.abstract-appreg=onboarded "tags.abstract-appreg-secret-expires=${SECRET_EXPIRES}" -o none \
    || die "could not tag resource group $MARKER_RG as onboarded"
  ok "marked $MARKER_RG as onboarded; secret expires ${SECRET_EXPIRES}"
fi
ok "done"
