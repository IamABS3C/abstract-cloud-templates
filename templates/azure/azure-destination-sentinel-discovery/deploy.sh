#!/usr/bin/env bash
# Run the Sentinel discovery in Azure.
#   ./deploy.sh RESOURCE_GROUP --parameters workspaceName=NAME         preview (what-if), changes nothing
#   ./deploy.sh RESOURCE_GROUP --yes --parameters workspaceName=NAME   deploy
# parameters.example.json shows one value for each parameter: copy it, keep what you need, and pass --parameters @your.json.
set -euo pipefail
cd "$(dirname "$0")"
[ $# -ge 1 ] || { sed -n '2,5p' "$0"; exit 2; }
rg="$1"; shift
yes=0; args=()
for a in "$@"; do if [ "$a" = "--yes" ]; then yes=1; else args+=("$a"); fi; done
name="azure-destination-sentinel-discovery"
if [ "$yes" -eq 0 ]; then
  exec az deployment group what-if --resource-group "$rg" --name "$name" --template-file azuredeploy.json "${args[@]+"${args[@]}"}"
fi
exec az deployment group create --resource-group "$rg" --name "$name" --template-file azuredeploy.json "${args[@]+"${args[@]}"}" \
  --query "{state:properties.provisioningState, correlationId:properties.correlationId, outputs:properties.outputs}" -o json
