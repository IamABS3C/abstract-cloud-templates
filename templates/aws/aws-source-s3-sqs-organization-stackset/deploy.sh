#!/usr/bin/env bash
# Roll one sibling per-source template out to every account in an organizational unit with a
# service-managed StackSet. The sibling's parameters.example.json supplies the stack-set parameters
# (copy it and edit first); scripts/stackset.sh does the work and accepts --dry-run.
#   ./deploy.sh <template-id> <ou-id> "<region> [<region> ...]" [--auto-deploy] [--update] [--dry-run]
# Example: ./deploy.sh aws-source-vpc-flow-logs-s3-sqs ou-abcd-12345678 "us-east-1 us-west-2" --dry-run
set -euo pipefail
cd "$(dirname "$0")"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ "$#" -ge 3 ] || { echo "usage: ./deploy.sh <template-id> <ou-id> \"<regions>\" [--auto-deploy] [--update] [--dry-run]" >&2; exit 2; }
ID="$1"; OU="$2"; REGIONS="$3"; shift 3
case "$ID" in aws-source-*-s3-sqs) ;; *) echo "$ID is not a per-source S3 template" >&2; exit 2 ;; esac
[ -f "../${ID}/template.yaml" ] || { echo "no template ../${ID}/template.yaml" >&2; exit 2; }
PARAMS=()
while IFS= read -r kv; do PARAMS+=(--param "$kv"); done \
  < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "../${ID}/parameters.example.json")
if grep -q '=<' <(printf '%s\n' "${PARAMS[@]}"); then
  echo "../${ID}/parameters.example.json still holds a <placeholder>; edit it first" >&2; exit 2
fi
exec ./scripts/stackset.sh --name "abstract-${ID#aws-source-}" --template "../${ID}/template.yaml" \
  --ou "$OU" --regions "$REGIONS" "${PARAMS[@]}" "$@"
