output "workspace_onboarding" {
  description = "Everything needed to finish the Google Workspace integration — the delegation values for the Admin console, and the field values for Abstract."
  value = !var.enable_workspace ? null : {
    step_1_domain_wide_delegation = {
      where     = "admin.google.com → Security → Access and data control → API controls → Domain-wide delegation → Add new"
      client_id = try(google_service_account.workspace[0].unique_id, "(known after apply)")
      scopes    = join(",", local.workspace_scopes)
      note      = "Paste client_id into 'Client ID' and the scopes string into 'OAuth scopes' EXACTLY as shown, comma-separated with no spaces. Requires a Workspace SUPER ADMIN — a GCP Owner cannot do this."
    }
    step_2_create_key = {
      command = "mkdir -p ~/abstract-keys && chmod 700 ~/abstract-keys && gcloud iam service-accounts keys create ~/abstract-keys/abstract-workspace-key.json --iam-account=${try(google_service_account.workspace[0].email, "")} && chmod 600 ~/abstract-keys/abstract-workspace-key.json"
      note    = "Upload to Abstract, then DELETE the local copy. Not created in Terraform on purpose — it would put a private key in state."
    }
    step_3_abstract_integration = {
      integration      = "default.google_workspace (Event Source, PULL)"
      admin_email      = var.workspace_admin_email
      credentials      = "the JSON key from step 2 — must be under 1 MB"
      application_name = local.workspace_apps
    }
    service_account_email = try(google_service_account.workspace[0].email, "")
  }
}
output "workspace_applications_selected" {
  description = "Resolved Workspace applications after group expansion."
  value       = var.enable_workspace ? local.workspace_apps : []
}
