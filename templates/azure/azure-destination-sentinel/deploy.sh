#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# The Entra app registration cannot be created in ARM: run scripts/new-app-registration.sh first,
# then pass its service principal object id as --parameters principalId=<object-id>.
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
az deployment group "$MODE" --resource-group "${ARGS[0]:?resource group}" \
  --template-file azuredeploy.json --parameters @parameters.example.json "${ARGS[@]:1}"
