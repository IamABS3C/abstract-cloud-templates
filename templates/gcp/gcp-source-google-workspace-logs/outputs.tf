output "workspace_onboarding" {
  description = "The delegation values for admin.google.com, and the field values for Abstract."
  value       = module.workspace.workspace_onboarding
}

output "workspace_applications_selected" {
  value = module.workspace.workspace_applications_selected
}
