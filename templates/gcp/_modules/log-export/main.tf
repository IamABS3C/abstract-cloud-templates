# =============================================================================
#  Abstract Security — GCP org-wide log onboarding
#  One aggregated sink carries the whole estate: Cloud Audit Logs, GKE audit,
#  VPC flow, firewall, Cloud SQL, BigQuery, IAM, Cloud Run — into one Pub/Sub
#  topic and one Abstract integration.
#
#  Projects created later are in scope AUTOMATICALLY, because an aggregated
#  sink's scope is containment, not an enumerated project list.
#
#  Provenance: schema-reviewed. Written to the current google provider surface
#  and cross-checked against vendor docs; NOT applied against a live project.
#  Run: terraform init && terraform validate && terraform plan
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# -----------------------------------------------------------------------------
# 1. Topic + subscription, in a DEDICATED logging project.
#    Not a workload project: Pub/Sub publish quota is consumed here, and a
#    workload owner should not be able to read or break the security pipeline.
# -----------------------------------------------------------------------------

resource "google_pubsub_topic" "abstract" {
  # Renaming topic_name FORCE-REPLACES this topic and cascades to the
  # subscription, silently discarding every message not yet acknowledged —
  # which on this pipeline is unrecovered security telemetry, and there is no
  # backfill. create_before_destroy narrows the window; prevent_destroy stops
  # a stray `destroy` taking the pipeline with it.
  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
  }

  project = var.log_project
  name    = var.topic_name
  labels  = var.labels
}

resource "google_pubsub_subscription" "abstract" {
  # The subscription IS the buffer. Destroying it drops everything not yet
  # pulled, with no error and no way back.
  lifecycle {
    prevent_destroy = true
  }


  # Push is OPT-IN and wrong for Abstract, which pulls. A push subscription
  # produces a feed Abstract cannot read, and the symptom is zero events with a
  # healthy sink -- so the OIDC token is mandatory rather than optional: an
  # unauthenticated push endpoint accepts anything that can reach it.
  dynamic "push_config" {
    for_each = var.push_endpoint != "" ? [1] : []
    content {
      push_endpoint = var.push_endpoint
      oidc_token {
        service_account_email = var.push_service_account_email
      }
    }
  }

  project = var.log_project
  name    = var.subscription_name
  topic   = google_pubsub_topic.abstract.id
  labels  = var.labels

  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = "${var.retention_days * 24 * 60 * 60}s"

  # An empty ttl means NEVER EXPIRE. This is not cosmetic: the Pub/Sub default
  # deletes a subscription after 31 days of inactivity, so a quiet pilot over a
  # holiday silently destroys the feed and nothing reports an error.
  expiration_policy {
    ttl = ""
  }

  # Retry rather than drop on transient consumer failure.
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Wiring the policy is what actually makes dead-lettering happen. An earlier version of
  # this module created the dead-letter TOPIC and never referenced it here, so
  # enable_dead_letter = true produced an orphan topic and no dead-lettering at all — worse
  # than the feature being absent, because it looked like it worked.
  dynamic "dead_letter_policy" {
    for_each = var.enable_dead_letter ? [1] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter[0].id
      max_delivery_attempts = var.dead_letter_max_delivery_attempts
    }
  }
}

# Optional dead-letter topic. Off by default because a DLQ nobody reads is worse than none —
# it converts a loud failure into a silent one. Enable it only alongside an alert on its depth.
resource "google_pubsub_topic" "dead_letter" {
  count   = var.enable_dead_letter ? 1 : 0
  project = var.log_project
  name    = "${var.topic_name}-dead-letter"
  labels  = var.labels
}

# Dead-lettering is performed by the Pub/Sub SERVICE agent, not by the subscriber. It needs
# publisher on the dead-letter topic and subscriber on the source subscription, or messages
# that exceed max_delivery_attempts are simply retried forever instead of being dead-lettered
# — which is the same silent non-behaviour as not wiring the policy at all.
resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  count   = var.enable_dead_letter ? 1 : 0
  project = var.log_project
  topic   = google_pubsub_topic.dead_letter[0].id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.log.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "dead_letter_subscriber" {
  count        = var.enable_dead_letter ? 1 : 0
  project      = var.log_project
  subscription = google_pubsub_subscription.abstract.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.log.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Needed for the Pub/Sub service-agent address above.
data "google_project" "log" {
  project_id = var.log_project
}

# -----------------------------------------------------------------------------
# 2. The aggregated sink. --include-children is what makes it AGGREGATED.
# -----------------------------------------------------------------------------

resource "google_logging_organization_sink" "abstract" {
  lifecycle { prevent_destroy = true }

  count  = var.sink_scope == "organization" ? 1 : 0
  name   = var.sink_name
  org_id = var.org_id

  destination      = "pubsub.googleapis.com/${google_pubsub_topic.abstract.id}"
  include_children = true
  filter           = local.effective_filter

  dynamic "exclusions" {
    for_each = var.exclusions
    content {
      name        = exclusions.value.name
      description = exclusions.value.description
      filter      = exclusions.value.filter
    }
  }
}

resource "google_logging_folder_sink" "abstract" {
  lifecycle { prevent_destroy = true }

  count  = var.sink_scope == "folder" ? 1 : 0
  name   = var.sink_name
  folder = var.folder_id

  destination      = "pubsub.googleapis.com/${google_pubsub_topic.abstract.id}"
  include_children = true
  filter           = local.effective_filter

  dynamic "exclusions" {
    for_each = var.exclusions
    content {
      name        = exclusions.value.name
      description = exclusions.value.description
      filter      = exclusions.value.filter
    }
  }
}

resource "google_logging_project_sink" "abstract" {
  lifecycle { prevent_destroy = true }

  count   = var.sink_scope == "project" ? 1 : 0
  name    = var.sink_name
  project = var.sink_project != "" ? var.sink_project : var.log_project

  destination = "pubsub.googleapis.com/${google_pubsub_topic.abstract.id}"
  filter      = local.effective_filter

  # A project sink has no include_children -- there is nothing below a project.
  # This scope does NOT cover future projects. It is a pilot, and it should be
  # replaced by an org or folder sink before go-live.
  unique_writer_identity = true

  dynamic "exclusions" {
    for_each = var.exclusions
    content {
      name        = exclusions.value.name
      description = exclusions.value.description
      filter      = exclusions.value.filter
    }
  }
}

# Billing account logs live OUTSIDE the resource hierarchy entirely -- an org
# sink does not capture them, which surprises people who assume org scope means
# everything. Separate resource, separate writer identity.
resource "google_logging_billing_account_sink" "abstract" {
  lifecycle { prevent_destroy = true }

  count           = var.sink_scope == "billing_account" ? 1 : 0
  name            = var.sink_name
  billing_account = var.billing_account_id

  destination = "pubsub.googleapis.com/${google_pubsub_topic.abstract.id}"
  filter      = local.effective_filter

  dynamic "exclusions" {
    for_each = var.exclusions
    content {
      name        = exclusions.value.name
      description = exclusions.value.description
      filter      = exclusions.value.filter
    }
  }
}

locals {
  # one() rather than a ternary with [0], deliberately.
  #
  # HCL evaluates BOTH arms of a conditional and then discards the diagnostics of the
  # unselected one — verified against hcl v2.0.0 / v2.16.2 / v2.24.0 and the OpenTofu fork,
  # and confirmed live on OpenTofu v1.12.5. So `cond ? org[0].x : folder[0].x` does work
  # here, because sink_scope is constrained by a validation block to exactly the two values
  # that guarantee one arm has an element.
  #
  # But it is safe only for that reason, and it fails loudly the moment the constraint is
  # relaxed: with any third value both counts become 0 and the TAKEN arm errors with
  # "Invalid index ... is empty tuple". one() returns null on an empty collection instead,
  # so coalesce picks whichever sink actually exists and the expression cannot be broken by
  # a future edit to the variable.
  writer_identity = coalesce(
    one(google_logging_organization_sink.abstract[*].writer_identity),
    one(google_logging_folder_sink.abstract[*].writer_identity),
    one(google_logging_project_sink.abstract[*].writer_identity),
    one(google_logging_billing_account_sink.abstract[*].writer_identity),
  )
}

# -----------------------------------------------------------------------------
# 3. Let the sink publish.
#
#    THE #1 CAUSE OF "the sink exists and nothing arrives". The sink runs as its
#    own service identity, created with the sink, holding NO permissions at all
#    until this binding exists. Unlike other clouds GCP does tell you: watch
#    logging.googleapis.com/exports/error_count and the daily [ACTION REQUIRED]
#    email — but only if somebody is looking.
# -----------------------------------------------------------------------------

resource "google_pubsub_topic_iam_member" "sink_writer" {
  project = var.log_project
  topic   = google_pubsub_topic.abstract.id
  role    = "roles/pubsub.publisher"
  member  = local.writer_identity
}

# -----------------------------------------------------------------------------
# 4. The identity Abstract authenticates as.
#    SUBSCRIBER on the SUBSCRIPTION — not publisher, and not project-wide.
#    Abstract PULLS; it never publishes.
# -----------------------------------------------------------------------------

resource "google_service_account" "abstract" {
  project      = var.log_project
  account_id   = var.service_account_id
  display_name = "Abstract Security log reader"
  description  = "Pulls Cloud Logging entries from the Abstract Pub/Sub subscription. Least privilege: subscriber on one subscription."
}

resource "google_pubsub_subscription_iam_member" "abstract" {
  project      = var.log_project
  subscription = google_pubsub_subscription.abstract.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.abstract.email}"
}

# Key creation is opt-in. There is no Workload Identity Federation option on the
# Abstract GCP Pub/Sub source today (three fields: project_id, subscription_id,
# credentials), so a static key is currently the only path — but generating it
# through Terraform puts the private key in STATE. Prefer creating it out of band.
resource "google_service_account_key" "abstract" {
  count              = var.create_service_account_key ? 1 : 0
  service_account_id = google_service_account.abstract.name
}
