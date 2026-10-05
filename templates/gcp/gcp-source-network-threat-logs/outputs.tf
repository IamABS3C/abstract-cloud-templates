output "abstract_onboarding" {
  description = "Everything needed to configure the Abstract GCP Pub/Sub Source, in one object."
  value       = module.log_export.abstract_onboarding
}

output "topic_id" {
  description = "Pub/Sub topic the sink publishes to."
  value       = module.log_export.topic_id
}

output "subscription_id" {
  description = "Short subscription name. This is what goes in the Abstract integration's Subscription ID field."
  value       = module.log_export.subscription_id
}

output "service_account_email" {
  description = "Identity Abstract authenticates as. Holds subscriber on one subscription only."
  value       = module.log_export.service_account_email
}

output "sink_writer_identity" {
  description = "The sink's writer identity."
  value       = module.log_export.sink_writer_identity
}

output "effective_filter" {
  description = "The literal Cloud Logging filter configured on the sink."
  value       = module.log_export.effective_filter
}

output "selected_log_sources" {
  description = "Resolved categories with their volume tier."
  value       = module.log_export.selected_log_sources
}

output "volume_profile" {
  description = "Count of selected sources by volume tier."
  value       = module.log_export.volume_profile
}
