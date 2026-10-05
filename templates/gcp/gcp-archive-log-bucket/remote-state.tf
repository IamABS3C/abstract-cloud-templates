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
  # The archive filter MUST match the stream, or the archive quietly captures
  # less than the stream and you trust it anyway during an investigation.
  stream_filter_resolved = var.remote_state_bucket != "" ? try(
    data.terraform_remote_state.log_export[0].outputs.effective_filter,
    var.stream_filter
  ) : var.stream_filter

  archive_filter = local.stream_filter_resolved != "" ? local.stream_filter_resolved : var.filter
}
