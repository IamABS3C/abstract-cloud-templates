#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
# A fixed deployment name per template keeps each template's outputs in its own history; a later --name wins.
az deployment sub "$MODE" --name azure-source-activity-log-subscription --location "${ARGS[0]:?location}" \
  --template-file azuredeploy.json --parameters @parameters.example.json "${ARGS[@]:1}"
