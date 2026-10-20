# Permissions — every grant, at every scope

Most GCP onboarding failures are permission failures, and almost all of them are about
**scope height** rather than role name. The role is usually obvious; *where* it has to be
held is not.

Run `tools/gcp-guided-setup/preflight.sh` before anything else — it checks the ones that matter.

---

## The one that blocks people

> ### `roles/logging.configWriter` at the **ORGANIZATION** (or at the folder or project you export)
>
> This is the blocking prerequisite for an aggregated sink, and it is **rarely held by
> whoever owns the project**. Subscription Owner is not enough. Project Owner is not
> enough. Editor is not enough.
>
> It is the single most common reason a GCP onboarding session produces a decision list
> instead of a working feed. **Identify the human who holds it before scheduling
> anything.**

To find who holds it directly:

```bash
gcloud organizations get-iam-policy YOUR_ORG_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/logging.configWriter" \
  --format="table(bindings.members)"
```

That list shows direct grants only. A grant through a group or a custom role does not appear in
it, so to know whether you can create the sink yourself, run `preflight.sh`: it asks Google
directly, which counts every route.

---

## Grant exactly these roles, with `--grant`

The guided setup lists, checks and grants the roles it needs. Replace EMAIL with the address of the person who
runs the setup (a bare address is a user; put `group:` or `serviceAccount:` before it for those). Check them,
changing nothing. For your own address it asks Google which permissions you hold by any route (directly, through a
group, or inherited from a folder or the organization); for someone else's it reads the bindings each policy holds
directly, and names Policy Troubleshooter for the rest:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant EMAIL --check
```

Someone who can set IAM policy at the scope then grants them, one binding per role, asked one at a time
(optional roles default to no). Without that right it prints the commands to hand to someone who has it:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant EMAIL
```

The roles come from one list, [`tools/gcp-guided-setup/permissions.json`](../../tools/gcp-guided-setup/permissions.json),
which the script, the step-by-step guide ([STEP-BY-STEP.md](STEP-BY-STEP.md)) and the app all read. It also holds the
roles for deploying with Infrastructure Manager: `--grant EMAIL --for infra-manager` for the person who starts the
deployment, and `--grant serviceAccount:EMAIL --for infra-manager-sa` for the service account it runs as (see
[DEPLOY-INFRA-MANAGER.md](DEPLOY-INFRA-MANAGER.md)). Every role below was checked to exist with
`gcloud iam roles describe` on 2026-10-12, and the script asks Google again before it offers one;
`python3 tools/gcp-guided-setup/permissions.py verify` checks every row, title and permission against Google.

| Role | Where | Required | For |
|---|---|---|---|
| `roles/browser` (organization or project scope) or `roles/resourcemanager.folderViewer` (folder scope) | the scope | required | See the scope, its folders and projects (script steps 1 and 3). Not `roles/resourcemanager.organizationViewer`: it holds only `resourcemanager.organizations.get`, so it cannot list projects |
| `roles/logging.configWriter` | the scope | required | Create the sink (script step 4) |
| `roles/orgpolicy.policyViewer` | the scope | required | Read the organization policies that can block the key (script step 3) |
| `roles/iam.securityReviewer` | the scope | required | Read IAM policies and the audit settings (script steps 2, 5 and 6) |
| `roles/resourcemanager.projectCreator` | the organization or folder | optional | Create a new logging project (script step 3) |
| `roles/iam.securityAdmin` | the scope | optional | Turn on Data Access logs (script step 6). **Powerful:** it can change IAM anywhere at the scope |
| `roles/billing.user` | a billing account | optional | Link billing to the logging project (script step 3) |
| `roles/pubsub.admin` | the logging project | required | Topic, subscription and their grants (script steps 4 and 5) |
| `roles/iam.serviceAccountAdmin` | the logging project | required | Abstract's service accounts (script steps 5 and 7) |
| `roles/iam.serviceAccountKeyAdmin` | the logging project | required | The key Abstract signs in with (script steps 5 and 7) |
| `roles/serviceusage.serviceUsageAdmin` | the logging project | required | Turn on the APIs (script steps 3, 7 and 8) |
| `roles/monitoring.editor` | the logging project | optional | The health alerts (script step 8) |

A project you create in script step 3 makes you its Owner, so the logging-project roles matter only for a
project that already exists. Script step 2 checks every one of these roles the same way, before anything is built. The roles outlive the setup, so take them back once the pipeline works: script step 10,
`--remove` and `--teardown` each list every binding `--grant` recorded with the `remove-iam-policy-binding`
command that takes it back, and `--teardown --include-grants` removes those bindings, and only those.

### What `--teardown` needs

`--teardown` reads across the organization before it deletes anything, so the person running it needs to see
the folders and projects (`roles/browser` at the organization) and, for each kind of piece it finds, the role
that made it: `roles/logging.configWriter` where the sinks are; `roles/pubsub.admin` and
`roles/iam.serviceAccountAdmin` in each project holding an `abstract-…` topic or reader account;
`roles/monitoring.editor` there for the alerts; and, once it has found an `abstract-…` topic, at the
organization `roles/securitycenter.notificationConfigEditor` for Security Command Center notification configs
and `roles/cloudasset.owner` for Cloud Asset feeds. A refused listing of the topics, subscriptions or reader
accounts in a project is a failure, and the answers file stays. A refused listing of Security Command Center
notification configs or Cloud Asset feeds is not: a config left behind only points at a topic that is gone, so it
becomes a by-hand line with the command to check, and the teardown still finishes. These two organization-level
listings have no project of their own, so gcloud bills them to `billing/quota_project`, or else your current
project; when the API is off there, Google answers SERVICE_DISABLED (measured on a real organization). Turn the
API on there, or name a project where it is on (`gcloud config set billing/quota_project PROJECT_ID`), to have
them checked. `--include-audit-settings` also needs
`roles/iam.securityAdmin` at the scope script step 6 changed, as step 6 did.

---

## By deployment

### `gcp-source-audit-logs-organization` / `gcp-source-audit-logs-folder` / `gcp-source-audit-logs-project`

| Principal | Role | Scope | Why |
|---|---|---|---|
| deployer | `roles/logging.configWriter` | **org / folder / project** | Create the sink. **The blocker** |
| deployer | `roles/pubsub.admin` | logging project | Topic, subscription, IAM bindings |
| deployer | `roles/iam.serviceAccountAdmin` | logging project | Create Abstract's identity |
| deployer | `roles/serviceusage.serviceUsageAdmin` | logging project | Enable APIs |
| **sink writer identity** | `roles/pubsub.publisher` | **the TOPIC** | Created *with* the sink, holds **nothing** until granted. **The #1 cause of a healthy-looking sink that delivers nothing** |
| abstract | `roles/pubsub.subscriber` | **the SUBSCRIPTION** | Abstract **pulls**. Not publisher, not project-wide |

The writer-identity grant is automated here. It is called out because when a customer wires
this by hand, it is what they miss.

### `gcp-foundation-data-access-audit-logs`

| Principal | Role | Scope |
|---|---|---|
| deployer | **`roles/iam.securityAdmin`** (or Organization Admin; either holds `resourcemanager.organizations.setIamPolicy`) | organization |

Not Logging Admin. Not Owner on a project. This modifies the **organization IAM policy**,
and it is usually a different person again from the `logging.configWriter` holder.

### `gcp-source-google-workspace-logs`

| Principal | Role | Where | Why |
|---|---|---|---|
| deployer | `roles/iam.serviceAccountAdmin` | logging project | Create the delegated SA |
| **a human** | **Workspace SUPER ADMIN** | `admin.google.com` | Grant domain-wide delegation. **No API exists** |
| the service account | *nothing in GCP IAM* | — | Its access comes entirely from delegation |

> A GCP Owner **cannot** grant domain-wide delegation. If nobody on the call is a Workspace
> super admin, that is where the deployment stops.

### `gcp-source-security-command-center-findings`

Kept by Abstract on a GCP Pub/Sub Source configuration of its own that runs the extended GCP Pub/Sub parser
([ABSTRACT-INTEGRATION.md](ABSTRACT-INTEGRATION.md#network-logs-asset-changes-and-security-command-center-findings)).

| Principal | Role | Scope |
|---|---|---|
| deployer | `roles/securitycenter.notificationConfigEditor` | organization. Without it, creating the notification config is refused with 403 |
| abstract | `roles/pubsub.subscriber` | the findings subscription |

Requires **Security Command Center Standard or Premium active at the organization** (tested with Premium). An
organization still on legacy Security Command Center gets 400 "Security Command Center Legacy has been permanently
disabled".

### `gcp-source-asset-and-iam-changes`

Kept by Abstract on a GCP Pub/Sub Source configuration of its own that runs the extended GCP Pub/Sub parser.

| Principal | Role | Scope | Why |
|---|---|---|---|
| deployer | `roles/cloudasset.owner` | **organization** | Create the organization feed. **Not included in Organization Admin**: without it the topic and subscription are created and the feed is refused with 403 |
| deployer | `roles/pubsub.admin` | logging project | Topic, subscription, IAM bindings |
| **Cloud Asset service agent of the logging project** (`service-PROJECT_NUMBER@gcp-sa-cloudasset`, PROJECT_NUMBER being the project's number) | `roles/pubsub.publisher` | the topic | The feed publishes as the agent of its billing project. There is no organization-level Cloud Asset agent |
| abstract | `roles/pubsub.subscriber` | the asset subscription | Read the changes |

### `gcp-archive-log-bucket`

| Principal | Role | Scope |
|---|---|---|
| deployer | `roles/storage.admin` | logging project |
| **archive sink writer identity** | `roles/storage.objectCreator` | the bucket |

The archive sink has its **own** writer identity, distinct from the streaming sink's. Each
sink gets one; each needs its own grant.

### `gcp-source-cloud-storage-bucket-logs`

| Principal | Role | Scope | Why |
|---|---|---|---|
| **GCS service agent** — one PER OWNING PROJECT | `roles/pubsub.publisher` | the topic | **The notification publishes as the service agent, not as you.** Buckets in different projects have DIFFERENT agents; use `bucket_map` so each is granted, or the unlucky buckets deliver nothing |
| abstract | `roles/pubsub.subscriber` | the subscription | Read the pointer |
| abstract | `roles/storage.objectViewer` | **the bucket**, IAM-condition-scoped to `object_name_prefix` when set | Read the object the pointer points at. Without a prefix the grant is bucket-wide |
| abstract | `roles/cloudkms.cryptoKeyDecrypter` | the KMS key | CMEK buckets only — without it every fetch fails blaming Storage |

> **The notification is a pointer, not the data.** Two grants on two different services.
> Missing the second gives you notifications with no content, which reads like a parser bug
> and is not one.

### `gcp-monitoring-pipeline-health-alerts`

| Principal | Role | Scope |
|---|---|---|
| deployer | `roles/monitoring.editor` | logging project |

### `gcp-foundation-logging-project`

| Principal | Role | Scope |
|---|---|---|
| deployer | `roles/resourcemanager.projectCreator` | org or folder | *only* with `create_project = true` |
| deployer | `roles/billing.user` | the billing account | *only* with `create_project = true` |

---

## Who needs what, and when

The order a setup runs in, and the grant each part needs at that point. "You" is whoever runs the guided
script, the console click path, the gcloud commands or a local Terraform apply; with Infrastructure Manager,
the service account it runs as needs the same build roles (see [By deployment method](#by-deployment-method)).

| When | Who | Role | Where |
|---|---|---|---|
| Before anything: the read-only checks | you | `roles/browser` (organization or project) or `roles/resourcemanager.folderViewer` (folder) | the scope |
| | you | `roles/orgpolicy.policyViewer` | the scope |
| | you | `roles/iam.securityReviewer` | the scope |
| The logging project, only if you create it | you | `roles/resourcemanager.projectCreator` | the organization or folder |
| | you | `roles/billing.user` | the billing account |
| APIs | you | `roles/serviceusage.serviceUsageAdmin` | the logging project |
| The pipeline: topic, subscription and their grants | you | `roles/pubsub.admin` | the logging project |
| The sink | you | `roles/logging.configWriter` | the scope (or the billing account, for billing-account logs) |
| | the sink's writer identity | `roles/pubsub.publisher` | the topic only |
| Abstract's access | you | `roles/iam.serviceAccountAdmin` and `roles/iam.serviceAccountKeyAdmin` | the logging project |
| | Abstract's service account | `roles/pubsub.subscriber` | the subscription only |
| IAM, identity and Data Access logs (the audit settings) | you | `roles/iam.securityAdmin` | the scope |
| Google Workspace | you | `roles/iam.serviceAccountAdmin`, `roles/iam.serviceAccountKeyAdmin` and `roles/serviceusage.serviceUsageAdmin` (Admin SDK API) | the logging project |
| | a Workspace super admin | domain-wide delegation of `admin.reports.audit.readonly` | `admin.google.com` |
| Health alerts | you | `roles/monitoring.editor` | the logging project |
| Connect Abstract | — | nothing in Google Cloud | Abstract |
| Afterwards | — | take back every role `--grant` added | each place it was granted |

---

## By scope: organization, folder or project

Only some roles move with the scope you export. The rest always go on the logging project, whatever the
scope.

| Needed for | Organization | Folder | Project |
|---|---|---|---|
| See the scope, its folders and projects | `roles/browser` | `roles/resourcemanager.folderViewer` | `roles/browser` |
| Create the sink | `roles/logging.configWriter` on the organization (aggregated, with `include_children`) | `roles/logging.configWriter` on the folder (aggregated) | `roles/logging.configWriter` on the project |
| Read the organization policies | `roles/orgpolicy.policyViewer` | `roles/orgpolicy.policyViewer` | `roles/orgpolicy.policyViewer` |
| Read IAM and the audit settings | `roles/iam.securityReviewer` | `roles/iam.securityReviewer` | `roles/iam.securityReviewer` |
| Change the audit settings (IAM, identity and Data Access logs) | `roles/iam.securityAdmin`, or `roles/resourcemanager.organizationAdmin` | `roles/iam.securityAdmin`, or `roles/resourcemanager.folderIamAdmin` or `roles/resourcemanager.folderAdmin` | `roles/iam.securityAdmin`, or `roles/resourcemanager.projectIamAdmin` |
| Create a new logging project | `roles/resourcemanager.projectCreator` | `roles/resourcemanager.projectCreator` | — |
| Asset and IAM-policy change feed | `roles/cloudasset.owner` (the template is organization-scoped) | `roles/cloudasset.owner` | `roles/cloudasset.owner` |
| Security Command Center notifications | `roles/securitycenter.notificationConfigEditor` (the template is organization-scoped) | — | — |

**Always on the logging project:** `roles/pubsub.admin`, `roles/iam.serviceAccountAdmin`,
`roles/iam.serviceAccountKeyAdmin`, `roles/serviceusage.serviceUsageAdmin` and, for alerts,
`roles/monitoring.editor`.

Every role that changes the audit settings holds `setIamPolicy` at its scope, so whoever holds it can grant
any role there. There is no narrower way: Google keeps the audit settings inside the IAM policy. Grant it for
the setup and take it back afterwards.

---

## Every identity involved

| Identity | Made by | Holds | Where |
|---|---|---|---|
| You (the person running the setup) | — | the roles above | the scope and the logging project |
| Abstract's service account (`abstract-pubsub-reader` by default) | you, in the logging project | `roles/pubsub.subscriber` | each Abstract subscription only (audit logs, and any other pipeline you add) |
| | | `roles/storage.objectViewer` | each bucket, only for `gcp-source-cloud-storage-bucket-logs`, scoped to the prefix when set |
| | | `roles/cloudkms.cryptoKeyDecrypter` | the KMS key, only for buckets encrypted with your own key |
| The network-threat pipeline's reader (`abstract-net-threat-reader` by default), only with `gcp-source-network-threat-logs` | you, in the logging project | `roles/pubsub.subscriber` | that pipeline's subscription only |
| Abstract's Workspace service account (`abstract-workspace-reader` by default) | you, in the logging project | nothing in Google Cloud IAM | its access is the delegated `admin.reports.audit.readonly` scope |
| Each sink's writer identity | Google, when the sink is created | `roles/pubsub.publisher` | that sink's topic only. An archive sink's identity needs `roles/storage.objectCreator` on the archive bucket instead |
| The Cloud Asset Inventory service agent (`service-PROJECT_NUMBER@gcp-sa-cloudasset.iam.gserviceaccount.com`) | Google | `roles/pubsub.publisher` | the asset topic |
| The Cloud Storage service agent of each project that owns a bucket | Google | `roles/pubsub.publisher` | the bucket-notification topic |
| The Infrastructure Manager service account (`infra-manager-abstract` by default) | you | `roles/config.agent` plus the build roles | see [DEPLOY-INFRA-MANAGER.md](DEPLOY-INFRA-MANAGER.md) |
| Each VM's service account, only for VM guest logs | you, or the project's default | `roles/logging.logWriter` and `roles/monitoring.metricWriter` | the project that owns the VM |

---

## More security and infrastructure sources

Abstract's managed GCP Pub/Sub parser, as shipped, keeps **Cloud Audit Logs only**: every other record that
reaches its subscription is pulled and then discarded. Rows marked **Extended parser** are kept on a configuration
of their own that runs the extended GCP Pub/Sub parser, which is not in the managed integration yet; until it is,
Abstract applies it to the configuration's parsers. The rows marked **No, today** still list the roles to turn
them on and route them, but routing them costs Pub/Sub throughput in Google Cloud and adds nothing in Abstract.
Rows marked *not measured* have the Cloud Audit Log format and should be kept, but nobody has checked one arrive
in Abstract.

Turning a source on happens **where the resource lives**, not at the sink's scope. With Shared VPC that is the
host project: subnets, firewall rules, Cloud NAT routers and Cloud DNS server policies all belong to the
network's project. For many projects, grant the role on a folder rather than the organization: a
`roles/compute.*Admin` grant at the organization is broad.

| Source | Kept by Abstract | Turn it on | Route it to Abstract |
|---|---|---|---|
| Admin Activity, System Event, Policy Denied audit logs | Yes | Always on | `roles/logging.configWriter` at the scope (the default filter) |
| IAM and identity logs: impersonation, token minting (`iam.googleapis.com`), Workload Identity Federation (`sts.googleapis.com`) | Yes | `roles/iam.securityAdmin` at the scope (ADMIN_READ, low volume) | the sink filter (`identity_access`, script step 6) |
| BigQuery Data Access logs | Yes | On by default in Google Cloud | the sink filter (script step 6, or `data_access_all` with `data_access_services`) |
| Cloud Storage, Cloud KMS and Secret Manager Data Access logs | Yes | `roles/iam.securityAdmin` at the scope. DATA_READ on Cloud Storage is high volume | the sink filter (script step 6, or `data_access_all` with `data_access_services`) |
| GKE audit logs (`k8s.io`) | Yes, not measured | Admin Activity is always on; Data Access needs `roles/iam.securityAdmin` | the sink filter |
| Access Transparency logs | Yes, not measured | Turned on for the organization in the console, where Google's eligibility rules apply | the `access_transparency` category |
| Google Workspace audit logs, through the Reports API | Yes, through the separate Google Workspace integration | A Workspace super admin grants domain-wide delegation | not a sink: see [Google Workspace: two routes](#google-workspace-two-routes) |
| Billing-account logs | Yes, not measured | Always on | `roles/logging.configWriter` on the billing account (`gcp-source-billing-account-logs`) |
| Objects in Cloud Storage buckets | Through the separate Cloud Storage notifications integration | `roles/storage.admin` on each bucket | `gcp-source-cloud-storage-bucket-logs` (see [By deployment](#by-deployment)) |
| VPC Flow Logs | Extended parser | `roles/compute.networkAdmin` on the subnet's project, or `roles/networkmanagement.admin` for VPC Flow Logs configurations | the `vpc_flows` category (high volume; needs `acknowledge_high_volume`) |
| Firewall rule logs | Extended parser | `roles/compute.securityAdmin` on the network's project; for hierarchical firewall policies, `roles/compute.orgFirewallPolicyAdmin` on the organization or folder | the `firewall` category |
| Cloud Armor (WAF) and load-balancer request logs | No, today | `roles/compute.loadBalancerAdmin` to turn on logging on each backend service, and `roles/compute.securityAdmin` for the Cloud Armor policy | the `load_balancer` categories. Cloud Armor's decisions are recorded in the load balancer's request log |
| Cloud NAT logs | Extended parser | `roles/compute.networkAdmin` on the router's project | the `nat_flows` category |
| Cloud DNS query logs | Extended parser | `roles/dns.admin` on the network's project (a server policy with logging on) | the `dns_queries` category |
| Cloud IDS threat logs | No, today | `roles/ids.admin` for the endpoint and `roles/compute.packetMirroringUser` for the Packet Mirroring policy that feeds it, on the network's project | `gcp-source-network-threat-logs` |
| Cloud NGFW Enterprise threat logs | No, today | `roles/networksecurity.admin` | not in a template: `platform_log_filters` with its log name |
| VM serial-port output | No, today | Serial-port logging is a project or instance setting (`roles/compute.instanceAdmin.v1`) | the `vm_guest` category |
| VM guest logs: syslog, Windows Event Log (Ops Agent) | No, today | `roles/osconfig.osPolicyAssignmentAdmin` on each project, to roll the Ops Agent out with an OS policy; each VM's service account needs `roles/logging.logWriter` | not in a template: `platform_log_filters` with the agent's log names |
| Cloud SQL database logs | No, today | Database flags (`roles/cloudsql.editor`) | the `cloudsql` category |
| Security Command Center findings | Extended parser | `roles/securitycenter.notificationConfigEditor` on the organization | `gcp-source-security-command-center-findings` |
| Asset and IAM-policy changes (Cloud Asset Inventory) | Extended parser | `roles/cloudasset.owner` at the scope | `gcp-source-asset-and-iam-changes` |

IAM policy changes themselves (`SetIamPolicy` on any resource) are Admin Activity audit logs, so they reach
Abstract with the default filter. The asset feed adds the before-and-after policy, which the extended parser keeps
as `gcp.asset_inventory`.

---

## Google Workspace: two routes

| Route | Who acts | Grants | Kept by Abstract |
|---|---|---|---|
| The Reports API (what `gcp-source-google-workspace-logs` and script step 7 set up) | you, then a Workspace super admin | you: `roles/iam.serviceAccountAdmin`, `roles/iam.serviceAccountKeyAdmin` and `roles/serviceusage.serviceUsageAdmin` on the logging project. The super admin: domain-wide delegation of `admin.reports.audit.readonly` to Abstract's Workspace service account | Yes, through the Google Workspace integration |
| Sharing Workspace data with Google Cloud | a Workspace super admin | A switch in the Admin console (Account settings, Legal and compliance, Sharing options). The audit logs then appear in Cloud Logging at the organization, with no service account and no key | **unverified:** whether the organization sink's filter matches them and whether Abstract's integration keeps them |

Google documents the second route: [Share data with Google Cloud services](https://knowledge.workspace.google.com/admin/getting-started/share-data-with-google-cloud-services)
and [Audit logs for Google Workspace](https://docs.cloud.google.com/logging/docs/audit/gsuite-audit-logging).

---

## By deployment method

| Method | Runs as | Roles |
|---|---|---|
| Guided script, console, gcloud commands, local Terraform | you | [the setup roles](#grant-exactly-these-roles-with---grant): `--grant EMAIL` |
| Infrastructure Manager | its own service account | You: `roles/serviceusage.serviceUsageAdmin`, `roles/iam.serviceAccountAdmin`, `roles/config.admin` on the logging project and `roles/iam.serviceAccountUser` on the service account (`--grant EMAIL --for infra-manager`). The service account: `roles/config.agent` plus the build roles (`--grant serviceAccount:EMAIL --for infra-manager-sa`). If the service account lives in another project, the Infrastructure Manager service agent needs `roles/iam.serviceAccountUser` and the Cloud Build service agent `roles/iam.serviceAccountTokenCreator` on it. See [DEPLOY-INFRA-MANAGER.md](DEPLOY-INFRA-MANAGER.md) |
| Terraform from a CI pipeline | a deploy service account, signed in through Workload Identity Federation rather than a key | the build roles the Infrastructure Manager service account holds, without `roles/config.agent` |
| Deployment Manager | — | Not offered. Google ended support for Deployment Manager on March 31, 2026 ([Deployment Manager deprecations](https://docs.cloud.google.com/deployment-manager/docs/deprecations)); use Infrastructure Manager |

Every role named in these new sections was checked to exist, and to hold the permission it is listed for, with
the IAM `roles.get` API on 2026-10-18.

---

## Least privilege, and where this repo deliberately stops short

**What is already narrow:**

- `roles/pubsub.subscriber` on **one subscription**, never project-wide
- The Workspace scope is the one read-only `admin.reports.audit.readonly` and nothing else
- Every binding is `_iam_member` (additive), never `_iam_policy` (authoritative), so nothing
  here can clobber a grant somebody else made
- `create_service_account_key` defaults **false** — a key in Terraform state is a key in
  whatever holds the state

**Where you can go narrower:**

`roles/pubsub.subscriber` grants `subscriptions.consume` but **not**
`pubsub.subscriptions.get`. Many pull clients call `GetSubscription` at startup.

`unverified:` whether Abstract's connector does. If it bites, the symptom is a **403 that
looks like a credentials problem and is not**. The hardening either way is a custom role
with `pubsub.subscriptions.consume` + `pubsub.subscriptions.get`, or adding
`roles/pubsub.viewer` on the subscription.

`roles/pubsub.editor` cannot set IAM on a topic or subscription (it holds no
`pubsub.topics.setIamPolicy`), so the grants for the sink's writer identity and Abstract's reader need
`roles/pubsub.admin` on the logging project, or a custom role with `pubsub.topics.{create,get,update,getIamPolicy,setIamPolicy}`
and `pubsub.subscriptions.{create,get,update,getIamPolicy,setIamPolicy}`.

`roles/iam.serviceAccountCreator` holds `iam.serviceAccounts.create` and `.get`, all a first run of the setup
uses. It cannot delete, so `--remove`, `--teardown` and `terraform destroy` still need
`roles/iam.serviceAccountAdmin`.

`roles/logging.configWriter` is enough for every sink here; `roles/logging.admin` is not needed.

Reading Data Access logs in the console needs `roles/logging.privateLogViewer`; `roles/logging.viewer` does not
show them.

---

## Org policies that will block this

| Policy | Effect | Response |
|---|---|---|
| `constraints/iam.disableServiceAccountKeyCreation`, and its managed successor `constraints/iam.managed.disableServiceAccountKeyCreation` | **Blocks the whole deployment** — Abstract authenticates with a service-account key. Either one blocks it | Request a scoped exception for the logging project, on whichever of the two is enforced (script step 3 checks both; see [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)). Longer term, Workload Identity Federation on the Abstract side is what removes the need |
| `constraints/iam.serviceAccountKeyExpiryHours` | Keys expire | Build rotation into the runbook rather than discovering it |
| `constraints/iam.disableCrossProjectServiceAccountUsage` | Blocks cross-project SA use | Keep the identity in the logging project |
| `constraints/gcp.restrictNonCmekServices` | Requires CMEK on Pub/Sub | Set the topic's KMS key |
| VPC Service Controls | Abstract pulls from **outside** the perimeter | Needs an ingress rule for the reader SA, or the logging project outside the perimeter |

The first one is the common blocker in hardened organizations, and nothing in this repo can
work around it — it is a policy exception or nothing.

---

## Key handling

The service-account key is the whole credential. Treat it accordingly:

1. **Create it out of band**, never in Terraform — `create_service_account_key` defaults
   false because a key in state is a key in whatever holds the state, and on the Cloud Shell
   path that is a home directory
2. **Upload straight to Abstract**, then `rm` the local copy
3. **Rotate on your standard cadence.** There is no automatic expiry unless the org policy
   sets one
4. **The Workspace key is broader than it looks** — domain-wide delegation is *domain*-wide
   and not project-scoped, so a leak reads the entire Workspace audit trail regardless of
   any GCP IAM control

---

## Checking all of this

```bash
./tools/gcp-guided-setup/preflight.sh --project YOUR_LOG_PROJECT --org-id YOUR_ORG_ID --report ~/readiness.md
```

Read-only. It checks identity, APIs, whether Google confirms you can create sinks
(`logging.sinks.create`, from `roles/logging.configWriter`) at your chosen scope,
whether Data Access is already enabled, and whether sinks already exist — then writes a
report with a numbered action list.
