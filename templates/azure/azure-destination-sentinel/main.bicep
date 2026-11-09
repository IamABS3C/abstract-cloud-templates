// =============================================================================
//  Abstract Security - Azure Sentinel DESTINATION onboarding (Bicep)
//  Version : 3.0
//  Author  : Abstract Security - Solutions Engineering
//
//  Provisions the Azure side of the Abstract "Azure Sentinel Destination"
//  integration - i.e. everything needed for Abstract to deliver events into
//  Microsoft Sentinel through the Azure Monitor Logs Ingestion API
//  (docs.abstractsecurity.app -> Integrations -> Destination -> Azure Sentinel
//  Destination).
//
//  Full stack (resource-group scope):
//    1. Log Analytics workspace     (create new, or reference an existing one
//                                     in this resource group)
//    2. Microsoft Sentinel          (onboarding state enabled on the workspace)
//    3. Data Collection Endpoint    (DCE - the ingestion endpoint)
//    4. Custom log table (*_CL)     (DCR-based, with a parameterizable schema)
//    5. Data Collection Rule (DCR)  (stream declaration -> workspace table)
//    6. RBAC on the DCR             (Monitoring Metrics Publisher, plus Monitoring
//                                     Contributor only if grantMonitoringContributor)
//                                     for the supplied service principal.
//    7. Optional ASIM dataflows     (enableAsim, off by default) and DCR error logs.
//
//  WHAT IT NEVER TOUCHES: analytics rules, automation rules, hunting queries,
//  workbooks, watchlists, data connectors, parsers, other tables, workspace
//  settings of an existing workspace, or the SecurityInsights solution of an
//  existing workspace. See docs/public/azure/sentinel-destination-assurance.md.
//
//  NOTE: an Entra app registration + client secret CANNOT be created in ARM.
//  Create the app first (or have Abstract Solutions create it), pass its
//  service principal OBJECT id as principalId, and enter the Client ID /
//  Client Secret / Tenant ID directly in the Abstract destination modal.
//
//  The deployment OUTPUTS map field-for-field to the Abstract modal:
//    Data Collection Rule ID   -> dataCollectionRuleImmutableId
//    Data Collection Endpoint  -> dataCollectionEndpointUrl
//    Log Stream Name           -> logStreamName  (Custom-<table>)
//
//  azuredeploy.json beside this file is compiled from it by: python -m tools.templates generate
// =============================================================================

// ---------------------------------------------------------------------------
// Core
// ---------------------------------------------------------------------------
@description('Azure region for the workspace, DCE and DCR. Keep these consistent (the DCE/DCR must be in the same region as the workspace).')
param location string = resourceGroup().location

@description('Tags applied to every created resource that supports tags.')
param tags object = {}

@description('Resource-specific tags, keyed by fully qualified Azure resource type.')
param tagsByResource object = {}

// ---------------------------------------------------------------------------
// Log Analytics workspace + Sentinel
// ---------------------------------------------------------------------------
@description('Create a new Log Analytics workspace. Set false to target an EXISTING workspace in THIS resource group (provide its name in workspaceName).')
param createWorkspace bool = true

@description('Workspace name. When creating: leave empty to auto-generate (abstract-sentinel-<hash>). When using an existing workspace: the exact name of that workspace (must live in this resource group).')
param workspaceName string = ''

@description('Workspace pricing tier. PerGB2018 is the standard pay-as-you-go tier.')
@allowed(['PerGB2018', 'CapacityReservation', 'Free', 'Standalone', 'PerNode'])
param workspaceSku string = 'PerGB2018'

@description('Workspace data retention in days. Only applied when creating a new workspace; an existing workspace is never modified. The Abstract table\'s own retention is customTableRetentionDays.')
@minValue(7)
@maxValue(730)
param workspaceRetentionDays int = 90

@description('Enable Microsoft Sentinel on the workspace (only applied when creating a new workspace; assumed already enabled for existing workspaces).')
param enableSentinel bool = true

@description('Region of the EXISTING workspace (Existing mode only). The DCE and DCR MUST be created in the same region as the target workspace, so if your existing workspace is in a different region than this deployment, set it here (e.g. eastus2). Leave empty to use the deployment location.')
param existingWorkspaceLocation string = ''

// ---------------------------------------------------------------------------
// Data Collection Endpoint + Rule + custom table
// ---------------------------------------------------------------------------
@description('Name of the Data Collection Endpoint (DCE) that receives data from Abstract.')
param dataCollectionEndpointName string = 'abstract-dce'

@description('Name of the Data Collection Rule (DCR) that routes data into the workspace table.')
param dataCollectionRuleName string = 'abstract-dcr'

@description('Custom log table name. MUST end in _CL. Enter this (as the stream Custom-<table>) in the "Log Stream Name" field of the Abstract destination modal.')
param customTableName string = 'AbstractEventLogs_CL'

@description('Custom table columns. Leave empty (recommended) to use the generated ACS schema: one column per top-level key of the event Abstract sends, with a DCR transformation that sets TimeGenerated. Supply columns only for a custom payload shape; the DCR stream then uses the same columns and transformKql.')
param tableColumns array = []

@description('DCR transformation used only when tableColumns is supplied. The generated schema carries its own transformation.')
param transformKql string = 'source'

@description('Send the Data Collection Rule\'s ingestion errors (rejected requests, malformed payloads, limit and transformation errors) to the DCRLogErrors table in the workspace. Without it, data Azure refuses or drops is invisible to the customer and to Abstract.')
param enableDcrErrorLogs bool = true

@description('Also write each event into Microsoft\'s ASIM normalized tables (ASimAuthenticationEventLogs and the others listed in asimSchemas), mapped from the Abstract Common Schema by the Abstract ASIM mappings. Off by default. Microsoft\'s built-in ASIM parsers read those tables, so once this is on every ASIM analytics rule, hunting query and workbook already running in the workspace also sees Abstract data: expect new alerts, duplicates where Microsoft\'s own connector collects the same vendor, and a second copy of each mapped event in billing. Turn it on in a staging workspace first, or one schema at a time with asimSchemas. Needs Microsoft Sentinel on the workspace and the generated Abstract schema (tableColumns left empty). Every event still also lands in the Abstract table.')
param enableAsim bool = false

@description('ASIM schemas to write, by name (for example [\'Authentication\', \'NetworkSession\']). [\'*\'] (default) writes every schema the Abstract ASIM mappings cover; [] writes none.')
param asimSchemas array = [
  '*'
]

@description('With enableAsim on, keep each event that an ASIM dataflow takes out of the Abstract table, so it is stored once (in its ASim table) instead of twice. Off by default to keep existing deployments unchanged: content that reads only the Abstract table, such as the Abstract content pack before it reads the ASim tables too, no longer sees those events. Events no ASIM dataflow takes, and everything when enableAsim is off, still land in the Abstract table.')
param excludeAsimFromAbstractTable bool = false

@description('A KQL condition over the Abstract stream selecting events that one of your additionalDataFlows stores. Those events are written by no ASIM dataflow and never go to the lake table, and with excludeAsimFromAbstractTable on they are also kept out of the Abstract table, so each is stored once, in the additionalDataFlows table. It must match exactly what that dataflow takes, or events are lost or stored twice. Empty (default) changes nothing. Set by the Abstract Security for Microsoft Sentinel solution; leave empty when deploying this template on its own.')
param asimExcludeKql string = ''

@description('Name of a second custom table on the Auxiliary (lake-only) plan, for events nothing in Sentinel reads, for example AbstractLake_CL. Empty (default) turns the lake route off. Lake rows cost data lake ingestion and processing (about 0.15 USD per GB at eastus list price against 4.30 in the analytics tier) and are searchable with KQL in the data lake, but analytics rules, ASIM parsers and custom detections do not run on them.')
param lakeTableName string = ''

@description('ACS event categories to send to the lake table instead of the Abstract table, for example [\'network\', \'dns\']. An event matches when its event.category contains one of them. Events an ASIM dataflow takes never go to the lake. Empty (default) turns the lake route off.')
param lakeCategories array = []

@description('Total retention of the lake table in days (30 to 4383).')
@minValue(30)
@maxValue(4383)
param lakeRetentionDays int = 365

@description('Retention of the Abstract table in days. 0 (default) sends no retention, so an existing table keeps its retention and a new table uses the workspace default. A value shortens or lengthens the table\'s total retention; shortening deletes data older than the new value.')
@minValue(0)
@maxValue(4383)
param customTableRetentionDays int = 0

@description('Table plan for the Abstract table. Keep (default) keeps the plan an existing table already has, and create a new table as Analytics: a redeploy then never changes a table\'s plan, or its cost, by accident. Analytics runs analytics rules and our content pack on it. Auxiliary is the Sentinel data lake tier: cheap long retention and KQL jobs, but no analytics rules or alerts. Basic sits between them. Setting a plan on an existing table switches it; Azure applies the new plan to the whole table.')
@allowed(['Keep', 'Analytics', 'Basic', 'Auxiliary'])
param customTablePlan string = 'Keep'

@description('Extra tables to create before the Data Collection Rule, for dataflows passed in additionalDataFlows (for example a vendor table such as OktaV2_CL). Each item is {name, columns}, columns in Log Analytics table format. Empty (default) creates none. Used by the Abstract Security for Microsoft Sentinel solution; leave empty when deploying this template on its own.')
param additionalTables array = []

@description('Extra DCR dataflows on the Abstract stream, each {transformKql, outputStream}. They read the same Custom-<table> stream as the catch-all and do not change what the catch-all keeps. Empty (default) adds none. Azure allows at most 20 dataflows per DCR, counting the catch-all, the ASIM routes and the lake route. Used by the Abstract Security for Microsoft Sentinel solution; leave empty when deploying this template on its own.')
param additionalDataFlows array = []

// ---------------------------------------------------------------------------
// RBAC for the Abstract service principal (granted on the DCR)
// ---------------------------------------------------------------------------
@description('Also grant Monitoring Contributor on the DCR. Off by default: sending data through the Logs Ingestion API needs only Monitoring Metrics Publisher, and Monitoring Contributor would let a leaked Abstract credential rewrite or delete the DCR and its error-log setting. Turn on only if your Abstract destination setup specifically asks for it.')
param grantMonitoringContributor bool = false

@description('Object ID of the service principal Abstract authenticates as (the Enterprise Application object ID, NOT the Application/client ID). Leave empty to skip role assignments and grant them yourself later.')
param principalId string = ''

@description('Type of the principal being granted RBAC (avoids PrincipalNotFound on freshly created SPNs).')
@allowed(['ServicePrincipal', 'User', 'Group'])
param principalType string = 'ServicePrincipal'

// ---------------------------------------------------------------------------
// Derived values
// ---------------------------------------------------------------------------
var autoWorkspaceName = 'abstract-sentinel-${uniqueString(resourceGroup().id)}'
var effectiveWorkspaceName = createWorkspace ? (empty(workspaceName) ? autoWorkspaceName : workspaceName) : workspaceName
var workspaceResourceId = resourceId('Microsoft.OperationalInsights/workspaces', effectiveWorkspaceName)

// The DCE and DCR must be co-located with the destination workspace. When
// creating a new workspace they share the deployment location; for an existing
// workspace in another region, callers set existingWorkspaceLocation.
var effectiveLocation = createWorkspace ? location : (empty(existingWorkspaceLocation) ? location : existingWorkspaceLocation)
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

// ACS-to-ASIM mappings, generated by tools/templates/sentinel.py from _modules/sentinel/asim/*.kql. They
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
  transformKql: empty(asimExcludeKql) ? route.transformKql : 'source\n| where not(${asimExcludeKql})\n${substring(route.transformKql, length('source\n'))}'
  outputStream: route.outputStream
}]

// One home per event. Each enabled ASIM route's own filter becomes a flag (generated: selectionKql / selectedFlag /
// tempColumns); the lake flag takes the chosen categories that no ASIM route takes. The Abstract table then drops what
// the ASIM routes take (when excludeAsimFromAbstractTable is on) and what the lake takes. Spliced in after `source`.
var lakeEnabled = !empty(lakeTableName) && !empty(lakeCategories) && useGeneratedSchema
var asimAny = empty(enabledAsimRoutes) ? 'false' : '(${join(map(enabledAsimRoutes, route => route.selectedFlag), ' or ')})'
var excludeAsim = excludeAsimFromAbstractTable && !empty(enabledAsimRoutes)
// Events an additionalDataFlows lane stores (asimExcludeKql): no ASIM dataflow and no lake for them, and with store-once
// on, no Abstract table either. Dropped explicitly, because an ASIM selection flag is false for an event no route maps.
// The lane selection is computed once, as the _lane column, so the catch-all and lake transforms carry its text one time
// only (Azure caps a transformKql at 15,360 characters).
var laneNotClause = empty(asimExcludeKql) ? '' : ' and not(_lane)'
var needsSelection = excludeAsim || lakeEnabled
var selectionParts = concat(empty(asimExcludeKql) ? [] : ['| extend _lane = (${asimExcludeKql})'], empty(enabledAsimRoutes) ? [] : map(enabledAsimRoutes, route => route.selectionKql), lakeEnabled ? [
  '| extend _lake_category = tolower(tostring(event.category))'
  '| extend _lake = (${join(map(lakeCategories, c => '_lake_category has \'${toLower(c)}\''), ' or ')}) and not(${asimAny})${laneNotClause}'
] : [])
var selectionColumns = concat(empty(asimExcludeKql) ? [] : ['_lane'], empty(enabledAsimRoutes) ? [] : flatten(map(enabledAsimRoutes, route => concat([route.selectedFlag], route.tempColumns))), lakeEnabled ? [
  '_lake'
  '_lake_category'
] : [])
var transformBody = substring(effectiveTransformKql, length('source\n'))
var catchAllDropBase = excludeAsim ? (lakeEnabled ? '${asimAny} or _lake' : asimAny) : '_lake'
var catchAllDrop = (excludeAsim && !empty(asimExcludeKql)) ? '${catchAllDropBase} or _lane' : catchAllDropBase
var catchAllTransformKql = needsSelection ? 'source\n${join(selectionParts, '\n')}\n| where not(${catchAllDrop})\n| project-away ${join(selectionColumns, ', ')}\n${transformBody}' : effectiveTransformKql
var lakeTransformKql = 'source\n${join(selectionParts, '\n')}\n| where _lake\n| project-away ${join(selectionColumns, ', ')}\n${transformBody}'
var lakeStreamName = 'Custom-${lakeTableName}'
var lakeFlows = lakeEnabled ? [
  {
    streams: [
      streamName
    ]
    destinations: [
      logAnalyticsDestinationName
    ]
    transformKql: lakeTransformKql
    outputStream: lakeStreamName
  }
] : []

// Caller-supplied dataflows on the same input stream (see additionalDataFlows).
var extraFlows = [for flow in additionalDataFlows: {
  streams: [
    streamName
  ]
  destinations: [
    logAnalyticsDestinationName
  ]
  transformKql: flow.transformKql
  outputStream: flow.outputStream
}]

// Stream name for a DCR-based custom table is always Custom-<table>.
var streamName = 'Custom-${customTableName}'
var logAnalyticsDestinationName = 'abstractSentinelWorkspace'

// Built-in role definition IDs.
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var monitoringContributorRoleId = '749f88d5-cbae-40b8-bcfc-e573ddc772fa'

// ---------------------------------------------------------------------------
// Log Analytics workspace
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

// Microsoft Sentinel onboarding (extension resource on the workspace).
resource sentinelOnboarding 'Microsoft.SecurityInsights/onboardingStates@2024-03-01' = if (createWorkspace && enableSentinel) {
  scope: workspace
  name: 'default'
  properties: {}
}

// ---------------------------------------------------------------------------
// Custom log table (DCR-based, *_CL). Created on the (new or existing) workspace.
// ---------------------------------------------------------------------------
resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2026-03-01' = {
  name: '${effectiveWorkspaceName}/${customTableName}'
  properties: union({
    schema: {
      name: customTableName
      columns: customTableArmColumns
    }
  }, customTablePlanProperty, customTableRetentionProperty)
  dependsOn: createWorkspace ? [
    workspace
  ] : []
}

// Lake-only table (Auxiliary plan): same columns as the Abstract table, so the same transformation fills it.
resource lakeTable 'Microsoft.OperationalInsights/workspaces/tables@2026-03-01' = if (lakeEnabled) {
  name: '${effectiveWorkspaceName}/${empty(lakeTableName) ? 'unused_CL' : lakeTableName}'
  properties: {
    plan: 'Auxiliary'
    totalRetentionInDays: lakeRetentionDays
    schema: {
      name: lakeTableName
      columns: customTableArmColumns
    }
  }
  dependsOn: createWorkspace ? [
    workspace
  ] : []
}

// Tables for additionalDataFlows (created only when that parameter supplies them).
resource additionalTable 'Microsoft.OperationalInsights/workspaces/tables@2026-03-01' = [for table in additionalTables: {
  name: '${effectiveWorkspaceName}/${table.name}'
  properties: {
    schema: {
      name: table.name
      columns: table.columns
    }
  }
  dependsOn: createWorkspace ? [
    workspace
  ] : []
}]

// ---------------------------------------------------------------------------
// Data Collection Endpoint
// ---------------------------------------------------------------------------
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


// ---------------------------------------------------------------------------
// Data Collection Rule: Custom-<table> stream -> workspace custom table
// ---------------------------------------------------------------------------
resource dcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: dataCollectionRuleName
  location: effectiveLocation
  tags: union(tags, contains(tagsByResource, 'Microsoft.Insights/dataCollectionRules') ? tagsByResource['Microsoft.Insights/dataCollectionRules'] : {})
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      // DCR stream column types are all lower-case (datetime, string, int, ...).
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
        streams: [
          streamName
        ]
        destinations: [
          logAnalyticsDestinationName
        ]
        transformKql: catchAllTransformKql
        outputStream: streamName
      }
    ], asimFlows, lakeFlows, extraFlows)
  }
  dependsOn: [
    customTable
    lakeTable
    additionalTable
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
// RBAC on the DCR for the Abstract service principal
// ---------------------------------------------------------------------------
resource metricsPublisherAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(dcr.id, principalId, monitoringMetricsPublisherRoleId)
  scope: dcr
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalType: principalType
  }
}

resource monitoringContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId) && grantMonitoringContributor) {
  name: guid(dcr.id, principalId, monitoringContributorRoleId)
  scope: dcr
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringContributorRoleId)
    principalType: principalType
  }
}

// ---------------------------------------------------------------------------
// Outputs - field-for-field for the Abstract "Azure Sentinel Destination" modal
// ---------------------------------------------------------------------------
output workspaceName string = effectiveWorkspaceName
output workspaceResourceId string = workspaceResourceId
output customTableName string = customTableName
output dataCollectionRuleImmutableId string = dcr.properties.immutableId
output dataCollectionEndpointUrl string = dce.properties.logsIngestion.endpoint
output logStreamName string = streamName
output rbacAssigned bool = !empty(principalId)
output dataFlowCount int = 1 + length(asimFlows) + length(lakeFlows) + length(extraFlows)

output abstractSentinelOnboarding object = {
  azureMonitorDetails: {
    dataCollectionRuleId: dcr.properties.immutableId
    dataCollectionEndpoint: dce.properties.logsIngestion.endpoint
    logStreamName: streamName
  }
  authentication: {
    clientId: '(Entra ID > App registrations > your app > Application (client) ID)'
    clientSecretValue: '(Entra ID > App registrations > your app > Certificates & secrets)'
    applicationTenantId: subscription().tenantId
  }
  rbac: !empty(principalId) ? (grantMonitoringContributor ? 'Monitoring Metrics Publisher + Monitoring Contributor granted on the DCR to principal ${principalId}' : 'Monitoring Metrics Publisher granted on the DCR to principal ${principalId}') : '(no principalId supplied - assign Monitoring Metrics Publisher on the DCR yourself)'
  docs: 'https://docs.abstractsecurity.app/docs/integrations/destination-integrations/azure-sentinel-destination/'
}
