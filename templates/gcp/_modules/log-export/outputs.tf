output "topic_id" {
  description = "Pub/Sub topic the sink publishes to."
  value       = google_pubsub_topic.abstract.id
}

output "subscription_id" {
  description = "Short subscription name. This is what goes in the Abstract integration's Subscription ID field."
  value       = google_pubsub_subscription.abstract.name
}

output "abstract_project_id" {
  description = "Goes in the Abstract integration's Project ID field. NOTE: this is the project holding the SUBSCRIPTION, not the projects generating logs. With an org sink the logs come from dozens of projects and this field still names one — the field people fill in wrong most often."
  value       = var.log_project
}

output "service_account_email" {
  description = "Identity Abstract authenticates as. Holds subscriber on one subscription only."
  value       = google_service_account.abstract.email
}

output "sink_writer_identity" {
  description = "The sink's own service identity. It holds NO permissions until granted pubsub.publisher on the topic — which this module does. If you ever rebuild the sink by hand, this is the grant to remember."
  value       = local.writer_identity
}

output "effective_filter" {
  description = "The filter actually applied. Read it before applying: routing is write-time and there is NO backfill, so anything this filter misses is permanently lost."
  value       = local.effective_filter
}

output "abstract_onboarding" {
  description = "Everything needed to configure the Abstract GCP Pub/Sub Source, in one object."
  value = {
    integration     = "default.google_cloud_pub_sub.0_0_11"
    project_id      = var.log_project
    subscription_id = google_pubsub_subscription.abstract.name
    credentials     = var.create_service_account_key ? "see terraform output -raw service_account_key (WARNING: also in state)" : "create out of band, outside the repo clone: mkdir -p ~/abstract-keys && chmod 700 ~/abstract-keys && gcloud iam service-accounts keys create ~/abstract-keys/abstract-pubsub-key.json --iam-account=${google_service_account.abstract.email} && chmod 600 ~/abstract-keys/abstract-pubsub-key.json"
    next_steps = [
      "1. Verify the sink publishes: check logging.googleapis.com/exports/error_count and look for sink_error entries.",
      "2. Confirm topic/send_request_count is rising. Zero here is the sink or the publisher binding, NOT Abstract.",
      "3. Enable Data Access audit logs in the org IAM audit config if data_access is in audit_streams — the filter matches NOTHING until you do, and that reads exactly like a broken sink.",
      "4. Configure the Abstract integration with project_id + subscription_id + the key file.",
      "5. Spot-check that user_name, related.user and cloud.project_id are populated. That proves value, not just plumbing."
    ]
  }
}

output "service_account_key" {
  description = "Base64 service-account key, only when create_service_account_key = true. Prefer creating it out of band — this value lands in Terraform state."
  value       = var.create_service_account_key ? google_service_account_key.abstract[0].private_key : ""
  sensitive   = true
}

output "selected_log_sources" {
  description = "Resolved categories with their volume tier — read this before applying."
  value = {
    for c in local.selected : c => {
      tier = try(local.log_catalog[c].tier, "unknown")
      what = try(local.log_catalog[c].what, "")
    }
  }
}

output "volume_profile" {
  description = "Count of selected sources by volume tier. Any 'extreme' entry needs a measured baseline before you quote a number."
  value = {
    low     = length([for c in local.selected : c if try(local.log_catalog[c].tier, "") == "low"])
    medium  = length([for c in local.selected : c if try(local.log_catalog[c].tier, "") == "medium"])
    high    = length([for c in local.selected : c if try(local.log_catalog[c].tier, "") == "high"])
    extreme = length([for c in local.selected : c if try(local.log_catalog[c].tier, "") == "extreme"])
  }
}


