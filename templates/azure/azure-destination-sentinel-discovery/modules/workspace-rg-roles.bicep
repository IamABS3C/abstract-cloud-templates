// Read roles for the discovery identity on the resource group that holds the Sentinel workspace.
targetScope = 'resourceGroup'

param principalId string

var roles = {
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  MicrosoftSentinelReader: '8d289c81-5878-46d4-8554-54e1e3d8b5cb'
  LogAnalyticsReader: '73c42c96-874c-492b-b04d-ab87d138a893'
}

resource assignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for role in items(roles): {
    name: guid(resourceGroup().id, principalId, role.value)
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.value)
      principalId: principalId
      principalType: 'ServicePrincipal'
      description: 'Sentinel discovery kit: read-only inventory (${role.key})'
    }
  }
]
