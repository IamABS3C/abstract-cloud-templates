#!/usr/bin/env bash
# Preview with what-if, then deploy with --yes. Parameters come from parameters.example.json
# (copy it and edit, or pass --parameters key=value after the scope arguments).
# The Entra side of this path cannot be a template, so these sub-commands run the shared driver
# ../_modules/deploy-appreg.sh with the matching action; every further argument is passed through:
#   ./deploy.sh bootstrap   create the managed identity and grant it Graph consent (Global Administrator, once)
#   ./deploy.sh grant       give the acting identity its roles on the target subscriptions and the Key Vault
#   ./deploy.sh remediate   backfill existing subscriptions through a remediation task
#   ./deploy.sh onboard     onboard one subscription now
#   ./deploy.sh verify      re-check admin consent for a created app (--app-id <app-id>)
set -euo pipefail
cd "$(dirname "$0")"
case "${1:-}" in
  bootstrap) shift; exec ../_modules/deploy-appreg.sh -a Bootstrap "$@" ;;
  grant)     shift; exec ../_modules/deploy-appreg.sh -a Grant "$@" ;;
  remediate) shift; exec ../_modules/deploy-appreg.sh -a Remediate "$@" ;;
  onboard)   shift; exec ../_modules/deploy-appreg.sh -a Onboard "$@" ;;
  verify)    shift; exec ../_modules/deploy-appreg.sh -a Verify "$@" ;;
esac
MODE=what-if; ARGS=()
for a in "$@"; do [ "$a" = "--yes" ] && MODE=create || ARGS+=("$a"); done
az deployment mg "$MODE" --management-group-id "${ARGS[0]:?management group id}" --location "${ARGS[1]:?location}" \
  --template-file azuredeploy.json --parameters @parameters.example.json "${ARGS[@]:2}"
