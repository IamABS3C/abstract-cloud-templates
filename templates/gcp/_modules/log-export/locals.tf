# Audit-stream selection is expressed as log_categories now (see log_catalog.tf).
# audit_streams is kept as a compatibility shim so existing tfvars keep working:
# each entry maps onto the equivalent catalog category.

locals {
  audit_stream_alias = {
    activity     = "admin_activity"
    system_event = "system_event"
    policy       = "policy_denied"
    data_access  = "data_access_all"
  }

  # Anything named in audit_streams is folded into log_categories.
  audit_derived_categories = [
    for s in var.audit_streams : lookup(local.audit_stream_alias, s, s)
  ]
}
