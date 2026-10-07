#!/usr/bin/env bash
# Preview the change with a change set, then apply it with --yes. Parameters come from
# parameters.example.json (copy it and edit, or pass Key=Value overrides after the stack name).
#   ./deploy.sh <stack-name> [Key=Value ...]          # create the change set and show it
#   ./deploy.sh <stack-name> [Key=Value ...] --yes    # create and execute it
set -euo pipefail
cd "$(dirname "$0")"
command -v aws >/dev/null || { echo "aws CLI v2 is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
EXECUTE=false; ARGS=()
for a in "$@"; do if [ "$a" = "--yes" ]; then EXECUTE=true; else ARGS+=("$a"); fi; done
[ "${#ARGS[@]}" -ge 1 ] || { echo "usage: ./deploy.sh <stack-name> [Key=Value ...] [--yes]" >&2; exit 2; }
STACK="${ARGS[0]}"
# a Key=Value on the command line replaces that key from the file
KEYS=" "; for kv in "${ARGS[@]:1}"; do KEYS="$KEYS${kv%%=*} "; done
OVERRIDES=()
while IFS= read -r kv; do
  case "$KEYS" in *" ${kv%%=*} "*) ;; *) OVERRIDES+=("$kv") ;; esac
done < <(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' parameters.example.json)
OVERRIDES+=("${ARGS[@]:1}")
if grep -q '=<' <(printf '%s\n' "${OVERRIDES[@]}"); then
  echo "parameters.example.json still holds a <placeholder>; set it or pass Key=Value" >&2; exit 2
fi
# The stack has ten alarm slots; refuse more names rather than leave some queues silently unwatched.
for kv in "${OVERRIDES[@]}"; do
  case "$kv" in DeadLetterQueueNames=*)
    n=$(printf '%s' "${kv#*=}" | tr ',' '\n' | grep -c .)
    [ "$n" -le 10 ] || { echo "DeadLetterQueueNames has $n names; this stack alarms on ten at most. Deploy a second stack for the rest." >&2; exit 2; } ;;
  esac
done
MODE=(--no-execute-changeset); $EXECUTE && MODE=()
aws cloudformation deploy --stack-name "$STACK" --template-file template.yaml \
  --capabilities CAPABILITY_NAMED_IAM --parameter-overrides "${OVERRIDES[@]}" ${MODE[@]+"${MODE[@]}"}
$EXECUTE && aws cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].Outputs' --output table
exit 0
