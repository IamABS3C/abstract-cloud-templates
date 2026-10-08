# Google Cloud guided setup

<walkthrough-tutorial-duration duration="20"></walkthrough-tutorial-duration>

## Before you start

One walkthrough that creates and checks everything Abstract needs in Google Cloud, in the order it has to happen. Nothing changes until you say yes, and every step can be re-checked later.

Each page runs one part of the guided script, called script step 1 to 10. It prints what it will do, asks before it changes anything, and checks the result. You can stop at any step and come back; your answers are kept for this Cloud Shell session. The session is temporary, so script step 10 has you download them, with the service-account key.

Make the script runnable:

```bash
cd "$(git rev-parse --show-toplevel)"
chmod +x tools/gcp-guided-setup/*.sh
```

Click **Start** to begin.

## Check first

**Why.** See what you already have before anything is created. The estate audit is read-only: it lists your organization, folders and projects, every log sink that already exports logs, Pub/Sub topics, and your audit settings.

```bash
./tools/gcp-guided-setup/audit-gcp-estate.sh
```

**You should see:** Your organization, and the sinks set on it that already send logs somewhere. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one.

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

## Script step 2: What you can change

**What it does.** Asks Google which of the needed permissions you hold, before anything is created.

**Why.** A missing permission otherwise fails halfway through, leaving half a pipeline.

**Permissions it checks:**

- Logs Configuration Writer (roles/logging.configWriter) on the organization, for the log sink. Not included in Organization Admin
- Organization Admin or Security Admin on the same scope, for Data Access logs (script step 6)
- Project Creator + Billing User on the organization and billing account, for a new logging project (script step 3)
- Owner, or Pub/Sub Admin + Service Account Admin + Service Account Key Admin + Service Usage Admin on the logging project, for script steps 3 to 5. Script step 3 checks these, once the project is chosen

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
```

**You should see:** A ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time: script step 3 checks it.

## Script step 3: Logging project

**What it does.** Creates a dedicated logging project or uses one you have, optionally links billing, and turns on the APIs. Then it checks your rights in the project, and whether the organization policy iam.disableServiceAccountKeyCreation blocks the key script step 5 makes, before script step 4 builds anything.

**Why.** One project holds the topic, the subscription and Abstract's account. Keep it separate from workloads.

**Creates:**

- A project (only if you choose to create one)
- APIs: Pub/Sub, Cloud Logging, IAM, Resource Manager (plus Admin SDK and Monitoring if you add script steps 7 and 8)

_Billing is optional on this path. Pub/Sub and Logging free tiers cover an audit feed._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
```

**You should see:** A ✓ for the active project, every API, building the pipeline in the project, and "service-account keys are allowed". A ✗ on the key policy means: ask for an exception on this project before you go on.

Prefer Terraform? The same piece is `templates/gcp/gcp-foundation-logging-project`.

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

## Script step 5: Abstract's access

**What it does.** Creates the service account Abstract signs in as, lets it read only the one subscription, and makes its key.

**Why.** Abstract pulls. It needs subscriber on the subscription and nothing else.

**Creates:**

- Service account abstract-pubsub-reader
- Subscriber role on the subscription only
- A JSON key, in ~/abstract-keys, readable only by you and outside any repository

_The key leaves Cloud Shell in script step 10, goes into Abstract, and is then deleted everywhere._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
```

**You should see:** A ✓ for the account, for reading the subscription, for "no project-wide roles", and for a key file in ~/abstract-keys.

## Script step 6: Data Access logs (optional)

**What it does.** Turns on logs of who read or changed data in BigQuery, Cloud Storage and Cloud KMS, and routes them.

**Why.** Admin Activity logs are always on. Data Access logs are off until two switches are both on.

- Switch 1, generate them: the audit settings at your scope. Only the audit settings change; a copy is saved first.
- Switch 2, route them: the sink filter from script step 4. Either switch alone does nothing, silently.

_DATA_READ is high volume and off by default. Start with ADMIN_READ and DATA_WRITE._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
```

Answer **no** at the first question to skip it.

**You should see:** A ✓ for switch 1 and switch 2, for each service you chose.

Prefer Terraform? The same piece is `templates/gcp/gcp-foundation-data-access-audit-logs`.

## Script step 7: Google Workspace logs (optional)

**What it does.** Sets up sign-in, admin and token logs from Google Workspace, which never pass through Cloud Logging.

**Why.** Abstract reads them from the Workspace Reports API as a separate account a Workspace super admin allows.

**Creates:**

- Admin SDK API on the logging project
- Service account abstract-workspace-reader and its key

**A person must do this part:** A Workspace super admin opens admin.google.com → Security → Access and data control → API controls → Domain-wide delegation → Add new, and enters the Client ID and the two read-only scopes the script prints. A Google Cloud Owner cannot do this step.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
```

Answer **no** at the first question to skip it.

**You should see:** A ✓ "delegation works: the Reports API answered as" your admin. Delegation can take a few minutes after the super admin saves it; run this step again until it does.

Prefer Terraform? The same piece is `templates/gcp/gcp-source-google-workspace-logs`.

## Script step 8: Health alerts (optional)

**What it does.** Creates three alerts and an email channel, so you hear when the pipeline stops.

**Why.** A stopped pipeline is silent. These catch sink errors, no messages, and Abstract not reading.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
```

Answer **no** at the first question to skip it.

**You should see:** Three "Abstract log pipeline" alert policies exist, sending to your email.

Prefer Terraform? The same piece is `templates/gcp/gcp-monitoring-pipeline-health-alerts`.

## Script step 9: Test and verify

**What it does.** Writes a harmless admin event inside your scope and waits for it on a probe subscription of its own, never on Abstract's.

**Why.** Proves the whole path before Abstract is involved. A new sink needs about 3 minutes before it routes anything.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
```

**You should see:** A ✓ "the test event arrived on abstract-audit-logs", usually within 5 minutes.

## Script step 10: Connect Abstract

**What it does.** Prints the exact values for the GCP Pub/Sub Source integration in Abstract (and the Google Workspace Audit Log Integration, if you set it up), and the commands that get the key files out of this temporary session.

**Why.** The project field is the one most often filled in wrong. It is the project with the subscription.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
```

**Get the keys out of Cloud Shell.** They exist only in this session. Download them to the computer you use for Abstract. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat:

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

Then download your answers. This Cloud Shell session is temporary, and the clean-up needs them to know what the setup made. If you ran script step 6, download its backup of your earlier audit settings too:

```bash
cloudshell download ~/.abstract-gcp-setup.env
ls abstract-audit-config-backup-*.json 2>/dev/null && cloudshell download abstract-audit-config-backup-*.json
```

## Clean up

To remove the setup later, delete the integrations in Abstract first, so they stop reading. In a new session, upload the answers file you downloaded (More, then Upload) and load it with `--state`. Then list what would be removed. Nothing is deleted without --confirm:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
```

Lost the answers file? `--remove --project <logging-project-id>` lists everything that carries the setup's names, with the command to remove each, and deletes nothing itself.

When the list is right, remove it:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
```

It removes only what this setup created: the sink, topic and subscription, the service accounts, the health alerts and the key files. It never deletes the logging project. Data Access audit settings, and anything that existed before you started, are listed for you to change by hand.

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Check everything again at any time. It changes nothing:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --check
```

Delete every copy of the key files once they are uploaded to Abstract: in Cloud Shell and on your computer.
