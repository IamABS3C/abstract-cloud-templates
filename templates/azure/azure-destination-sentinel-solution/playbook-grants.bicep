// =============================================================================
//  The playbooks' role assignments, deployed by main.bicep when it stored the Abstract API key (keyVaultMode Create or
//  Existing) and grantPlaybookRoles is true. A module, not inline, because each playbook's principal id is known only
//  after the content module ran; inside this module it is a parameter, so every assignment name is a deterministic guid
//  of scope, principal and role, and a rerun is a no-op.
//
//  Each playbook's system-assigned identity gets (each grant behind its own switch, because Azure refuses a second
//  assignment of a role an identity already holds on that scope under another name: RoleAssignmentExists):
//    - Key Vault Secrets User on the one secret that holds the Abstract API key (not the vault), so the playbooks read
//      that secret and nothing else in the vault. Microsoft Learn: "Azure RBAC for Key Vault allows roles assignment at
//      ... Individual key, secret, and certificate" (key-vault/general/rbac-migration).
//    - Microsoft Sentinel Responder on the workspace, which the Microsoft Sentinel connector needs to update incidents
//      and add comments (sentinel/automation/authenticate-playbooks-to-sentinel).
// =============================================================================
targetScope = 'resourceGroup'

@description('Name of the Log Analytics workspace that runs Microsoft Sentinel, in this resource group.')
param workspaceName string

@description('Name of the Key Vault that holds the Abstract API key, in this resource group.')
param keyVaultName string

@description('Name of the secret that holds the Abstract API key.')
param secretName string

@description('The playbooks, as the content module outputs them: [{ name, principalId }]. An empty principalId is skipped.')
param playbooks array

@description('Grant Microsoft Sentinel Responder on the workspace. Off when the playbooks already hold it from another assignment.')
param grantResponder bool = true

@description('Grant Key Vault Secrets User on the secret. Off when the playbooks already hold it from another assignment.')
param grantSecretsUser bool = true

// Built-in role definition ids (az role definition list --name "<role>" --query "[].name", read 2026-11-12).
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var sentinelResponderRoleId = '3e150937-b8fe-4cfb-8069-0eaf05ecd056'
var grantees = filter(playbooks, p => !empty(p.principalId))

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

resource vault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: keyVaultName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2026-02-01' existing = {
  parent: vault
  name: secretName
}

resource secretReaders 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for p in grantees: if (grantSecretsUser) {
  name: guid(secret.id, p.principalId, keyVaultSecretsUserRoleId)
  scope: secret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: p.principalId
    // The identity was created moments earlier: the type lets Azure skip the directory lookup that can fail with
    // PrincipalNotFound while Entra replicates.
    principalType: 'ServicePrincipal'
    description: 'Abstract playbook ${p.name}: read the Abstract API key.'
  }
}]

resource sentinelResponders 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for p in grantees: if (grantResponder) {
  name: guid(workspace.id, p.principalId, sentinelResponderRoleId)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sentinelResponderRoleId)
    principalId: p.principalId
    principalType: 'ServicePrincipal'
    description: 'Abstract playbook ${p.name}: read and update Microsoft Sentinel incidents.'
  }
}]

output grantedPlaybooks array = map(grantees, p => p.name)
