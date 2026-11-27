#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# The resource group is only where the deployment runs: the two apps are tenant-wide Entra objects
# and nothing is created in the group. what-if does not show Microsoft Graph resources.
# There is no azuredeploy.json: the Microsoft Graph extension does not compile to plain ARM, so az
# compiles main.bicep itself and fetches the extension named in bicepconfig.json (needs network
# access to mcr.microsoft.com).
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
# A fixed deployment name per template keeps each template's outputs in its own history; a later --name wins.
az deployment group "$MODE" --name azure-access-m365-graph-apps --resource-group "${ARGS[0]:?resource group}" \
  --template-file main.bicep --parameters @parameters.example.json "${ARGS[@]:1}"
