output "abstract_onboarding" {
  description = "Paste these into the Abstract GCP Pub/Sub integration."
  value       = module.log_export.abstract_onboarding
}

output "topic_id" {
  description = "Pub/Sub topic the sink publishes to."
  value       = module.log_export.topic_id
}

output "subscription_id" {
  description = "Pub/Sub subscription ID for Abstract to pull from."
  value       = module.log_export.subscription_id
}

output "service_account_email" {
  description = "Identity Abstract authenticates as. Holds subscriber on the subscription."
  value       = module.log_export.service_account_email
}

output "sink_writer_identity" {
  description = "The sink's service identity that publishes to the topic."
  value       = module.log_export.sink_writer_identity
}

output "effective_filter" {
  description = "The literal Cloud Logging filter applied to the billing account sink. Read this before applying."
  value       = module.log_export.effective_filter
}

output "selected_log_sources" {
  description = "Resolved log categories."
  value       = module.log_export.selected_log_sources
}

output "volume_profile" {
  description = "Count of selected sources by volume tier."
  value       = module.log_export.volume_profile
}
