# Abstract Security for Microsoft Sentinel, deployed from Terraform.
#
# This wraps the solution's own ARM template (../azuredeploy.json), so Terraform and the Deploy to Azure
# button deploy exactly the same thing. Terraform tracks the deployment; the resources are the template's.
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.100, < 5.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  # Every parameter of the template, from the variable of the same name. An empty string is left out so the template
  # keeps its own default (location, for one, defaults to the resource group's region).
  from_variables = {
    location                          = var.location
    createWorkspace                   = var.createWorkspace
    workspaceName                     = var.workspaceName
    workspaceRetentionDays            = var.workspaceRetentionDays
    existingWorkspaceLocation         = var.existingWorkspaceLocation
    tags                              = var.tags
    principalId                       = var.principalId
    dataCollectionEndpointName        = var.dataCollectionEndpointName
    dataCollectionRuleName            = var.dataCollectionRuleName
    customTablePlan                   = var.customTablePlan
    customTableRetentionDays          = var.customTableRetentionDays
    enableDcrErrorLogs                = var.enableDcrErrorLogs
    enableAsim                        = var.enableAsim
    asimSchemas                       = var.asimSchemas
    excludeAsimFromAbstractTable      = var.excludeAsimFromAbstractTable
    lakeTableName                     = var.lakeTableName
    lakeCategories                    = var.lakeCategories
    lakeRetentionDays                 = var.lakeRetentionDays
    nativeVendors                     = var.nativeVendors
    oktaDomain                        = var.oktaDomain
    excludeNativeVendorsFromAsim      = var.excludeNativeVendorsFromAsim
    deployDataConnectors              = var.deployDataConnectors
    deployParsers                     = var.deployParsers
    deployAnalyticsRules              = var.deployAnalyticsRules
    enabledAnalyticsRules             = var.enabledAnalyticsRules
    deployHuntingQueries              = var.deployHuntingQueries
    deployWorkbooks                   = var.deployWorkbooks
    deployDiscovery                   = var.deployDiscovery
    deployDiscoveryWorkbook           = var.deployDiscoveryWorkbook
    deployAutomationRules             = var.deployAutomationRules
    enableAutomationRules             = var.enableAutomationRules
    deployPlaybooks                   = var.deployPlaybooks
    deployPlaybookAutomationRules     = var.deployPlaybookAutomationRules
    abstractBaseUrl                   = var.abstractBaseUrl
    abstractVendorAccountId           = var.abstractVendorAccountId
    keyVaultSecretUri                 = var.keyVaultSecretUri
    lookbackHours                     = var.lookbackHours
    keyVaultMode                      = var.keyVaultMode
    abstractApiKey                    = var.abstractApiKey
    keyVaultName                      = var.keyVaultName
    keyVaultNameSuffix                = var.keyVaultNameSuffix
    keyVaultSecretName                = var.keyVaultSecretName
    grantPlaybookRoles                = var.grantPlaybookRoles
    grantPlaybookResponder            = var.grantPlaybookResponder
    grantPlaybookSecretsUser          = var.grantPlaybookSecretsUser
    deployDataPlane                   = var.deployDataPlane
    deployContent                     = var.deployContent
    discoveryDays                     = var.discoveryDays
    discoveryDeviceDays               = var.discoveryDeviceDays
    discoveryProfileTopTables         = var.discoveryProfileTopTables
    discoverySkipRuleQueryText        = var.discoverySkipRuleQueryText
    discoverySkipContentQueryText     = var.discoverySkipContentQueryText
    discoveryDeployWorkbook           = var.discoveryDeployWorkbook
    discoverySendToAbstract           = var.discoverySendToAbstract
    discoveryAbstractSasUrl           = var.discoveryAbstractSasUrl
    discoveryStorageAccountName       = var.discoveryStorageAccountName
    discoveryAssignSubscriptionReader = var.discoveryAssignSubscriptionReader
    discoveryGrantDeployerBlobRead    = var.discoveryGrantDeployerBlobRead
    discoveryRbacWaitMinutes          = var.discoveryRbacWaitMinutes
  }
  parameters = merge(
    { for k, v in local.from_variables : k => v if v != "" },
    var.extra_parameters,
  )
}

resource "azurerm_resource_group_template_deployment" "solution" {
  name                = "abstract-sentinel-solution"
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"
  template_content    = file("${path.module}/../azuredeploy.json")
  parameters_content  = jsonencode({ for k, v in local.parameters : k => { value = v } })
}
