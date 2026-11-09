#!/usr/bin/env bash
# Deploy Abstract Security for Microsoft Sentinel into a resource group.
#   ./deploy.sh RESOURCE_GROUP [--parameters @my.parameters.json | NAME=VALUE ...]         preview (what-if), changes nothing
#   ./deploy.sh RESOURCE_GROUP --yes [--parameters @my.parameters.json | NAME=VALUE ...]   deploy
# Without --parameters every parameter takes its default. parameters.example.json shows one value for each: copy it to
# my.parameters.json, keep the ones you want, and pass --parameters @my.parameters.json. It is never read on its own,
# because its values are examples, not choices.
# On a brand-new workspace with ASIM on, Azure can refuse the first Data Collection Rule with InvalidOutputTable because
# Microsoft Sentinel creates the ASim tables a minute or two after onboarding. This script then waits 3 minutes and
# deploys once more with the same inputs; the second run completes it.
set -euo pipefail
cd "$(dirname "$0")"
[ $# -ge 1 ] || { sed -n '2,10p' "$0"; exit 2; }
rg="$1"; shift
yes=0; args=()
for a in "$@"; do if [ "$a" = "--yes" ]; then yes=1; else args+=("$a"); fi; done
# A fixed deployment name keeps the outputs under one name: az deployment group show -n azure-destination-sentinel-solution
name="azure-destination-sentinel-solution"
if [ "$yes" -eq 0 ]; then
  exec az deployment group what-if --resource-group "$rg" --name "$name" --template-file azuredeploy.json "${args[@]+"${args[@]}"}"
fi
run() {
  az deployment group create --resource-group "$rg" --name "$name" --template-file azuredeploy.json "${args[@]+"${args[@]}"}" \
    --query "{state:properties.provisioningState, correlationId:properties.correlationId, outputs:properties.outputs}" -o json
}
if out="$(run 2>&1)"; then echo "$out"; exit 0; fi
echo "$out" >&2
if grep -q "InvalidOutputTable" <<<"$out"; then
  echo "InvalidOutputTable: the ASim tables are not there yet on this new workspace. Waiting 3 minutes, then deploying again." >&2
  sleep 180
  run
else
  exit 1
fi
