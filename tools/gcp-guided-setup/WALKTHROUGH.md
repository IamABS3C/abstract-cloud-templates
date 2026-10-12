# Google Cloud guided setup

<walkthrough-tutorial-duration duration="20"></walkthrough-tutorial-duration>

## Before you start

One walkthrough that creates and checks everything Abstract needs in Google Cloud, in the order it has to happen. Nothing changes until you say yes, and every step can be re-checked later.

Each page runs one part of the guided script, called script step 1 to 10. It prints what it will do, asks before it changes anything, and checks the result.

Your answers are saved in an answers file, `~/.abstract-gcp-setup.env`. You can stop at any step and come back while this Cloud Shell session lasts. The session opened from this link is temporary: when it ends, the answers file, the service-account key and the backup of your audit settings go with it. A new session starts again at script step 1, or loads the answers file you downloaded with `--state ~/.abstract-gcp-setup.env` (upload it first: More, then Upload). Download the key as soon as script step 5 makes it.

If your run may pause, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and get the repository with `git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates`.

Cloud Shell opened from this link starts signed out, because Google does not give a repository it does not own your credentials. Sign in, which also gives the scripts the same sign-in, and make the scripts runnable:

```bash
gcloud auth login --update-adc
cd "$(git rev-parse --show-toplevel)"
chmod +x tools/gcp-guided-setup/*.sh
```

The script's first screen also offers to sign you in, switch account, start over or update the scripts.

Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

Click **Start** to begin.

## Check first

**Why.** See what you already have before anything is created. The estate audit is read-only: it lists your organization, folders and projects, every log sink that already exports logs, Pub/Sub topics, and your audit settings.

```bash
./tools/gcp-guided-setup/audit-gcp-estate.sh
```

**You should see:** Your organization, and the sinks set on it that already send logs somewhere. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one.

Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview) · [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)

## Script step 1: Sign-in and organization

**What it does.** Confirms who you are signed in as, finds your organization and asks how much of Google Cloud should send logs.

**Why.** Every later check is made for this account. The scope decides what is covered.

- Whole organization: every project, including ones created later. Recommended.
- One folder: every project in it. Projects outside it are missed.
- One project: a pilot. Other and future projects are not covered.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
```

**You should see:** The account and organization are shown, and the scope is saved.

Google documentation: [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

## Script step 2: What you can change

**What it does.** Asks Google which of the needed permissions you hold, before anything is created.

**Why.** A missing permission otherwise fails halfway through, leaving half a pipeline.

**Permissions it checks:**

- Logs Configuration Writer (roles/logging.configWriter) at your scope (the organization, folder or project you chose), for the log sink. At the organization, Organization Admin does not include it
- For Data Access logs (script step 6), the right to change the IAM policy at your scope: Organization Admin (organization), Folder Admin (folder), or Owner or Project IAM Admin (project), or Security Admin at that scope
- Project Creator + Billing User on the organization and billing account, for a new logging project (script step 3)
- Owner, or Pub/Sub Admin + Service Account Admin + Service Account Key Admin + Service Usage Admin on the logging project, for script steps 3 to 5. Script step 3 checks these, once the project is chosen

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
```

**You should see:** A ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time: script step 3 checks it.

Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions)

## Script step 3: Logging project

**What it does.** Creates a dedicated logging project or uses one you have, optionally links billing, and turns on the APIs. Then it checks your rights in the project, and whether either organization policy that blocks the key script step 5 makes is enforced: iam.disableServiceAccountKeyCreation or its managed successor iam.managed.disableServiceAccountKeyCreation. An exception is needed on whichever one the script marks ✗, before script step 4 builds anything.

**Why.** One project holds the topic, the subscription and Abstract's account. Keep it separate from workloads.

**Creates:**

- A project (only if you choose to create one)
- APIs: Pub/Sub, Cloud Logging, IAM, Resource Manager

_Script step 7 turns on the Admin SDK API itself. Script step 8 turns on the Monitoring API itself, before it creates anything._

_Billing is optional on this path. Pub/Sub and Logging free tiers cover an audit feed._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
```

**You should see:** A ✓ for the active project, every API, building the pipeline in the project, and "service-account keys are allowed". A ✗ on the key policy means: ask for an exception on this project before you go on.

Prefer Terraform? The same piece is `templates/gcp/gcp-foundation-logging-project`.

Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

## Script step 4: Log pipeline

**What it does.** Creates the topic and subscription, then the sink that copies audit logs to the topic as they are written.

**Why.** The sink sits at your chosen scope, so new projects are covered automatically. There is no backfill. An existing sink to the same topic is reused and its filter is only ever extended.

**Creates:**

- Pub/Sub topic abstract-audit-logs
- Subscription abstract-audit-logs-sub that never expires, 7 days retention
- Log sink abstract-org-audit-sink at the scope, including child projects (an existing sink to the same topic is reused)
- Publisher role on the topic for the sink's writer identity (the Google-managed account the sink publishes as)

_The publisher grant is the step most often missed. Without it the sink looks healthy and sends nothing._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
```

**You should see:** A ✓ for the sink sending to the topic, its filter, and "the sink's own identity can publish". To see the grant yourself, `gcloud pubsub topics get-iam-policy abstract-audit-logs --project=<logging-project-id>` lists the writer identity under roles/pubsub.publisher.

Prefer Terraform? The same piece is `templates/gcp/gcp-source-audit-logs-organization, gcp-source-audit-logs-folder or gcp-source-audit-logs-project`.

Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)

## Script step 5: Abstract's access

**What it does.** Creates the service account Abstract signs in as, lets it read only the one subscription, and makes its key.

**Why.** Abstract pulls. It needs subscriber on the subscription and nothing else.

**Creates:**

- Service account abstract-pubsub-reader
- Subscriber role on the subscription only
- A JSON key, in ~/abstract-keys, readable only by you and outside any repository

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
```

_The key goes into Abstract and is then deleted everywhere. In a temporary Cloud Shell session, download it as soon as script step 5 makes it, so a session that ends early does not take it with it. After script step 5 shows the key file:_

```bash
cloudshell download ~/abstract-keys/abstract-pubsub-key.json
```

**You should see:** A ✓ for the account, for reading the subscription, for "no project-wide roles", and for a key file in ~/abstract-keys.

Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

## Script step 6: Data Access logs (optional)

**What it does.** Turns on Data Access logs and routes them: who minted service-account tokens or impersonated a service account, who exchanged a federated identity (GitHub Actions, AWS, Azure), and who read or changed data in BigQuery, Cloud Storage and Cloud KMS. For identity it switches on iam.googleapis.com and sts.googleapis.com in the audit settings, and routes their events, which arrive as iamcredentials.googleapis.com and sts.googleapis.com. Keep both in the suggested list.

**Why.** Admin Activity logs are always on. Data Access logs are off until two switches are both on, except BigQuery's: Google writes BigQuery's Data Access logs by default, so BigQuery needs only switch 2.

- Switch 1, generate them: the audit settings at your scope. Only the audit settings change; a copy is saved first.
- Switch 2, route them: the sink filter from script step 4. For most services either switch alone does nothing, silently; BigQuery needs only this one.

_DATA_READ is high volume and off by default. Start with ADMIN_READ and DATA_WRITE._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
```

Answer **no** at the first question to skip it.

**You should see:** A ✓ for switch 1 (Data Access is generated for each service you chose, iam.googleapis.com and sts.googleapis.com among them) and for switch 2 (the sink routes each of them, naming iamcredentials.googleapis.com and sts.googleapis.com).

Prefer Terraform? The same piece is `templates/gcp/gcp-foundation-data-access-audit-logs`.

Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)

## Script step 7: Google Workspace logs (optional)

**What it does.** Sets up sign-in, admin and token logs from Google Workspace, read from the Workspace Reports API; Abstract does not depend on Cloud Logging for them.

**Why.** Abstract reads them from the Workspace Reports API as a separate account a Workspace super admin allows.

**Creates:**

- Admin SDK API on the logging project
- Service account abstract-workspace-reader and its key

**A person must do this part:** A Workspace super admin opens admin.google.com → Security → Access and data control → API controls → Domain-wide delegation → Add new, and enters the Client ID and the one read-only scope the script prints, `https://www.googleapis.com/auth/admin.reports.audit.readonly`. A Google Cloud Owner cannot do this step.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
```

Answer **no** at the first question to skip it.

**You should see:** A ✓ "delegation works: the Reports API answered as" your admin. Delegation can take a few minutes after the super admin saves it; run this step again until it does.

Prefer Terraform? The same piece is `templates/gcp/gcp-source-google-workspace-logs`.

Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

## Script step 8: Health alerts (optional)

**What it does.** Creates three alerts and an email channel, so you hear when the pipeline stops.

**Why.** A stopped pipeline is silent. These catch sink errors, no messages, and Abstract not reading.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
```

Answer **no** at the first question to skip it.

**You should see:** Three "Abstract log pipeline" alert policies exist, sending to your email.

Prefer Terraform? The same piece is `templates/gcp/gcp-monitoring-pipeline-health-alerts`.

Google documentation: [Alerting overview](https://docs.cloud.google.com/monitoring/alerts) · [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

## Script step 9: Test and verify

**What it does.** Writes a harmless admin event inside your scope and waits for it on a probe subscription of its own, never on Abstract's.

**Why.** Proves the whole path before Abstract is involved. A new sink needs about 3 minutes before it routes anything.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
```

**You should see:** A ✓ "the test event arrived on abstract-audit-logs", usually within 5 minutes.

Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull)

## Script step 10: Connect Abstract

**What it does.** Prints the exact values for the GCP Pub/Sub Source integration in Abstract (and the Google Workspace Audit Log Integration, if you set it up), and, in Cloud Shell, the commands that download the key files, your answers file and the backup of your audit settings.

**Why.** The project field is the one most often filled in wrong. It is the project with the subscription.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
```

**Get the keys out of Cloud Shell.** In a session opened from this link they exist only there. Download them to the computer you use for Abstract. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat:

```bash
cloudshell download ~/abstract-keys/abstract-pubsub-key.json
ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
```

**In Abstract,** add the **GCP Pub/Sub Source** integration:

- Project ID: the logging project the script printed, the one with the subscription, not the projects the logs come from
- Subscription ID: abstract-audit-logs-sub, the short name only
- Credentials: upload abstract-pubsub-key.json

If you set up Workspace, add the **Google Workspace Audit Log Integration** too: Admin Email, Credentials (abstract-workspace-key.json) and Application Name. Every application is selected by default; to start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

**Then delete every copy of the keys,** here and the downloaded ones:

```bash
rm -f ~/abstract-keys/abstract-pubsub-key.json ~/abstract-keys/abstract-workspace-key.json
```

**You should see:** Events from the integration in Abstract's event search within a few minutes. The first are the test events script step 9 wrote, which waited on the subscription. Re-check the cloud side any time with: ./tools/gcp-guided-setup/abstract-gcp-setup.sh --check

Then download your answers. A Cloud Shell session opened from this link is temporary, and the clean-up needs them to know what the setup made. If script step 6 changed your audit settings, download its backup of the earlier settings too:

```bash
cloudshell download ~/.abstract-gcp-setup.env
ls ~/abstract-audit-config-backup-*.json 2>/dev/null && cloudshell download ~/abstract-audit-config-backup-*.json
```

Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys) · [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub)

## Clean up

To remove the setup later, delete the integrations in Abstract first, so they stop reading. The clean-up reads your answers file, `~/.abstract-gcp-setup.env`. In the session where you ran the setup it is already there. In a new session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after `--state`. Then list what would be removed. Nothing is deleted without --confirm:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
```

Each item is marked would remove, kept or by hand. If a name is not one this setup made, stop: the answers file is the wrong one.

Lost the answers file? `--remove --project <logging-project-id>` lists everything that carries the setup's names, with the command to remove each, and deletes nothing itself.

When the list is right, remove it:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
```

It removes only what this setup created: the sink, topic and subscription, the service accounts, the health alerts and the key files. It never deletes the logging project. Data Access audit settings, and anything that existed before you started, are listed by hand for you to change. Every item then shows as removed, kept or by hand; act on each by-hand line.

Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Check everything again at any time. It changes nothing:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --check
```

Delete every copy of the key files once they are uploaded to Abstract: in Cloud Shell and on your computer.
