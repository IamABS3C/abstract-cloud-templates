output "scc_topic" {
  description = "Topic SCC publishes findings to. Separate from the audit-log topic on purpose — different shape, different rate."
  value       = try(google_pubsub_topic.scc[0].id, null)
}

output "scc_subscription" {
  description = "Subscription Abstract pulls findings from."
  value       = try(google_pubsub_subscription.scc[0].name, null)
}

output "notification_config" {
  description = "The org NotificationConfig. Its existence is what makes SCC reach Pub/Sub at all — no log filter can substitute."
  value       = try(google_scc_v2_organization_notification_config.abstract[0].name, null)
}
