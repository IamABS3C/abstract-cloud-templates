# How the data flows

Every Google Cloud feed to Abstract follows one of four paths. Knowing which path a log source
takes tells you where to look when it goes quiet. [Troubleshooting](TROUBLESHOOTING.md) walks the
checks in order.

Abstract always pulls. Nothing in your project pushes to Abstract, and Abstract needs no inbound
access to your network.

---

## The four paths

| Path | Used by | What carries the data |
|---|---|---|
| **Log Router sink to Pub/Sub** | Audit logs, network threat logs, billing account logs | A sink at organization, folder, project or billing-account scope writes matching log entries to a topic |
| **Own feed to Pub/Sub** | Security Command Center findings, Cloud Asset Inventory changes | The service publishes to a topic itself. No log sink can carry it |
| **Object notification to Pub/Sub** | Logs that are already files in a Cloud Storage bucket | Pub/Sub carries a pointer to the object. Abstract then reads the object |
| **Reports API poll** | Google Workspace audit logs | Abstract calls the Admin SDK Reports API. No Pub/Sub, no Cloud Logging |

---

## Path 1: sink to Pub/Sub

```
 log sources                 Cloud Logging                    your logging project              Abstract
 -----------                 -------------                    --------------------              --------
 every project   --write-->  Log Router                        Pub/Sub topic
 in the scope                  sink (filter, include-children)    |  (sink's own identity
                               evaluated when each                |   must hold publisher)
                               entry is written     --------->    v
                                                              subscription  <---- pull ----  Abstract
                                                              (never expires,                (service account,
                                                               7 days retention)              subscriber only)
```

What to know about each hop:

1. **The log entry is written.** Admin Activity audit logs are always on. Data Access logs are off
   until you turn them on. Firewall, DNS and load balancer logs are off until you enable them on
   the resource. A sink can only route what is already being generated.
2. **The sink matches it.** The sink sits at one scope and, with child inclusion, sees everything
   below it. The filter is evaluated at write time. There is no backfill, so a filter that was too
   narrow leaves a permanent gap. [Filters](FILTERS.md) covers how to pick.
3. **The sink writes to the topic.** It does this as its own identity, which Google creates with the
   sink and which holds no permissions. The templates grant it `roles/pubsub.publisher` on the
   topic. Without that grant the sink looks healthy and delivers nothing.
4. **The subscription holds the messages.** It never expires and keeps unacknowledged messages for
   seven days. If Abstract stops reading for longer than that, the oldest messages are lost.
5. **Abstract pulls.** It signs in as a service account that holds `roles/pubsub.subscriber` on the
   subscription and nothing else. It acknowledges each message once it has it.

A new sink takes about three minutes before it routes anything. Events written before then are not
routed and cannot be recovered. Wait, then write a fresh test event.

### Defaults

| Item | Default name |
|---|---|
| Topic | `abstract-audit-logs` |
| Subscription | `abstract-audit-logs-sub` |
| Sink | `abstract-org-audit-sink` |
| Abstract's service account | `abstract-pubsub-reader` |

The folder and project templates use the same names at their own scope.

---

## Path 2: the service's own feed

Security Command Center and Cloud Asset Inventory do not write to Cloud Logging, so a sink never
sees them. Each has its own configuration (a notification config, an asset feed) that publishes to a
topic of its own. Each needs its own subscription and its own grant to the publishing identity.

| Feed | Default topic | Needs |
|---|---|---|
| Security Command Center findings | `abstract-findings` | Security Command Center Premium or Enterprise |
| Cloud Asset Inventory | `abstract-asset-changes` | `roles/cloudasset.owner` for the deployer at the organization, and a publisher grant for the Cloud Asset service agent of the logging project |

See [Permissions](PERMISSIONS.md) for who needs which role.

---

## Path 3: object notifications

For logs that are already objects in a bucket, such as a vendor export or an archive you want to
backfill. A bucket notification publishes a short message to a topic (`abstract-gcs-notifications`)
each time an object is written. The message is a pointer, not the log.

Abstract needs two grants on two services: subscriber on the subscription to read the pointer, and
`roles/storage.objectViewer` on the bucket to read the object. With only the first you get
notifications and no content, which looks like a parser fault and is not one.

The notification is published by the Cloud Storage service agent of the project that owns the
bucket. Buckets in different projects have different agents, so each needs its own publisher grant.

---

## Path 4: Google Workspace

Workspace audit data comes from the Admin SDK Reports API. Abstract's Google Workspace
integration polls it, one checkpoint per application. The only thing in Google Cloud is a service
account, which Workspace administrators authorize through domain-wide delegation.

Workspace sign-ins do not travel the log sink path. See [Google Workspace](WORKSPACE.md) and
[Identity](IDENTITY.md).

---

## What does not travel these paths

| Not carried | Why | Where to look |
|---|---|---|
| Billing account logs through an organization sink | Billing accounts sit outside the resource hierarchy | `templates/gcp/gcp-source-billing-account-logs` |
| Data Access logs, until enabled | Off by default. A filter that names them matches nothing and raises no error | [Filters](FILTERS.md) |
| Logs from another organization | A sink cannot route across organizations | One deployment per organization |
| Anything inside a VPC Service Controls perimeter, if Abstract reads from outside it | The perimeter blocks the pull | [VPC Service Controls](VPC-SC.md) |

---

## Which template builds which path

| Template | Path | What it creates |
|---|---|---|
| [gcp-source-audit-logs-organization](../../templates/gcp/gcp-source-audit-logs-organization/README.md) | 1 | Organization sink, topic, subscription, reader account |
| [gcp-source-audit-logs-folder](../../templates/gcp/gcp-source-audit-logs-folder/README.md) | 1 | The same at folder scope |
| [gcp-source-audit-logs-project](../../templates/gcp/gcp-source-audit-logs-project/README.md) | 1 | The same at project scope, for a pilot |
| [gcp-source-network-threat-logs](../../templates/gcp/gcp-source-network-threat-logs/README.md) | 1 | A filtered sink for firewall, DNS, load balancer and IDS logs, on its own topic |
| [gcp-source-billing-account-logs](../../templates/gcp/gcp-source-billing-account-logs/README.md) | 1 | A billing-account sink on its own topic |
| [gcp-source-security-command-center-findings](../../templates/gcp/gcp-source-security-command-center-findings/README.md) | 2 | A notification config, topic and subscription |
| [gcp-source-asset-and-iam-changes](../../templates/gcp/gcp-source-asset-and-iam-changes/README.md) | 2 | An organization asset feed, topic and subscription |
| [gcp-source-cloud-storage-bucket-logs](../../templates/gcp/gcp-source-cloud-storage-bucket-logs/README.md) | 3 | Bucket notifications, topic and subscription |
| [gcp-source-google-workspace-logs](../../templates/gcp/gcp-source-google-workspace-logs/README.md) | 4 | A service account for domain-wide delegation |
| [gcp-foundation-logging-project](../../templates/gcp/gcp-foundation-logging-project/README.md) | all | The logging project and its APIs |
| [gcp-foundation-data-access-audit-logs](../../templates/gcp/gcp-foundation-data-access-audit-logs/README.md) | 1 | Turns on Data Access logs, so a filter can match them |
| [gcp-archive-log-bucket](../../templates/gcp/gcp-archive-log-bucket/README.md) | 1 | A second sink that writes to Cloud Storage for retention and backfill |
| [gcp-monitoring-pipeline-health-alerts](../../templates/gcp/gcp-monitoring-pipeline-health-alerts/README.md) | 1 | Alerts for a stalled feed, a sink error or a dead-letter backlog |

The guided script `tools/gcp-guided-setup/abstract-gcp-setup.sh` builds the same pieces as the
Terraform templates. Use one or the other for a given setup. [The setup guide](GUIDE.md) says when.

---

## What Abstract does with it

Abstract reads each message, parses it into its common schema and routes it by your pipelines.
Parsing is not something you configure in Google Cloud. The integration settings are in
[Abstract integration](ABSTRACT-INTEGRATION.md).

One limit decides how you set up the extra feeds. The managed Google Cloud Pub/Sub parser keeps
only Cloud Audit Log records. Security Command Center findings, asset changes and the network
threat logs (firewall, DNS, load balancer, IDS) arrive and are counted as collected, but are not
stored unless that source has a parser of its own. Create each as a separate source in Abstract.
The asset feed has a parser in its template folder.
