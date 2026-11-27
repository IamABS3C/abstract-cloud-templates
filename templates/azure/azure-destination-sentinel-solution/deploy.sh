#!/usr/bin/env bash
# Deploy Abstract Security for Microsoft Sentinel into a resource group.
#   ./deploy.sh RESOURCE_GROUP [--parameters @my.parameters.json | NAME=VALUE ...]         preview (what-if), changes nothing
#   ./deploy.sh RESOURCE_GROUP --yes [--parameters @my.parameters.json | NAME=VALUE ...]   deploy
# Without --parameters every parameter takes its default. parameters.example.json shows one value for each: copy it to
# my.parameters.json, keep the ones you want, and pass --parameters @my.parameters.json. It is never read on its own,
# because its values are examples, not choices.
# On a brand-new workspace with ASIM on, Azure can refuse the first Data Collection Rule with InvalidOutputTable because
# Microsoft Sentinel creates the ASim tables a minute or two after onboarding. This script then waits 3 minutes and
# deploys once more with the same inputs; the second run completes it.
# Exit 3: a lane family rule this deployment would create has the name of a rule it did not make (see preflight below).
set -euo pipefail
cd "$(dirname "$0")"
[ $# -ge 1 ] || { sed -n '2,10p' "$0"; exit 2; }
rg="$1"; shift
yes=0; args=()
for a in "$@"; do if [ "$a" = "--yes" ]; then yes=1; else args+=("$a"); fi; done
# A fixed deployment name keeps the outputs under one name: az deployment group show -n azure-destination-sentinel-solution
name="azure-destination-sentinel-solution"

# Family rules (laneFamilies) are named <dataCollectionRuleName>-<family>, and Azure REPLACES a rule that already has that
# name. Before the preview and before the deployment, each family rule these parameters would create is looked up: it may
# be missing, or carry this deployment's two tags (abstract-lane-family = <family>, abstract-main-rule = <main rule>);
# anything else stops here, so an unrelated rule is never overwritten. Its lines go to stderr; stdout stays the result JSON.
family_rules() {
  python3 - "$@" <<'PY'
import json, sys
from pathlib import Path
args, params, i = sys.argv[1:], {}, 0
def take(spec):
    if spec.startswith("@"):
        doc = json.loads(Path(spec[1:]).read_text())
        for k, v in doc.get("parameters", doc).items():
            params[k] = v.get("value") if isinstance(v, dict) and "value" in v else v
    elif "=" in spec:
        k, v = spec.split("=", 1)
        try:
            params[k] = json.loads(v)
        except ValueError:
            params[k] = v
while i < len(args):
    if args[i] in ("--parameters", "-p"):
        i += 1
        while i < len(args) and not args[i].startswith("-"):
            take(args[i]); i += 1
        continue
    i += 1
if params.get("deployDataPlane", True) in (False, "false"):
    sys.exit(0)
main = params.get("dataCollectionRuleName", "abstract-dcr")
chosen, families = params.get("nativeVendors", []), params.get("laneFamilies", [])
lanes = json.loads(Path("content/native-vendors.json").read_text())["vendors"] + json.loads(Path("content/native-lanes.generated.json").read_text())["lanes"]
for family in sorted({l["family"] for l in lanes if l.get("option", l["name"]) in chosen and l.get("family") in families}):
    print(f"{main}-{family} {family} {main}")
PY
}
preflight() {
  local rule family main tags bad=0
  while read -r rule family main; do
    [ -n "$rule" ] || continue
    if ! tags="$(az monitor data-collection rule show --resource-group "$rg" --name "$rule" --query tags -o json 2>/dev/null)"; then
      echo "Family rule $rule: not in $rg, it will be created." >&2; continue
    fi
    # az prints nothing, not null, for a rule with no tags
    if python3 -c 'import json,sys; t=json.loads(sys.argv[1] or "null") or {}; sys.exit(0 if t.get("abstract-lane-family")==sys.argv[2] and t.get("abstract-main-rule")==sys.argv[3] else 1)' "$tags" "$family" "$main"; then
      echo "Family rule $rule: made by this deployment (tags abstract-lane-family=$family, abstract-main-rule=$main), it will be updated in place." >&2
    else
      echo "Family rule $rule: a Data Collection Rule of this name is already in $rg and was not made by this deployment (its tags: ${tags:-none}). Deploying would replace its streams, destinations and dataflows. Rename or remove it, choose another dataCollectionRuleName, or leave family $family out of laneFamilies." >&2
      bad=1
    fi
  done < <(family_rules "${args[@]+"${args[@]}"}")
  return $bad
}
preflight || exit 3

if [ "$yes" -eq 0 ]; then
  exec az deployment group what-if --resource-group "$rg" --name "$name" --template-file azuredeploy.json "${args[@]+"${args[@]}"}"
fi
run() {
  az deployment group create --resource-group "$rg" --name "$name" --template-file azuredeploy.json "${args[@]+"${args[@]}"}" \
    --query "{state:properties.provisioningState, correlationId:properties.correlationId, outputs:properties.outputs}" -o json
}
if out="$(run 2>&1)"; then echo "$out"; exit 0; fi
echo "$out" >&2
if grep -q "InvalidOutputTable" <<<"$out"; then
  echo "InvalidOutputTable: the ASim tables are not there yet on this new workspace. Waiting 3 minutes, then deploying again." >&2
  sleep 180
  run
else
  exit 1
fi
