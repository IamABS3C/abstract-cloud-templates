# Google Cloud alerts when the Abstract feed stalls

<!-- Generated from template.yml by `python -m tools.templates generate`. Do not edit. -->

A stalled consumer, a missing IAM grant and a deleted sink all look the same from outside: everything is green and there is no data. These Cloud Monitoring alert policies catch sink export failures, an unconsumed subscription, a feed that went dark and a receiving dead-letter topic.

**Cloud:** gcp · **Role:** monitoring · **Scope:** project

![How Google Cloud alerts when the Abstract feed stalls fits together](diagram.png)

Editable source: [diagram.drawio](diagram.drawio)

## When to use

Alongside gcp-source-audit-logs-organization, not later.

**Not for:** As a replacement for checking the feed in Abstract; these watch the Google side only.

Not sure this is the right one, or what to deploy before it? Answer a few questions in [the setup guide](https://github.com/IamABS3C/abstract-cloud-templates/blob/main/docs/gcp/GUIDE.md).

## Deploy

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/IamABS3C/abstract-cloud-templates&cloudshell_git_branch=main&cloudshell_workspace=templates/gcp/gcp-monitoring-pipeline-health-alerts&cloudshell_tutorial=TUTORIAL.md)

Or from a shell, in this folder:

```bash
./deploy.sh
```

In Cloud Shell, create `backend.tf` first (TUTORIAL.md, the Terraform section, step 1): the session's files, Terraform state included, are deleted when it ends, so `./deploy.sh` stops there without it.

## Prerequisites

- A notification channel; the module refuses to deploy without one unless explicitly acknowledged
- The log-export pipeline deployed, ideally in the same session as connecting Abstract

## Cost

Alert policies are free; Cloud Monitoring bills only for metrics beyond the free allotment, which these do not add.

## Parameters

| Name | Type | Required | Description | Find it |
|---|---|---|---|---|
| `log_project` | string | yes | DEDICATED logging or security project holding this pipeline. Not a workload project. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with templates/gcp/gcp-foundation-logging-project (set create_project = true). | `gcloud projects list --format='value(projectId)'` |
| `topic_id` | string | no | Topic NAME (not the full path), from gcp-source-audit-logs-organization. |  |
| `subscription_id` | string | no | Subscription NAME (not the full path), from gcp-source-audit-logs-organization. |  |
| `dead_letter_topic_id` | string | no | Dead-letter topic to watch. Empty disables that policy. |  |
| `notification_channels` | array | no | Channel IDs. List them with: gcloud beta monitoring channels list --format='value(name)' |  |
| `acknowledge_no_channel` | bool | no | Deploy the policies with no notification channel. They then fire into nothing; set it only while a channel is being arranged. |  |
| `retention_days` | int | no | Pub/Sub message retention in days. This is the entire recovery window: unacked messages older than this are deleted. |  |
| `unacked_age_threshold_seconds` | int | no | Fire when the oldest unacked message is older than this. Default one hour, a small fraction of a 7-day window. |  |
| `absence_threshold_seconds` | int | no | Fire when nothing has been published for this long. Default one hour. |  |
| `prefix` | string | no | Alert display-name prefix, so the policies are findable among existing ones. |  |

## Permissions

- **roles/monitoring.editor** on The logging project: Deployer: Create the alert policies.
- **roles/serviceusage.serviceUsageAdmin** on The logging project: Deployer: Turn on the APIs this template uses. Terraform reads which are on and turns on only those still off.

## Creates

- An alert policy for the sink failing to export (critical)
- An alert policy for Abstract not consuming, firing at one hour against the retention window (critical)
- An alert policy for the feed going dark, using a metric-absence condition (error)
- An alert policy for the dead-letter topic receiving messages (warning)

## Never touches

- The topic, subscription and sink it watches
- Existing alert policies and notification channels

## Outputs

- `alert_policies`

## Verify

These read, and change nothing. They use LOG_PROJECT from the guided setup's answers: run `source ~/.abstract-gcp-setup.env` first, or `export` each one. An UPPERCASE word such as YOUR_BUCKET or BILLING_ACCOUNT_ID is yours to replace.

| Check | Command | Healthy when |
|---|---|---|
| Every policy is enabled and wired to a channel | `curl -s "https://monitoring.googleapis.com/v3/projects/$LOG_PROJECT/alertPolicies" -H "Authorization: Bearer $(gcloud auth print-access-token)"` | Each "Abstract log pipeline" policy shows enabled true and at least one notification channel. |
| The stall alert before Abstract is connected |  | It fires, correctly, because nothing consumes the subscription yet. |

## Google documentation

Google's own pages on what this template sets up:

- [Alerting overview](https://docs.cloud.google.com/monitoring/alerts)
- [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui)
- [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).
- [Google Cloud metrics: P through Z](https://docs.cloud.google.com/monitoring/api/metrics_gcp_p_z#gcp-pubsub)
- [Create and manage notification channels](https://docs.cloud.google.com/monitoring/support/notification-options)
