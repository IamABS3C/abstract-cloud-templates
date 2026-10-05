# Google Cloud guided setup

<walkthrough-tutorial-duration duration="20"></walkthrough-tutorial-duration>

## Before you start

One walkthrough that creates and checks everything Abstract needs in Google Cloud, in the order it has to happen. Nothing changes until you say yes, and every step can be re-checked later.

Each step runs one part of the guided script. It prints what it will do, asks before it changes anything, and checks the result. You can stop at any step and come back; your answers are kept.

Make the script runnable:

```bash
chmod +x tools/gcp-guided-setup/abstract-gcp-setup.sh
```

Click **Start** to begin.

## 1. Sign-in and organization

**What it does.** Confirms who you are signed in as, finds your organization and asks how much of Google Cloud should send logs.

**Why.** Every later check is made for this account. The scope decides what is covered.

- Whole organization: every project, including ones created later. Recommended.
- One folder: every project in it. Projects outside it are missed.
- One project: a pilot. Other and future projects are not covered.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
```

**You should see:** The account and organization are shown, and the scope is saved.

## 2. What you can change

**What it does.** Asks Google which of the needed permissions you hold, before anything is created.

**Why.** A missing permission otherwise fails halfway through, leaving half a pipeline.

**Permissions it checks:**

- Logs Configuration Writer (roles/logging.configWriter) on the organization, for the log sink. Not included in Organization Admin
- Organization Admin or Security Admin on the same scope, for Data Access logs (step 6
- Project Creator + Billing User on the organization and billing account, for a new logging project (step 3
- Owner, or Pub/Sub Admin + Service Account Admin + Service Account Key Admin + Service Usage Admin on the logging project, for steps 3 to 5

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
```

**You should see:** Every row is green, or you know who to ask. It also checks the org policy that blocks service-account keys.

## 3. Logging project

**What it does.** Creates a dedicated logging project or uses one you have, optionally links billing, and turns on the APIs.

**Why.** One project holds the topic, the subscription and Abstract's account. Keep it separate from workloads.

**Creates:**

- A project (only if you choose to create one)
- APIs: Pub/Sub, Cloud Logging, IAM, Resource Manager (plus Admin SDK and Monitoring if you add steps 7 and 8)

_Billing is optional on this path. Pub/Sub and Logging free tiers cover an audit feed._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
```

**You should see:** The project is active and every API is on.

Prefer Terraform? The same piece is `templates/gcp/gcp-foundation-logging-project`.

## 4. Log pipeline

**What it does.** Creates the topic and subscription, then the sink that copies audit logs to the topic as they are written.

**Why.** The sink sits at your chosen scope, so new projects are covered automatically. There is no backfill. An existing sink to the same topic is reused and its filter is only ever extended.

**Creates:**

- Pub/Sub topic abstract-audit-logs
- Subscription abstract-audit-logs-sub that never expires, 7 days retention
- Log sink abstract-org-audit-sink at the scope, including child projects (an existing sink to the same topic is reused)
- Publisher role on the topic for the sink's own identity

_The publisher grant is the step most often missed. Without it the sink looks healthy and sends nothing._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
```

**You should see:** The sink points at the topic, its filter is current, and its identity can publish.

Prefer Terraform? The same piece is `templates/gcp/gcp-source-audit-logs-organization, gcp-source-audit-logs-folder or gcp-source-audit-logs-project`.

## 5. Abstract's access

**What it does.** Creates the service account Abstract signs in as, lets it read only the one subscription, and makes its key.

**Why.** Abstract pulls. It needs subscriber on the subscription and nothing else.

**Creates:**

- Service account abstract-pubsub-reader
- Subscriber role on the subscription only
- A JSON key, in ~/abstract-keys, readable only by you and outside any repository

_Upload the key to Abstract, then delete the file._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
```

**You should see:** The account exists, can read the subscription, and holds no project-wide roles.

## 6. Data Access logs (optional)

**What it does.** Turns on logs of who read or changed data in BigQuery, Cloud Storage and Cloud KMS, and routes them.

**Why.** Admin Activity logs are always on. Data Access logs are off until two switches are both on.

- Switch 1, generate them: the audit settings at your scope. Only the audit settings change; a copy is saved first.
- Switch 2, route them: the sink filter from step 4. Either switch alone does nothing, silently.

_DATA_READ is high volume and off by default. Start with ADMIN_READ and DATA_WRITE._

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
```

Answer **no** at the first question to skip it.

**You should see:** Both switches report on for each service.

Prefer Terraform? The same piece is `templates/gcp/gcp-foundation-data-access-audit-logs`.

## 7. Google Workspace logs (optional)

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

**You should see:** The script signs in as the account for your admin and gets an answer from the Reports API.

Prefer Terraform? The same piece is `templates/gcp/gcp-source-google-workspace-logs`.

## 8. Health alerts (optional)

**What it does.** Creates three alerts and an email channel, so you hear when the pipeline stops.

**Why.** A stopped pipeline is silent. These catch sink errors, no messages, and Abstract not reading.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
```

Answer **no** at the first question to skip it.

**You should see:** Three "Abstract log pipeline" alert policies exist, sending to your email.

Prefer Terraform? The same piece is `templates/gcp/gcp-monitoring-pipeline-health-alerts`.

## 9. Test and verify

**What it does.** Writes a harmless admin event inside your scope and waits for it on the subscription.

**Why.** Proves the whole path before Abstract is involved. A new sink needs about 3 minutes before it routes anything.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
```

**You should see:** The probe event arrives, usually within 5 minutes.

## 10. Connect Abstract

**What it does.** Prints the exact values for the GCP Pub/Sub integration (and Google Workspace, if you set it up).

**Why.** The project field is the one most often filled in wrong. It is the project with the subscription.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
```

**You should see:** Events appear in Abstract under vendor GCP. Re-check any time with: ./tools/gcp-guided-setup/abstract-gcp-setup.sh --check

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Check everything again at any time. It changes nothing:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --check
```

Delete the key files once they are uploaded to Abstract.
