#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# Replace managedIdentityResourceId first: it must be a user-assigned identity that already holds
# Microsoft Graph Application.ReadWrite.All with admin consent. Treat it as tier-0 and remove the
# permission once the deployment has finished.
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
# A fixed deployment name per template keeps each template's outputs in its own history; a later --name wins.
az deployment group "$MODE" --name azure-destination-sentinel-app-by-script --resource-group "${ARGS[0]:?resource group}" \
  --template-file azuredeploy.json --parameters @parameters.example.json "${ARGS[@]:1}"
