output "archive_bucket" {
  description = "Bucket the archive sink writes to."
  value       = try(google_storage_bucket.archive[0].name, null)
}

output "archive_writer_identity" {
  description = "The archive sink's writer identity. Distinct from the streaming sink's — each sink gets its own, and each needs its own grant."
  value       = try(google_logging_organization_sink.archive[0].writer_identity, null)
}
