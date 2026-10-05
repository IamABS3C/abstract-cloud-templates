# Key Vault secrets reader

<!-- Generated from template.yml by `python -m tools.templates generate`. Do not edit. -->

A small helper that grants one role to one principal on an existing Key Vault. The Sentinel destination templates call it as a module to give their identities Key Vault Secrets Officer or Secrets User on the vault that holds the client secret.

**Cloud:** azure · **Role:** access · **Scope:** resource-group

## Deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FIamABS3C%2Fabstract-cloud-templates%2Fmain%2Ftemplates%2Fazure%2Fazure-access-key-vault-secrets-reader%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2FIamABS3C%2Fabstract-cloud-templates%2Fmain%2Ftemplates%2Fazure%2Fazure-access-key-vault-secrets-reader%2FcreateUiDefinition.json)

Or from a shell, in this folder:

```bash
./deploy.sh
```

## Prerequisites

- An existing Key Vault in the target resource group
- The principal's object ID and the role definition ID; set principalType for a freshly created identity to avoid PrincipalNotFound

## Parameters

| Name | Type | Required | Description | Find it |
|---|---|---|---|---|
| `keyVaultName` | string | yes | Name of the existing Key Vault the role is granted on, in the deployment resource group. | `az keyvault list -g <resource-group> --query [].name -o tsv` |
| `principalId` | string | yes | Object ID of the identity receiving the role (a service principal, user or group), not its application (client) ID. | `az ad sp show --id <application-client-id> --query id -o tsv` |
| `roleDefinitionId` | string | yes | Full resource ID of the role definition to grant, for example the built-in Key Vault Secrets User or Key Vault Secrets Officer role. | `az role definition list --name "Key Vault Secrets User" --query [].id -o tsv` |
| `principalType` | string | no | Principal type of principalId. Set it for a freshly created identity to avoid PrincipalNotFound while the directory replicates; leave empty when the type is not known (for example a user or group supplied by the deployer). |  |

## Permissions

- **Rights to create role assignments on the vault** on The Key Vault's resource group: Deployer: For a vault in another resource group, the deployer needs role-assignment rights there too.

## Creates

- One role assignment scoped to the named Key Vault, with a deterministic name derived from the vault, principal and role

## Never touches

- The Key Vault itself, its secrets, keys, access policies and network rules (it is referenced as an existing resource)
- Any other role assignment on the vault or anywhere else

## Outputs

