#!/usr/bin/env bash
#
# stackset.sh - Roll an Abstract Security source across many accounts/regions
# with CloudFormation StackSets (SERVICE_MANAGED, for AWS Organizations).
#
# Usage:
#   scripts/stackset.sh --name abstract-cloudtrail --template cloudformation/s3-log-source.yaml \
#     --ou ou-xxxx-xxxxxxxx --regions "us-east-1 us-west-2" \
#     --param SourceType=CloudTrail --param AbstractPrincipalArn=111122223333 \
#     --param ExternalId=SECRET
#
# Options:
#   --name <stackset>        StackSet name (required).
#   --template <file>        Template file (required).
#   --ou <ou-id>             Target Organizational Unit ID (required for create-instances).
#   --regions "<r1 r2 ...>"  Space-separated regions (required for create-instances).
#   --param Key=Value        Repeatable; passed as a stack-set parameter.
#   --auto-deploy            Enable auto-deployment to new accounts in the OU.
#   --update                 Update an existing StackSet instead of creating it.
#   --dry-run                Print the AWS CLI commands without running them.
#   -h, --help               Show this help.
#
# Notes:
# - Requires Organizations trusted access for CloudFormation StackSets.
# - For org-wide CloudTrail prefer a single organization trail (CtIsOrganizationTrail=true)
#   in the management account over per-account trails.

set -euo pipefail

NAME=""; TEMPLATE=""; OU=""; REGIONS=""; AUTO_DEPLOY=false; UPDATE=false; DRY_RUN=false
PARAMS=()

die() { echo "ERROR: $*" >&2; exit 1; }
run() { if $DRY_RUN; then printf '+ %q ' "$@"; echo; else "$@"; fi; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --ou) OU="$2"; shift 2 ;;
    --regions) REGIONS="$2"; shift 2 ;;
    --param) PARAMS+=("$2"); shift 2 ;;
    --auto-deploy) AUTO_DEPLOY=true; shift ;;
    --update) UPDATE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$NAME" ]] || die "--name is required."
[[ -n "$TEMPLATE" ]] || die "--template is required."
[[ -f "$TEMPLATE" ]] || die "Template not found: $TEMPLATE"
command -v aws >/dev/null 2>&1 || die "aws CLI not found."

# Build --parameters array (Key=..,Value=.. form).
PARAM_ARGS=()
for kv in "${PARAMS[@]:-}"; do
  [[ -z "$kv" ]] && continue
  key="${kv%%=*}"; val="${kv#*=}"
  PARAM_ARGS+=("ParameterKey=${key},ParameterValue=${val}")
done

if $UPDATE; then
  run aws cloudformation update-stack-set \
    --stack-set-name "$NAME" \
    --template-body "file://${TEMPLATE}" \
    --capabilities CAPABILITY_NAMED_IAM \
    ${PARAM_ARGS:+--parameters "${PARAM_ARGS[@]}"}
else
  echo "==> Creating StackSet ${NAME}..."
  run aws cloudformation create-stack-set \
    --stack-set-name "$NAME" \
    --template-body "file://${TEMPLATE}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --permission-model SERVICE_MANAGED \
    --auto-deployment "Enabled=${AUTO_DEPLOY},RetainStacksOnAccountRemoval=false" \
    ${PARAM_ARGS:+--parameters "${PARAM_ARGS[@]}"}
fi

if [[ -n "$OU" && -n "$REGIONS" ]]; then
  echo "==> Creating stack instances in OU ${OU} across: ${REGIONS}"
  # shellcheck disable=SC2086
  run aws cloudformation create-stack-instances \
    --stack-set-name "$NAME" \
    --deployment-targets "OrganizationalUnitIds=${OU}" \
    --regions ${REGIONS} \
    --operation-preferences FailureToleranceCount=0,MaxConcurrentCount=5
else
  echo "==> Skipping create-stack-instances (provide --ou and --regions to roll out)."
fi

echo "==> Done."
