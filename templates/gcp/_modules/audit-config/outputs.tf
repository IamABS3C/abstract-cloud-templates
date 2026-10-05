output "enabled" {
  description = "Resolved audit configuration."
  value = {
    scope            = var.scope
    services         = local.services
    log_types        = local.log_types
    exempted_members = var.exempted_members
    note             = "Admin Activity is always on and is not managed here. Only Data Access is."
  }
}
