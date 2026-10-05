output "abstract_onboarding" {
  description = "Paste these into the Abstract GCP Pub/Sub integration."
  value       = module.log_export.abstract_onboarding
}

output "effective_filter" {
  description = "The literal Cloud Logging filter. Read this before applying — it decides both coverage and bill."
  value       = module.log_export.effective_filter
}

output "selected_log_sources" { value = module.log_export.selected_log_sources }
output "volume_profile" { value = module.log_export.volume_profile }
output "sink_writer_identity" { value = module.log_export.sink_writer_identity }
