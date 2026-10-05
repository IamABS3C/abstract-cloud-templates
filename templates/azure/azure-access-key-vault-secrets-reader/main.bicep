targetScope = 'resourceGroup'

param keyVaultName string
param principalId string
param roleDefinitionId string

@description('Principal type of principalId. Set it for a freshly created identity to avoid PrincipalNotFound while the directory replicates; leave empty when the type is not known (for example a user or group supplied by the deployer).')
@allowed(['', 'ServicePrincipal', 'User', 'Group'])
param principalType string = ''

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: keyVaultName
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, roleDefinitionId)
  scope: keyVault
  properties: {
    principalId: principalId
    roleDefinitionId: roleDefinitionId
    principalType: empty(principalType) ? null : principalType
  }
}
