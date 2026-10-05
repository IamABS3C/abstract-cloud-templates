resource "terraform_data" "guards" {
  count = var.enable_scc_findings ? 1 : 0
  lifecycle {
    precondition {
      condition     = var.org_id != ""
      error_message = "SCC findings use an ORGANIZATION NotificationConfig, so org_id is required.\nSCC does not flow through the Log Router at all — no filter can collect it."
    }
    precondition {
      condition     = var.subscriber_service_account_email != ""
      error_message = "subscriber_service_account_email is required — pass the service account the log-export module created, so one identity reads both feeds."
    }
  }
}
