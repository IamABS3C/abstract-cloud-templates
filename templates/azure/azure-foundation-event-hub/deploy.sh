#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# --profile <name> uses examples/<name>.parameters.json instead of parameters.example.json
# (abstract-recommended, hybrid, ip-allowlist, private-only or safe-mode).
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=(); PARAMS=@parameters.example.json
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) MODE=create ;;
    --profile) PARAMS="@examples/${2:?profile name}.parameters.json"; shift ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
az deployment group "$MODE" --resource-group "${ARGS[0]:?resource group}" \
  --template-file azuredeploy.json --parameters "$PARAMS" "${ARGS[@]:1}"
