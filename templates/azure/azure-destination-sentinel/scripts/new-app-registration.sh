#!/usr/bin/env bash
# =============================================================================
#  Abstract Security - Azure Sentinel Destination: app registration + RBAC
#  Standalone operator script (bash / az CLI).  Runs in Azure Cloud Shell or
#  locally (macOS/Linux) with the Azure CLI signed in.
#
#  WHAT IT DOES
#    ARM/Bicep cannot create Entra app registrations, so this script does the
#    identity half that the sentinel-destination template can't:
#      1. Creates (or reuses) a single-tenant Entra app registration for
#         Abstract + its service principal.
#      2. Generates a client secret (shown ONCE, or pushed to Key Vault).
#      3. Optionally deploys the template one directory up (azuredeploy.json) so the
#         SP is granted Monitoring Metrics Publisher on the DCR (all the Logs
#         Ingestion API needs), then prints the exact
#         values for the Abstract "Azure Sentinel Destination" modal.
#
#  The Abstract app needs NO Graph API permissions / admin consent - it is
#  purely an identity that receives DCR RBAC. You only need rights to register
#  an app in the tenant (and, to deploy, Contributor + User Access
#  Administrator / Owner on the target resource group).
#
#  SECURITY: the client secret is printed once, or stored in Key Vault with
#  --keyvault. It is never logged. For the Key Vault write it passes through a
#  temporary file readable only by you, deleted immediately after.
#
#  USAGE
#    ./new-app-registration.sh \
#        --app-name Abstract-Sentinel-App \
#        [--subscription <id>] \
#        [--deploy --resource-group <rg> [--location <region>]] \
#        [--table AbstractEventLogs_CL] [--dce abstract-dce] [--dcr abstract-dcr] \
#        [--keyvault <kv-name>] [--secret-years 1] [--yes]
#
#    Identity only (no Azure resources):
#        ./new-app-registration.sh --app-name Abstract-Sentinel-App
#
#    Full one-shot (identity + full ingestion stack + RBAC):
#        ./new-app-registration.sh --app-name Abstract-Sentinel-App \
#            --deploy --resource-group rg-abstract-sentinel --location eastus
# =============================================================================
set -euo pipefail

# ---- defaults ---------------------------------------------------------------
APP_NAME="Abstract-Sentinel-App"
SUBSCRIPTION=""
DEPLOY=false
RESOURCE_GROUP=""
LOCATION="eastus"
TABLE_NAME="AbstractEventLogs_CL"
DCE_NAME="abstract-dce"
DCR_NAME="abstract-dcr"
KEYVAULT=""
SECRET_YEARS=1
ASSUME_YES=false
SECRET_DISPLAY_NAME="abstract-sentinel-secret"

# Resolve the compiled template that lives one directory up, regardless of CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../azuredeploy.json"

# ---- args -------------------------------------------------------------------
usage() { sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-name)        APP_NAME="$2"; shift 2;;
    --subscription)    SUBSCRIPTION="$2"; shift 2;;
    --deploy)          DEPLOY=true; shift;;
    --resource-group|-g) RESOURCE_GROUP="$2"; shift 2;;
    --location|-l)     LOCATION="$2"; shift 2;;
    --table)           TABLE_NAME="$2"; shift 2;;
    --dce)             DCE_NAME="$2"; shift 2;;
    --dcr)             DCR_NAME="$2"; shift 2;;
    --keyvault)        KEYVAULT="$2"; shift 2;;
    --secret-years)    SECRET_YEARS="$2"; shift 2;;
    --yes|-y)          ASSUME_YES=true; shift;;
    -h|--help)         usage 0;;
    *) echo "Unknown option: $1" >&2; usage 1;;
  esac
done

err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
info() { printf '\033[36m%s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32m%s\033[0m\n' "$*" >&2; }

command -v az >/dev/null 2>&1 || { err "Azure CLI (az) not found. Install it or run in Azure Cloud Shell."; exit 1; }
az account show >/dev/null 2>&1 || { err "Not signed in. Run: az login"; exit 1; }

if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi
TENANT_ID="$(az account show --query tenantId -o tsv)"
SUB_ID="$(az account show --query id -o tsv)"
SUB_NAME="$(az account show --query name -o tsv)"

info "Tenant : $TENANT_ID"
info "Sub    : $SUB_NAME ($SUB_ID)"
info "App    : $APP_NAME"
$DEPLOY && info "Deploy : $RESOURCE_GROUP ($LOCATION) using $(basename "$TEMPLATE")"

if $DEPLOY && [[ -z "$RESOURCE_GROUP" ]]; then
  err "--deploy requires --resource-group <rg>."; exit 1
fi
if $DEPLOY && [[ ! -f "$TEMPLATE" ]]; then
  err "Template not found: $TEMPLATE"; exit 1
fi

if ! $ASSUME_YES; then
  read -r -p "Proceed against the tenant/subscription above? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { err "Aborted."; exit 1; }
fi

# ---- 1. app registration (idempotent by displayName) ------------------------
# A name proves nothing: anyone allowed to register apps could create one with this
# name, and this script would then give it a credential and DCR access. Reuse an app
# only if exactly one has the name and it carries the marker tag the Sentinel
# templates and this script write on apps they create.
MARKER="abstract:sentinel-destination"
MATCHES="$(az ad app list --display-name "$APP_NAME" --query "[].{appId:appId, tags:tags}" -o json)"
read -r MATCH_COUNT APP_ID MARKED <<<"$(printf '%s' "$MATCHES" | python3 -c "
import json, sys
apps = json.load(sys.stdin) or []
first = apps[0] if apps else {}
print(len(apps), first.get('appId') or '-', 'yes' if '$MARKER' in (first.get('tags') or []) else 'no')")"
if [[ "$MATCH_COUNT" -gt 1 ]]; then
  err "$MATCH_COUNT app registrations are named '$APP_NAME' - choose a unique --app-name."; exit 1
elif [[ "$MATCH_COUNT" -eq 1 ]]; then
  if [[ "$MARKED" != yes ]]; then
    err "An app named '$APP_NAME' ($APP_ID) exists but was not created for the Abstract Sentinel destination, so it is not reused. Choose another --app-name, or tag it if you created it for Abstract: az rest --method PATCH --url \"https://graph.microsoft.com/v1.0/applications(appId='$APP_ID')\" --body '{\"tags\":[\"$MARKER\"]}'"
    exit 1
  fi
  info "Reusing existing app registration '$APP_NAME' (appId $APP_ID)."
else
  info "Creating app registration '$APP_NAME' (single-tenant)…"
  APP_ID="$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)"
  sleep 15   # directory replication before the tag
  az rest --method PATCH --url "https://graph.microsoft.com/v1.0/applications(appId='${APP_ID}')" \
    --headers "Content-Type=application/json" --body "{\"tags\":[\"${MARKER}\"]}" -o none
  ok "Created app (appId $APP_ID)."
fi

# ---- 2. service principal (idempotent) --------------------------------------
SP_OBJECT_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)"
if [[ -z "$SP_OBJECT_ID" || "$SP_OBJECT_ID" == "None" ]]; then
  info "Creating service principal for the app…"
  SP_OBJECT_ID="$(az ad sp create --id "$APP_ID" --query id -o tsv)"
  # Directory replication can lag; give role assignment a chance to resolve it.
  sleep 15
fi
ok "Service principal object id: $SP_OBJECT_ID"

# ---- 3. client secret (append so existing secrets survive) ------------------
info "Generating client secret (valid ${SECRET_YEARS}y)…"
SECRET_VALUE="$(az ad app credential reset --id "$APP_ID" --append \
  --display-name "$SECRET_DISPLAY_NAME" --years "$SECRET_YEARS" \
  --query password -o tsv)"

SECRET_SINK="printed below (copy it now - it cannot be retrieved again)"
if [[ -n "$KEYVAULT" ]]; then
  info "Storing secret in Key Vault '$KEYVAULT' as secret 'abstract-sentinel-client-secret'…"
  # Through a 0600 file, not the command line, so the value never shows in the process list.
  SECRET_FILE="$(mktemp)"; chmod 600 "$SECRET_FILE"; printf '%s' "$SECRET_VALUE" > "$SECRET_FILE"
  KV_URI="$(az keyvault secret set --vault-name "$KEYVAULT" \
      --name abstract-sentinel-client-secret --file "$SECRET_FILE" --encoding utf-8 --tags appId="$APP_ID" \
      --expires "$(date -u -v+"${SECRET_YEARS}"y +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+${SECRET_YEARS} years" +%Y-%m-%dT%H:%M:%SZ)" \
      --query id -o tsv)"; rm -f "$SECRET_FILE"
  SECRET_SINK="stored in Key Vault: $KV_URI"
  SECRET_VALUE="(stored in Key Vault - not shown)"
fi

# ---- 4. optional deployment (grants Monitoring Metrics Publisher on the DCR) --
DCR_IMMUTABLE_ID=""; DCE_URL=""; STREAM_NAME="Custom-${TABLE_NAME}"
if $DEPLOY; then
  az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none
  info "Deploying the Sentinel Destination stack (workspace + Sentinel + DCE + table + DCR + RBAC)…"
  DEPLOY_NAME="abstract-sentinel-$(date +%s 2>/dev/null || echo run)"
  OUTPUTS="$(az deployment group create \
      --name "$DEPLOY_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --template-file "$TEMPLATE" \
      --parameters createWorkspace=true location="$LOCATION" \
                   customTableName="$TABLE_NAME" \
                   dataCollectionEndpointName="$DCE_NAME" \
                   dataCollectionRuleName="$DCR_NAME" \
                   principalId="$SP_OBJECT_ID" principalType=ServicePrincipal \
      --query properties.outputs -o json)"
  _get() { echo "$OUTPUTS" | python3 -c "import sys,json;print(json.load(sys.stdin).get('$1',{}).get('value',''))"; }
  DCR_IMMUTABLE_ID="$(_get dataCollectionRuleImmutableId)"
  DCE_URL="$(_get dataCollectionEndpointUrl)"
  STREAM_NAME="$(_get logStreamName)"
  ok "Deployment complete."
fi

# ---- 5. summary → the Abstract modal ---------------------------------------
cat >&2 <<EOF

============================================================================
 Abstract "Azure Sentinel Destination" - configuration values
============================================================================
 Authentication
   Client ID (Application ID)   : $APP_ID
   Application Tenant ID        : $TENANT_ID
   Client Secret Value          : $SECRET_VALUE
     ↳ $SECRET_SINK
   Service principal object id  : $SP_OBJECT_ID   (used for DCR RBAC)
EOF

if $DEPLOY; then
  cat >&2 <<EOF

 Azure Monitor Details
   Data Collection Rule ID      : $DCR_IMMUTABLE_ID
   Data Collection Endpoint     : $DCE_URL
   Log Stream Name              : $STREAM_NAME

 RBAC granted on the DCR: Monitoring Metrics Publisher
EOF
else
  cat >&2 <<EOF

 Next: from the template folder, deploy the ingestion stack and grant RBAC to this SP, e.g.
   az deployment group create -g <rg> \\
     --template-file azuredeploy.json \\
     --parameters @examples/default.parameters.json \\
     --parameters principalId=$SP_OBJECT_ID
 …or re-run this script with --deploy --resource-group <rg>.
 Then read DCR ID / DCE URL / stream name from the deployment Outputs.
EOF
fi

echo "============================================================================" >&2
ok "Done."
