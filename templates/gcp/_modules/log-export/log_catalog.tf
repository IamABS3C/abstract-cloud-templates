# ---------------------------------------------------------------------------
# The log-source catalog.
#
# Every collectable GCP surface, as a named category with its exact filter
# clause and a volume tier. You pick categories by INTENT; the module composes
# the filter string.
#
# Why a catalog and not a free-text filter list: a hand-written Cloud Logging
# filter fails SILENTLY. A typo in a logName matches nothing, returns no error,
# and is indistinguishable from a broken sink — which costs days. Here a name
# that is not in the catalog fails at PLAN time with the valid list printed.
#
# Volume tiers are relative, not absolute. Measure before you quote.
#   low       collect always — small and high signal
#   medium    collect always — worth its cost
#   high      collect with intent — real money on a large estate
#   extreme   opt in deliberately; these can dominate the entire bill
# ---------------------------------------------------------------------------

locals {
  log_catalog = {
    # ---- Audit and identity ------------------------------------------------
    admin_activity = {
      clause = "logName:\"cloudaudit.googleapis.com%2Factivity\""
      tier   = "low"
      what   = "Every IAM change and every resource create/update/delete. The single highest-value stream in GCP. Always on, cannot be disabled, free to generate."
    }
    system_event = {
      clause = "logName:\"cloudaudit.googleapis.com%2Fsystem_event\""
      tier   = "low"
      what   = "Google-initiated actions — live migration, automatic restarts. Always on."
    }
    access_transparency = {
      clause = "logName:\"cloudaudit.googleapis.com%2Faccess_transparency\""
      tier   = "low"
      what   = "GOOGLE EMPLOYEE access to your data, with the justification. A named control in most cloud-security questionnaires, and tiny volume. Requires an eligible support tier or Assured Workloads — if that is not in place the stream simply does not exist and this collects nothing."
    }
    policy_denied = {
      clause = "logName:\"cloudaudit.googleapis.com%2Fpolicy\""
      tier   = "low"
      what   = "A service denied access due to a security-policy violation. Always on, but charged."
    }
    identity_access = {
      clause = "(logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND protoPayload.serviceName=(\"iamcredentials.googleapis.com\" OR \"sts.googleapis.com\" OR \"login.googleapis.com\" OR \"iap.googleapis.com\"))"
      tier   = "low"
      what   = "Authentication and identity events: service account impersonation (GenerateAccessToken), Workload Identity Federation (STS token exchange), Google Workspace shared login events, and Identity-Aware Proxy. Requires Data Access audit logging on these services."
    }

    # ---- Kubernetes --------------------------------------------------------
    gke_control_plane = {
      clause = "(logName:\"cloudaudit.googleapis.com%2Factivity\" AND protoPayload.serviceName=(\"k8s.io\" OR \"container.googleapis.com\"))"
      tier   = "medium"
      what   = "Pod exec, RBAC changes, privileged workload creation, cluster admin. The parser lifts pod-exec into process.command_line — the container-breakout precursor."
    }
    gke_container_logs = {
      clause = "resource.type=\"k8s_container\""
      tier   = "extreme"
      what   = "Application stdout/stderr from every pod. Usually a platform-observability concern, not a SOC one. Exclude unless a named detection needs it."
    }

    binary_authorization = {
      clause = "logName:\"binaryauthorization.googleapis.com%2Fcontinuous_validation\""
      tier   = "low"
      what   = "Unsigned or unattested container images admitted or blocked. A DISTINCT log ID from the Binary Authorization policy-change events, which are already in admin_activity — this is enforcement, those are configuration."
    }

    # ---- Networking --------------------------------------------------------
    firewall = {
      clause = "logName:\"compute.googleapis.com%2Ffirewall\""
      tier   = "medium"
      what   = "Denied and allowed connections against specific rules. Must be enabled PER FIREWALL RULE — the sink cannot turn it on."
    }
    dns_queries = {
      clause = "logName:\"dns.googleapis.com%2Fdns_queries\""
      tier   = "high"
      what   = "The best C2 and exfiltration signal in GCP. Off by default; enabled per VPC network policy."
    }
    vpc_flows = {
      clause = "logName:\"compute.googleapis.com%2Fvpc_flows\""
      tier   = "extreme"
      what   = "Enabled per subnet with a configurable SAMPLING RATE — sampling is the cost control, and it belongs at the subnet, not here. Unlike Azure, these genuinely can reach the streaming path."
    }
    nat_flows = {
      clause = "logName:\"compute.googleapis.com%2Fnat_flows\""
      tier   = "high"
      what   = "Egress attribution. Consider log translations only, or errors only."
    }
    load_balancer = {
      clause = "resource.type=\"http_load_balancer\""
      tier   = "high"
      what   = "Cloud Armor WAF decisions ride inside the load-balancer request logs."
    }
    # load_balancer above matches only the global external Application Load Balancer.
    # Regional external and internal (regional and cross-region) Application Load
    # Balancers write their request logs under different monitored-resource types:
    #   http_external_regional_lb_rule
    #     https://docs.cloud.google.com/load-balancing/docs/https/https-reg-logging-monitoring
    #   internal_http_lb_rule
    #     https://docs.cloud.google.com/load-balancing/docs/l7-internal/monitoring
    # A separate category, so selecting it never changes the filter of a sink that
    # already routes load_balancer.
    load_balancer_regional_internal = {
      clause = "resource.type=(\"http_external_regional_lb_rule\" OR \"internal_http_lb_rule\")"
      tier   = "high"
      what   = "Request logs, and the Cloud Armor decisions inside them, from regional external and internal Application Load Balancers. Logging is enabled per backend service."
    }

    # ---- Compute and serverless -------------------------------------------
    cloud_run = {
      clause = "resource.type=(\"cloud_run_revision\" OR \"cloud_function\")"
      tier   = "high"
      what   = "Request logs plus stdout/stderr. Application signal, not control plane."
    }
    vm_guest = {
      clause = "logName:\"compute.googleapis.com%2Fserial_port\""
      tier   = "high"
      what   = "Serial-port output from VMs. Narrowed deliberately: a bare resource.type=gce_instance also matches every log entry ATTRIBUTED to a VM org-wide, which is an extreme-tier volume wearing a high-tier label. For guest OS logs use a forwarder, not the Log Router."
    }

    # ---- Databases and data stores ----------------------------------------
    cloudsql = {
      clause = "logName:\"cloudsql.googleapis.com%2Fpostgres.log\" OR logName:\"cloudsql.googleapis.com%2Fmysql.err\" OR logName:\"cloudsql.googleapis.com%2Fsqlserver.err\""
      tier   = "high"
      what   = "Engine logs. Auth and admin events are already in admin_activity; these add query-level detail."
    }
  }

  # ---- Data Access, kept separate because it is the cost decision ---------
  # Off by default in GCP and enabled in the org IAM audit config, NOT here.
  # A clause referencing it matches nothing until that is done.
  wants_data_access = contains(distinct(concat(var.log_categories, local.audit_derived_categories)), "data_access_all")

  # Data Access is emitted ONLY when explicitly requested. Keying this off
  # data_access_services alone was a real bug: that variable has a non-empty
  # DEFAULT, so the clause was added even when nobody asked for it. Because
  # Data Access is off by default in GCP it matched nothing at first — then
  # would have started costing money the day someone enabled it org-wide for
  # an unrelated reason. Silent, delayed, and expensive.
  data_access_clause = !local.wants_data_access ? [] : (
    length(var.data_access_services) > 0
    ? ["(logName:\"cloudaudit.googleapis.com%2Fdata_access\" AND protoPayload.serviceName=(${join(" OR ", [for s in var.data_access_services : "\"${s}\""])}))"]
    : ["logName:\"cloudaudit.googleapis.com%2Fdata_access\""]
  )

  # ---- Resolution --------------------------------------------------------
  # Union of explicit categories and anything derived from the audit_streams shim.
  requested          = distinct(concat(var.log_categories, local.audit_derived_categories))
  selected           = [for c in local.requested : c if c != "data_access_all"]
  unknown_categories = [for c in local.selected : c if !contains(keys(local.log_catalog), c)]
  extreme_selected   = [for c in local.selected : c if try(local.log_catalog[c].tier, "") == "extreme"]

  catalog_clauses = [for c in local.selected : local.log_catalog[c].clause if contains(keys(local.log_catalog), c)]

  # Every clause is parenthesised before joining. A flat OR chain is correct only
  # while no clause contains a top-level AND -- several now do, and one more edit
  # would otherwise change operator precedence silently across the whole filter.
  all_clauses = [
    for c in concat(local.catalog_clauses, local.data_access_clause, local.extra_clauses) :
    substr(c, 0, 1) == "(" ? c : "(${c})"
  ]
  assembled_filter = join("\n  OR ", local.all_clauses)
  extra_clauses    = [for f in var.platform_log_filters : "logName:\"${f}\""]

  effective_filter = var.custom_filter != "" ? var.custom_filter : local.assembled_filter
}

# A category name that is not in the catalog would produce a filter matching
# nothing, with no error. Fail at plan instead.
resource "terraform_data" "validate_categories" {
  lifecycle {
    precondition {
      condition     = var.push_endpoint == "" || var.push_service_account_email != ""
      error_message = "push_endpoint requires push_service_account_email for OIDC. An unauthenticated push endpoint accepts anything that can reach it.\nNote: Abstract PULLS -- leave push_endpoint empty unless the destination is an HTTP collector."
    }
    precondition {
      condition     = var.sink_scope != "project" || var.acknowledge_pilot_scope
      error_message = "sink_scope = project covers ONE project and does not include future projects.\nThat defeats the point of an aggregated sink. For a deliberate pilot set acknowledge_pilot_scope = true, and schedule the org conversation."
    }
    precondition {
      condition     = var.sink_scope != "billing_account" || var.billing_account_id != ""
      error_message = "sink_scope = billing_account requires billing_account_id. Find it with: gcloud billing accounts list"
    }
    precondition {
      condition     = var.sink_scope != "folder" || var.folder_id != ""
      error_message = "sink_scope = folder requires folder_id."
    }
    precondition {
      condition     = var.sink_scope != "organization" || var.org_id != ""
      error_message = "sink_scope = organization requires org_id. Find it with: gcloud organizations list"
    }
    precondition {
      condition     = length(local.unknown_categories) == 0
      error_message = "Unknown log_categories: ${join(", ", local.unknown_categories)}.\nValid: ${join(", ", sort(keys(local.log_catalog)))}, data_access_all.\nAn unrecognised name would silently collect nothing."
    }
    precondition {
      condition     = var.acknowledge_high_volume || length(local.extreme_selected) == 0
      error_message = "These categories can dominate your entire bill: ${join(", ", local.extreme_selected)}.\nMeasure a 7-day baseline first. To proceed anyway set acknowledge_high_volume = true."
    }
    precondition {
      condition     = var.acknowledge_high_volume || !local.wants_data_access || length(var.data_access_services) > 0
      error_message = "data_access_all with an EMPTY data_access_services routes Data Access logs for every service, estate-wide.\nOn a BigQuery-heavy estate that moves total volume by one to two orders of magnitude.\nScope it (bigquery.googleapis.com, storage.googleapis.com) or set acknowledge_high_volume = true."
    }
  }
}
