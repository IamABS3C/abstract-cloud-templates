output "abstract_onboarding" {
  description = "Values for the Abstract integration."
  value = {
    project_id            = var.log_project
    subscription_id       = var.subscription_name
    service_account_email = local.sa_email
    buckets               = keys(local.bucket_projects)
    note                  = "The notification is a POINTER. Abstract needs pubsub.subscriber on the subscription AND storage.objectViewer on each bucket — both are granted here."
  }
}

output "gcs_service_agents" {
  description = "Per owning project, the principal that actually publishes. If notifications never arrive from a bucket, check ITS project's agent holds roles/pubsub.publisher on the topic."
  value       = { for p, sa in data.google_storage_project_service_account.gcs : p => sa.email_address }
}

output "notification_ids" {
  value = { for k, n in google_storage_notification.abstract : k => n.notification_id }
}
