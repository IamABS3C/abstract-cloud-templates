// =============================================================================
//  Abstract Security - Azure Sentinel DESTINATION, app registration included,
//  with NO pre-existing privileged identity
//
//  Creates the Entra app registration Abstract signs in as, its service principal,
//  and the whole Sentinel destination stack, in one deployment. The app is created
//  with the Microsoft Graph Bicep extension (generally available since July 2025),
//  as the person running the deployment - so no managed identity has to exist
//  beforehand and none holds tenant-wide Graph rights afterwards.
//
//  TWO MODES
//    automateSecret = false (default, least privilege)
//      Creates the app and service principal (no API permissions, tagged
//      abstract:sentinel-destination) and the destination stack. No managed
//      identity is created. Microsoft Graph Bicep cannot create client secrets, so
//      create one afterwards (the output secretCommand shows how) and paste it into
//      Abstract once.
//      The deployer needs: rights to register an app (the default user setting, or
//      the Application Developer role), plus Owner - or Contributor + User Access
//      Administrator - on the resource group.
//
//    automateSecret = true
//      Also creates a user-assigned managed identity that OWNS only this app, grants
//      it Microsoft Graph Application.ReadWrite.OwnedBy (it can manage only apps it
//      owns), creates a Key Vault, and runs a deployment script as that identity to
//      create the client secret and store it in the vault.
//      The deployer additionally needs Privileged Role Administrator or Global
//      Administrator, to grant that Graph permission.
//
//  DEPLOY WITH AZURE CLI OR AZURE POWERSHELL. Microsoft documents interactive
//  Microsoft Graph Bicep deployments for those two tools; the portal's
//  Deploy-to-Azure button is not documented for them, so this template has no
//  portal wizard. az deployment group what-if does not preview Microsoft Graph
//  resources. Deleting the resource group does not delete the app registration.
//
//    az deployment group create -g <rg> --mode Incremental \
//      --template-file solutions/templates/destinations/sentinel-destination-graph.bicep \
//      --parameters createWorkspace=false workspaceName=<workspace>
// =============================================================================
extension microsoftGraphV1

// ---------------------------------------------------------------------------
// Core
// ---------------------------------------------------------------------------
@description('Azure region for the DCE, DCR and (when automateSecret) the identity, Key Vault and script.')
param location string = resourceGroup().location

@description('Tags applied to every created Azure resource that supports tags.')
param tags object = {}

@description('Resource-specific tags, keyed by fully qualified Azure resource type.')
param tagsByResource object = {}

// ---------------------------------------------------------------------------
// App registration
// ---------------------------------------------------------------------------
@description('Display name of the app registration Abstract signs in as.')
param appDisplayName string = 'Abstract-Sentinel-Destination'

@description('Tenant-wide unique key for the app registration (Microsoft Graph uniqueName). It makes redeploys update the same app instead of creating another. Immutable once the app exists.')
param appUniqueName string = 'abstract-sentinel-destination'

// ---------------------------------------------------------------------------
// Optional secret automation
// ---------------------------------------------------------------------------
@description('Create the client secret automatically: adds a managed identity that owns only this app (Graph Application.ReadWrite.OwnedBy), a Key Vault and a deployment script. Needs a Privileged Role Administrator or Global Administrator deployer. Off: create the secret yourself afterwards (see the secretCommand output).')
param automateSecret bool = false

@description('Key Vault to create for the client secret (automateSecret only). Empty generates abskv-<hash>.')
param keyVaultName string = ''

@description('Name of the Key Vault secret that holds the client secret (automateSecret only).')
param secretName string = 'abstract-sentinel-client-secret'

@description('Client secret lifetime in years (automateSecret only).')
@allowed([1, 2])
param secretValidityYears int = 1

@description('Mint a new secret even if the stored one is still valid (automateSecret only).')
param forceSecretRotation bool = false

@description('Object ID of a user or group that may read the secret from Key Vault (Key Vault Secrets User), so someone can paste it into Abstract (automateSecret only). Empty: grant it yourself; the deployer is not given access automatically.')
param secretReaderObjectId string = ''

@description('Azure CLI version for the deployment script (automateSecret only).')
param azCliVersion string = '2.60.0'

// ---------------------------------------------------------------------------
// Destination stack (passed to sentinel-destination.bicep)
// ---------------------------------------------------------------------------
@description('Create a new Log Analytics workspace. Set false to target an EXISTING workspace in THIS resource group.')
param createWorkspace bool = true

@description('Workspace name. Creating: empty auto-generates abstract-sentinel-<hash>. Existing: the exact name (in this resource group).')
param workspaceName string = ''

@description('Region of the EXISTING workspace (Existing mode only). Empty = the deployment location.')
param existingWorkspaceLocation string = ''

@allowed(['PerGB2018', 'CapacityReservation', 'Free', 'Standalone', 'PerNode'])
param workspaceSku string = 'PerGB2018'

@description('Workspace retention in days. Only applied when creating a new workspace.')
@minValue(7)
@maxValue(730)
param workspaceRetentionDays int = 90

@description('Enable Microsoft Sentinel on a new workspace.')
param enableSentinel bool = true

param dataCollectionEndpointName string = 'abstract-dce'
param dataCollectionRuleName string = 'abstract-dcr'
param customTableName string = 'AbstractEventLogs_CL'

@minValue(0)
@maxValue(4383)
param customTableRetentionDays int = 0

@allowed(['Keep', 'Analytics', 'Basic', 'Auxiliary'])
param customTablePlan string = 'Keep'

param enableDcrErrorLogs bool = true
param enableAsim bool = false
param asimSchemas array = [
  '*'
]
param grantMonitoringContributor bool = false

// ---------------------------------------------------------------------------
// Derived
// ---------------------------------------------------------------------------
var marker = 'abstract:sentinel-destination'
var graphAppId = '00000003-0000-0000-c000-000000000000'
var effectiveKeyVaultName = empty(keyVaultName) ? 'abskv-${uniqueString(resourceGroup().id, appUniqueName)}' : keyVaultName
var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// ---------------------------------------------------------------------------
// Secret-writer identity (automateSecret only). It owns the app, so with
// Application.ReadWrite.OwnedBy it can manage this app and no other.
// ---------------------------------------------------------------------------
resource secretWriter 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (automateSecret) {
  name: 'abstract-sentinel-secret-writer'
  location: location
  tags: union(tags, contains(tagsByResource, 'Microsoft.ManagedIdentity/userAssignedIdentities') ? tagsByResource['Microsoft.ManagedIdentity/userAssignedIdentities'] : {})
}

// ---------------------------------------------------------------------------
// App registration + service principal (Microsoft Graph Bicep)
// ---------------------------------------------------------------------------
resource app 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: appUniqueName
  displayName: appDisplayName
  signInAudience: 'AzureADMyOrg'
  // The marker the Sentinel scripts require before they will reuse an app.
  tags: [
    marker
  ]
  notes: 'Abstract Security Azure Sentinel Destination: publishes to one Data Collection Rule through the Logs Ingestion API. Has no API permissions.'
  owners: {
    relationshipSemantics: 'append'
    relationships: automateSecret ? [
      secretWriter!.properties.principalId
    ] : []
  }
}

resource sp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: app.appId
  tags: [
    marker
  ]
  owners: {
    relationshipSemantics: 'append'
    relationships: automateSecret ? [
      secretWriter!.properties.principalId
    ] : []
  }
}

// ---------------------------------------------------------------------------
// Graph Application.ReadWrite.OwnedBy for the secret writer (automateSecret only)
// ---------------------------------------------------------------------------
resource msGraph 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: graphAppId
}

resource ownedByGrant 'Microsoft.Graph/appRoleAssignedTo@v1.0' = if (automateSecret) {
  principalId: secretWriter!.properties.principalId
  resourceId: msGraph.id
  appRoleId: first(filter(msGraph.appRoles, role => role.value == 'Application.ReadWrite.OwnedBy'))!.id
}

// ---------------------------------------------------------------------------
// Key Vault + deployment script (automateSecret only)
// ---------------------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' = if (automateSecret) {
  name: effectiveKeyVaultName
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
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
  }
}

module kvOfficer '../azure-access-key-vault-secrets-reader/main.bicep' = if (automateSecret) {
  name: 'kv-officer-${uniqueString(resourceGroup().id, appUniqueName)}'
  params: {
    keyVaultName: effectiveKeyVaultName
    principalId: secretWriter!.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
  }
  dependsOn: [
    keyVault
  ]
}

module kvReader '../azure-access-key-vault-secrets-reader/main.bicep' = if (automateSecret && !empty(secretReaderObjectId)) {
  name: 'kv-reader-${uniqueString(resourceGroup().id, appUniqueName, secretReaderObjectId)}'
  params: {
    keyVaultName: effectiveKeyVaultName
    principalId: secretReaderObjectId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
  }
  dependsOn: [
    keyVault
  ]
}

resource secretScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (automateSecret) {
  name: 'abstract-create-secret'
  location: location
  tags: union(tags, contains(tagsByResource, 'Microsoft.Resources/deploymentScripts') ? tagsByResource['Microsoft.Resources/deploymentScripts'] : {})
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${secretWriter.id}': {}
    }
  }
  properties: {
    azCliVersion: azCliVersion
    retentionInterval: 'PT1H'
    // Always: the container and its storage are removed whether the script succeeds or fails.
    cleanupPreference: 'Always'
    timeout: 'PT30M'
    environmentVariables: [
      { name: 'APP_NAME', value: appDisplayName }
      { name: 'KEY_VAULT_MODE', value: 'Create' }
      { name: 'KV_NAME', value: effectiveKeyVaultName }
      { name: 'VAULT_URI', value: keyVault!.properties.vaultUri }
      { name: 'SECRET_NAME', value: secretName }
      { name: 'SECRET_YEARS', value: string(secretValidityYears) }
      { name: 'FORCE_ROTATE', value: string(forceSecretRotation) }
    ]
    // The same script the with-app template uses. The app and service principal already
    // exist and carry the marker, so it only adds and stores the secret.
    scriptContent: loadTextContent('../_modules/sentinel-app-deploymentscript.sh')
  }
  dependsOn: [
    kvOfficer
    ownedByGrant
    sp
  ]
}

// ---------------------------------------------------------------------------
// The destination stack, with the new service principal as the Abstract identity
// ---------------------------------------------------------------------------
module destination '../azure-destination-sentinel/main.bicep' = {
  name: 'abstract-sentinel-destination-stack'
  params: {
    location: location
    tags: tags
    tagsByResource: tagsByResource
    createWorkspace: createWorkspace
    workspaceName: workspaceName
    existingWorkspaceLocation: existingWorkspaceLocation
    workspaceSku: workspaceSku
    workspaceRetentionDays: workspaceRetentionDays
    enableSentinel: enableSentinel
    dataCollectionEndpointName: dataCollectionEndpointName
    dataCollectionRuleName: dataCollectionRuleName
    customTableName: customTableName
    customTableRetentionDays: customTableRetentionDays
    customTablePlan: customTablePlan
    enableDcrErrorLogs: enableDcrErrorLogs
    enableAsim: enableAsim
    asimSchemas: asimSchemas
    grantMonitoringContributor: grantMonitoringContributor
    principalId: sp.id
    principalType: 'ServicePrincipal'
  }
}

// ---------------------------------------------------------------------------
// Outputs - everything the Abstract Azure Sentinel Destination needs except the secret
// ---------------------------------------------------------------------------
output clientId string = app.appId
output applicationTenantId string = tenant().tenantId
output servicePrincipalObjectId string = sp.id
output dataCollectionRuleImmutableId string = destination.outputs.dataCollectionRuleImmutableId
output dataCollectionEndpointUrl string = destination.outputs.dataCollectionEndpointUrl
output logStreamName string = destination.outputs.logStreamName
output workspaceName string = destination.outputs.workspaceName
output clientSecretKeyVaultUri string = automateSecret ? '${keyVault!.properties.vaultUri}secrets/${secretName}' : ''
output secretCommand string = automateSecret ? 'az keyvault secret show --vault-name ${effectiveKeyVaultName} --name ${secretName} --query value -o tsv   # needs Key Vault Secrets User (secretReaderObjectId)' : 'az ad app credential reset --id ${app.appId} --append --display-name abstract-sentinel-client-secret --years 1 --query password -o tsv   # shown once: paste it into Abstract, or store it in Key Vault'
output secretWriterNote string = automateSecret ? 'Identity abstract-sentinel-secret-writer owns only this app and holds Graph Application.ReadWrite.OwnedBy. Keep it for rotation, or delete it.' : 'No managed identity was created.'
