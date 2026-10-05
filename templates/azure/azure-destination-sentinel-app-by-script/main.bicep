// =============================================================================
//  Abstract Security - Azure Sentinel DESTINATION, ONE-CLICK incl. app registration
//  Version : 1.0  (opt-in / advanced variant of sentinel-destination.bicep)
//  Author  : Abstract Security - Solutions Engineering
//
//  This variant provisions the Sentinel destination and creates the Entra app
//  registration using an Azure deploymentScript. Key Vault can be created,
//  supplied by resource ID, or skipped. When skipped, the customer creates the
//  client secret in Entra after deployment; ARM never returns secret values.
//
//  WHAT IT CREATES
//    1. Optional Key Vault storage for the generated client secret.
//    2. deploymentScript running as the supplied provisioning identity: creates
//       (or reuses) the Entra app and service principal. With Key Vault enabled it
//       generates and stores the secret; without it, the customer creates the
//       secret in Entra after deployment.
//    3. Log Analytics workspace + Microsoft Sentinel + DCE + custom _CL table + DCR.
//    4. RBAC on the DCR for the runtime SP: Monitoring Metrics Publisher, plus
//       Monitoring Contributor only if grantMonitoringContributor.
//    5. Optional ASIM dataflows (enableAsim, off by default) and DCR error logs.
//
//  WHAT IT NEVER TOUCHES: analytics rules, automation rules, hunting queries,
//  workbooks, watchlists, data connectors, parsers, other tables, workspace
//  settings of an existing workspace, or the SecurityInsights solution of an
//  existing workspace. See solutions/docs/sentinel-destination-assurance.md.
//
//  PREREQUISITES (cannot be bootstrapped inside ARM)
//    * A USER-ASSIGNED MANAGED IDENTITY for the provisioning script. Tenant
//      bootstrap must grant it the Microsoft Graph application permission
//      Application.ReadWrite.All with admin consent by a Global Administrator,
//      once per tenant. This template only creates an app, its service principal
//      and a client secret, so it does not need AppRoleAssignment.ReadWrite.All.
//      Application.ReadWrite.All can add credentials to ANY app in the tenant, so
//      treat this identity as tier-0: keep it in a resource group only admins can
//      write to, and remove its Graph permission (or delete it) after onboarding.
//      For production, the standard sentinel-destination template with an app you
//      create yourself avoids a standing privileged identity entirely.
//    * The deploying principal needs Owner (or Contributor + User Access
//      Administrator) on the resource group to create the role assignments.
//
//  SECURITY NOTE: the client secret is never returned in deployment outputs. If
//  Key Vault is skipped, create the secret in Entra and copy it once into Abstract.
//
//  Compile:  az bicep build --file sentinel-destination-with-app.bicep \
//                --outfile sentinel-destination-with-app.azuredeploy.json
// =============================================================================

// ---------------------------------------------------------------------------
// Core
// ---------------------------------------------------------------------------
@description('Azure region for the workspace, DCE, DCR, Key Vault and deployment script.')
param location string = resourceGroup().location

@description('Tags applied to every created resource that supports tags.')
param tags object = {}

@description('Resource-specific tags, keyed by fully qualified Azure resource type.')
param tagsByResource object = {}

// ---------------------------------------------------------------------------
// Identity that runs the app-registration script (PREREQUISITE - see header)
// ---------------------------------------------------------------------------
@description('Resource ID of the user-assigned provisioning identity. Tenant bootstrap must grant it Microsoft Graph Application.ReadWrite.All with admin consent; this template does not use AppRoleAssignment.ReadWrite.All.')
param managedIdentityResourceId string

@description('Display name for the Entra app registration created for Abstract.')
param appDisplayName string = 'Abstract-Sentinel-App'

@description('Client-secret validity in years when a Key Vault mode generates the secret.')
@minValue(1)
@maxValue(2)
param secretValidityYears int = 1

@description('Optional user or group object ID granted Key Vault Secrets User when Key Vault is enabled.')
#disable-next-line secure-secrets-in-params // this is an AAD object id, not a secret
param secretReaderObjectId string = ''

@description('Azure CLI version for the deployment script container. Verify the selected image version is available before changing this value.')
param azCliVersion string = '2.60.0'

@description('Name of the Key Vault secret holding the client secret.')
param secretName string = 'abstract-sentinel-client-secret'

@description('''
Force a NEW client secret even when the vault already holds a valid one.

Leave false. The script now rotates only when no secret exists or the existing one
expires within 30 days, which makes re-running this template safe - the previous
behaviour minted a fresh secret on every deployment, so a re-run silently created a
new Key Vault version while Abstract kept using the old value.

Set true only for a deliberate rotation, and update Abstract with the new value.
''')
param forceSecretRotation bool = false

// ---------------------------------------------------------------------------
// Key Vault
// ---------------------------------------------------------------------------
@allowed(['Create', 'Existing', 'None'])
@description('Create a new Key Vault, use an existing vault by resource ID, or skip Key Vault. In None mode, create the client secret in Entra after deployment.')
param keyVaultMode string = 'Create'

@description('Key Vault name (3-24 lowercase alphanumerics/hyphens, globally unique). Leave empty to auto-generate abstract-kv-<hash>.')
param keyVaultName string = ''

@description('Full resource ID of the existing Key Vault. Used only when keyVaultMode is Existing.')
param existingKeyVaultResourceId string = resourceGroup().id

// ---------------------------------------------------------------------------
// Workspace + Sentinel
// ---------------------------------------------------------------------------
@description('Create a new Log Analytics workspace. Set false to target an EXISTING workspace in THIS resource group.')
param createWorkspace bool = true

@description('Workspace name. Creating: empty auto-generates abstract-sentinel-<hash>. Existing: the exact name (in this resource group).')
param workspaceName string = ''

@description('Region of the EXISTING workspace (Existing mode only). DCE/DCR must match it. Empty = use the deployment location.')
param existingWorkspaceLocation string = ''

@allowed(['PerGB2018', 'CapacityReservation', 'Free', 'Standalone', 'PerNode'])
param workspaceSku string = 'PerGB2018'

@description('Workspace data retention in days. Only applied when creating a new workspace; an existing workspace is never modified. The Abstract table\'s own retention is customTableRetentionDays.')
@minValue(7)
@maxValue(730)
param workspaceRetentionDays int = 90

param enableSentinel bool = true

// ---------------------------------------------------------------------------
// DCE / DCR / custom table
// ---------------------------------------------------------------------------
param dataCollectionEndpointName string = 'abstract-dce'
param dataCollectionRuleName string = 'abstract-dcr'

@description('Custom log table name. MUST end in _CL.')
param customTableName string = 'AbstractEventLogs_CL'

@description('Custom table columns. Leave empty (recommended) to use the generated ACS schema: one column per top-level key of the event Abstract sends, with a DCR transformation that sets TimeGenerated. Supply columns only for a custom payload shape; the DCR stream then uses the same columns and transformKql.')
param tableColumns array = []

@description('DCR transformation used only when tableColumns is supplied. The generated schema carries its own transformation.')
param transformKql string = 'source'

@description('Send the Data Collection Rule\'s ingestion errors (rejected requests, malformed payloads, limit and transformation errors) to the DCRLogErrors table in the workspace. Without it, data Azure refuses or drops is invisible to the customer and to Abstract.')
param enableDcrErrorLogs bool = true

@description('Also write each event into Microsoft\'s ASIM normalized tables (ASimAuthenticationEventLogs and the others listed in asimSchemas), mapped from the Abstract Common Schema by solutions/asim. Off by default. Microsoft\'s built-in ASIM parsers read those tables, so once this is on every ASIM analytics rule, hunting query and workbook already running in the workspace also sees Abstract data: expect new alerts, duplicates where Microsoft\'s own connector collects the same vendor, and a second copy of each mapped event in billing. Turn it on in a staging workspace first, or one schema at a time with asimSchemas. Needs Microsoft Sentinel on the workspace and the generated Abstract schema (tableColumns left empty). Every event still also lands in the Abstract table.')
param enableAsim bool = false

@description('ASIM schemas to write, by name (for example [\'Authentication\', \'NetworkSession\']). [\'*\'] (default) writes every schema solutions/asim maps; [] writes none.')
param asimSchemas array = [
  '*'
]

@description('Retention of the Abstract table in days. 0 (default) sends no retention, so an existing table keeps its retention and a new table uses the workspace default. A value shortens or lengthens the table\'s total retention; shortening deletes data older than the new value.')
@minValue(0)
@maxValue(4383)
param customTableRetentionDays int = 0

@description('Also grant Monitoring Contributor on the DCR. Off by default: sending data through the Logs Ingestion API needs only Monitoring Metrics Publisher, and Monitoring Contributor would let a leaked Abstract credential rewrite or delete the DCR and its error-log setting. Turn on only if your Abstract destination setup specifically asks for it.')
param grantMonitoringContributor bool = false

@description('Table plan for the Abstract table. Keep (default) keeps the plan an existing table already has, and create a new table as Analytics: a redeploy then never changes a table\'s plan, or its cost, by accident. Analytics runs analytics rules and our content pack on it. Auxiliary is the Sentinel data lake tier: cheap long retention and KQL jobs, but no analytics rules or alerts. Basic sits between them. Setting a plan on an existing table switches it; Azure applies the new plan to the whole table.')
@allowed(['Keep', 'Analytics', 'Basic', 'Auxiliary'])
param customTablePlan string = 'Keep'

// ---------------------------------------------------------------------------
// Derived values + role definition IDs
// ---------------------------------------------------------------------------
var autoWorkspaceName = 'abstract-sentinel-${uniqueString(resourceGroup().id)}'
var effectiveWorkspaceName = createWorkspace ? (empty(workspaceName) ? autoWorkspaceName : workspaceName) : workspaceName
var workspaceResourceId = resourceId('Microsoft.OperationalInsights/workspaces', effectiveWorkspaceName)
var effectiveLocation = createWorkspace ? location : (empty(existingWorkspaceLocation) ? location : existingWorkspaceLocation)
// The Create-mode vault resource always gets a valid name. It is deployed only in
// Create mode, but ARM still resolves its id (module names, dependsOn) in every
// mode, and an empty name there fails template validation in None mode.
var keyVaultResourceName = empty(keyVaultName) ? 'abstract-kv-${uniqueString(resourceGroup().id)}' : keyVaultName
var effectiveKeyVaultName = keyVaultMode == 'Existing' ? last(split(existingKeyVaultResourceId, '/')) : (keyVaultMode == 'Create' ? keyVaultResourceName : '')
var existingKeyVaultSubscriptionId = split(existingKeyVaultResourceId, '/')[2]
var existingKeyVaultResourceGroupName = split(existingKeyVaultResourceId, '/')[4]
// Generated by gen-sentinel-schema.py from the ACS field catalog. The
// stream mirrors the payload (it still carries the reserved id and type keys);
// the transformation sets TimeGenerated and renames those two.
var generatedSchema = loadJsonContent('../_modules/sentinel/sentinel-destination.schema.json')
var useGeneratedSchema = empty(tableColumns)
var effectiveTableColumns = useGeneratedSchema ? generatedSchema.tableColumns : tableColumns
// Log Analytics table columns want 'dateTime' (capital T); everything else is lower-case.
var customTableArmColumns = [for col in effectiveTableColumns: {
  name: col.name
  type: toLower(string(col.type)) == 'datetime' ? 'dateTime' : toLower(string(col.type))
}]
// customTablePlan 'Keep' sends no plan, so Azure keeps an existing table's plan (Analytics for a new table).
var customTablePlanProperty = customTablePlan == 'Keep' ? {} : { plan: customTablePlan }
// customTableRetentionDays 0 sends no retention, so a redeploy never shortens an existing table's retention.
var customTableRetentionProperty = customTableRetentionDays > 0 ? { totalRetentionInDays: customTableRetentionDays } : {}
var effectiveStreamColumns = useGeneratedSchema ? generatedSchema.streamColumns : tableColumns
var effectiveTransformKql = useGeneratedSchema ? generatedSchema.transformKql : transformKql

// ACS-to-ASIM mappings, generated by gen-sentinel-asim.py from solutions/asim/*.kql. They
// read the generated ACS stream columns, so they are skipped when tableColumns overrides
// the schema, and the ASim tables exist only when Microsoft Sentinel is on the workspace.
var asimRouteCatalog = loadJsonContent('../_modules/sentinel/sentinel-asim-routes.generated.json').routes
// An existing workspace is assumed to run Sentinel already (the portal sends enableSentinel=false for it).
var enabledAsimRoutes = enableAsim && (enableSentinel || !createWorkspace) && useGeneratedSchema ? filter(asimRouteCatalog, route => contains(asimSchemas, '*') || contains(asimSchemas, route.name)) : []
var asimFlows = [for route in enabledAsimRoutes: {
  streams: [
    streamName
  ]
  destinations: [
    logAnalyticsDestinationName
  ]
  transformKql: route.transformKql
  outputStream: route.outputStream
}]
var streamName = 'Custom-${customTableName}'
var logAnalyticsDestinationName = 'abstractSentinelWorkspace'
// secretName is now a PARAMETER (it was hardcoded here) so more than one Abstract
// secret can live in the same vault.

var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var monitoringContributorRoleId = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// Identity that runs the script (must already have app-creation directory rights).
resource runnerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: last(split(managedIdentityResourceId, '/'))
  scope: resourceGroup(split(managedIdentityResourceId, '/')[2], split(managedIdentityResourceId, '/')[4])
}

// ---------------------------------------------------------------------------
// Key Vault (optional; RBAC authorization)
// ---------------------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' = if (keyVaultMode == 'Create') {
  name: keyVaultResourceName
  location: location
  tags: union(tags, contains(tagsByResource, 'Microsoft.KeyVault/vaults') ? tagsByResource['Microsoft.KeyVault/vaults'] : {})
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    // Purge protection stops a deleted vault (and the secret in it) being purged before
    // its soft-delete period ends. It cannot be turned off once on.
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
  }
}

resource existingKeyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: keyVaultMode == 'Existing' ? effectiveKeyVaultName : 'unused-key-vault'
  scope: resourceGroup(existingKeyVaultSubscriptionId, existingKeyVaultResourceGroupName)
}

module kvOfficerAssignmentNew '../azure-access-key-vault-secrets-reader/main.bicep' = if (keyVaultMode == 'Create') {
  name: 'kv-officer-new-${uniqueString(keyVault.id, managedIdentityResourceId)}'
  scope: resourceGroup()
  params: {
    keyVaultName: effectiveKeyVaultName
    principalId: runnerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
  }
  dependsOn: [keyVault]
}

module kvOfficerAssignmentExisting '../azure-access-key-vault-secrets-reader/main.bicep' = if (keyVaultMode == 'Existing') {
  name: 'kv-officer-existing-${uniqueString(existingKeyVault.id, managedIdentityResourceId)}'
  scope: resourceGroup(existingKeyVaultSubscriptionId, existingKeyVaultResourceGroupName)
  params: {
    keyVaultName: effectiveKeyVaultName
    principalId: runnerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(existingKeyVaultSubscriptionId, 'Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
  }
}

module kvReaderAssignmentNew '../azure-access-key-vault-secrets-reader/main.bicep' = if (keyVaultMode == 'Create' && !empty(secretReaderObjectId)) {
  name: 'kv-reader-new-${uniqueString(keyVault.id, secretReaderObjectId)}'
  scope: resourceGroup()
  params: {
    keyVaultName: effectiveKeyVaultName
    principalId: secretReaderObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
  }
  dependsOn: [keyVault]
}

module kvReaderAssignmentExisting '../azure-access-key-vault-secrets-reader/main.bicep' = if (keyVaultMode == 'Existing' && !empty(secretReaderObjectId)) {
  name: 'kv-reader-existing-${uniqueString(existingKeyVault.id, secretReaderObjectId)}'
  scope: resourceGroup(existingKeyVaultSubscriptionId, existingKeyVaultResourceGroupName)
  params: {
    keyVaultName: effectiveKeyVaultName
    principalId: secretReaderObjectId
    roleDefinitionId: subscriptionResourceId(existingKeyVaultSubscriptionId, 'Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
  }
}

// ---------------------------------------------------------------------------
// deploymentScript: create app + SP; optionally generate/store a secret
// ---------------------------------------------------------------------------
resource appScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'abstract-create-app'
  location: location
  tags: union(tags, contains(tagsByResource, 'Microsoft.Resources/deploymentScripts') ? tagsByResource['Microsoft.Resources/deploymentScripts'] : {})
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityResourceId}': {}
    }
  }
  properties: {
    azCliVersion: azCliVersion
    retentionInterval: 'PT1H'
    // Always: the script's container and storage are removed even when it fails, so
    // the privileged identity is never left attached to a running container.
    cleanupPreference: 'Always'
    timeout: 'PT30M'
    environmentVariables: [
      { name: 'APP_NAME', value: appDisplayName }
      { name: 'KV_NAME', value: effectiveKeyVaultName }
      { name: 'KEY_VAULT_MODE', value: keyVaultMode }
      { name: 'VAULT_URI', value: keyVaultMode == 'Create' ? keyVault.?properties.vaultUri : (keyVaultMode == 'Existing' ? existingKeyVault.?properties.vaultUri : '') }
      { name: 'SECRET_NAME', value: secretName }
      { name: 'SECRET_YEARS', value: string(secretValidityYears) }
      { name: 'FORCE_ROTATE', value: string(forceSecretRotation) }
    ]
    scriptContent: loadTextContent('../_modules/sentinel-app-deploymentscript.sh')
  }
  dependsOn: keyVaultMode == 'Create' ? [kvOfficerAssignmentNew] : (keyVaultMode == 'Existing' ? [kvOfficerAssignmentExisting] : [])
}

// ---------------------------------------------------------------------------
// Log Analytics workspace + Sentinel
// ---------------------------------------------------------------------------
resource workspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' = if (createWorkspace) {
  name: effectiveWorkspaceName
  location: location
  tags: union(tags, contains(tagsByResource, 'Microsoft.OperationalInsights/workspaces') ? tagsByResource['Microsoft.OperationalInsights/workspaces'] : {})
  properties: {
    sku: {
      name: workspaceSku
    }
    retentionInDays: workspaceRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = if (createWorkspace && enableSentinel) {
  scope: workspace
  name: 'default'
  properties: {}
}

// ---------------------------------------------------------------------------
// Custom log table + DCE + DCR
// ---------------------------------------------------------------------------
resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2026-03-01' = {
  name: '${effectiveWorkspaceName}/${customTableName}'
  properties: union({
    schema: {
      name: customTableName
      columns: customTableArmColumns
    }
  }, customTablePlanProperty, customTableRetentionProperty)
  dependsOn: createWorkspace ? [workspace] : []
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2024-03-11' = {
  name: dataCollectionEndpointName
  location: effectiveLocation
  tags: union(tags, contains(tagsByResource, 'Microsoft.Insights/dataCollectionEndpoints') ? tagsByResource['Microsoft.Insights/dataCollectionEndpoints'] : {})
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: dataCollectionRuleName
  location: effectiveLocation
  tags: union(tags, contains(tagsByResource, 'Microsoft.Insights/dataCollectionRules') ? tagsByResource['Microsoft.Insights/dataCollectionRules'] : {})
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      '${streamName}': {
        columns: [for col in effectiveStreamColumns: {
          name: col.name
          type: toLower(string(col.type))
        }]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceResourceId
          name: logAnalyticsDestinationName
        }
      ]
    }
    dataFlows: concat([
      {
        streams: [streamName]
        destinations: [logAnalyticsDestinationName]
        transformKql: effectiveTransformKql
        outputStream: streamName
      }
    ], asimFlows)
  }
  dependsOn: [
    customTable
    sentinelOnboarding
  ]
}


// ---------------------------------------------------------------------------
// DCR error logs -> DCRLogErrors in the workspace. The DCR metrics only count
// failures; this is the only place that records WHY a request was refused or
// a row dropped. Azure samples these per hour, so it is evidence, not a tally.
// ---------------------------------------------------------------------------
resource dcrErrorLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDcrErrorLogs) {
  name: 'abstract-dcr-errors'
  scope: dcr
  properties: {
    workspaceId: workspaceResourceId
    logs: [
      {
        category: 'LogErrors'
        enabled: true
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// RBAC on the DCR for the newly-created SP.
// Assignment NAME uses a static discriminator (names cannot depend on the
// script's runtime output); principalId takes the runtime SP object id.
// ---------------------------------------------------------------------------
resource metricsPublisherAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcr.id, 'abstract-app-metrics-publisher', monitoringMetricsPublisherRoleId)
  scope: dcr
  properties: {
    principalId: appScript.properties.outputs.spObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource monitoringContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantMonitoringContributor) {
  name: guid(dcr.id, 'abstract-app-monitoring-contributor', monitoringContributorRoleId)
  scope: dcr
  properties: {
    principalId: appScript.properties.outputs.spObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs - everything the Abstract modal needs EXCEPT the secret (in Key Vault)
// ---------------------------------------------------------------------------
output clientId string = appScript.properties.outputs.appId
output applicationTenantId string = appScript.properties.outputs.tenantId
output servicePrincipalObjectId string = appScript.properties.outputs.spObjectId
output clientSecretKeyVaultUri string = keyVaultMode == 'None' ? '' : appScript.properties.outputs.keyVaultSecretUri
output keyVaultName string = effectiveKeyVaultName
output workspaceName string = effectiveWorkspaceName
output customTableName string = customTableName
output dataCollectionRuleImmutableId string = dcr.properties.immutableId
output dataCollectionEndpointUrl string = dce.properties.logsIngestion.endpoint
output logStreamName string = streamName
output secretCreationInstructions string = keyVaultMode == 'None' ? 'Create a client secret for this app in Entra after deployment and copy its value once into Abstract. Entra will not show the value again.' : 'Read the client secret from the configured Key Vault and enter it in Abstract.'
output abstractModalHint string = keyVaultMode == 'None' ? 'Create a client secret for the app in Entra, then enter that value into Abstract; all other fields are in the outputs above.' : 'Read the client secret from Key Vault "${effectiveKeyVaultName}"; all other fields are in the outputs above.'
