#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# The resource group must be the one that holds the Sentinel workspace. Store the Abstract API key in
# Key Vault first and pass its secret URI as keyVaultSecretUri; the template never takes the key itself.
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
az deployment group "$MODE" --resource-group "${ARGS[0]:?resource group}" \
  --template-file azuredeploy.json --parameters @parameters.example.json "${ARGS[@]:1}"
