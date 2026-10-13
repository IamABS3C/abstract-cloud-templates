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
# Picking or creating the management group, and the deployer's rights on it, are
# ./deploy.sh access <Action>, which runs ../_modules/tenant-access.sh:
#   ./deploy.sh access Check    [-m <mg-id>]          management groups, settings, your roles
#   ./deploy.sh access MgCreate -m <mg-id>            create one (you become its Owner)
#   ./deploy.sh access MgAddSub -m <mg-id> -s <subscription-id>
#   ./deploy.sh access Grant --for log-policy --assignee <upn> -m <mg-id>
#   ./deploy.sh access Revoke                         undo what access recorded
set -euo pipefail
cd "$(dirname "$0")"
if [ "${1:-}" = access ]; then shift; exec ../_modules/tenant-access.sh --setup azure-source-all-logs-management-group-policy -a "${1:?action}" "${@:2}"; fi
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
