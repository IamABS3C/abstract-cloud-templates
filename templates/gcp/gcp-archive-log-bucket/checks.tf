# With remote state configured the filter is READ from 02-audit-logs-organization and cannot
# diverge. Without it, this asserts the hand-copy still matches.
check "archive_filter_matches_stream" {
  assert {
    condition     = local.archive_filter != ""
    error_message = "No filter resolved. Set remote_state_bucket to read it from 02-audit-logs-organization, or pass `filter` explicitly."
  }
}

check "hand_copy_matches_when_used" {
  assert {
    condition     = var.remote_state_bucket != "" || var.stream_filter == "" || trimspace(var.filter) == trimspace(var.stream_filter)
    error_message = "filter does not match stream_filter — the archive would capture a DIFFERENT set of logs from the streaming sink.\nBetter: set remote_state_bucket and stop hand-copying it."
  }
}
