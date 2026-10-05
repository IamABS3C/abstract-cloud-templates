resource "google_project_service" "required" {
  for_each = toset([
    "cloudasset.googleapis.com",
    "pubsub.googleapis.com",
  ])
  project            = var.log_project
  service            = each.value
  disable_on_destroy = false
}
