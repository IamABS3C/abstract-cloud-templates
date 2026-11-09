#!/usr/bin/env bash
# Removes what the Sentinel discovery template created. Does nothing without --yes.
#   ./teardown.sh <resource-group>         shows what would be removed
#   ./teardown.sh <resource-group> --yes   removes it
# Deleting the resource group alone would leave work behind in other scopes, so this first removes, for every discovery
# identity in the group: its role assignments on the workspace resource group and subscription, and the deployment-history
# records its modules left there. Then it deletes the resource group, including the storage account and every report in it.
# It never touches a workspace, its tables, its content or anything else in the workspace's resource group.
set -euo pipefail
RG="${1:?usage: teardown.sh <resource-group> [--yes]}"
YES="${2:-}"
echo "Subscription: $(az account show --query '[name,id]' -o tsv | paste -sd' ' -)"
echo "Resource group $RG contains:"
az resource list -g "$RG" --query "[].{type:type,name:name}" -o table

for row in $(az identity list -g "$RG" --query "[?starts_with(name,'abstract-sentinel-discovery-')].[name,principalId]" -o tsv | tr '\t' ','); do
  name="${row%%,*}"; pid="${row##*,}"; suffix="${name##*-}"
  echo; echo "Identity $name ($pid) holds:"
  az role assignment list --assignee "$pid" --all --query "[].{role:roleDefinitionName,scope:scope}" -o table
  ids=$(az role assignment list --assignee "$pid" --all --query "[].id" -o tsv)
  # Azure returns /resourcegroups/ or /resourceGroups/ depending on the assignment, so classify the scope text case-insensitively.
  all_scopes=$(az role assignment list --assignee "$pid" --all --query "[].scope" -o tsv | sort -u)
  scopes=$(echo "$all_scopes" | grep -iE '^/subscriptions/[^/]+/resourcegroups/[^/]+$' || true)
  subs=$(echo "$all_scopes" | grep -iE '^/subscriptions/[^/]+$' || true)
  if [ "$YES" = "--yes" ]; then
    [ -z "$ids" ] || az role assignment delete --ids $ids
    for s in $scopes; do
      sub=$(echo "$s" | cut -d/ -f3); group=$(echo "$s" | cut -d/ -f5)
      az deployment group delete --subscription "$sub" -g "$group" -n "sentinel-discovery-roles-$suffix" || true
    done
    for s in $subs; do
      az deployment sub delete --subscription "${s##*/}" -n "sentinel-discovery-reader-$suffix" || true
    done
    echo "Removed its role assignments and module records."
  fi
done

if [ "$YES" != "--yes" ]; then
  echo; echo "Nothing removed. Run: $0 $RG --yes"; exit 0
fi
az group delete -n "$RG" --yes --no-wait
echo "Deletion of $RG started (az group show -n $RG to follow it)."
