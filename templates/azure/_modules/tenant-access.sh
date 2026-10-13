#!/usr/bin/env bash
# =============================================================================
#  Abstract Security - Azure tenant access and management groups
#
#  A tenant-scope or management-group-scope template needs Azure RBAC at that
#  scope, and no Entra role grants it, not even Global Administrator. The error
#    "does not have authorization to perform action
#     'Microsoft.Resources/deployments/validate/action'"
#  means exactly that right is missing, not that the template is broken. This
#  driver checks, grants and removes those rights, and picks or creates the
#  management group the Policy templates are assigned at.
#
#    Check      read-only: who you are, whether you are elevated, the tenant's
#               management-group settings, the management groups you can see,
#               and the roles an assignee holds at "/" and at a management group
#    Elevate    Global Administrator only: User Access Administrator at "/" for
#               yourself, which is what lets you grant the roles below
#    Grant      the roles one template's deployer needs, one assignment per
#               role, each printed and asked first, each recorded:
#                 --for entra          Contributor at "/" (or --role <name>) and
#                                      the Entra Security Administrator role
#                 --for log-policy     Resource Policy Contributor and Role Based
#                 --for appreg-policy  Access Control Administrator on -m <mg-id>
#                 --namespace <id>     also Role Based Access Control Administrator
#                                      on an Event Hubs namespace (log-policy Grant)
#    MgCreate   create a management group, or confirm one that exists. Whoever
#               creates it is its Owner, which covers every Policy template here
#    MgAddSub   move a subscription into a management group, recording where it
#               was; refuses when it cannot read the current group unless --from
#               names it, because a move without a known origin cannot be undone
#    MgDefault  make a management group the default for new subscriptions
#    Revoke     undo what THIS SETUP recorded, newest first: grants, moves, the
#               default, the management groups it created (only if empty), and
#               elevation last. --keep-groups undoes only grants and elevation, for
#               when the deploy is done and the management group stays. Elevation
#               is removed by the assignment id Elevate recorded, never by role
#
#  Usage, from a template folder whose ./deploy.sh wraps it as "access"
#  (./deploy.sh access <Action> passes every further argument through), or directly:
#    ../_modules/tenant-access.sh -a Check     [--assignee <upn|object-id>] [-m <mg-id>]
#    ../_modules/tenant-access.sh -a MgCreate  -m <mg-id> [--display-name <name>] [--parent <mg-id>]
#    ../_modules/tenant-access.sh -a MgAddSub  -m <mg-id> -s <subscription-id> [--from <mg-id>]
#    ../_modules/tenant-access.sh -a MgDefault -m <mg-id>
#    ../_modules/tenant-access.sh -a Elevate
#    ../_modules/tenant-access.sh -a Grant     --for entra --assignee <upn|object-id>
#    ../_modules/tenant-access.sh -a Grant     --for log-policy --assignee <upn|object-id> -m <mg-id>
#    ../_modules/tenant-access.sh -a Revoke    [--keep-groups] [--assignee <upn>] [-m <mg-id>]
#  Options: --setup <id>: the record this run writes and Revoke reads, one per setup
#  (~/.abstract-azure-access.<id>.record; every ./deploy.sh access passes its template id, so one
#  template's Revoke never removes another's grants); --state <file> names a record file
#  outright; --from <mg-id> (MgAddSub: the subscription's current group when Azure will not say);
#  --role <name> (entra only, default Contributor); --no-entra-role (skip the directory role,
#  e.g. where PIM manages it); -y/--yes (no questions).
#
#  Every write is one az call for one role or one object, printed before it runs. Without a
#  terminal and without --yes it is printed and not run, so it can be handed to someone who
#  holds the right. Reads no secrets and writes none.
# =============================================================================
set -euo pipefail

STATE=""; SETUP=""
ACTION=""; MG_ID=""; DISPLAY_NAME=""; PARENT=""; FROM_MG=""; SUB_ID=""; ASSIGNEE=""; FOR=""; NAMESPACE_ID=""
ROOT_ROLE="Contributor"; ENTRA_ROLE=true; ASSUME_YES=false; KEEP_GROUPS=false

GRAPH="https://graph.microsoft.com/v1.0"
MG_SCOPE="/providers/Microsoft.Management/managementGroups"
ENTRA_ROLE_NAME="Security Administrator"
POLICY_ROLES=("Resource Policy Contributor" "Role Based Access Control Administrator")

say()  { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m  + %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
die()  { printf '\033[0;31m  X %s\033[0m\n' "$*" >&2; exit 1; }

usage() { sed -n '3,57p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--action)           ACTION="$2"; shift 2 ;;
    -m|--management-group) MG_ID="$2"; shift 2 ;;
    -s|--subscription)     SUB_ID="$2"; shift 2 ;;
    -u|--assignee)         ASSIGNEE="$2"; shift 2 ;;
    -f|--for)              FOR="$2"; shift 2 ;;
    -n|--namespace)        NAMESPACE_ID="$2"; shift 2 ;;
    --display-name)        DISPLAY_NAME="$2"; shift 2 ;;
    --parent)              PARENT="$2"; shift 2 ;;
    --from)                FROM_MG="$2"; shift 2 ;;
    --setup)               SETUP="$2"; shift 2 ;;
    --role)                ROOT_ROLE="$2"; shift 2 ;;
    --no-entra-role)       ENTRA_ROLE=false; shift ;;
    --keep-groups)         KEEP_GROUPS=true; shift ;;
    --state)               STATE="$2"; shift 2 ;;
    -y|--yes)              ASSUME_YES=true; shift ;;
    -h|--help)             usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -z "$ACTION" ]] && usage
if [[ -z "$STATE" ]]; then
  [[ -z "$SETUP" || "$SETUP" =~ ^[A-Za-z0-9._-]+$ ]] || die "not a valid --setup id: $SETUP"
  STATE="${HOME}/.abstract-azure-access${SETUP:+.$SETUP}.record"
fi
command -v az >/dev/null || die "az CLI not found."
az account show >/dev/null 2>&1 || die "not logged in. Run 'az login'."
TENANT=$(az account show --query tenantId -o tsv)

ERRF=$(mktemp); trap 'rm -f "$ERRF"' EXIT
OUT=""

# One write: print it, ask, run it. A refusal for lack of rights says so plainly, so the printed
# command can go to someone who has the right. Returns non-zero when nothing was changed.
write() {
  local what="$1"; shift
  printf '  $'; printf ' %q' "$@"; printf '\n'
  if ! $ASSUME_YES; then
    if [[ ! -t 0 ]]; then warn "not run: no terminal, and --yes was not given"; return 1; fi
    local r; read -r -p "  ${what}? [y/N] " r
    [[ "$r" =~ ^[Yy]$ ]] || { warn "skipped"; return 1; }
  fi
  if OUT=$("$@" 2>"$ERRF"); then return 0; fi
  local err; err=$(tr -d '\n' <"$ERRF" | head -c 400)
  if grep -qiE 'RoleAssignmentExists|already exists' <<<"$err"; then
    ok "already present; not recorded, so Revoke will leave it alone"
    return 1
  fi
  if grep -qiE 'AuthorizationFailed|Authorization_RequestDenied|does not have authorization|Insufficient privileges|Forbidden' <<<"$err"; then
    warn "FAILED, you do not hold the right for this: $err"
    warn "Hand the command above to someone who does${NEED_HINT:+. It needs $NEED_HINT}."
  else
    warn "FAILED: $err"
  fi
  return 1
}

record() { ( umask 077; printf '%s\n' "$*" >> "$STATE" ); }

# What a refused write needs, named per action. Elevation (User Access Administrator at "/") lets
# a Global Administrator grant roles; it does not include hierarchy-settings or deployment rights.
NEED_HINT="a role that can assign roles at that scope: Owner, User Access Administrator or Role Based Access Control Administrator; a Global Administrator gets User Access Administrator at \"/\" from -a Elevate"

need_mg() {
  [[ -n "$MG_ID" ]] || die "-m <management-group-id> is required for $ACTION."
  # Management group ids: up to 90 letters, digits, - _ ( ) and periods, not ending in a period.
  [[ "$MG_ID" =~ ^[A-Za-z0-9_().-]{1,90}$ && "$MG_ID" != *. ]] || die "not a valid management group id: $MG_ID"
}

me_id() { az ad signed-in-user show --query id -o tsv; }

# Resolve --assignee to an object id and principal type, so role assignments never depend on
# a later directory lookup.
PRINCIPAL_ID=""; PRINCIPAL_TYPE=""
resolve_assignee() {
  [[ -n "$ASSIGNEE" ]] || die "--assignee <upn|object-id> is required for $ACTION."
  local id
  if id=$(az ad user show --id "$ASSIGNEE" --query id -o tsv 2>/dev/null) && [[ -n "$id" ]]; then
    PRINCIPAL_ID="$id"; PRINCIPAL_TYPE=User
  elif id=$(az ad group show --group "$ASSIGNEE" --query id -o tsv 2>/dev/null) && [[ -n "$id" ]]; then
    PRINCIPAL_ID="$id"; PRINCIPAL_TYPE=Group
  elif id=$(az ad sp show --id "$ASSIGNEE" --query id -o tsv 2>/dev/null) && [[ -n "$id" ]]; then
    PRINCIPAL_ID="$id"; PRINCIPAL_TYPE=ServicePrincipal
  else
    die "no user, group or service principal found for $ASSIGNEE"
  fi
  ok "$ASSIGNEE is $PRINCIPAL_TYPE $PRINCIPAL_ID"
}

# Assignment ids held directly AT the scope (not inherited), for one principal and role. Azure
# returns resource ids in its own casing, so the scope is compared without case.
held_at() {
  local principal="$1" role="$2" scope="$3"
  { az role assignment list --assignee "$principal" --role "$role" --scope "$scope" \
      --query "[].[id, scope]" -o tsv 2>/dev/null || true; } |
    awk -F'\t' -v s="$scope" 'tolower($2) == tolower(s) { print $1 }'
}

hierarchy_raw() { az account management-group hierarchy-settings list --name "$TENANT" -o json 2>/dev/null || true; }
# One scalar field from az JSON, whatever wraps it; empty, never a failure, when it is absent.
json_field() { { grep -o "\"$1\": *[^,}]*" || true; } | head -1 | sed 's/^[^:]*: *//; s/"//g'; }

grant_rbac() {
  local role="$1" scope="$2"
  if [[ -n "$(held_at "$PRINCIPAL_ID" "$role" "$scope")" ]]; then
    ok "$role at $scope: already held directly, nothing to do"
    return 0
  fi
  if write "Give $ASSIGNEE $role at $scope" \
      az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type "$PRINCIPAL_TYPE" \
        --role "$role" --scope "$scope" --query id -o tsv; then
    record "rbac|${OUT}|${role}|${scope}|${ASSIGNEE}"
    ok "granted $role at $scope"
  fi
}

grant_entra_role() {
  local def have body
  def=$(az rest --method get \
    --url "${GRAPH}/roleManagement/directory/roleDefinitions?\$filter=displayName%20eq%20'Security%20Administrator'&\$select=id" \
    --query "value[0].id" -o tsv 2>/dev/null || true)
  [[ -n "$def" ]] || { warn "could not read the Entra role $ENTRA_ROLE_NAME; assign it in the Entra admin center"; return 0; }
  have=$(az rest --method get \
    --url "${GRAPH}/roleManagement/directory/roleAssignments?\$filter=principalId%20eq%20'${PRINCIPAL_ID}'%20and%20roleDefinitionId%20eq%20'${def}'" \
    --query "value[0].id" -o tsv 2>/dev/null || true)
  if [[ -n "$have" ]]; then ok "Entra $ENTRA_ROLE_NAME: already held, nothing to do"; return 0; fi
  body=$(printf '{"principalId":"%s","roleDefinitionId":"%s","directoryScopeId":"/"}' "$PRINCIPAL_ID" "$def")
  if write "Give $ASSIGNEE the Entra role $ENTRA_ROLE_NAME" \
      az rest --method post --url "${GRAPH}/roleManagement/directory/roleAssignments" \
        --headers "Content-Type=application/json" --body "$body" --query id -o tsv; then
    record "entra|${OUT}|${ENTRA_ROLE_NAME}|${ASSIGNEE}"
    ok "granted Entra $ENTRA_ROLE_NAME"
  fi
}

# -----------------------------------------------------------------------------
do_check() {
  say "Signed in"
  az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
  local me; me=$(me_id 2>/dev/null || true)

  say "Elevated access (User Access Administrator at \"/\")"
  if [[ -n "$me" && -n "$(held_at "$me" "User Access Administrator" /)" ]]; then
    warn "yes: you can grant roles anywhere in the tenant. Remove it when done (-a Revoke, or the Entra Properties toggle)"
  else
    ok "no"
  fi

  say "Your Entra directory roles"
  az rest --method get --url "${GRAPH}/me/memberOf/microsoft.graph.directoryRole?\$select=displayName" \
    --query "value[].displayName" -o tsv 2>/dev/null || warn "could not read them"

  say "Management-group settings for tenant $TENANT"
  local raw req def
  raw=$(hierarchy_raw)
  req=$(json_field requireAuthorizationForGroupCreation <<<"$raw")
  def=$(json_field defaultManagementGroup <<<"$raw")
  if [[ -z "$raw" ]]; then
    warn "could not read them; creating a management group may need Management Group Contributor on the root group"
  elif [[ "$req" == "true" ]]; then
    warn "creating a management group needs Management Group Contributor (or Owner) on the root group $TENANT"
  else
    ok "any user can create a management group, and becomes its Owner"
  fi
  ok "new subscriptions land in: ${def:-the root group $TENANT}"

  say "Management groups you can see"
  az account management-group list --query "[].{name:name, displayName:displayName}" -o table 2>/dev/null \
    || warn "none visible: you need a role on a management group, or elevation, to see them"

  local who="${ASSIGNEE:-$me}"
  [[ -n "$who" ]] || return 0
  say "Roles ${ASSIGNEE:-you} hold at the tenant root \"/\""
  az role assignment list --assignee "$who" --scope / --query "[?scope=='/'].roleDefinitionName" -o tsv 2>/dev/null \
    || warn "cannot list them: reading \"/\" needs a role there or elevation"
  if [[ -n "$MG_ID" ]]; then
    need_mg
    say "Roles ${ASSIGNEE:-you} hold on $MG_ID, inherited ones included"
    az role assignment list --assignee "$who" --scope "${MG_SCOPE}/${MG_ID}" --include-inherited \
      --query "[].{role:roleDefinitionName, scope:scope}" -o table 2>/dev/null || warn "cannot list them"
  fi

  say "What each template's deployer needs"
  echo "  Entra ID logs (tenant scope)      Microsoft.Resources/deployments/* at \"/\" (Contributor or Owner there)"
  echo "                                    and the Entra role $ENTRA_ROLE_NAME. The Entra admin center path"
  echo "                                    needs only $ENTRA_ROLE_NAME."
  echo "  Policy templates (management grp) Owner on the group, or ${POLICY_ROLES[0]} and"
  echo "                                    ${POLICY_ROLES[1]} there. Creating the group makes you its Owner."
}

do_elevate() {
  local me; me=$(me_id)
  if [[ -n "$(held_at "$me" "User Access Administrator" /)" ]]; then
    ok "already elevated; not recorded, so Revoke will leave it alone"
    return 0
  fi
  if write "Elevate your own access (User Access Administrator at \"/\")" \
      az rest --method post --url "/providers/Microsoft.Authorization/elevateAccess?api-version=2016-07-01"; then
    # Record the new assignment's own id, so Revoke removes exactly this one and never a User
    # Access Administrator someone was given at "/" by other means. It can take a moment to appear.
    local id="" i
    for i in 1 2 3 4 5 6; do
      id=$(held_at "$me" "User Access Administrator" / | head -1)
      [[ -n "$id" ]] && break
      sleep 5
    done
    record "elevated|${me}|${id}"
    ok "elevated"
    [[ -n "$id" ]] || warn "the new assignment is not readable yet; Revoke will fall back to removing your User Access Administrator at \"/\" by role"
    warn "Azure can take a few minutes to apply it. If the next step says AuthorizationFailed, run az login again and retry."
  fi
}

do_grant() {
  resolve_assignee
  case "$FOR" in
    entra)
      say "Tenant-scope deploy rights for $ASSIGNEE"
      grant_rbac "$ROOT_ROLE" /
      if $ENTRA_ROLE; then grant_entra_role; else ok "Entra role skipped (--no-entra-role)"; fi ;;
    log-policy|appreg-policy)
      need_mg
      say "Policy deploy rights for $ASSIGNEE on $MG_ID"
      local role
      for role in "${POLICY_ROLES[@]}"; do grant_rbac "$role" "${MG_SCOPE}/${MG_ID}"; done ;;
    *) die "--for must be entra, log-policy or appreg-policy" ;;
  esac
  if [[ -n "$NAMESPACE_ID" ]]; then
    say "Rights to grant on the Event Hubs namespace"
    grant_rbac "${POLICY_ROLES[1]}" "$NAMESPACE_ID"
  fi
  # Measured 2026-10-13 on a grant at "/": the session's existing token was refused with "If access
  # was recently granted, please refresh your credentials" for 12 minutes; a token minted after the
  # grant passed at 6 minutes. Propagation, not a broken grant.
  warn "A grant at this scope takes minutes to apply (measured: 12 with the existing sign-in, 6 after az logout && az login). AuthorizationFailed in that window is not a failed grant: wait, or sign in again, then retry."
  warn "Remove these when the setup is done: -a Revoke"
}

do_mg_create() {
  need_mg
  if az account management-group show --name "$MG_ID" --output none 2>/dev/null; then
    ok "$MG_ID exists and you can see it: using it, nothing created"
    return 0
  fi
  local cmd=(az account management-group create --name "$MG_ID" --display-name "${DISPLAY_NAME:-$MG_ID}")
  [[ -n "$PARENT" ]] && cmd+=(--parent "$PARENT")
  if [[ "$(hierarchy_raw | json_field requireAuthorizationForGroupCreation)" == "true" ]]; then
    warn "this tenant requires Management Group Contributor (or Owner) on the root group to create one"
  fi
  NEED_HINT="Management Group Contributor or Owner on the root management group $TENANT"
  if write "Create management group $MG_ID" "${cmd[@]}" --output none; then
    record "mg|${MG_ID}"
    ok "created $MG_ID under ${PARENT:-the default parent}; you are its Owner"
    warn "Azure can take up to 30 minutes to show a new group everywhere."
  fi
}

# The subscription's current management group: the entities list (core CLI) first, Resource Graph
# as a fallback. Empty when neither can see it.
sub_parent() {
  local id
  id=$(az account management-group entities list \
    --query "[?type=='/subscriptions' && name=='$1'].parent.id | [0]" -o tsv 2>/dev/null || true)
  if [[ -z "$id" ]] && az extension show --name resource-graph --output none 2>/dev/null; then
    id=$(az graph query -q "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' and subscriptionId =~ '$1' | project mg=tostring(properties.managementGroupAncestorsChain[0].name)" \
      --query "data[0].mg" -o tsv 2>/dev/null || true)
  fi
  [[ -z "$id" ]] || basename "$id"
}

do_mg_add_sub() {
  need_mg
  [[ -n "$SUB_ID" ]] || die "-s <subscription-id> is required for MgAddSub."
  local prev; prev=$(sub_parent "$SUB_ID")
  if [[ -n "$FROM_MG" ]]; then
    [[ -z "$prev" || "$prev" == "$FROM_MG" ]] || die "$SUB_ID is in $prev now, not in --from $FROM_MG"
    prev="$FROM_MG"
  fi
  if [[ "$prev" == "$MG_ID" ]]; then ok "$SUB_ID is already in $MG_ID"; return 0; fi
  # A move whose origin is unknown could never be undone, so it is not made.
  [[ -n "$prev" ]] || die "cannot read which group $SUB_ID is in now. Look it up (Azure portal, Management groups) and pass --from <mg-id>, so Revoke can move it back."
  warn "the subscription will inherit every Policy and role on $MG_ID, and lose those of $prev"
  NEED_HINT="managementGroups/write on $MG_ID and on $prev (the root group is exempt), and roleAssignments/write on the subscription"
  if write "Move subscription $SUB_ID into $MG_ID (from $prev)" \
      az account management-group subscription add --name "$MG_ID" --subscription "$SUB_ID" --output none; then
    record "mgsub|${MG_ID}|${SUB_ID}|${prev}"
    ok "moved"
  fi
}

do_mg_default() {
  need_mg
  local raw prev target="${MG_SCOPE}/${MG_ID}" verb=create
  raw=$(hierarchy_raw)
  prev=$(json_field defaultManagementGroup <<<"$raw")
  if [[ "$prev" == "$target" ]]; then ok "$MG_ID is already the default"; return 0; fi
  # update changes only the default; create replaces the whole settings object, so use it only
  # when there is none to keep.
  grep -qE '"(requireAuthorizationForGroupCreation|defaultManagementGroup)"' <<<"$raw" && verb=update
  # Measured 2026-10-13: User Access Administrator at "/" is refused settings/write on the root group.
  NEED_HINT="Hierarchy Settings Administrator or Owner on the root management group $TENANT (elevation alone is not enough)"
  if write "Make $MG_ID the default management group for every new subscription" \
      az account management-group hierarchy-settings "$verb" --name "$TENANT" --default-management-group "$target" --output none; then
    # When this run created the settings object, undo deletes it rather than leaving one behind. The
    # target is recorded too: hierarchy settings are shared by every setup, so undo must first check
    # that the default is still the one this setup chose.
    record "mgdefault|${prev}|${verb}|${target}"
    ok "new subscriptions now land in $MG_ID"
  fi
}

# Undo one recorded line. Returns non-zero to keep the line for a later Revoke.
undo() {
  local kind a b c d
  IFS='|' read -r kind a b c d <<<"$1"
  case "$kind" in
    rbac)
      write "Remove $b at $c from ${d:-the assignee}" az role assignment delete --ids "$a" --output none ;;
    entra)
      write "Remove the Entra role $b" az rest --method delete --url "${GRAPH}/roleManagement/directory/roleAssignments/${a}" ;;
    mgsub)
      if [[ -z "$c" ]]; then warn "$b was moved into $a from a group this record does not name: move it back by hand, then delete its line from $STATE"; return 1; fi
      write "Move subscription $b back to $c" az account management-group subscription add --name "$c" --subscription "$b" --output none ;;
    mgdefault)
      # Another setup may have changed the default since (the settings object is tenant-wide); then
      # this record is not ours to undo, and it stays until that setup has undone its own change.
      local now; now=$(hierarchy_raw | json_field defaultManagementGroup)
      if [[ -n "$now" && -n "$c" && "$now" != "$c" ]]; then
        warn "the default management group is now $now, not the $c this setup chose: someone changed it since, so it is left alone (line kept)"
        return 1
      fi
      if [[ "$b" == create ]]; then
        write "Remove the hierarchy settings this setup created (new subscriptions land in the root group again)" \
          az account management-group hierarchy-settings delete --name "$TENANT" --yes --output none
      else
        write "Restore the default management group to ${a:-the root group}" \
          az account management-group hierarchy-settings update --name "$TENANT" \
            --default-management-group "${a:-${MG_SCOPE}/${TENANT}}" --output none
      fi ;;
    mg)
      local children
      children=$(az account management-group show --name "$a" --expand --query "length(children || \`[]\`)" -o tsv 2>/dev/null || echo "?")
      if [[ "$children" != "0" ]]; then
        warn "$a still holds subscriptions or groups ($children): not deleted. Empty it, then run Revoke again"
        return 1
      fi
      write "Delete the empty management group $a" az account management-group delete --name "$a" --output none ;;
    elevated)
      if [[ -n "$b" ]]; then
        write "Remove the elevated access this setup created (User Access Administrator at \"/\", $b)" \
          az role assignment delete --ids "$b" --output none
      else
        write "Remove your elevated access (User Access Administrator at \"/\")" \
          az role assignment delete --assignee "$a" --role "User Access Administrator" --scope / --output none
      fi ;;
    *) warn "unknown line in $STATE: $1"; return 1 ;;
  esac
}

# With nothing recorded here, show what is still granted instead of implying it is all gone: the
# record may be in another Cloud Shell, or lost with an expired session.
show_remaining() {
  warn "nothing recorded in $STATE, on this machine. If access ran elsewhere, run Revoke there, or remove by hand what is listed below"
  local f others=()
  for f in "${HOME}"/.abstract-azure-access*.record; do [[ -s "$f" && "$f" != "$STATE" ]] && others+=("$f"); done
  [[ ${#others[@]} -eq 0 ]] || warn "other setups have records here: ${others[*]}; each is revoked from its own template folder, or with --state <file>"
  local me; me=$(me_id 2>/dev/null || true)
  if [[ -n "$me" && -n "$(held_at "$me" "User Access Administrator" /)" ]]; then
    warn "you are still elevated: az role assignment delete --assignee $me --role \"User Access Administrator\" --scope /"
  else
    ok "you are not elevated"
  fi
  [[ -n "$ASSIGNEE" ]] || { ok "add --assignee <upn> to list what that person still holds at \"/\" and on -m"; return 0; }
  say "Roles $ASSIGNEE holds directly at \"/\""
  az role assignment list --assignee "$ASSIGNEE" --scope / --query "[?scope=='/'].{role:roleDefinitionName, id:id}" -o table 2>/dev/null \
    || warn "cannot list them: reading \"/\" needs a role there or elevation"
  if [[ -n "$MG_ID" ]]; then
    need_mg
    say "Roles $ASSIGNEE holds on $MG_ID"
    az role assignment list --assignee "$ASSIGNEE" --scope "${MG_SCOPE}/${MG_ID}" \
      --query "[].{role:roleDefinitionName, scope:scope, id:id}" -o table 2>/dev/null || warn "cannot list them"
  fi
}

do_revoke() {
  [[ -s "$STATE" ]] || { show_remaining; return 0; }
  local lines=() keep=() line i
  while IFS= read -r line; do [[ -n "$line" ]] && lines+=("$line"); done <"$STATE"
  say "Undoing ${#lines[@]} recorded change(s), newest first; elevation last"
  # Two passes: everything else, then elevation, which the rest may need.
  for pass in rest elevated; do
    for ((i=${#lines[@]}-1; i>=0; i--)); do
      line="${lines[i]}"
      if [[ "$pass" == rest && "$line" == elevated\|* ]] || [[ "$pass" == elevated && "$line" != elevated\|* ]]; then
        continue
      fi
      if $KEEP_GROUPS && [[ "$line" == mg* ]]; then keep=("$line" ${keep[@]+"${keep[@]}"}); continue; fi
      undo "$line" || keep=("$line" ${keep[@]+"${keep[@]}"})
    done
  done
  if [[ ${#keep[@]} -eq 0 ]]; then
    rm -f "$STATE"; ok "everything recorded is undone"
  else
    ( umask 077; printf '%s\n' "${keep[@]}" > "$STATE" )
    warn "${#keep[@]} change(s) kept in $STATE for the next Revoke"
  fi
}

case "$ACTION" in
  Check|check)         do_check ;;
  Elevate|elevate)     do_elevate ;;
  Grant|grant)         do_grant ;;
  MgCreate|mgcreate)   do_mg_create ;;
  MgAddSub|mgaddsub)   do_mg_add_sub ;;
  MgDefault|mgdefault) do_mg_default ;;
  Revoke|revoke)       do_revoke ;;
  *) die "unknown action '$ACTION'." ;;
esac
