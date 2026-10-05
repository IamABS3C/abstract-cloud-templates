#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. By default the policies are assigned REPORT-ONLY:
# examples/default.parameters.json sets effect=AuditIfNotExists and enforcementMode=DoNotEnforce,
# so they report what they would onboard and change nothing. Read the compliance counts first.
# --enforce uses parameters.example.json instead, which keeps the template defaults
# (effect=DeployIfNotExists, enforcementMode=Default): settings are then written everywhere.
# Copy either file and edit it, or pass --parameters key=value after the scope arguments.
# Assigning the policies is only the first of three steps: the assignment identities still need
# Event Hubs Data Owner on the namespace, and existing resources need a remediation task.
# scripts/deploy-log-streams.sh does assign + grant + remediate in one go (-a All).
set -euo pipefail
cd "$(dirname "$0")"
MODE=what-if; ARGS=(); PARAMS=@examples/default.parameters.json
for a in "$@"; do
  case "$a" in
    --yes) MODE=create ;;
    --enforce) PARAMS=@parameters.example.json ;;
    *) ARGS+=("$a") ;;
  esac
done
az deployment mg "$MODE" --management-group-id "${ARGS[0]:?management group id}" --location "${ARGS[1]:?location}" \
  --template-file azuredeploy.json --parameters "$PARAMS" "${ARGS[@]:2}"
