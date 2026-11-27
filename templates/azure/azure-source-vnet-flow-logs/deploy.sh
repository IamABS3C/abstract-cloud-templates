#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# Deploy into a resource group in the virtual networks' region, once per region. The flow logs are
# created in the region's Network Watcher resource group (NetworkWatcherRG by default), so the
# deployer needs Network Contributor there as well.
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
# A fixed deployment name per template keeps each template's outputs in its own history; a later --name wins.
az deployment group "$MODE" --name azure-source-vnet-flow-logs --resource-group "${ARGS[0]:?resource group}" \
  --template-file azuredeploy.json --parameters @parameters.example.json "${ARGS[@]:1}"
