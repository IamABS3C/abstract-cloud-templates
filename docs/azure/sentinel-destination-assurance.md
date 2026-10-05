# Microsoft Sentinel Destination — what it does, and what it can never change

This is the assurance guide for security, cloud and SOC teams deciding whether to connect
Abstract to a production Microsoft Sentinel workspace. It covers the Abstract Azure
Sentinel Destination integration and the two templates in this repository that prepare
Azure for it:

| Template | Use it when |
| --- | --- |
| [`sentinel-destination`](../../templates/azure/azure-destination-sentinel/README.md) | **Recommended for production.** You create the Entra app registration yourself (or with [`new-app-registration.sh`](../../templates/azure/azure-destination-sentinel/scripts/new-app-registration.sh)) and pass its service principal. No privileged identity is involved. |
| [`sentinel-destination-graph`](../../templates/azure/azure-destination-sentinel-app-by-graph/README.md) | **Recommended when you want the app created for you.** Creates the app registration and service principal as the person deploying, with the Microsoft Graph Bicep extension. **No managed identity has to exist first.** Optionally creates a managed identity that owns only this app to generate the secret. Azure CLI or PowerShell only. |
| [`sentinel-destination-with-app`](../../templates/azure/azure-destination-sentinel-app-by-script/README.md) | Portal wizard alternative. A deployment script creates the app registration and client secret, running as a **tier-0 managed identity you must create beforehand** (see [Identities](#6-identities-and-permissions)). |

Every statement below comes from one of three places, and says which when it matters:
- the templates and scripts in this repository, which are the source of truth;
- a measurement on a test Sentinel workspace fed by an Abstract test tenant (**Measured**);
- Microsoft's documentation (**Microsoft docs**).

Anything not established one of those ways is marked **Not verified**.

---

## At a glance

- **It never creates, edits, disables or deletes** an analytics rule, automation rule,
  hunting query, workbook, watchlist, data connector, parser or function, and it never
  changes the settings of an existing workspace or its Microsoft Sentinel onboarding. The
  only Microsoft Sentinel resource either template writes is the onboarding state of a
  **new** workspace it creates itself.
- **In an existing workspace the standard template adds three resources**: a custom table
  (`AbstractEventLogs_CL`), a Data Collection Endpoint and a Data Collection Rule. With
  defaults it also adds a diagnostic setting and one role assignment, both on that DCR.
  The with-app template additionally creates a Key Vault, a deployment script and the Entra
  app ([section 3](#3-exactly-what-each-template-creates-or-changes)).
- **With the default roles, the identity Abstract uses can only publish rows to that one
  DCR.** It gets Monitoring Metrics Publisher on the DCR, nothing on the workspace, and no
  Microsoft Graph permissions. It cannot read your data or touch your rules. (Opting into
  Monitoring Contributor also lets it change that DCR.)
- **Writing Microsoft's ASIM tables is off by default.** When you turn it on, your
  existing ASIM analytics rules start seeing Abstract data too. That is the point of the
  feature, and it is also the one way this destination can change how your existing
  detections behave. [Section 8](#8-asim-the-one-setting-that-changes-existing-detections)
  explains how to turn it on safely.
- **A redeploy never shortens retention or changes the table plan** unless you choose a
  value for those settings.

---

## 1. How the pieces fit

```
source -> Abstract (collect, normalize to ACS, filter, reduce, enrich)
       -> Abstract "Azure Sentinel Destination" (in your Abstract tenant)
            authenticates as your Entra app (client ID + secret, your tenant)
            POSTs each event to the Logs Ingestion API
       -> Data Collection Endpoint (your subscription)
       -> Data Collection Rule (your subscription)
            |- every event                      -> AbstractEventLogs_CL
            '- optional, mapped from ACS        -> Microsoft ASim*Logs tables
```

**What the Abstract destination integration does.** Abstract's managed Azure Sentinel
Destination sends each event, in the Abstract Common Schema (ACS), to the Azure Monitor
Logs Ingestion API:

- **Credentials:** a client ID and secret for an Entra app registration in your tenant,
  plus your tenant ID.
- **Target:** three values the templates output: `dataCollectionRuleImmutableId`,
  `dataCollectionEndpointUrl` and `logStreamName` (`Custom-AbstractEventLogs_CL`).
- **Payload:** each event is sent as its own nested JSON. The destination adds
  `timestamp` (a copy of `@timestamp`), `acs_type` and `acs_resource_*`. The DCR sets
  `TimeGenerated` from `timestamp` and stores ACS `id` and `type` as `acs_id` and
  `acs_type`, because Log Analytics reserves those names.
- **Configuration check:** when you save the destination, Abstract posts a single
  one-field test record (**Measured**: it lands with `TimeGenerated` set at arrival). That
  record proves the credentials and DCR work, not the table schema.

The destination is a push API client: it signs in to Entra ID and posts to the Logs
Ingestion API. It holds no Azure role other than the one you grant on the DCR, so it has no
access to Azure Resource Manager, Microsoft Graph or the Sentinel API.

**Measured end to end** (Abstract test tenant → the real destination → test workspace):
every event landed with its fields populated, including nested `ext.*` fields. Of 423
leaf values compared, 390 were byte-identical and 24 more differed only in date or number
formatting.

---

## 2. Choosing a deployment

| Question | Standard | Graph (no managed identity) | With-app (bring your own identity) |
| --- | --- | --- | --- |
| Who creates the app registration? | You, before deploying | The template, as the person deploying | A deployment script, as your managed identity |
| Managed identity needed beforehand? | No | **No** | **Yes**, holding Graph `Application.ReadWrite.All` |
| Managed identity afterwards? | None | None; or, with `automateSecret`, one that owns only this app (Graph `Application.ReadWrite.OwnedBy`) | Yours, still tier-0 |
| Client secret | You create it | You create it (the `secretCommand` output), or `automateSecret` stores one in a new Key Vault | New or existing Key Vault, or you create it |
| Deployer needs (Entra) | Rights to register an app | Rights to register an app; with `automateSecret`, Privileged Role Administrator or Global Administrator | Nothing extra beyond using the identity |
| Deployer needs (Azure) | Owner, or Contributor + User Access Administrator, on the resource group | The same | The same |
| How to deploy | Portal wizard or CLI | Azure CLI or PowerShell only | Portal wizard or CLI |
| Recommended for | Production, when you create the app yourself | Production, when the template should create the app | Portal-only teams, labs |

Both templates deploy at resource-group scope and can create a new workspace or target an
existing one. For an existing workspace, the DCE and DCR must be in the same region as the
workspace (set `existingWorkspaceLocation`).

---

## 3. Exactly what each template creates or changes

### Standard template (`sentinel-destination`)

| Resource | Created when | What it contains | In an existing workspace |
| --- | --- | --- | --- |
| Log Analytics workspace | `createWorkspace` = true | SKU, retention, resource-permission access mode | **Not created or modified** |
| Microsoft Sentinel onboarding (`onboardingStates/default`) | `createWorkspace` and `enableSentinel` | Turns Sentinel on | **Not created or modified** |
| Table `AbstractEventLogs_CL` (name from `customTableName`) | Always | 75 columns generated from the ACS catalog: `TimeGenerated`, one per top-level ACS key, and the fields the destination adds (`timestamp`, `acs_type`, `acs_resource_*`) | Created, or updated if a table of that name exists ([section 5](#5-what-it-can-change-and-how-to-control-it)) |
| Data Collection Endpoint (`abstract-dce`) | Always | Public ingestion endpoint | Created in the resource group |
| Data Collection Rule (`abstract-dcr`) | Always | One input stream; one dataflow to the Abstract table; one per enabled ASIM schema | Created in the resource group |
| Diagnostic setting `abstract-dcr-errors` on the DCR | `enableDcrErrorLogs` (default on) | Sends the DCR's ingestion errors to `DCRLogErrors` | Created on the new DCR only |
| Role assignment: Monitoring Metrics Publisher on the DCR | `principalId` supplied | The Abstract app's service principal | Scoped to the new DCR only |
| Role assignment: Monitoring Contributor on the DCR | `principalId` supplied **and** `grantMonitoringContributor` (default off) | Same principal | Scoped to the new DCR only |

Source: `templates/azure/azure-destination-sentinel/main.bicep`.

### Graph template (`sentinel-destination-graph`)

Everything in the standard table above (it calls the standard template as a module, with
the new service principal as `principalId`). In addition:

| Resource | Created when | Notes |
| --- | --- | --- |
| **Entra app registration** (Microsoft Graph Bicep) | Always | No API permissions; tagged `abstract:sentinel-destination`; `uniqueName` keeps redeploys on the same app |
| **Service principal** for the app | Always | Receives Monitoring Metrics Publisher on the DCR |
| User-assigned managed identity `abstract-sentinel-secret-writer` | `automateSecret` | Made an owner of the app and its service principal, and nothing else |
| Graph app role `Application.ReadWrite.OwnedBy` for that identity | `automateSecret` | Lets it manage only apps it owns |
| Key Vault (RBAC authorization, soft delete, purge protection) | `automateSecret` | Holds only the client secret |
| Role: Key Vault Secrets Officer for the identity; Secrets User for `secretReaderObjectId` | `automateSecret` (reader only if supplied) | On the new vault only |
| Deployment script `abstract-create-secret` | `automateSecret` | Runs the same script as the with-app template, as the identity, to add the secret and store it |

Microsoft Graph Bicep cannot create client secrets (**Microsoft docs**), which is why the
secret is either created by you or by the optional deployment script. `what-if` does not
preview the Graph resources, and deleting the resource group does not delete the app.

**Measured on a test tenant (2026-09-28):**
- **Without `automateSecret`:**
  - the deployment created the app and service principal with no API permissions and no
    managed identity, and granted Monitoring Metrics Publisher on the DCR;
  - a redeploy reused the same app.
- **With `automateSecret`:**
  - the identity's only Graph permission was `Application.ReadWrite.OwnedBy`;
  - the secret was stored with the app's `appId` tag;
  - a redeploy reused it rather than adding another;
  - running as that identity, adding a secret to an app it did not own failed with
    *Insufficient privileges* (it can still read app registrations' properties);
  - the stored secret signed in and ingested a row through the DCR (HTTP 204).

### With-app template (`sentinel-destination-with-app`)

Everything in the standard table above, except that the role assignment always goes to
the service principal the script creates. In addition:

| Resource | Created when | Notes |
| --- | --- | --- |
| Key Vault (RBAC authorization, soft delete, purge protection) | `keyVaultMode` = Create | Holds only the client secret |
| Role: Key Vault Secrets Officer for the provisioning identity | `keyVaultMode` = Create or Existing | On the new vault, or on the existing vault you name. For an existing vault in another resource group, the deployer needs role-assignment rights there too |
| Role: Key Vault Secrets User for a reader you name | `secretReaderObjectId` supplied and `keyVaultMode` = Create or Existing | Optional |
| Deployment script `abstract-create-app` | Always | Runs `templates/azure/_modules/sentinel-app-deploymentscript.sh` as the provisioning identity. Azure creates a temporary storage account and container instance for it; with `cleanupPreference: Always` it removes them when the script ends, whether it succeeds or fails (**Microsoft docs**) |
| **Outside Azure Resource Manager (in Entra ID):** app registration, service principal, one client secret | Always (the secret only with a Key Vault) | The app has **no** API permissions. It is tagged `abstract:sentinel-destination` |

Deleting the resource group does **not** delete the Entra app or service principal.

---

## 4. What it never touches

Neither template contains a resource of these types, and neither script calls an API
that writes them:

- Microsoft Sentinel analytics rules, automation rules, hunting queries, bookmarks,
  incidents, watchlists, workbooks, data connectors, threat intelligence, or settings
  (`Microsoft.SecurityInsights/*`, apart from `onboardingStates` on a **new** workspace).
- Workspace functions, saved searches or parsers — including every ASIM parser.
- Any table other than the Abstract table. The ASIM tables are Microsoft's; the DCR adds
  rows to them when ASIM is on, and never creates, alters or re-plans them.
- An existing workspace's SKU, retention, daily cap, access mode, network settings or
  workspace transformation DCR.
- Any other DCR, DCE or diagnostic setting, unless it has the same name as one the
  template creates ([section 5](#5-what-it-can-change-and-how-to-control-it)).

The identity Abstract runs as cannot change any of these either: it holds only Monitoring
Metrics Publisher on the DCR ([section 6](#6-identities-and-permissions)).

> **The optional content pack is different.** The Sentinel content pack in
> [Sentinel content pack](../../templates/azure/azure-destination-sentinel-content-pack/README.md) template is a separate install. It does add analytics rules,
> automation rules, hunting queries, workbooks and playbooks, all of its own, never
> modifying yours. [Section 11](#11-the-optional-content-pack) covers it.

---

## 5. What it can change, and how to control it

Deploy in **Incremental** mode, which is Azure's default and what every command in this
guide uses: nothing outside the template is deleted. **Never** deploy these templates with
`--mode Complete`: in Existing mode the workspace is not part of the template, so Complete
mode would delete it and everything else in the resource group.

Within the template, a deployment writes each resource it declares. That matters in four
places.

| What | When it happens | Control |
| --- | --- | --- |
| **The Abstract table's column list** | A table named `customTableName` already exists | Columns not in the generated schema are removed, and a column whose type differs fails the deployment (**Microsoft docs**). A table created by an older, wrapped version of the destination (`TimeGenerated`, `Message`, `AbstractEvent`) would lose `Message` and `AbstractEvent`. Check first (pre-check 2 below), or use a new table name |
| **The Abstract table's retention and plan** | Only when you set them | `customTableRetentionDays` = 0 (default) sends no retention, and `customTablePlan` = Keep (default) sends no plan, so both stay as they are. **Measured:** a table update without retention kept 60 days interactive / 180 days total; redeploys over an Auxiliary table kept it Auxiliary. Setting a shorter retention deletes older data; setting a plan switches the whole table |
| **A DCR, DCE or diagnostic setting with the same name** | `abstract-dcr`, `abstract-dce` or `abstract-dcr-errors` already exists in the resource group | The template replaces it. A second destination in the same resource group with the default names would take over the first one's DCR. Give each destination its own names |
| **A new workspace, redeployed** | You redeploy in Create mode into the same resource group | The auto-generated name is deterministic, so the template re-applies its SKU, retention, access mode and tags to that workspace. After the first deployment, redeploy in **Existing** mode |

---

## 6. Identities and permissions

| Identity | Created by | Microsoft Graph | Azure roles (scope) | Least privilege? |
| --- | --- | --- | --- | --- |
| **Abstract runtime app** (the one Abstract authenticates as) | You, the operator scripts, or the with-app script | **None** | Monitoring Metrics Publisher (the DCR). Monitoring Contributor (the DCR) only if `grantMonitoringContributor` | Yes, by default |
| **Secret writer** (Graph template with `automateSecret`) | The template | `Application.ReadWrite.OwnedBy`, and owner of this one app only | Key Vault Secrets Officer (the new vault) | Yes |
| **Provisioning identity** (with-app only) | You, before deploying | `Application.ReadWrite.All` | Key Vault Secrets Officer (the new vault, or your existing vault) | No — see below |
| **Secret reader** (optional) | You name it | None | Key Vault Secrets User (the vault) | Acceptable |

**Monitoring Metrics Publisher** grants `Microsoft.Insights/Telemetry/Write`, the only
permission the Logs Ingestion API needs (**Microsoft docs**). **Measured:** with Monitoring Contributor removed
from the destination's service principal, Abstract kept delivering events to the test
workspace for the 25 minutes it was watched, including through a DCR redeploy. Monitoring Contributor is
therefore off by default; it would let the identity rewrite or delete the DCR and its
error-log setting.

**The provisioning identity is tier-0.** `Application.ReadWrite.All` can add a credential
to any app registration in the tenant, which can be used to act as that app. If you use
the with-app template:

- keep the identity in a resource group only administrators can write to;
- remove its Graph permission, or delete it, after onboarding;
- in Existing Key Vault mode, remove its Key Vault Secrets Officer role afterwards (it
  applies to the whole vault).

To avoid that identity altogether, use the **Graph template**. It creates the app as the
person deploying, and for secret automation it creates an identity that owns only this app
with `Application.ReadWrite.OwnedBy`. **Measured:** that is enough for the script, and the
identity cannot add a secret to any other app.

### If a credential leaked

| Credential | What an attacker could do | What they could not do |
| --- | --- | --- |
| Abstract runtime secret (default roles) | Send made-up rows to the Abstract table and, if ASIM is on, to the ASIM tables | Read any data; change rules, tables, the DCR or workspace settings |
| The same, with Monitoring Contributor granted | The above, plus rewrite or delete the DCR (stopping ingestion) and remove its error logs | Read workspace data; touch Sentinel content |
| Secret writer (Graph template) | Add or remove secrets on this one app, and read app registrations' properties | Change any app it does not own (**Measured**) |
| Provisioning identity (with-app) | Add a secret to any app registration in the tenant | — treat as a tenant-compromise risk |

---

## 7. Secrets

- The client secret is **never** returned in deployment outputs, deployment script output
  or logs. The script writes it to Key Vault through a file readable only by the script,
  never on a command line.
- A re-run reuses the stored secret while it has more than 30 days left and still belongs
  to the same app. The script never overwrites a same-named secret tagged for a different
  app, even with `forceSecretRotation`, and refuses a same-named secret with no `appId` tag
  unless `forceSecretRotation` is set.
- An existing app registration is reused only if exactly one has the name and it carries
  the `abstract:sentinel-destination` tag. The operator script
  ([`new-app-registration.sh`](../../templates/azure/azure-destination-sentinel/scripts/new-app-registration.sh))
  applies the same rule and tags the secret it stores with the app's `appId`.
- These decisions are tested on every change by running the script against a stubbed Azure
  CLI in the templates' source repository.
- If Key Vault is skipped (`keyVaultMode` = None), no secret is created: create one in
  Entra and paste it into Abstract once.
- Secrets last `secretValidityYears` (default 1 year). Rotation adds a new secret; remove
  the old one in Entra after Abstract is updated.
- Recommended: store the secret in Key Vault, restrict who can read it, and enable Key
  Vault diagnostic logging.

---

## 8. ASIM: the one setting that changes existing detections

With `enableAsim` on, the DCR also maps each event from ACS into Microsoft's normalized
table for its activity (`ASimAuthenticationEventLogs`, `ASimNetworkSessionLogs` and six
others; see [sentinel-asim.md](sentinel-asim.md)). Microsoft's built-in ASIM parsers read
those tables automatically (**Microsoft docs**), so:

- **Every ASIM analytics rule, hunting query and workbook already running in the
  workspace sees Abstract data from the moment rows arrive.** That can raise new
  incidents.
- **Duplicates:** if Microsoft's own connector also collects a vendor, ASIM returns that
  vendor's events twice, which can double-count thresholds.
- **Cost:** each mapped event is stored at least twice, once in the Abstract table and once
  in an ASIM table. An event whose category spans two schemas (for example authentication
  and iam, or web and network) lands in both ASIM tables.
- **UEBA:** Microsoft's documented UEBA sources do not include the ASIM tables, so UEBA
  should be unaffected (**Not verified** on a workspace).

**Built-in protections:**
- off by default;
- Abstract findings and alerts never go to the activity tables;
- events more than two days old stay out of the ASIM tables. Azure restamps such events
  with their arrival time (**Microsoft docs**), so a replay or backfill would otherwise look
  like live activity.

**To turn it on safely:**

1. **Stage it.** Enable it on a staging workspace that runs the same ASIM rules, or on
   production with one schema at a time (`asimSchemas`, for example `['Authentication']`).
2. **Find overlaps before and after:**
   ```kusto
   _Im_Authentication(starttime=ago(1d), endtime=now())
   | summarize Abstract = countif(isnotempty(tostring(AdditionalFields.AbstractEventId))),
               Other    = countif(isempty(tostring(AdditionalFields.AbstractEventId)))
       by EventVendor, EventProduct
   ```
   A vendor with both counts above zero is collected twice. Keep one source, or leave
   that schema out.
3. **Exclude Abstract rows from a specific rule** if needed:
   `| where isempty(tostring(AdditionalFields.AbstractEventId))`.
4. **Compare incident counts per rule** for 72 hours before and after.
5. **Wait 15 minutes after any DCR change** before judging. Measured: a DCR update takes
   about that long to settle, and the ASIM tables missed events in the first few minutes
   after each update.

---

## 9. Cost

| Item | Charged? |
| --- | --- |
| Ingestion into the Abstract table | Yes, at the table's plan (Analytics by default; Basic or Auxiliary are cheaper, but Sentinel analytics rules cannot run on Auxiliary, per **Microsoft docs**) |
| Ingestion into ASIM tables (when on) | Yes, a further copy of each mapped event |
| Retention beyond the free period | Yes |
| `DCRLogErrors` | Yes, normally tiny |
| DCE, DCR, role assignments | **Not verified** as free; no charge is published |
| With-app extras | Key Vault operations; a few cents per deployment-script run |

Abstract's own filtering, deduplication and aggregation happen before any of this, which
is where the savings come from.

---

## 10. Safe rollout runbook for a production workspace

**Pre-checks** (run in the target workspace):

1. **Who writes the ASIM tables today** (only matters if you will enable ASIM):
   ```kusto
   union withsource=TableName ASim*Logs
   | where TimeGenerated > ago(7d)
   | summarize count() by TableName, EventVendor, EventProduct
   ```
2. **Does the Abstract table already exist**, and with what columns, plan and retention?
   ```bash
   az monitor log-analytics workspace table show -g <rg> --workspace-name <ws> -n AbstractEventLogs_CL
   ```
3. **Name collisions:**
   ```bash
   az resource list -g <rg> --query "[?name=='abstract-dce' || name=='abstract-dcr']"
   ```
4. **Preview the deployment** without changing anything:
   ```bash
   az deployment group what-if -g <rg> \
     --template-file templates/azure/azure-destination-sentinel/main.bicep \
     --parameters createWorkspace=false workspaceName=<ws> principalId=<sp-object-id>
   ```
   what-if lists the table's `retentionInDays`, `totalRetentionInDays` and `plan` as
   removed, because the template does not send them. Azure keeps them. **Measured:** a
   real deployment with the defaults left a table at 60 days interactive / 120 days total
   and Analytics.

**Deploy:**

1. Create the Abstract app registration (for example
   `templates/azure/azure-destination-sentinel/scripts/new-app-registration.sh`), and store its secret in Key Vault.
2. Deploy the standard template in Existing mode with unique DCE and DCR names, ASIM off,
   and retention and plan left on their defaults.
   ```bash
   az deployment group create -g <rg> --mode Incremental \
     --template-file templates/azure/azure-destination-sentinel/main.bicep \
     --parameters createWorkspace=false workspaceName=<ws> principalId=<sp-object-id> \
                  dataCollectionEndpointName=<unique-dce> dataCollectionRuleName=<unique-dcr>
   ```
3. Enter the three outputs, the client ID, secret and tenant ID in Abstract's Azure
   Sentinel Destination, and route one low-volume source first.

**Validate:**

```kusto
AbstractEventLogs_CL | where TimeGenerated > ago(1h) | summarize count() by vendor, product
DCRLogErrors | where TimeGenerated > ago(1h) | summarize count() by OperationName, Message
```

Compare the Abstract table count with the event count Abstract reports for the route.

**Roll back completely**, in this order:

1. Stop the route in Abstract (or delete the destination).
2. Delete the diagnostic setting, then the role assignments on the DCR.
3. Delete the DCR, then the DCE.
4. Delete the Abstract table **only if its data can go** (this deletes the data).
5. Delete the Entra app registration (it deletes its service principal) and its Key
   Vault secret.
6. With-app template: delete the Key Vault if the template created it. Purge protection
   keeps it recoverable for its soft-delete period.

**What cannot be undone:**
- rows already written, until their retention ends (a purge needs the Data Purger role and
  is asynchronous);
- ingestion already billed;
- incidents that ASIM rules already raised on Abstract rows;
- data removed by a retention or column change you chose.

---

## 11. The optional content pack

[`templates/azure/azure-destination-sentinel-content-pack/mainTemplate.json`](../../templates/azure/azure-destination-sentinel-content-pack/README.md) installs
Abstract content into the workspace. It is separate from the destination templates and
only ever adds its own items:

- two analytics rules (installed **disabled**);
- three automation rules (installed **disabled**, and scoped to the pack's two rules by
  rule ID, so they never act on your incidents);
- the `ASim_AbstractEvent` function and three hunting queries (saved searches);
- three workbooks;
- three Logic App playbooks and their API connections;
- two connector tiles, which are display only. The second one's instructions describe
  deploying an optional Logic App pull connector (`solution/connector/`), which writes
  four more `_CL` tables if you choose to deploy it.

The Verdict playbook adds a comment and, for a malicious verdict, raises severity to
High; it never changes an incident's status.

Items are identified by fixed IDs. Reinstalling or updating the pack restores the pack's
own items to their shipped state (including disabled), so tune copies rather than the
originals. Review each item before enabling it.

---

## 12. Recommendations checklist

- [ ] Use the **standard** template (create the app yourself) or the **Graph** template
      (the template creates the app) in production. Neither needs a pre-existing privileged
      identity.
- [ ] Grant **Monitoring Metrics Publisher on the DCR only**. Leave
      `grantMonitoringContributor` off.
- [ ] Store the client secret in **Key Vault**; limit who can read it; rotate it before
      it expires and remove the old one.
- [ ] Give every destination **unique DCE and DCR names**.
- [ ] Deploy into an existing workspace in **Existing** mode, and redeploy a new one in
      Existing mode after the first deployment.
- [ ] Leave **retention and plan** on their defaults unless you mean to change them.
- [ ] Keep **ASIM off** until you have staged it; enable one schema at a time.
- [ ] Never **seed, replay or backfill** test data into a production workspace.
- [ ] Keep `enableDcrErrorLogs` on and alert on new `DCRLogErrors` rows.
- [ ] Run `what-if` before every deployment and wait 15 minutes after DCR changes.
- [ ] If you used the with-app template, **remove the provisioning identity's Graph
      permission** afterwards.
- [ ] Install the content pack only if wanted, and review each rule before enabling it.

---

## 13. Evidence

**Measured on a test Sentinel workspace fed by an Abstract test tenant, 2026-09-28:**

- End-to-end field fidelity of the real destination (section 1).
- A table update without retention kept 60 / 180 days, and a full template deployment with
  the defaults kept 60 / 120 days and the Analytics plan. Redeploying over an Auxiliary
  table kept it Auxiliary. Redeploys kept the DCR's immutable ID.
- Existing-workspace mode keeps every ASIM dataflow while the portal sends
  `enableSentinel = false`. `asimSchemas = []` produces no ASIM dataflows
  (`az deployment group what-if`).
- Events kept arriving after Monitoring Contributor was removed from the destination's
  service principal.
- DCR updates take about 15 minutes to settle.
- The with-app deployment script's decisions, tested on every change against a stubbed Azure CLI:
  - it stores a new secret through a file, never on a command line;
  - it refuses a secret tagged for another app, even when rotation is forced;
  - it refuses an untagged same-named secret unless rotation is forced;
  - it refuses an untagged app with the same name, or more than one;
  - it removes an unstored credential when the Key Vault write fails;
  - it reuses a valid secret without rotating it.

**Not verified:**

- The with-app template's latest changes against a live tenant: purge protection,
  `cleanupPreference: Always`, and file-based secret writes. The script logic was tested
  only against the stubbed CLI.
- The Graph template from the portal: Microsoft documents Microsoft Graph Bicep only for
  Azure CLI and PowerShell, so it has no Deploy-to-Azure button.
- Whether any Microsoft ASIM rule has alerted on Abstract rows. The test data held none of
  the activity the ten rules that were run look for.
- DCE and DCR billing.
- Whether Microsoft's E5 data grant covers the ASIM tables.
- Whether UEBA ignores rows in the ASIM tables (Microsoft's source list says it does).
- The operator script's new app-tag check against a live tenant
  (`new-app-registration.sh` sets the tag through a Graph PATCH and reads it back with `az ad app list`).
- The app-registration paths' new tag checks and the Azure Policy path's durable marker
  against a live tenant; both are compile-checked only.
