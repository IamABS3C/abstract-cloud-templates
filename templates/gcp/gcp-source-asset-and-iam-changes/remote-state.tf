# Take Abstract's identity from 02-audit-logs-organization's STATE rather than a hand-copy.
#
# Every cross-root value in this repo was previously a string a human retyped,
# which drifts silently the moment either side changes. This reads it.
#
# Optional by design: `remote_state_bucket = ""` falls back to the literal, so a
# customer without a shared backend is not blocked — they just carry the
# hand-copy risk knowingly instead of accidentally.
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
    error_message = "Could not resolve Abstract's service account.\nEither set remote_state_bucket + remote_state_prefix to read it from 02-audit-logs-organization's state, or paste subscriber_service_account_email directly."
  }
}
