# Asset and IAM changes to Abstract: asset feed

<!-- Generated from template.yml by `python -m tools.templates generate`. Do not edit. -->

> [!NOTE]
> Abstract keeps these records only when the GCP Pub/Sub Source configuration for this subscription runs the extended GCP Pub/Sub parser, whose asset sub-parser comes from this template's parsers/cloud-asset-inventory.yml: it stores each IAM policy change as gcp.asset_inventory with action iam_policy_grant, iam_policy_revoke or iam_policy_change. The managed parser as shipped keeps Cloud Audit Logs only and stored none of them in a test. The extended parser is not in the managed integration yet; until it is, Abstract applies it to this configuration's parsers.

<picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/docs/brand/abstract-logo-white.svg"><img src="https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/docs/brand/abstract-logo-black.svg" alt="Abstract Security" height="40"></picture>

Cloud Asset Inventory publishes to Pub/Sub through its own feed, which no log sink can carry. It records what an IAM policy now is and what it was before, the diff a detection wants, alongside the audit log of who called which API.

**Cloud:** gcp · **Role:** source · **Scope:** organization

![How Asset and IAM changes to Abstract: asset feed fits together](diagram.png)

Editable source: [diagram.drawio](diagram.drawio)

## When to use

Alongside gcp-source-audit-logs-organization, for policy diffs and asset inventory.

**Not for:** As a replacement for the audit-log sink; the two answer different questions. Configure it as a GCP Pub/Sub Source configuration of its own in Abstract.

Not sure this is the right one, or what to deploy before it? Answer a few questions in [the setup guide](https://github.com/IamABS3C/abstract-cloud-templates/blob/main/docs/gcp/GUIDE.md).

## Deploy

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/IamABS3C/abstract-cloud-templates&cloudshell_git_branch=main&cloudshell_workspace=templates/gcp/gcp-source-asset-and-iam-changes&cloudshell_tutorial=TUTORIAL.md)

Or from a shell, in this folder:

```bash
./deploy.sh
```

In Cloud Shell, create `backend.tf` first (TUTORIAL.md, the Terraform section, step 1): the session's files, Terraform state included, are deleted when it ends, so `./deploy.sh` stops there without it.

## Prerequisites

- Abstract's service account from gcp-source-audit-logs-organization, read from its state or pasted as subscriber_service_account_email
- An empty asset_types feeds every asset type and is refused without acknowledge_all_asset_types
- roles/cloudasset.owner at the organization, and the Cloud Asset API on the billing project, whose service agent (service-PROJECT_NUMBER@gcp-sa-cloudasset.iam.gserviceaccount.com, with PROJECT_NUMBER that project's number) publishes
- One GCP Pub/Sub Source configuration in Abstract for this subscription, running the extended GCP Pub/Sub parser: never this subscription on the audit-log configuration
- A feed_id no other feed in the organization uses: feed names are unique per organization, and an existing one fails with 409
- The feed publishes one plain-text "You have successfully configured real time feed" message when it is created or updated; the extended parser drops it, and the managed parser records it as a parsing error

## Cost

Asset feeds are free; Pub/Sub throughput follows the rate of IAM and resource changes.

## Parameters

| Name | Type | Required | Description | Find it |
|---|---|---|---|---|
| `org_id` | string | yes | Organization ID the inventory feed binds to. Find it with: gcloud organizations list | `gcloud organizations list --format='value(ID)'` |
| `log_project` | string | yes | DEDICATED logging or security project holding this pipeline. Not a workload project. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with templates/gcp/gcp-foundation-logging-project (set create_project = true). | `gcloud projects list --format='value(projectId)'` |
| `remote_state_bucket` | string | no | GCS bucket holding gcp-source-audit-logs-organization's state. Set this and Abstract's identity is READ rather than retyped. Empty falls back to subscriber_service_account_email. |  |
| `remote_state_prefix` | string | no | State key of gcp-source-audit-logs-organization. It keeps that folder's original name, 01-organization, so existing state is found. |  |
| `subscriber_service_account_email` | string | no | Fallback when remote_state_bucket is empty. From gcp-source-audit-logs-organization's abstract_onboarding output. |  |
| `content_type` | string | no | IAM_POLICY (default, highest security value) \| RESOURCE \| ORG_POLICY \| ACCESS_POLICY \| OS_INVENTORY \| RELATIONSHIP |  |
| `asset_types` | array | no | Asset types to watch. Empty means everything and requires acknowledge_all_asset_types. |  |
| `acknowledge_all_asset_types` | bool | no | Required when asset_types is empty, which feeds every asset type in the organization. |  |
| `feed_id` | string | no | Name of the organization feed. Feed names are unique per organization, so a second deployment in the same organization (another logging project, a lab) needs its own; an existing name fails with 409 Requested entity already exists. |  |
| `retention_days` | int | no | Pub/Sub message retention in days. This is the entire recovery window: unacked messages older than this are deleted. |  |
| `labels` | object | no | Labels applied to every resource this template creates. |  |

## Permissions

- **roles/cloudasset.owner** on The organization: Deployer: Create the organization feed.
- **roles/pubsub.admin** on The logging project: Deployer: Create the topic, the subscription and their IAM bindings.
- **roles/serviceusage.serviceUsageAdmin** on The logging project: Deployer: Turn on the APIs this template uses, and create the Cloud Asset Inventory service agent. Terraform turns on only the APIs still off.
- **roles/pubsub.publisher** on The topic: Cloud Asset Inventory service agent: The feed publishes as its own agent; without the grant it delivers nothing.
- **roles/pubsub.subscriber** on The asset subscription: Abstract service account: Pull the changes.

## Creates

- A Pub/Sub topic and subscription for asset changes
- roles/pubsub.publisher for the Cloud Asset Inventory service agent on the topic
- An organization asset feed (IAM_POLICY by default) over a security-first set of asset types
- roles/pubsub.subscriber for Abstract's service account on the subscription

## Never touches

- Existing asset feeds
- The audit-log topic, subscription and sink: the feed has its own topic
- Abstract's service account: reused from the audit-log template, not created

## Outputs

- `abstract_onboarding`
- `cai_service_agent`

## Verify

| Check | Command | Healthy when |
|---|---|---|
| The service agent that must publish | `terraform output cai_service_agent` | The agent is listed and holds publisher on the topic. |

## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Monitor asset changes with Pub/Sub](https://docs.cloud.google.com/asset-inventory/docs/monitor-asset-changes#create_feeds)
- [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription)
- [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles)
- [pubsub_subscription](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription)
