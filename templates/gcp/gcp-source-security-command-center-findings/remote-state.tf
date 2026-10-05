# Read cross-root values from 02-audit-logs-organization's STATE rather than a hand-copy.
# A retyped string drifts silently the moment either side changes; this cannot.
# Optional: leave remote_state_bucket empty and the literal is used instead, so a
# customer without a shared backend is not blocked — they just carry the risk
# knowingly rather than accidentally.
data "terraform_remote_state" "log_export" {
  count   = var.remote_state_bucket == "" ? 0 : 1
  backend = "gcs"
  config = {
    bucket = var.remote_state_bucket
    prefix = var.remote_state_prefix
  }
}

locals {
  subscriber_email = var.remote_state_bucket != "" ? try(
    data.terraform_remote_state.log_export[0].outputs.abstract_onboarding.service_account_email,
    var.subscriber_service_account_email
  ) : var.subscriber_service_account_email
}

check "subscriber_identity_resolved" {
  assert {
    condition     = local.subscriber_email != ""
    error_message = "Could not resolve Abstract's service account. Set remote_state_bucket, or paste subscriber_service_account_email."
  }
}
