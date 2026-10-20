output "scc_topic" { value = module.scc.scc_topic }
output "scc_subscription" { value = module.scc.scc_subscription }

output "abstract_onboarding" {
  description = "Values for Abstract's GCP Pub/Sub Source: a configuration of its own for this subscription, read with the audit-log reader account."
  value = {
    project_id      = var.log_project
    subscription_id = module.scc.scc_subscription
  }
}
