variable "org_id" {
  description = "Organization ID. Required when sink_scope = organization. Find it with: gcloud organizations list"
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "Folder ID. Required when sink_scope = folder."
  type        = string
  default     = ""
}

variable "sink_scope" {
  description = <<-EOT
    Where the sink binds. THIS IS THE MOST CONSEQUENTIAL CHOICE IN THE MODULE.

      organization    Everything, current and future, by containment. The right answer
                      for almost everyone.
      folder          Same guarantee, narrower containment. Use when org scope is not
                      granted yet.
      project         ONE project. Does NOT cover future projects, and there is no
                      include_children below a project. Pilot only -- requires
                      acknowledge_pilot_scope = true so nobody ships it by accident.
      billing_account Billing account logs, which live OUTSIDE the resource hierarchy
                      and are NOT captured by an organization sink.
  EOT
  type        = string
  default     = "organization"

  validation {
    condition     = contains(["organization", "folder", "project", "billing_account"], var.sink_scope)
    error_message = "sink_scope must be one of: organization, folder, project, billing_account."
  }
}

variable "sink_project" {
  description = "Project to bind the sink to when sink_scope = project. Defaults to log_project."
  type        = string
  default     = ""
}

variable "billing_account_id" {
  description = "Billing account ID when sink_scope = billing_account. Find it with: gcloud billing accounts list"
  type        = string
  default     = ""
}

variable "acknowledge_pilot_scope" {
  description = "Required for sink_scope = project. A project sink does not cover future projects, which defeats the purpose of an aggregated sink. Set true only for a deliberate pilot."
  type        = bool
  default     = false
}


variable "log_project" {
  description = "DEDICATED logging/security project that hosts the topic and subscription. Do not use a workload project: Pub/Sub publish quota is consumed here, and a workload owner should not be able to read or break the security pipeline."
  type        = string

  validation {
    condition     = length(var.log_project) > 0
    error_message = "log_project is required."
  }
}

variable "audit_streams" {
  description = <<-EOT
    Which Cloud Audit Log streams to route. THE cost and value fork for the whole engagement.

      activity      Admin Activity — always on, free to generate, LOW volume. Every IAM change
                    and every resource create/delete/modify. Carries most control-plane detections.
      system_event  Always on, low volume.
      policy        Policy Denied. Always on, and charged.
      data_access   OFF BY DEFAULT and dominated by DATA_READ. BigQuery query bytes and GCS
                    object-level access — the exfiltration signal — exist nowhere else. On a
                    BigQuery-heavy estate this moves volume by 1-2 ORDERS OF MAGNITUDE.

    Routing is evaluated at WRITE TIME. There is no backfill. Start broader than you think you
    need for a 7-day baseline, then tighten — the reverse leaves a permanent hole.
  EOT
  type        = list(string)
  default     = ["activity", "system_event"]

  validation {
    condition     = length([for s in var.audit_streams : s if !contains(["activity", "system_event", "policy", "data_access"], s)]) == 0
    error_message = "audit_streams entries must be one of: activity, system_event, policy, data_access."
  }
}

variable "data_access_services" {
  description = <<-EOT
    When data_access is in audit_streams, restrict it to these services rather than the whole
    estate. Recommended opening position: bigquery.googleapis.com, storage.googleapis.com,
    cloudkms.googleapis.com, iamcredentials.googleapis.com, sts.googleapis.com, login.googleapis.com —
    captures data exfiltration and identity/auth token events without ingesting every routine read.
    Empty list means ALL services, which is the expensive option. Choose it deliberately.
  EOT
  type        = list(string)
  default     = ["bigquery.googleapis.com", "storage.googleapis.com", "cloudkms.googleapis.com", "iamcredentials.googleapis.com", "sts.googleapis.com", "login.googleapis.com"]
}

variable "platform_log_filters" {
  description = <<-EOT
    Extra Cloud Logging filter clauses OR-ed onto the audit filter. These are the high-value
    platform logs — all of them arrive through this same sink, because in GCP almost everything
    is a Cloud Logging entry.

      compute.googleapis.com%2Ffirewall     firewall rule hits — enabled PER RULE
      dns.googleapis.com%2Fdns_queries      best C2 and exfil signal in GCP — off by default
      compute.googleapis.com%2Fvpc_flows    VERY high volume; use the native sampling rate
      compute.googleapis.com%2Fnat_flows    egress attribution

    Deliberately EXCLUDES GKE container stdout/stderr, which is enormous and almost entirely
    not security signal.
  EOT
  type        = list(string)
  default     = []
}

variable "custom_filter" {
  description = "Complete override. When non-empty, audit_streams / data_access_services / platform_log_filters are ignored and this is used verbatim. Escape hatch for a filter the module cannot express."
  type        = string
  default     = ""
}

variable "exclusions" {
  description = "Sink exclusion filters for known noise — health checks, chatty service accounts. Exclusions cost NOTHING to evaluate while ingestion and Pub/Sub throughput are billed, so this is the cheapest cost lever available. Max 50 per sink."
  type = list(object({
    name        = string
    description = string
    filter      = string
  }))
  default = []
}

variable "topic_name" {
  type    = string
  default = "abstract-audit-logs"
}

variable "subscription_name" {
  type    = string
  default = "abstract-audit-logs-sub"
}

variable "sink_name" {
  type    = string
  default = "abstract-org-audit-sink"
}

variable "service_account_id" {
  type    = string
  default = "abstract-pubsub-reader"
}

variable "retention_days" {
  description = "Pub/Sub message retention. 7 days absorbs an Abstract-side outage without loss. This is your entire recovery window."
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 31
    error_message = "Pub/Sub message retention must be between 1 and 31 days."
  }
}

variable "ack_deadline_seconds" {
  type    = number
  default = 60
}

variable "enable_dead_letter" {
  description = "Create a dead-letter topic AND wire it to the subscription. Default false on purpose: a DLQ nobody reads converts a loud failure into a silent one. Enable it only alongside an alert on its depth."
  type        = bool
  default     = false
}

variable "dead_letter_max_delivery_attempts" {
  description = "Deliveries attempted before a message is dead-lettered. Pub/Sub requires 5-100."
  type        = number
  default     = 10

  validation {
    condition     = var.dead_letter_max_delivery_attempts >= 5 && var.dead_letter_max_delivery_attempts <= 100
    error_message = "max_delivery_attempts must be between 5 and 100 (Pub/Sub limit)."
  }
}

variable "create_service_account_key" {
  description = "Generate the service-account JSON key in Terraform. Default FALSE because it puts the private key in Terraform STATE. Prefer creating it out of band with gcloud and uploading it straight to Abstract."
  type        = bool
  default     = false
}

variable "labels" {
  type    = map(string)
  default = {}
}


variable "log_categories" {
  description = <<-EOT
    Named log sources to route, from the catalog in log_catalog.tf. Pick by intent;
    the module composes the filter. An unknown name FAILS AT PLAN rather than
    silently collecting nothing.

    Audit and identity : admin_activity, system_event, policy_denied, identity_access
    Kubernetes         : gke_control_plane, gke_container_logs
    Networking         : firewall, dns_queries, vpc_flows, nat_flows, load_balancer,
                         load_balancer_regional_internal
    Compute            : cloud_run, vm_guest
    Databases          : cloudsql
    Data plane         : data_access_all (prefer data_access_services to scope it)

    Default is the Tier-1 security set: control plane, Kubernetes admin, firewall
    and DNS. Small, high signal, and it delivers most detections on its own.
  EOT
  type        = list(string)
  default     = ["admin_activity", "system_event", "gke_control_plane", "firewall", "dns_queries"]
}

variable "acknowledge_high_volume" {
  description = "Required to select any 'extreme' tier category (vpc_flows, gke_container_logs, data_access_all). These can dominate the entire bill; measure a 7-day baseline first."
  type        = bool
  default     = false
}

# --- Security Command Center -------------------------------------------------




# --- GCS archive -------------------------------------------------------------






# --- Delivery mode -----------------------------------------------------------

variable "push_endpoint" {
  description = <<-EOT
    Optional Pub/Sub PUSH endpoint (HTTPS).

    LEAVE THIS EMPTY for Abstract. The Abstract GCP integration is a PULL consumer -- it
    authenticates with a service-account key and pulls from the subscription. Setting a
    push endpoint creates a subscription Abstract cannot read from, and the symptom is
    zero events with a perfectly healthy sink.

    Set it only when the destination is an HTTP collector that expects to be pushed to.
  EOT
  type        = string
  default     = ""
}

variable "push_service_account_email" {
  description = "Service account whose OIDC token signs push requests. Required when push_endpoint is set -- an unauthenticated push endpoint accepts anything that can reach it."
  type        = string
  default     = ""
}

# --- Google Workspace / Cloud Identity ---------------------------------------





