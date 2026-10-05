# ---------------------------------------------------------------------------
# Alerting on the pipeline itself.
#
# Everything else in this repo documents silent failures. This is what catches
# them. Without it the design is honest about the risk and does nothing about
# it, which is worse than not knowing — the docs create confidence the runtime
# does not earn.
#
# THE ONE THAT MATTERS MOST is oldest_unacked_message_age. Pub/Sub retention is
# your ENTIRE recovery window: when it expires, the data is gone permanently,
# with no error and no backfill. Alerting at a fraction of that window is the
# difference between an incident and a data-loss event.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

locals {
  channels = var.notification_channels
}

# 1. The sink cannot publish.
#    Catches the missing writer-identity grant AND publish-quota exhaustion.
#    When a sink cannot publish, Cloud Logging DROPS the entry — no retry, no
#    backfill. This is the only signal that it happened.
resource "google_monitoring_alert_policy" "sink_errors" {
  project      = var.log_project
  display_name = "${var.prefix} — log sink is failing to export"
  combiner     = "OR"

  conditions {
    display_name = "exports/error_count > 0"
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/exports/error_count\" AND resource.type=\"logging_sink\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  documentation {
    content   = "The Cloud Logging sink is failing to export. Almost always the sink's writer identity lacks roles/pubsub.publisher on the topic, or Pub/Sub publish quota in the DESTINATION project is exhausted.\n\nLog entries that fail to export are DROPPED. There is no retry and no backfill, so every minute this is firing is permanently lost data.\n\nCheck: gcloud logging sinks describe SINK --organization=ORG --format='value(writerIdentity)' then the topic's IAM policy."
    mime_type = "text/markdown"
  }

  notification_channels = local.channels
  severity              = "CRITICAL"
}

# 2. Abstract has stopped consuming — THE most important alert here.
resource "google_monitoring_alert_policy" "consumer_stalled" {
  project      = var.log_project
  display_name = "${var.prefix} — Abstract is not consuming (data loss pending)"
  combiner     = "OR"

  conditions {
    display_name = "oldest unacked message older than ${var.unacked_age_threshold_seconds}s"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" AND resource.type=\"pubsub_subscription\" AND resource.label.\"subscription_id\"=\"${var.subscription_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.unacked_age_threshold_seconds
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  documentation {
    content   = "Messages are sitting unacknowledged. Abstract is not consuming, or cannot.\n\n**This is a countdown, not a warning.** Pub/Sub retention is ${var.retention_days} days. When the oldest message reaches that age it is DELETED and the data is gone permanently — no error, no backfill.\n\nThis alert fires at ${var.unacked_age_threshold_seconds}s, deliberately a small fraction of the window, so there is time to act.\n\nCheck the Abstract integration's credentials and status first; the cloud side is almost certainly fine if this alert fired and the sink-error alert did not."
    mime_type = "text/markdown"
  }

  notification_channels = local.channels
  severity              = "CRITICAL"
}

# 3. The feed went dark.
#    Absence of data is the failure this whole repo is about, and a metric
#    threshold cannot catch "nothing arrived" — the metric simply stops being
#    written. A MetricAbsence condition can.
resource "google_monitoring_alert_policy" "feed_dark" {
  project      = var.log_project
  display_name = "${var.prefix} — no logs published for ${var.absence_threshold_seconds}s"
  combiner     = "OR"

  conditions {
    display_name = "topic send_request_count absent"
    condition_absent {
      filter   = "metric.type=\"pubsub.googleapis.com/topic/send_request_count\" AND resource.type=\"pubsub_topic\" AND resource.label.\"topic_id\"=\"${var.topic_id}\""
      duration = "${var.absence_threshold_seconds}s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  documentation {
    content   = "Nothing has been published to the topic. Either the estate genuinely went quiet — implausible for org-wide audit logs — or the sink was deleted, disabled, or its filter was narrowed to match nothing.\n\nA narrowed filter is the likeliest cause and the hardest to spot, because routing is evaluated at WRITE TIME: the logs are not queued anywhere, they were simply never routed, and they cannot be recovered later."
    mime_type = "text/markdown"
  }

  notification_channels = local.channels
  severity              = "ERROR"
}

# 4. Something reached the dead-letter topic.
#    A DLQ nobody reads is worse than no DLQ: it converts a loud failure into a
#    silent one and adds storage cost for the privilege.
resource "google_monitoring_alert_policy" "dead_letter" {
  count        = var.dead_letter_topic_id == "" ? 0 : 1
  project      = var.log_project
  display_name = "${var.prefix} — messages arriving in the dead-letter topic"
  combiner     = "OR"

  conditions {
    display_name = "dead-letter topic receiving messages"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/topic/send_request_count\" AND resource.type=\"pubsub_topic\" AND resource.label.\"topic_id\"=\"${var.dead_letter_topic_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  documentation {
    content   = "Messages are being dead-lettered — Abstract repeatedly failed to process them.\n\nA dead-letter topic that nobody reads is worse than none: it turns a loud failure into a silent one and charges you for the storage. This alert is what makes it worth having."
    mime_type = "text/markdown"
  }

  notification_channels = local.channels
  severity              = "WARNING"
}

resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = length(var.notification_channels) > 0 || var.acknowledge_no_channel
      error_message = "No notification_channels. These policies would fire into the void — the same failure mode as an Action Group with a dead webhook, and indistinguishable from having no alerting at all until the day it matters.\nCreate a channel (gcloud beta monitoring channels create) or set acknowledge_no_channel = true if you are wiring them by hand."
    }
    precondition {
      condition     = var.unacked_age_threshold_seconds < var.retention_days * 86400
      error_message = "unacked_age_threshold_seconds (${var.unacked_age_threshold_seconds}) is not less than the retention window (${var.retention_days * 86400}s).\nAn alert that fires only once retention has already expired tells you about data you have already lost. Set it to a fraction of the window — the default is 1 hour."
    }
  }
}
