// Reader on the workspace's subscription, for the data collection rules, endpoints, workbooks and playbooks the kit lists.
targetScope = 'subscription'

param principalId string

var reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, reader)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', reader)
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'Sentinel discovery kit: read-only inventory (Reader)'
  }
}
