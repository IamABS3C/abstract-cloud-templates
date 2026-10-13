#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# A tenant-scope deploy needs Microsoft.Resources/deployments/* at "/" besides the Entra role;
# ./deploy.sh access <Action> runs ../_modules/tenant-access.sh to check, grant and later remove it:
#   ./deploy.sh access Check  [--assignee <upn>]      what you and the deployer hold
#   ./deploy.sh access Elevate                       Global Administrator: rights to grant at "/"
#   ./deploy.sh access Grant --for entra --assignee <upn>
#   ./deploy.sh access Revoke                        remove what Elevate and Grant recorded
set -euo pipefail
cd "$(dirname "$0")"
if [ "${1:-}" = access ]; then shift; exec ../_modules/tenant-access.sh --setup azure-source-entra-id-logs-tenant -a "${1:?action}" "${@:2}"; fi
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
az deployment tenant "$MODE" --location "${ARGS[0]:?location}" \
  --template-file azuredeploy.json --parameters @parameters.example.json "${ARGS[@]:1}"
