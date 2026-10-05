#!/usr/bin/env bash
# Upload the child templates this stack nests to a private S3 bucket, then preview the master stack
# with a change set and apply it with --yes. CloudFormation only loads a nested TemplateURL from S3.
# Parameters come from parameters.example.json (copy it and edit, or pass Key=Value overrides).
#   ./deploy.sh <stack-name> <template-bucket> [Key=Value ...]          # upload, create the change set, show it
#   ./deploy.sh <stack-name> <template-bucket> [Key=Value ...] --yes    # upload, create and execute it
# PREFIX (default abstract) sets the key prefix; the region is AWS_REGION, else the CLI's default.
set -euo pipefail
cd "$(dirname "$0")"
command -v aws >/dev/null || { echo "aws CLI v2 is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
EXECUTE=false; ARGS=()
for a in "$@"; do if [ "$a" = "--yes" ]; then EXECUTE=true; else ARGS+=("$a"); fi; done
[ "${#ARGS[@]}" -ge 2 ] || { echo "usage: ./deploy.sh <stack-name> <template-bucket> [Key=Value ...] [--yes]" >&2; exit 2; }
STACK="${ARGS[0]}"; BUCKET="${ARGS[1]}"; PREFIX="${PREFIX:-abstract}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region || true)}}"
[ -n "$REGION" ] || { echo "set AWS_REGION" >&2; exit 2; }
BASE="https://${BUCKET}.s3.${REGION}.amazonaws.com/${PREFIX}"
for id in aws-source-cloudtrail-s3-sqs aws-source-cloudfront-logs-s3-sqs aws-source-load-balancer-logs-s3-sqs aws-source-route53-resolver-logs-s3-sqs aws-source-s3-access-logs-s3-sqs aws-source-vpc-flow-logs-s3-sqs aws-source-waf-logs-s3-sqs aws-source-cloudwatch-logs-api aws-source-kinesis-stream aws-source-security-lake; do
  aws s3 cp "../${id}/template.yaml" "s3://${BUCKET}/${PREFIX}/${id}.yaml" --region "$REGION" --content-type application/x-yaml
done
# a Key=Value on the command line replaces that key from the file; TemplateBaseUrl is always this upload
KEYS=" TemplateBaseUrl "; for kv in "${ARGS[@]:2}"; do KEYS="$KEYS${kv%%=*} "; done
OVERRIDES=("TemplateBaseUrl=${BASE}")
while IFS= read -r kv; do
  case "$KEYS" in *" ${kv%%=*} "*) ;; *) OVERRIDES+=("$kv") ;; esac
done < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' parameters.example.json)
OVERRIDES+=("${ARGS[@]:2}")
if grep -q '=<' <(printf '%s\n' "${OVERRIDES[@]}"); then
  echo "parameters.example.json still holds a <placeholder>; set it or pass Key=Value" >&2; exit 2
fi
MODE=(--no-execute-changeset); $EXECUTE && MODE=()
aws cloudformation deploy --stack-name "$STACK" --template-file template.yaml --region "$REGION" \
  --capabilities CAPABILITY_NAMED_IAM --parameter-overrides "${OVERRIDES[@]}" ${MODE[@]+"${MODE[@]}"}
$EXECUTE && aws cloudformation describe-stacks --stack-name "$STACK" --region "$REGION" --query 'Stacks[0].Outputs' --output table
exit 0
