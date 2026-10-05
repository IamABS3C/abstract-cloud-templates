resource "terraform_data" "guards" {
  count = var.enable_gcs_archive ? 1 : 0
  lifecycle {
    precondition {
      condition     = var.archive_bucket_name != ""
      error_message = "enable_gcs_archive requires archive_bucket_name (globally unique across all of GCS)."
    }
    precondition {
      condition     = var.sink_scope == "organization"
      error_message = "The archive sink is organization-scope only for now. Open an issue if you need folder or project scope."
    }
  }
}
