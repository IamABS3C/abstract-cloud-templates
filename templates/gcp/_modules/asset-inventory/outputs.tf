output "abstract_onboarding" {
  description = "Values for the Abstract integration. A SEPARATE source from the audit-log feed — different shape, different parser."
  value = {
    project_id      = var.log_project
    subscription_id = var.subscription_name
    content_type    = var.content_type
    asset_types     = var.asset_types
  }
}

output "cai_service_agent" {
  description = "The principal that publishes. If the feed exists and nothing arrives, check this holds roles/pubsub.publisher on the topic."
  value       = google_project_service_identity.cai.email
}
