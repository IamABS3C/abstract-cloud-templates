locals {
  # The ARM template's outputs, by their own names. Unknown until the deployment has run.
  outputs = { for k, v in jsondecode(azurerm_resource_group_template_deployment.solution.output_content) : k => v.value }
}

output "workspaceName" {
  description = "Passed through from the solution deployment: workspaceName."
  value       = local.outputs["workspaceName"]
}

output "workspaceResourceId" {
  description = "Passed through from the solution deployment: workspaceResourceId."
  value       = local.outputs["workspaceResourceId"]
}

output "dataCollectionRuleImmutableId" {
  description = "Passed through from the solution deployment: dataCollectionRuleImmutableId."
  value       = local.outputs["dataCollectionRuleImmutableId"]
}

output "dataCollectionEndpointUrl" {
  description = "Passed through from the solution deployment: dataCollectionEndpointUrl."
  value       = local.outputs["dataCollectionEndpointUrl"]
}

output "logStreamName" {
  description = "Passed through from the solution deployment: logStreamName."
  value       = local.outputs["logStreamName"]
}

output "rbacAssigned" {
  description = "Passed through from the solution deployment: rbacAssigned."
  value       = local.outputs["rbacAssigned"]
}

output "dataFlowCount" {
  description = "Passed through from the solution deployment: dataFlowCount."
  value       = local.outputs["dataFlowCount"]
}

output "nativeVendorTables" {
  description = "Passed through from the solution deployment: nativeVendorTables."
  value       = local.outputs["nativeVendorTables"]
}

output "discoveryReportBlobUrl" {
  description = "Passed through from the solution deployment: discoveryReportBlobUrl."
  value       = local.outputs["discoveryReportBlobUrl"]
}

output "contentTemplateCount" {
  description = "Passed through from the solution deployment: contentTemplateCount."
  value       = local.outputs["contentTemplateCount"]
}

output "abstractDestination" {
  description = "Four of the values Abstract's Azure Sentinel Destination needs: tenant ID, Data Collection Endpoint, Data Collection Rule ID and Log Stream Name. The app's client ID and secret come from Entra ID."
  value       = local.outputs["abstractDestination"]
}
