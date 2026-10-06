# Audit logs, one project

<!-- Generated from template.yml by `python -m tools.templates generate`. Do not edit. -->

A project-scope sink that proves the whole pipeline end to end before organization-scope IAM is requested. It does not cover future or other projects; replace it with the organization sink once the pilot is proven.

**Cloud:** gcp · **Role:** source · **Scope:** project

![How Audit logs, one project fits together](diagram.png)

Editable source: [diagram.drawio](diagram.drawio)

## When to use

Proving the pipeline before asking for organization-scope IAM.

**Not for:** As a per-project pattern: deploy gcp-source-audit-logs-organization and delete this sink once the pilot is proven.

## Deploy

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/IamABS3C/abstract-cloud-templates&cloudshell_git_branch=main&cloudshell_workspace=templates/gcp/gcp-source-audit-logs-project&cloudshell_tutorial=TUTORIAL.md)

Or from a shell, in this folder:

```bash
./deploy.sh
```

## Prerequisites

- One project to pilot on

## Cost

Pub/Sub throughput for one project's audit logs.

## Parameters

| Name | Type | Required | Description | Find it |
|---|---|---|---|---|
| `org_id` | string | no | Organization ID. Optional for a project-scope pilot. | `gcloud organizations list --format='value(ID)'` |
| `sink_project` | string | no | The ONE project whose logs are exported. Defaults to log_project. |  |
| `log_project` | string | yes | DEDICATED logging or security project holding the topic and subscription. Not a workload project — Pub/Sub publish quota is consumed here, and a workload owner should not be able to read or break the security pipeline. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with templates/gcp/gcp-foundation-logging-project (set create_project = true) — do not point this at a workload project. | `gcloud projects list --format='value(projectId)'` |
| `log_categories` | array | no | Named sources to route. See _modules/log-export/log_catalog.tf for the catalog. |  |
| `data_access_services` | array | no | When data_access_all is in log_categories, restrict Data Access logs to these services rather than the whole estate. Empty means allServices, the expensive option. |  |
| `exclusions` | array | no | Sink exclusion filters for known noise (health checks, chatty service accounts). Exclusions cost nothing to evaluate while ingestion and Pub/Sub throughput are billed, so this is the cheapest cost lever. Max 50 per sink. |  |
| `acknowledge_high_volume` | bool | no | Required to select any extreme-tier category (vpc_flows, gke_container_logs, data_access_all). These can dominate the bill; measure a 7-day baseline first. |  |
| `labels` | object | no | Labels applied to every resource this template creates. |  |
| `retention_days` | int | no | Pub/Sub message retention, 1-31. THIS IS YOUR ENTIRE RECOVERY WINDOW: when the oldest unacked message reaches it, the data is deleted permanently with no error and no backfill. 7 gives you a long weekend. |  |
| `ack_deadline_seconds` | int | no | Pub/Sub ack deadline for Abstract's subscription, in seconds. |  |
| `enable_dead_letter` | bool | no | Send repeatedly-failing messages to a dead-letter topic instead of retrying forever. Pair it with gcp-monitoring-pipeline-health-alerts — a dead-letter topic nobody watches converts a loud failure into a silent one. |  |
| `dead_letter_max_delivery_attempts` | int | no | Deliveries attempted before a message is dead-lettered (Pub/Sub allows 5-100). Used only with enable_dead_letter. |  |
| `topic_name` | string | no | Renaming this FORCE-REPLACES the topic and cascades to the subscription, discarding every un-acked message. prevent_destroy blocks it; that is intentional. |  |
| `subscription_name` | string | no | Pull subscription Abstract reads. Renaming it replaces the subscription. |  |
| `sink_name` | string | no | Name of the Cloud Logging sink. |  |
| `service_account_id` | string | no | Account ID of the service account Abstract authenticates as (roles/pubsub.subscriber on the subscription only). |  |
| `custom_filter` | string | no | Replace the assembled filter entirely. Bypasses every guard in the catalog -- you own the volume. |  |
| `platform_log_filters` | array | no | Extra raw logName clauses the catalog does not cover, e.g. cloudaudit.googleapis.com%2Faccess_transparency |  |

## Permissions

- **roles/logging.configWriter** on The project: Deployer: Create the project sink.
- **roles/pubsub.admin** on The logging project: Deployer: Create the topic, subscription and IAM bindings.
- **roles/iam.serviceAccountAdmin** on The logging project: Deployer: Create Abstract's service account.
- **roles/serviceusage.serviceUsageAdmin** on The logging project: Deployer: Enable APIs.
- **roles/pubsub.publisher** on The topic: Sink writer identity: Created with the sink and holding nothing until granted; this module grants it.
- **roles/pubsub.subscriber** on The subscription only: Abstract service account: Abstract pulls; not publisher, not project-wide.

## Creates

- A Pub/Sub topic (default abstract-audit-logs) and a never-expiring pull subscription (default abstract-audit-logs-sub, 7-day retention)
- The roles/pubsub.publisher binding for the sink's writer identity
- A service account (default abstract-pubsub-reader) with roles/pubsub.subscriber on the subscription only
- Optional dead-letter topic (enable_dead_letter, off by default)
- A project sink, acknowledged as pilot scope

## Never touches

- Other projects, and projects created later: a project sink has no include_children

## Outputs

- `abstract_onboarding`
- `effective_filter`
- `selected_log_sources`
- `sink_writer_identity`
- `volume_profile`

## Verify

| Check | Command | Healthy when |
|---|---|---|
| A fresh event flows end to end | `PROBE=abstract-probe-$(date +%s) gcloud pubsub subscriptions create "$PROBE" --topic=abstract-audit-logs --project=<log-project-id> --expiration-period=1d gcloud pubsub topics create abstract-probe-topic --project=<log-project-id> --quiet gcloud pubsub topics delete abstract-probe-topic --project=<log-project-id> --quiet sleep 75 gcloud pubsub subscriptions pull "$PROBE" --project=<log-project-id> --limit=5 --auto-ack gcloud pubsub subscriptions delete "$PROBE" --project=<log-project-id> --quiet` | Your own CreateTopic and DeleteTopic arrive on the probe subscription with principalEmail, resourceName and callerIp populated. Wait five minutes after creating the sink before testing. Never pull from Abstract's own subscription: --auto-ack there deletes events before Abstract reads them. |
| No sink errors | `gcloud logging read 'logName:"logging.googleapis.com%2Fsink_error"' --limit=20 --project=<log-project-id>` | No sink_error entries. |
