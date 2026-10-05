# Enable what this deployment needs, here rather than in 01-logging-project.
#
# Terraform fails PARTWAY when an API is missing — after creating some resources
# — and the error names the API rather than the fix. Enabling is idempotent and
# costs nothing, so every root owns its own dependencies.
#
# disable_on_destroy = false deliberately: disabling an API can break unrelated
# resources in the same project, and the failure surfaces far from the change.
resource "google_project_service" "required" {
  for_each = toset([
    "logging.googleapis.com",
    "storage.googleapis.com",
  ])
  project            = var.log_project
  service            = each.value
  disable_on_destroy = false
}
