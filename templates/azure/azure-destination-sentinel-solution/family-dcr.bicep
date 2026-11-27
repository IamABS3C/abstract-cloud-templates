// =============================================================================
//  One lane family's Data Collection Rule (main.bicep, laneFamilies)
//
//  A family rule takes the same Custom-AbstractEventLogs_CL stream as the main rule, on the same Data Collection
//  Endpoint, and holds only that family's lanes: no catch-all, no ASIM routes, no lake. An event the family's lanes do
//  not select is dropped here, so Abstract sends a family rule only the sources its lanes are for (one Abstract
//  destination per rule). Each rule gets the Abstract app's Monitoring Metrics Publisher role and its own DCRLogErrors
//  diagnostic setting. Two tags mark the rule as this deployment's own (abstract-lane-family and abstract-main-rule);
//  deploy.sh and the portal form refuse to deploy over a rule of the same name that does not carry both, because Azure
//  would replace that rule's streams, destinations and dataflows.
// =============================================================================

@description('Name of this rule: the main rule\'s name and the family, for example abstract-dcr-endpoint.')
param name string

@description('Region of the workspace, where the endpoint and the main rule already are.')
param location string

@description('Tags on the rule and the tables it creates.')
param tags object = {}

@description('The lane family this rule holds, for example endpoint.')
param family string

@description('Name of the main Data Collection Rule this family rule belongs to; written as the abstract-main-rule tag.')
param mainRuleName string

@description('Name of the Data Collection Endpoint the main rule uses, in this resource group.')
param dataCollectionEndpointName string

@description('Name of the Log Analytics workspace, in this resource group.')
param workspaceName string

@description('The Abstract stream\'s columns: the same declaration as the main rule, so one Abstract payload fits every rule.')
param streamColumns array

@description('The family\'s dataflows in precedence order, each {transformKql, outputStream}; at most 20.')
param flows array

@description('Vendor tables the family\'s lanes write and that must exist first, each {name, columns}.')
param tables array = []

@description('Object ID of the Abstract app\'s service principal; empty skips the grant.')
param principalId string = ''

@description('Send the rule\'s ingestion errors to DCRLogErrors.')
param enableDcrErrorLogs bool = true

var streamName = 'Custom-AbstractEventLogs_CL'
var destinationName = 'abstractSentinelWorkspace'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource workspace 'Microsoft.OperationalInsights/workspaces@2026-03-01' existing = {
  name: workspaceName
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2024-03-11' existing = {
  name: dataCollectionEndpointName
}

resource familyTable 'Microsoft.OperationalInsights/workspaces/tables@2026-03-01' = [for table in tables: {
  parent: workspace
  name: table.name
  properties: {
    schema: {
      name: table.name
      columns: table.columns
    }
  }
}]

resource dcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: name
  location: location
  tags: union(tags, {
    'abstract-lane-family': family
    'abstract-main-rule': mainRuleName
  })
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      '${streamName}': {
        columns: [for col in streamColumns: {
          name: col.name
          type: toLower(string(col.type))
        }]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspace.id
          name: destinationName
        }
      ]
    }
    dataFlows: [for flow in flows: {
      streams: [
        streamName
      ]
      destinations: [
        destinationName
      ]
      transformKql: flow.transformKql
      outputStream: flow.outputStream
    }]
  }
  dependsOn: [
    familyTable
  ]
}

resource dcrErrorLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDcrErrorLogs) {
  name: 'abstract-dcr-errors'
  scope: dcr
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        category: 'LogErrors'
        enabled: true
      }
    ]
  }
}

resource metricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(dcr.id, principalId, monitoringMetricsPublisherRoleId)
  scope: dcr
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalType: 'ServicePrincipal'
  }
}

output family string = family
output dataCollectionRuleName string = dcr.name
output dataCollectionRuleImmutableId string = dcr.properties.immutableId
output logStreamName string = streamName
output dataFlowCount int = length(flows)
output outputStreams array = map(flows, flow => flow.outputStream)
