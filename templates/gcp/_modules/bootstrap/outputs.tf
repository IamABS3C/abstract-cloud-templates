output "project_id" {
  description = "The logging project, created or existing."
  value       = local.project_id
}

output "enabled_apis" {
  value = local.required_apis
}
