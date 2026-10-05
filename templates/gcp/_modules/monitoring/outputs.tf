output "alert_policies" {
  description = "The policies created. Four failure modes, each otherwise silent."
  value = {
    sink_cannot_publish = google_monitoring_alert_policy.sink_errors.name
    consumer_stalled    = google_monitoring_alert_policy.consumer_stalled.name
    feed_went_dark      = google_monitoring_alert_policy.feed_dark.name
    dead_letter         = try(google_monitoring_alert_policy.dead_letter[0].name, null)
  }
}
