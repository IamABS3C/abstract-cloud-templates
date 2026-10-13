# Permissions: every grant, at every scope

Most Azure onboarding failures are permission failures, and most of those are about **which system**
holds the right, not which role. Entra ID roles and Azure RBAC roles are separate: an Entra role never
grants an Azure right, and the reverse is true too. A Global Administrator holds no Azure RBAC role at all
until they elevate.

---

## The one that blocks people

> ### `Microsoft.Resources/deployments/*` at the scope you deploy to
>
> Every ARM or Bicep deployment, including its validation and what-if preview, needs this right at the
> deployment's own scope. Without it the deploy stops before anything is created:
>
> ```text
> You don't have authorization to perform action 'Microsoft.Resources/deployments/validate/action'.
> ```
>
> The Entra ID template deploys at **tenant scope**, so the scope is the tenant root `/`. Nobody holds a
> role there by default, Global Administrator included. Contributor on `/` is enough; Owner also works.

See what you, or the person who will deploy, hold. This changes nothing:

```bash
cd ~/abstract-cloud-templates/templates/azure
./azure-source-entra-id-logs-tenant/deploy.sh access Check --assignee USER
```

If it is missing, a Global Administrator grants it, deploys (or lets USER deploy), then removes it.
Each write is printed and asked first, and recorded in a file per template in your home directory
(`~/.abstract-azure-access.<template-id>.record`), so one template's `Revoke` never removes what another
template granted:

```bash
./azure-source-entra-id-logs-tenant/deploy.sh access Elevate
./azure-source-entra-id-logs-tenant/deploy.sh access Grant --for entra --assignee USER
./azure-source-entra-id-logs-tenant/deploy.sh access Revoke --keep-groups
```

`Elevate` is the same switch as Entra ID, Properties, **Access management for Azure resources**: it gives
the Global Administrator User Access Administrator at `/`, which is what lets them grant anything there.
**Elevation alone does not fix the error.** User Access Administrator, like Role Based Access Control
Administrator, can grant roles but holds no `Microsoft.Resources/deployments/*`, so the person who
deploys still needs Contributor (or Owner) at `/`, which is what `Grant --for entra` adds.
`Revoke` removes what `Grant` added, then the elevation, and only what this setup recorded. Run it as the
same person in the same Cloud Shell, because the record lives in that home directory.

**No rights at `/` at all?** The Entra admin center creates the same diagnostic setting with Security
Administrator alone: Entra ID, Monitoring & health, Diagnostic settings, Add diagnostic setting, Stream to
an event hub. Only the template path needs the root-scope right.

---

## Management groups: pick one, or create one

The Policy templates are assigned at a management group, and cover every subscription in it, including
ones added later. `access Check` lists the groups you can see and the tenant's setting for creating them.

```bash
cd ~/abstract-cloud-templates/templates/azure/azure-source-all-logs-management-group-policy
./deploy.sh access Check -m MG_ID
./deploy.sh access MgCreate -m MG_ID --display-name "Abstract onboarding"
./deploy.sh access MgAddSub -m MG_ID -s SUBSCRIPTION_ID
./deploy.sh access MgDefault -m MG_ID
```

- **Creating a group** needs no role unless the tenant turned on *Require write permissions for creating
  new management groups*; then it needs Management Group Contributor (or Owner) on the root group.
  Whoever creates a group is given **Owner** on it, which is every right the Policy templates need.
- **Moving a subscription** in needs write rights on the subscription and on both the group it leaves and
  the group it joins; the root group is exempt on either side. The subscription then inherits the new
  group's Policies and roles, and loses the old group's. `MgAddSub` records where it was, and refuses to
  move a subscription whose current group it cannot read unless you pass `--from MG_ID`, because a move
  with no known origin could never be undone.
- **The default group for new subscriptions** is the root group until changed. Changing it needs
  Hierarchy Settings Administrator (or Owner) on the root group. `MgDefault` changes only the default and
  keeps the tenant's other setting.
- Azure caches management-group changes for up to 30 minutes, so a new group or move can take that long
  to show everywhere.

`access Revoke` (without `--keep-groups`) undoes these too: the default goes back, each subscription moves
back, and a group `MgCreate` made is deleted only once it is empty. If those moves needed elevation the first
time, run `access Elevate` again before the final `Revoke`; it removes the elevation again at the end, by the
assignment id it created, never by role.

---

## Every role, by template

| Template | Role | Where | Who holds it |
|---|---|---|---|
| Entra ID logs (tenant) | `Microsoft.Resources/deployments/*`: Contributor or Owner | Tenant root `/` | Deployer. `access Grant --for entra` |
| Entra ID logs (tenant) | Security Administrator (Entra role) | The Entra tenant | Deployer. `access Grant --for entra` adds it unless `--no-entra-role` |
| Entra ID logs (tenant) | Attribute Log Administrator (Entra role) | The Entra tenant | Deployer, only for `CustomSecurityAttributeAuditLogs` |
| All Azure logs by Policy | Owner, or Resource Policy Contributor plus Role Based Access Control Administrator | The management group | Deployer. `access Grant --for log-policy` |
| All Azure logs by Policy | Role Based Access Control Administrator (or Owner) | Each Event Hubs namespace | Whoever runs `deploy-log-streams.sh -a Grant`. `access Grant ... --namespace NAMESPACE_ID` |
| App registrations by Policy | Owner, or Resource Policy Contributor plus Role Based Access Control Administrator | The management group | Deployer. `access Grant --for appreg-policy` |
| App registrations by Policy | Global Administrator or Privileged Role Administrator | The Entra tenant | Once, for the managed identity's Graph consent (`./deploy.sh bootstrap`) |
| Any Policy template | Management Group Contributor | The root management group | Only to create a group when the tenant protects the hierarchy |
| Activity Log, one subscription | Monitoring Contributor, which includes `Microsoft.Resources/deployments/*` | The subscription, not a resource group | Deployer |
| Resource-group templates | Contributor, plus User Access Administrator (or Owner instead of both) where the template creates role assignments | The resource group | Deployer. Each README names its own |

Each template's README lists its own permissions in full, including the ones its managed identities need.

Granting at `/` or on a management group needs a right to grant there: User Access Administrator, Role
Based Access Control Administrator or Owner. A Global Administrator gets User Access Administrator at `/`
from `access Elevate`. Granting an Entra role needs Privileged Role Administrator or Global Administrator.

> The `access` commands are tested against a stub Azure CLI only; they have not yet run against a live
> tenant. If `Revoke` finds nothing recorded, it lists what the caller and `--assignee` still hold rather
> than reporting success, because the record may sit in another Cloud Shell. Every role, scope and command above is from Microsoft Learn: *Tenant deployments with Bicep*
> (Required access), *Elevate access to manage all Azure subscriptions and management groups*, *Manage your
> Azure subscriptions at scale with management groups*, *Protect your resource hierarchy*, and *Azure
> built-in roles*.
