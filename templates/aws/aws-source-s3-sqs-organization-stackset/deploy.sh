#!/usr/bin/env bash
# Roll one sibling per-source template out to every account in an organizational unit with a
# service-managed StackSet. The sibling's parameters.example.json supplies the non-secret defaults;
# scripts/stackset.sh does the work and accepts --dry-run.
#
# Never write the External ID into parameters.example.json or any other file here: those files are
# tracked and published. Give it, and Abstract's account ID, in the environment instead:
#   read -rs ABSTRACT_EXTERNAL_ID && export ABSTRACT_EXTERNAL_ID
#   export ABSTRACT_PRINCIPAL=<abstract-account-id>
# Any other value can be given as --param Key=Value, which overrides the example file.
#   ./deploy.sh <template-id> <ou-id> "<region> [<region> ...]" [--param Key=Value ...] [--auto-deploy] [--update] [--dry-run]
# Example: ./deploy.sh aws-source-load-balancer-logs-s3-sqs ou-abcd-12345678 "us-east-1 us-west-2" --dry-run
set -euo pipefail
cd "$(dirname "$0")"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ "$#" -ge 3 ] || { echo "usage: ./deploy.sh <template-id> <ou-id> \"<regions>\" [--param Key=Value ...] [--auto-deploy] [--update] [--dry-run]" >&2; exit 2; }
ID="$1"; OU="$2"; REGIONS="$3"; shift 3
case "$ID" in aws-source-*-s3-sqs) ;; *) echo "$ID is not a per-source S3 template" >&2; exit 2 ;; esac
[ -f "../${ID}/template.yaml" ] || { echo "no template ../${ID}/template.yaml" >&2; exit 2; }

# Overrides, in increasing precedence: the environment, then --param on the command line.
OVR='{}'
[ -n "${ABSTRACT_PRINCIPAL:-}" ] && OVR=$(jq -c --arg v "$ABSTRACT_PRINCIPAL" '. + {AbstractPrincipalArn: $v}' <<<"$OVR")
[ -n "${ABSTRACT_EXTERNAL_ID:-}" ] && OVR=$(jq -c --arg v "$ABSTRACT_EXTERNAL_ID" '. + {ExternalId: $v}' <<<"$OVR")
REST=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --param)
      [ "$#" -ge 2 ] && [[ "$2" == *=* ]] || { echo "--param needs Key=Value" >&2; exit 2; }
      OVR=$(jq -c --arg kv "$2" '($kv | split("=")) as $p | . + {($p[0]): ($p[1:] | join("="))}' <<<"$OVR"); shift 2 ;;
    *) REST+=("$1"); shift ;;
  esac
done

PARAMS=()
while IFS= read -r kv; do PARAMS+=(--param "$kv"); done < <(
  jq -r --argjson o "$OVR" \
    '((map({key: .ParameterKey, value: .ParameterValue}) | from_entries) + $o) | to_entries[] | "\(.key)=\(.value)"' \
    "../${ID}/parameters.example.json")
MISSING=$(printf '%s\n' "${PARAMS[@]}" | grep '^[^=]*=<' | cut -d= -f1 | grep -v '^--param$' || true)
if [ -n "$MISSING" ]; then
  echo "still a <placeholder>: $(echo "$MISSING" | tr '\n' ' ')" >&2
  echo "set ABSTRACT_EXTERNAL_ID and ABSTRACT_PRINCIPAL in the environment, or pass --param Key=Value; never edit the tracked file" >&2
  exit 2
fi
exec ./scripts/stackset.sh --name "abstract-${ID#aws-source-}" --template "../${ID}/template.yaml" \
  --ou "$OU" --regions "$REGIONS" "${PARAMS[@]}" ${REST[@]+"${REST[@]}"}
