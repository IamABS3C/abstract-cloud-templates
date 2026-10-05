#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# There is no azuredeploy.json: the Microsoft Graph extension does not compile to plain ARM, so az
# compiles main.bicep itself and fetches the extension named in bicepconfig.json (needs network
# access to mcr.microsoft.com).
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
az deployment group "$MODE" --resource-group "${ARGS[0]:?resource group}" \
  --template-file main.bicep --parameters @parameters.example.json "${ARGS[@]:1}"
