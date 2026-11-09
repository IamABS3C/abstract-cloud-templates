// Sentinel discovery, deployable on its own: runs the read-only inventory kit against one workspace from inside Azure and
// writes the zip, the CSVs and a self-contained HTML report to a storage account in this resource group.
// The kit and the report builder are embedded (payload/, built by build.py). Nothing is downloaded at deploy time.
targetScope = 'resourceGroup'

@description('Region for the resources this template creates. The workspace can be in any region.')
param location string = resourceGroup().location

@description('Name of the Log Analytics workspace that has Microsoft Sentinel. It is only read.')
param workspaceName string

@description('Resource group of the workspace. Defaults to this resource group.')
param workspaceResourceGroup string = resourceGroup().name

@description('Subscription of the workspace. Defaults to this subscription.')
param workspaceSubscriptionId string = subscription().subscriptionId

@description('Grant the identity Reader on the workspace subscription. The kit needs it to list data collection rules, endpoints, Sentinel workbooks and playbooks. Off: those areas are recorded as not read.')
param assignSubscriptionReader bool = true

@description('Storage account for the output. Empty generates a name. Created with public blob access and shared-key access off.')
@maxLength(24)
param storageAccountName string = ''

@description('Give the person deploying this template Storage Blob Data Reader on the output container, so they can open the report. Shared keys are off, so the Owner role alone cannot read the blobs.')
param grantDeployerBlobRead bool = true

@description('Look-back window in days for volume, health, agents and rules.')
@minValue(1)
@maxValue(90)
param days int = 30

@description('Window in days for the CEF and Syslog sender breakdowns. These scan the raw tables; leave at 1.')
@minValue(1)
@maxValue(7)
param deviceDays int = 1

@description('How many of the largest Analytics-plan tables to break down by two columns. 0 turns it off.')
@minValue(0)
@maxValue(50)
param profileTopTables int = 15

@description('Leave the KQL text of analytics rules out of the output. The rule-to-table mapping is still produced.')
param skipRuleQueryText bool = false

@description('Leave the KQL text of functions, hunting queries and saved searches out of the output. The content-to-table mapping is still produced.')
param skipContentQueryText bool = false

@description('Install the Sentinel inventory workbook for this workspace. The workbook resource goes in this resource group.')
param deployWorkbook bool = true

@description('Send a copy to Abstract. OFF by default. When on, exactly two files leave your tenant, over HTTPS, to the SAS URL below: inventory.zip (the CSVs and summary.json: Azure resource names and IDs, table volumes, computer names and IP addresses from Heartbeat, device vendor and product names, and the KQL text of rules and functions unless you turned that off) and report.html (the same content as a report). No log records, watchlist items or credentials are in either file. With this off, nothing leaves your tenant.')
param sendToAbstract bool = false

@description('Only with sendToAbstract: the HTTPS SAS URL of the container Abstract gave you. It needs write permission on that container only.')
@secure()
param abstractSasUrl string = ''

@description('How long Azure keeps the deployment script resources and their logs after a run (ISO 8601). Azure allows 1 to 26 hours. The output in your storage account is not affected.')
param scriptRetention string = 'P1D'

@description('Minutes to wait for the role assignments to take effect before failing the deployment.')
@minValue(1)
@maxValue(45)
param rbacWaitMinutes int = 20

@description('Change this value to run the discovery again. The default runs it on every deployment.')
param forceUpdateTag string = utcNow()

@description('Tags for the resources this template creates.')
param tags object = {}

var workspaceId = resourceId(workspaceSubscriptionId, workspaceResourceGroup, 'Microsoft.OperationalInsights/workspaces', workspaceName)
// One identity, script pair and workbook per target workspace, so two workspaces can share this resource group.
var suffix = uniqueString(workspaceId)
var storageName = empty(storageAccountName) ? 'absdisc${uniqueString(resourceGroup().id)}' : storageAccountName
var containerName = 'sentinel-discovery'
var blobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var blobDataReader = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var manifest = loadJsonContent('payload/manifest.json')
// The report script's name in a variable, so reportBlobUrl's reference() names it without building a string inline.
var reportScriptName = 'sentinel-discovery-report-${suffix}'
// Endpoints of the cloud this deploys to, handed to both scripts instead of public-cloud host names.
var armEndpoint = environment().resourceManager
var storageSuffix = environment().suffixes.storage

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'abstract-sentinel-discovery-${suffix}'
  location: location
  tags: tags
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: { publicAccess: 'None' }
}

resource identityWrites 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: container
  name: guid(container.id, identity.id, blobDataContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataContributor)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Sentinel discovery kit: write the output to this container only'
  }
}

resource deployerReads 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantDeployerBlobRead) {
  scope: container
  name: guid(container.id, deployer().objectId, blobDataReader)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataReader)
    principalId: deployer().objectId
    description: 'Sentinel discovery kit: the deployer opens the report'
  }
}

module workspaceRoles 'modules/workspace-rg-roles.bicep' = {
  name: 'sentinel-discovery-roles-${suffix}'
  scope: resourceGroup(workspaceSubscriptionId, workspaceResourceGroup)
  params: { principalId: identity.properties.principalId }
}

module subscriptionReader 'modules/subscription-reader.bicep' = if (assignSubscriptionReader) {
  name: 'sentinel-discovery-reader-${suffix}'
  scope: subscription(workspaceSubscriptionId)
  params: { principalId: identity.properties.principalId }
}

resource inventory 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'sentinel-discovery-inventory-${suffix}'
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    azPowerShellVersion: '14.0'
    forceUpdateTag: forceUpdateTag
    retentionInterval: scriptRetention
    cleanupPreference: 'OnSuccess'
    timeout: 'PT2H'
    scriptContent: loadTextContent('payload/run-inventory.ps1')
    environmentVariables: [
      { name: 'KIT_BUNDLE_B64', value: loadTextContent('payload/kit.tgz.b64') }
      { name: 'KIT_BUNDLE_SHA256', value: manifest.bundles.kit.sha256 }
      { name: 'WS_SUBSCRIPTION_ID', value: workspaceSubscriptionId }
      { name: 'WS_RESOURCE_GROUP', value: workspaceResourceGroup }
      { name: 'WS_NAME', value: workspaceName }
      { name: 'STORAGE_ACCOUNT', value: storage.name }
      { name: 'CONTAINER', value: containerName }
      { name: 'DAYS', value: string(days) }
      { name: 'DEVICE_DAYS', value: string(deviceDays) }
      { name: 'PROFILE_TOP_TABLES', value: string(profileTopTables) }
      { name: 'SKIP_RULE_TEXT', value: toLower(string(skipRuleQueryText)) }
      { name: 'SKIP_CONTENT_TEXT', value: toLower(string(skipContentQueryText)) }
      { name: 'RBAC_WAIT_MINUTES', value: string(rbacWaitMinutes) }
      { name: 'ARM_ENDPOINT', value: armEndpoint }
      { name: 'STORAGE_SUFFIX', value: storageSuffix }
    ]
  }
  dependsOn: [
    identityWrites
    workspaceRoles
    subscriptionReader
    container
  ]
}

var reportEnv = [
  { name: 'REPORT_BUNDLE_B64', value: loadTextContent('payload/report.tgz.b64') }
  { name: 'REPORT_BUNDLE_SHA256', value: manifest.bundles.report.sha256 }
  { name: 'STORAGE_ACCOUNT', value: storage.name }
  { name: 'CONTAINER', value: containerName }
  { name: 'RUN_PREFIX', value: string(inventory.properties.outputs.runPrefix) }
  { name: 'SEND_TO_ABSTRACT', value: toLower(string(sendToAbstract)) }
  { name: 'STORAGE_SUFFIX', value: storageSuffix }
]

resource report 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: reportScriptName
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    azCliVersion: '2.75.0'
    forceUpdateTag: forceUpdateTag
    retentionInterval: scriptRetention
    cleanupPreference: 'OnSuccess'
    timeout: 'PT30M'
    scriptContent: loadTextContent('scripts/build-report.sh')
    environmentVariables: sendToAbstract ? concat(reportEnv, [{ name: 'ABSTRACT_SAS_URL', secureValue: abstractSasUrl }]) : reportEnv
  }
}

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = if (deployWorkbook) {
  name: guid('sentinel-discovery-workbook', workspaceId, resourceGroup().id)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Sentinel inventory (${workspaceName})'
    category: 'sentinel'
    version: 'Notebook/1.0'
    sourceId: workspaceId
    serializedData: loadTextContent('payload/workbook.json')
  }
}

output identityPrincipalId string = identity.properties.principalId
output storageAccountName string = storage.name
output containerName string = containerName
output runPrefix string = string(inventory.properties.outputs.runPrefix)
output reportBlobUrl string = string(report.properties.outputs.reportUrl)
output areasRead string = '${inventory.properties.outputs.areasOk} of ${inventory.properties.outputs.areasTotal}'
output readErrors int = int(inventory.properties.outputs.readErrors)
output readsRefused int = int(inventory.properties.outputs.readsRefused)
output pricesLive bool = bool(report.properties.outputs.pricesLive)
output sentToAbstract bool = bool(report.properties.outputs.sentToAbstract)
output listCostPerMonthNow string = string(report.properties.outputs.listCostPerMonthNow)
output workbookId string = deployWorkbook ? workbook.id : ''
