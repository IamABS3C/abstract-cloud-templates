# Google Cloud audit logs to Abstract, step by step

<!-- Generated from tools/guides/steps/gcp.yml by `python -m tools.templates generate`. Edit that file. -->

Every step of sending your Google Cloud audit logs to Abstract, written three ways: clicking through the Google Cloud console, typing gcloud commands, or deploying the same pipeline with Infrastructure Manager. Each step says who needs which role, how to check you hold it, and how to grant it if you do not. You end up with one log sink that copies audit logs to a Pub/Sub topic in a logging project, a subscription Abstract reads, and a service account that can read only that subscription. Nothing here touches your workloads. Prefer to be asked questions? The guided setup script in Cloud Shell does the same steps and checks each one; its step numbers are given on every step below. Deployment Manager is not offered: Google ended its support on 31 March 2026, new users have been unable to start with it since 30 June 2026, and Infrastructure Manager is its successor. The console click paths use the labels the Google Cloud console showed on 13 October 2026; the screenshots come from a test organization, with its names and IDs replaced by example values.

The same guide, with your own values filled into every command and every click, is in the onboarding app.
Every placeholder in CAPITALS below is one of these values:

| Value | What it is | Example |
|---|---|---|
| `YOUR_EMAIL` | Your Google account | `admin@example.com` |
| `ORG_ID` | Organization ID (digits). The Manage resources page of the Google Cloud console, or `gcloud organizations list`. | `123456789012` |
| `FOLDER_ID` | Folder ID (digits) | `987654321098` |
| `SOURCE_PROJECT_ID` | The project the logs come from | `app-prod-123` |
| `LOGGING_PROJECT_ID` | Logging project ID. 6 to 30 lowercase letters, digits and hyphens, starting with a letter. It cannot be changed later. | `security-logging-123` |
| `TEST_PROJECT_ID` | A project inside your scope, for the test event. Inside the organization, folder or project that sends logs. The test creates and deletes one Pub/Sub topic there. | `app-prod-123` |
| `BILLING_ACCOUNT_ID` | Billing account ID (optional, needed for Infrastructure Manager) | `0123AB-4567CD-89EF01` |
| `WRITER_IDENTITY` | The sink's writer identity. Shown when the sink is created. It starts with serviceAccount:. | `serviceAccount:service-org-123456789012@gcp-sa-logging.iam.gserviceaccount.com` |
| `INFRA_MANAGER_REGION` | Infrastructure Manager region. A region on Google's Infrastructure Manager locations page that your organization allows. | `us-central1` |
| `RELEASE_TAG` | Release tag of the templates repository. The newest release tag of the templates repository. The Infrastructure Manager deploy step lists them. | `release-20261013T204400Z-814a551` |
| `CHANNEL_ID` | Notification channel ID (digits). The last part of the channel name the alerts step lists. | `1234567890123456789` |
| `ALERT_EMAIL` | Email for pipeline alerts (optional) | `soc@example.com` |

**How do you want to work?**

- **Google Cloud console.** Click through the console. Nothing to install; every page is linked.
- **Command line.** gcloud commands, one per box, ready to paste into Cloud Shell or any terminal with gcloud. The guided script runs the same steps for you if you would rather answer questions.
- **Infrastructure Manager.** Google's managed Terraform. It deploys the pipeline from the public templates repository and keeps the Terraform state for you. Needs a logging project with billing enabled, because it runs on Cloud Build.

**What should send logs?**

- **The whole organization.** Every project, including ones created later. Pick it unless you cannot get organization-level access.
- **One folder.** Every project in the folder and its sub-folders. Projects outside it, including new ones created at the organization root, are missed.
- **One project.** A pilot that proves the pipeline before you ask for organization access. Replace it later; do not repeat it per project.

**The logging project**

- **Create a new one.** A project that holds only this pipeline. The cleanest choice.
- **Use one you have.** Fine if it is not a workload project. Anyone who owns it can read or break the pipeline.

**How much audit logging?**

- **Admin activity only.** Admin Activity, System Event and Policy Denied logs. Always on in Google Cloud, so there is nothing to turn on. The lowest volume.
- **Admin activity, identity and data changes (recommended).** Adds Data Access logs (Admin Read and Data Write) for BigQuery, Cloud Storage, Cloud KMS, IAM (service-account token minting) and the Security Token Service. Who read a configuration, who changed data, who minted a token. Moderate volume.
- **Everything.** Data Access logs, Data Read included, for every service. Every object read and every query is logged: the complete record, and where the bill comes from.

## Steps

1. [Sign in and find your IDs](#sign-in-and-find-your-ids)
2. [Check your permissions, and grant what is missing](#check-your-permissions-and-grant-what-is-missing)
3. [The logging project](#the-logging-project)
4. [Turn on the APIs](#turn-on-the-apis)
5. [Check and grant the Infrastructure Manager roles](#check-and-grant-the-infrastructure-manager-roles)
6. [The topic and the subscription Abstract reads](#the-topic-and-the-subscription-abstract-reads)
7. [The log sink](#the-log-sink)
8. [Let the sink publish to the topic](#let-the-sink-publish-to-the-topic)
9. [Deploy the pipeline with Infrastructure Manager](#deploy-the-pipeline-with-infrastructure-manager)
10. [Abstract's service account and key](#abstracts-service-account-and-key)
11. [Turn on Data Access logs](#turn-on-data-access-logs)
12. [Alerts for a stalled pipeline](#alerts-for-a-stalled-pipeline)
13. [Prove logs arrive](#prove-logs-arrive)
14. [Connect Abstract](#connect-abstract)
15. [Keep it healthy](#keep-it-healthy)

## Sign in and find your IDs

*Step 1 · guided script step 1*

Every later step names the organization, folder or project it acts on. Find the IDs once; the page fills them into every command and click path.

### Google Cloud console

Sign in to the Google Cloud console as YOUR_EMAIL. **Manage resources** lists your organization, its folders and projects with their IDs.

Open [Manage resources](https://console.cloud.google.com/cloud-resource-manager).

*The whole organization or One folder:* Copy the organization's ID (digits) into Your values.

*One folder:* Copy the folder's ID (digits) and the organization's ID into Your values.

*One project:* Copy the ID of the project the logs come from, and the organization's ID, into Your values.

### Command line

Open Cloud Shell from the console's top bar, or any terminal with gcloud. Sign in. It waits for you to open a link and paste back a code, so run it on its own:

```bash
gcloud auth login --update-adc
```

Check the account gcloud uses is yours. It prints one account, marked with a star:

```bash
gcloud auth list --filter=status:ACTIVE --format="value(account)"
```

Your organization's ID is the number in the ID column.

```bash
gcloud organizations list
```

*One folder:* Your folder's ID is the number in the ID column.

*One folder:*

```bash
gcloud resource-manager folders list --organization=ORG_ID
```

*One project:* Check the project the logs come from, and which organization or folder it sits under.

*One project:*

```bash
gcloud projects describe SOURCE_PROJECT_ID --format="value(projectId,lifecycleState,parent.type,parent.id)"
```

### Infrastructure Manager

Open Cloud Shell from the console's top bar, or any terminal with gcloud. Sign in. It waits for you to open a link and paste back a code, so run it on its own:

```bash
gcloud auth login --update-adc
```

Check the account gcloud uses is yours. It prints one account, marked with a star:

```bash
gcloud auth list --filter=status:ACTIVE --format="value(account)"
```

Your organization's ID is the number in the ID column.

```bash
gcloud organizations list
```

*One folder:* Your folder's ID is the number in the ID column.

*One folder:*

```bash
gcloud resource-manager folders list --organization=ORG_ID
```

*One project:* Check the project the logs come from, and which organization or folder it sits under.

*One project:*

```bash
gcloud projects describe SOURCE_PROJECT_ID --format="value(projectId,lifecycleState,parent.type,parent.id)"
```

### How you know it worked

gcloud lists your organization, and the ID you typed into this page matches it. An empty list means the account cannot see the organization: it needs Browser (roles/browser) there, which the next step checks.

Google documentation: [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions)

## Check your permissions, and grant what is missing

*Step 2 · guided script step 2*

Each step needs specific roles. Check them all now, before anything is built: a missing role found halfway leaves a half-built pipeline. The one that stops almost everyone is Logs Configuration Writer at the organization, folder or project of the sink. Organization Administrator does not include it.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/browser` Browser (organization scope) | the organization, folder or project of the sink | required | see the organization, its folders and projects (steps 1 and 3) |
| You, or whoever runs the setup | `roles/resourcemanager.folderViewer` Folder Viewer (folder scope) | the organization, folder or project of the sink | required | see the folder and its projects (steps 1 and 3) |
| You, or whoever runs the setup | `roles/browser` Browser (project scope) | the organization, folder or project of the sink | required | see the project (steps 1 and 3) |
| You, or whoever runs the setup | `roles/logging.configWriter` Logs Configuration Writer | the organization, folder or project of the sink | required | create the log sink (step 4) |
| You, or whoever runs the setup | `roles/orgpolicy.policyViewer` Organization Policy Viewer | the organization, folder or project of the sink | required | read the organization policies that can block the key (step 3) |
| You, or whoever runs the setup | `roles/iam.securityReviewer` Security Reviewer | the organization, folder or project of the sink | required | read IAM policies and the audit settings (steps 2, 5 and 6) |
| You, or whoever runs the setup | `roles/resourcemanager.projectCreator` Project Creator (organization, folder scope) | the organization, folder or project of the sink | optional | create a new logging project (step 3) |
| You, or whoever runs the setup | `roles/iam.securityAdmin` Security Admin | the organization, folder or project of the sink | optional | turn on Data Access logs (step 6). Powerful: it can change IAM anywhere at the scope |
| You, or whoever runs the setup | `roles/billing.user` Billing Account User | the billing account | optional | link a billing account to the logging project (step 3) |
| You, or whoever runs the setup | `roles/pubsub.admin` Pub/Sub Admin | the logging project | required | create the topic and subscription, and grant on them (steps 4 and 5) |
| You, or whoever runs the setup | `roles/iam.serviceAccountAdmin` Service Account Admin | the logging project | required | create Abstract's service accounts (steps 5 and 7) |
| You, or whoever runs the setup | `roles/iam.serviceAccountKeyAdmin` Service Account Key Admin | the logging project | required | create the key Abstract signs in with (steps 5 and 7) |
| You, or whoever runs the setup | `roles/serviceusage.serviceUsageAdmin` Service Usage Admin | the logging project | required | turn on the APIs (steps 3, 7 and 8) |
| You, or whoever runs the setup | `roles/monitoring.editor` Monitoring Editor | the logging project | optional | create the health alerts (step 8) |

### Google Cloud console

Check what you hold with Policy Troubleshooter. It counts every route: a direct grant, a group, or a role inherited from a folder or the organization.

Open [Policy Troubleshooter](https://console.cloud.google.com/iam-admin/troubleshooter).

Leave **Manual** selected. In **Principal** enter YOUR_EMAIL. Under **Resource permission pairs**, enter the resource's full name in **Resource 1** and a permission from the table above in **Permission 1**; **Add another pair** adds up to five pairs a query. Click **Check access**.

*The whole organization:*

```text
//cloudresourcemanager.googleapis.com/organizations/ORG_ID
```

*One folder:*

```text
//cloudresourcemanager.googleapis.com/folders/FOLDER_ID
```

*One project:*

```text
//cloudresourcemanager.googleapis.com/projects/SOURCE_PROJECT_ID
```

*Screenshot in the app: Policy Troubleshooter with a principal, the organization's full resource name and logging.sinks.create filled in, ready for Check access.*

Check the permissions on the logging project the same way, with //cloudresourcemanager.googleapis.com/projects/LOGGING_PROJECT_ID.

> Policy Troubleshooter cannot read permissions set on a Pub/Sub topic or subscription itself. For those, check the logging project instead, then look at the topic's or subscription's own permissions panel.

To grant a missing role: open the **IAM** page and select the organization, folder or project the table names. Click **Grant access**. In **New principals** enter the person's email, in **Role** search for the role's title and pick it, and click **Save**. One role per row; **Add another role** adds more in the same go.

Open [IAM](https://console.cloud.google.com/iam-admin/iam).

*Screenshot in the app: The Grant access panel at the organization, with one principal and the Logs Configuration Writer role chosen.*

> The IAM page lists inherited roles too, but you cannot change them there: change a role at the resource where it was granted.

### Command line

The guided script asks Google which of these permissions you hold, by any route: a direct grant, a group, or a role inherited from a folder or the organization. It changes nothing. Run it from the top folder of the templates repository. In Cloud Shell, fetch the repository first:

```bash
git clone https://github.com/IamABS3C/abstract-cloud-templates
```

```bash
cd abstract-cloud-templates
```

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL --check
```

Every role you lack is listed with the one command that grants it. Someone who can set IAM policy where each role goes (an Organization Administrator for the organization, a project Owner for the logging project) grants them all, asking before each one, one binding per role, and recording them so clean-up can take back exactly those:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL
```

Or grant a single role by hand with the command in the table above. Each adds one binding and changes nothing else in the policy. To check one permission for someone else, ask Policy Troubleshooter (it needs Security Reviewer and the Policy Troubleshooter API):

*The whole organization:*

```bash
gcloud policy-intelligence troubleshoot-policy iam //cloudresourcemanager.googleapis.com/organizations/ORG_ID --principal-email=YOUR_EMAIL --permission=logging.sinks.create
```

*One folder:*

```bash
gcloud policy-intelligence troubleshoot-policy iam //cloudresourcemanager.googleapis.com/folders/FOLDER_ID --principal-email=YOUR_EMAIL --permission=logging.sinks.create
```

*One project:*

```bash
gcloud policy-intelligence troubleshoot-policy iam //cloudresourcemanager.googleapis.com/projects/SOURCE_PROJECT_ID --principal-email=YOUR_EMAIL --permission=logging.sinks.create
```

### Infrastructure Manager

The guided script asks Google which of these permissions you hold, by any route: a direct grant, a group, or a role inherited from a folder or the organization. It changes nothing. Run it from the top folder of the templates repository. In Cloud Shell, fetch the repository first:

```bash
git clone https://github.com/IamABS3C/abstract-cloud-templates
```

```bash
cd abstract-cloud-templates
```

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL --check
```

Every role you lack is listed with the one command that grants it. Someone who can set IAM policy where each role goes (an Organization Administrator for the organization, a project Owner for the logging project) grants them all, asking before each one, one binding per role, and recording them so clean-up can take back exactly those:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL
```

Or grant a single role by hand with the command in the table above. Each adds one binding and changes nothing else in the policy. To check one permission for someone else, ask Policy Troubleshooter (it needs Security Reviewer and the Policy Troubleshooter API):

*The whole organization:*

```bash
gcloud policy-intelligence troubleshoot-policy iam //cloudresourcemanager.googleapis.com/organizations/ORG_ID --principal-email=YOUR_EMAIL --permission=logging.sinks.create
```

*One folder:*

```bash
gcloud policy-intelligence troubleshoot-policy iam //cloudresourcemanager.googleapis.com/folders/FOLDER_ID --principal-email=YOUR_EMAIL --permission=logging.sinks.create
```

*One project:*

```bash
gcloud policy-intelligence troubleshoot-policy iam //cloudresourcemanager.googleapis.com/projects/SOURCE_PROJECT_ID --principal-email=YOUR_EMAIL --permission=logging.sinks.create
```

### How you know it worked

The check prints a ✓ for every required role. Optional roles are needed only for what they name (a new project, billing, Data Access logs, alerts). A grant takes a minute or two to apply everywhere.

Google documentation: [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Troubleshoot IAM permissions](https://docs.cloud.google.com/policy-intelligence/docs/troubleshoot-access) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role) · [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter)

## The logging project

*Step 3 · guided script step 3*

One project holds the topic, the subscription and Abstract's service account. Keep it apart from anything that runs workloads: Pub/Sub quota is used here, and whoever owns the project can read or break the pipeline.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/browser` Browser (organization scope) | the organization, folder or project of the sink | required | see the organization, its folders and projects (steps 1 and 3) |
| You, or whoever runs the setup | `roles/resourcemanager.folderViewer` Folder Viewer (folder scope) | the organization, folder or project of the sink | required | see the folder and its projects (steps 1 and 3) |
| You, or whoever runs the setup | `roles/browser` Browser (project scope) | the organization, folder or project of the sink | required | see the project (steps 1 and 3) |
| You, or whoever runs the setup | `roles/orgpolicy.policyViewer` Organization Policy Viewer | the organization, folder or project of the sink | required | read the organization policies that can block the key (step 3) |
| You, or whoever runs the setup | `roles/resourcemanager.projectCreator` Project Creator (organization, folder scope) | the organization, folder or project of the sink | optional | create a new logging project (step 3) |
| You, or whoever runs the setup | `roles/billing.user` Billing Account User | the billing account | optional | link a billing account to the logging project (step 3) |
| You, or whoever runs the setup | `roles/serviceusage.serviceUsageAdmin` Service Usage Admin | the logging project | required | turn on the APIs (steps 3, 7 and 8) |

### Google Cloud console

*Create a new one:* Open [New Project](https://console.cloud.google.com/projectcreate).

*Create a new one:* In **Project name** enter LOGGING_PROJECT_ID. Check **Project ID** reads LOGGING_PROJECT_ID too and correct it if not: it can never change afterwards. In **Organization** pick your organization.

*Create a new one, The whole organization or One project:* **Parent resource** is the organization; leave it, and click **Create**.

*Create a new one, One folder:* In **Parent resource** click **Browse** and pick your folder (FOLDER_ID), then click **Create**.

*Create a new one:* *Screenshot in the app: The New Project form with the project name and ID filled in and the organization as parent resource.*

*Use one you have:* Using a project you have: open the **IAM** page for LOGGING_PROJECT_ID and check your roles against the table above, and check the Pub/Sub topics list has no abstract-audit-logs topic yet. If it has, someone set this up before; find them first.

*Use one you have:* Open [Pub/Sub topics](https://console.cloud.google.com/cloudpubsub/topic/list?project=LOGGING_PROJECT_ID).

Billing, optional for this pipeline and needed for Infrastructure Manager and the alerts: on **Manage billing accounts**, select the **My projects** tab, open the **Actions** menu on the LOGGING_PROJECT_ID row, select **Change billing**, choose the account (BILLING_ACCOUNT_ID), and click **Set account**.

Open [Manage billing accounts](https://console.cloud.google.com/billing).

Keys: an organization policy can forbid the key Abstract signs in with. On **Organization policies** for LOGGING_PROJECT_ID, type disableServiceAccountKeyCreation into the **Filter**. Two constraints are listed; their **Enforcement state** must read Inactive for the key step to work.

Open [Organization policies](https://console.cloud.google.com/iam-admin/orgpolicies?project=LOGGING_PROJECT_ID).

*Screenshot in the app: Organization policies filtered to the two key-creation constraints, both Inactive on the logging project.*

> Google enforces iam.disableServiceAccountKeyCreation by default for organizations created on or after 3 May 2024, so a newer organization usually needs the exception described in the key step.

### Command line

*Create a new one, The whole organization or One project:* Create it under your organization. The ID is permanent and unique across Google Cloud.

*Create a new one, The whole organization or One project:*

```bash
gcloud projects create LOGGING_PROJECT_ID --organization=ORG_ID
```

*Create a new one, One folder:* Create it under your folder. The ID is permanent and unique across Google Cloud.

*Create a new one, One folder:*

```bash
gcloud projects create LOGGING_PROJECT_ID --folder=FOLDER_ID
```

*Use one you have:* Check the project you are reusing exists, is active, and has no Abstract topic yet.

*Use one you have:*

```bash
gcloud projects describe LOGGING_PROJECT_ID --format="value(projectId,lifecycleState)"
```

*Use one you have:*

```bash
gcloud pubsub topics list --project=LOGGING_PROJECT_ID --format="value(name)"
```

Billing is optional for this pipeline: Pub/Sub and Cloud Logging have free tiers that cover an audit feed. Link it now if you will deploy with Infrastructure Manager or create the health alerts.

```bash
gcloud billing projects link LOGGING_PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
```

An organization policy can forbid service-account keys, which Abstract needs. Check both constraints now; "enforced: true" on either means the key will be refused until an exception is made for this project.

```bash
gcloud resource-manager org-policies describe iam.disableServiceAccountKeyCreation --project=LOGGING_PROJECT_ID --effective
```

```bash
gcloud org-policies describe iam.managed.disableServiceAccountKeyCreation --project=LOGGING_PROJECT_ID --effective
```

### Infrastructure Manager

Infrastructure Manager needs the logging project to exist, with an open billing account. Create it as on the command line path:

*Create a new one, The whole organization or One project:*

```bash
gcloud projects create LOGGING_PROJECT_ID --organization=ORG_ID
```

*Create a new one, One folder:*

```bash
gcloud projects create LOGGING_PROJECT_ID --folder=FOLDER_ID
```

```bash
gcloud billing projects link LOGGING_PROJECT_ID --billing-account=BILLING_ACCOUNT_ID
```

Confirm billing is on. It must print True; Cloud Build, which Infrastructure Manager runs on, refuses a project without it.

```bash
gcloud billing projects describe LOGGING_PROJECT_ID --format="value(billingEnabled)"
```

```bash
gcloud org-policies describe iam.managed.disableServiceAccountKeyCreation --project=LOGGING_PROJECT_ID --effective
```

The Terraform template that does the same: [`gcp-foundation-logging-project`](../../templates/gcp/gcp-foundation-logging-project/README.md).

### How you know it worked

The project is ACTIVE, and neither key constraint is enforced on it (or an exception is in place).

### If it does not

| If | Then |
|---|---|
| The project ID is taken | IDs are unique across all of Google Cloud. Add a suffix and try again. |
| A key constraint is enforced | An Organization Policy Administrator overrides it for this project only (the key step shows how), or Abstract cannot sign in. |

Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#managed-constraints) · [Create organization policies](https://docs.cloud.google.com/organization-policy/create-organization-policies)

## Turn on the APIs

*Step 4 · guided script step 3*

A new project has the Pub/Sub, Cloud Logging, IAM and Resource Manager APIs off. Turning them on takes a minute and costs nothing.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/browser` Browser (organization scope) | the organization, folder or project of the sink | required | see the organization, its folders and projects (steps 1 and 3) |
| You, or whoever runs the setup | `roles/resourcemanager.folderViewer` Folder Viewer (folder scope) | the organization, folder or project of the sink | required | see the folder and its projects (steps 1 and 3) |
| You, or whoever runs the setup | `roles/browser` Browser (project scope) | the organization, folder or project of the sink | required | see the project (steps 1 and 3) |
| You, or whoever runs the setup | `roles/orgpolicy.policyViewer` Organization Policy Viewer | the organization, folder or project of the sink | required | read the organization policies that can block the key (step 3) |
| You, or whoever runs the setup | `roles/resourcemanager.projectCreator` Project Creator (organization, folder scope) | the organization, folder or project of the sink | optional | create a new logging project (step 3) |
| You, or whoever runs the setup | `roles/billing.user` Billing Account User | the billing account | optional | link a billing account to the logging project (step 3) |
| You, or whoever runs the setup | `roles/serviceusage.serviceUsageAdmin` Service Usage Admin | the logging project | required | turn on the APIs (steps 3, 7 and 8) |

### Google Cloud console

Open [API Library](https://console.cloud.google.com/apis/library?project=LOGGING_PROJECT_ID).

Check the project picker shows LOGGING_PROJECT_ID. In **Search for APIs & Services**, find Cloud Pub/Sub API, open it and click **Enable**. Do the same for Cloud Logging API, Identity and Access Management (IAM) API, and Cloud Resource Manager API. An API already on shows **Manage** instead of **Enable**.

*Screenshot in the app: An API's page in the API Library with its Enable button (here the Infrastructure Manager API).*

### Command line

```bash
gcloud services enable pubsub.googleapis.com logging.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com --project=LOGGING_PROJECT_ID
```

Check all four are on. An organization policy that restricts services can make the command succeed and enable nothing.

```bash
gcloud services list --enabled --project=LOGGING_PROJECT_ID --format="value(config.name)"
```

### Infrastructure Manager

Infrastructure Manager needs its own API and Cloud Build's; each template turns on the APIs it uses itself. Without open billing this reports success and enables nothing, so check afterwards.

```bash
gcloud services enable config.googleapis.com cloudbuild.googleapis.com --project=LOGGING_PROJECT_ID
```

In the console, each API's page in the API Library has an **Enable** button:

*Screenshot in the app: The Infrastructure Manager API in the API Library, with its Enable button.*

```bash
gcloud services list --enabled --project=LOGGING_PROJECT_ID --format="value(config.name)"
```

### How you know it worked

The list includes pubsub.googleapis.com, logging.googleapis.com, iam.googleapis.com and cloudresourcemanager.googleapis.com (and, for Infrastructure Manager, config.googleapis.com and cloudbuild.googleapis.com).

Google documentation: [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [gcloud services enable](https://docs.cloud.google.com/sdk/gcloud/reference/services/enable)

## Check and grant the Infrastructure Manager roles

*Step 5 · guided script step 2 · only with Infrastructure Manager*

Infrastructure Manager runs Terraform as a service account of its own, in the logging project the steps before made. You need enough to create that account, act as it and start the deployment; the account needs what the templates create. The Logs Configuration Writer grant at the organization, folder or project of the sink is the one that gets missed: it fails at apply, after the topic and subscription already exist.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, to deploy with Infrastructure Manager | `roles/serviceusage.serviceUsageAdmin` Service Usage Admin | the logging project | required | turn on the Infrastructure Manager and Cloud Build APIs |
| You, to deploy with Infrastructure Manager | `roles/iam.serviceAccountAdmin` Service Account Admin | the logging project | required | create the service account Infrastructure Manager runs as |
| You, to deploy with Infrastructure Manager | `roles/config.admin` Cloud Infrastructure Manager Admin | the logging project | required | create previews and deployments |
| You, to deploy with Infrastructure Manager | `roles/iam.serviceAccountUser` Service Account User | the Infrastructure Manager service account | required | start a deployment that runs as the Infrastructure Manager service account |
| The Infrastructure Manager service account | `roles/config.agent` Cloud Infrastructure Manager Agent | the logging project | required | run deployments for Infrastructure Manager: it reads and writes the deployment's Terraform state |
| The Infrastructure Manager service account | `roles/logging.configWriter` Logs Configuration Writer | the organization, folder or project of the sink | required | create the log sink at the scope |
| The Infrastructure Manager service account | `roles/pubsub.admin` Pub/Sub Admin | the logging project | required | create the topic and subscription, and grant on them |
| The Infrastructure Manager service account | `roles/iam.serviceAccountAdmin` Service Account Admin | the logging project | required | create Abstract's service account |
| The Infrastructure Manager service account | `roles/serviceusage.serviceUsageAdmin` Service Usage Admin | the logging project | required | turn on the APIs each template names in apis.tf |
| The Infrastructure Manager service account | `roles/iam.securityAdmin` Security Admin | the organization, folder or project of the sink | optional | only to deploy gcp-foundation-data-access-audit-logs, which changes the audit settings at the scope |
| The Infrastructure Manager service account | `roles/monitoring.editor` Monitoring Editor | the logging project | optional | only to deploy gcp-monitoring-pipeline-health-alerts |

### Infrastructure Manager

Check your own roles for Infrastructure Manager, changing nothing. Run it from the top folder of the templates repository:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL --for infra-manager --check
```

Grant what is missing. A project Owner of the logging project runs it, or is handed the commands:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL --for infra-manager
```

Create the service account Infrastructure Manager runs as:

```bash
gcloud iam service-accounts create infra-manager-abstract --display-name="Infra Manager - Abstract" --project=LOGGING_PROJECT_ID
```

Grant it its roles. The Logs Configuration Writer grant goes on the organization, folder or project of the sink, so whoever can set IAM policy there runs it:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant serviceAccount:infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --for infra-manager-sa
```

### How you know it worked

Both checks print a ✓ for every required role.

Google documentation: [Access control with IAM](https://docs.cloud.google.com/infrastructure-manager/docs/access-control) · [Configure the service account](https://docs.cloud.google.com/infrastructure-manager/docs/configure-service-account) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role) · [Manage access to service accounts](https://docs.cloud.google.com/iam/docs/manage-access-service-accounts)

## The topic and the subscription Abstract reads

*Step 6 · guided script step 4*

The topic receives logs from the sink; Abstract pulls them from the subscription. Two subscription settings matter and neither is the default: it must never expire (an idle subscription is deleted after 31 days by default), and it keeps 7 days of messages, the buffer if Abstract is disconnected for a while.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/logging.configWriter` Logs Configuration Writer | the organization, folder or project of the sink | required | create the log sink (step 4) |
| You, or whoever runs the setup | `roles/pubsub.admin` Pub/Sub Admin | the logging project | required | create the topic and subscription, and grant on them (steps 4 and 5) |

### Google Cloud console

Open [Create topic](https://console.cloud.google.com/cloudpubsub/topic/create?project=LOGGING_PROJECT_ID).

In **Topic ID**, enter abstract-audit-logs. Clear **Add a default subscription**: it is ticked by default, and the subscription it makes expires after 31 days without activity, so you make the subscription yourself. Leave the rest, and click **Create** at the foot of the form.

*Screenshot in the app: Create topic with the topic ID abstract-audit-logs and Add a default subscription cleared.*

Open [Create subscription](https://console.cloud.google.com/cloudpubsub/subscription/create?project=LOGGING_PROJECT_ID).

In **Subscription ID**, enter abstract-audit-logs-sub. In **Select a Cloud Pub/Sub topic**, pick projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs. Leave **Delivery type** at **Pull**.

*Screenshot in the app: Create subscription with the subscription ID, the topic picked and Pull delivery.*

Under **Retry policy** select **Retry after exponential backoff delay**; it fills in 10 and 600 seconds, the same as the command line and Terraform. Set **Acknowledgement deadline** to 60.

*Screenshot in the app: Retry after exponential backoff delay with 10 and 600 seconds, and an acknowledgement deadline of 60 seconds.*

Under **Lifetime options**, leave **Message retention duration** at 7 days and select **Never expire** under **Expiration period**. Click **Create**.

*Screenshot in the app: Lifetime options with 7 days of retention and Never expire selected.*

### Command line

```bash
gcloud pubsub topics create abstract-audit-logs --project=LOGGING_PROJECT_ID
```

```bash
gcloud pubsub subscriptions create abstract-audit-logs-sub --topic=abstract-audit-logs --ack-deadline=60 --message-retention-duration=7d --expiration-period=never --min-retry-delay=10s --max-retry-delay=600s --project=LOGGING_PROJECT_ID
```

Check the settings. No expirationPolicy ttl means it never expires.

```bash
gcloud pubsub subscriptions describe abstract-audit-logs-sub --project=LOGGING_PROJECT_ID --format="yaml(topic,ackDeadlineSeconds,messageRetentionDuration,expirationPolicy)"
```

The Terraform template that does the same: [`gcp-source-audit-logs-organization`](../../templates/gcp/gcp-source-audit-logs-organization/README.md) (organization), [`gcp-source-audit-logs-folder`](../../templates/gcp/gcp-source-audit-logs-folder/README.md) (folder), [`gcp-source-audit-logs-project`](../../templates/gcp/gcp-source-audit-logs-project/README.md) (project).

### How you know it worked

The subscription reads projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs, keeps 7 days (604800s) and never expires.

### If it does not

| If | Then |
|---|---|
| It worked for a month, then stopped | The subscription expired. Set it to never expire, or recreate it with the command above. |

Google documentation: [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)

## The log sink

*Step 7 · guided script step 4*

One sink copies matching audit logs, as they are written, to the topic. At the organization or a folder it includes child resources, so it covers every project underneath, now and later. There is no backfill: what the filter misses while it is not in place is gone.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/logging.configWriter` Logs Configuration Writer | the organization, folder or project of the sink | required | create the log sink (step 4) |
| You, or whoever runs the setup | `roles/pubsub.admin` Pub/Sub Admin | the logging project | required | create the topic and subscription, and grant on them (steps 4 and 5) |

### Google Cloud console

Open [Log Router](https://console.cloud.google.com/logs/router).

*The whole organization:* In the resource picker at the top, select your organization, then click **Create sink**.

*One folder:* In the resource picker at the top, select your folder (FOLDER_ID), then click **Create sink**.

*One project:* In the resource picker at the top, select SOURCE_PROJECT_ID, then click **Create sink**.

**Sink details**: in **Sink name** enter abstract-org-audit-sink (it cannot be renamed later), and click **Next**.

**Sink destination**: in **Select sink service** choose **Cloud Pub/Sub topic**. The topic is in another project, so in **Select Cloud Pub/Sub topic** choose **Use a Cloud Pub/Sub topic in a project**. The service switches to **Other resource**, and **Sink destination** shows a template path; replace all of it with the topic's path, and click **Next**:

```text
pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs
```

*Screenshot in the app: Sink destination with Other resource and the topic's full path.*

*The whole organization:* **Choose logs to include in sink**: the default, **Include only logs ingested by this organization**, misses every project. Select **Include logs ingested by this organization and all child resources**.

*One folder:* **Choose logs to include in sink**: the default includes only the folder's own logs, which misses every project. Select the option that includes the folder and all child resources.

In **Build inclusion filter**, paste the filter, then click **Next**:

*Admin activity only:*

```text
logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy"
```

*Admin activity, identity and data changes (recommended):*

```text
logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy" OR (logName:"cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName=("bigquery.googleapis.com" OR "storage.googleapis.com" OR "cloudkms.googleapis.com" OR "iamcredentials.googleapis.com" OR "sts.googleapis.com"))
```

*Everything:*

```text
logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy" OR logName:"cloudaudit.googleapis.com%2Fdata_access"
```

*The whole organization or One folder:* *Screenshot in the app: Include logs ingested by this organization and all child resources selected, with the recommended filter pasted.*

Leave **Choose logs to filter out of sink (optional)** empty, and click **Create sink**.

Then copy the sink's writer identity: on **Log Router**, with the same resource selected, open the menu at the end of the abstract-org-audit-sink row and select **View sink details**. **Writer identity** has a copy button; paste it into 'The sink's writer identity' on this page.

*Screenshot in the app: The sink's menu on Log Router: View sink details, Edit sink, Disable sink, Delete sink, Troubleshoot sink.*

*Screenshot in the app: Sink details with Includes child resources Yes, the destination topic and the writer identity.*

### Command line

*Admin activity only:* The filter routes Admin Activity, System Event and Policy Denied logs.

*Admin activity, identity and data changes (recommended):* The filter routes Admin Activity, System Event and Policy Denied logs, and the Data Access logs the 'Turn on Data Access logs' step turns on: BigQuery, Cloud Storage, Cloud KMS, service-account token minting (its events carry iamcredentials.googleapis.com) and the Security Token Service.

*Everything:* The filter routes Admin Activity, System Event and Policy Denied logs, and every Data Access log.

*The whole organization, Admin activity only:*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --organization=ORG_ID --include-children --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy"'
```

*The whole organization, Admin activity, identity and data changes (recommended):*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --organization=ORG_ID --include-children --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy" OR (logName:"cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName=("bigquery.googleapis.com" OR "storage.googleapis.com" OR "cloudkms.googleapis.com" OR "iamcredentials.googleapis.com" OR "sts.googleapis.com"))'
```

*The whole organization, Everything:*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --organization=ORG_ID --include-children --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy" OR logName:"cloudaudit.googleapis.com%2Fdata_access"'
```

*One folder, Admin activity only:*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --folder=FOLDER_ID --include-children --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy"'
```

*One folder, Admin activity, identity and data changes (recommended):*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --folder=FOLDER_ID --include-children --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy" OR (logName:"cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName=("bigquery.googleapis.com" OR "storage.googleapis.com" OR "cloudkms.googleapis.com" OR "iamcredentials.googleapis.com" OR "sts.googleapis.com"))'
```

*One folder, Everything:*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --folder=FOLDER_ID --include-children --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy" OR logName:"cloudaudit.googleapis.com%2Fdata_access"'
```

*One project, Admin activity only:*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --project=SOURCE_PROJECT_ID --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy"'
```

*One project, Admin activity, identity and data changes (recommended):*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --project=SOURCE_PROJECT_ID --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy" OR (logName:"cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName=("bigquery.googleapis.com" OR "storage.googleapis.com" OR "cloudkms.googleapis.com" OR "iamcredentials.googleapis.com" OR "sts.googleapis.com"))'
```

*One project, Everything:*

```bash
gcloud logging sinks create abstract-org-audit-sink pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs --project=SOURCE_PROJECT_ID --log-filter='logName:"cloudaudit.googleapis.com%2Factivity" OR logName:"cloudaudit.googleapis.com%2Fsystem_event" OR logName:"cloudaudit.googleapis.com%2Fpolicy" OR logName:"cloudaudit.googleapis.com%2Fdata_access"'
```

gcloud prints the sink's writer identity, the account the sink publishes as. Copy it, serviceAccount: included, into "The sink's writer identity" on this page. To see it again:

*The whole organization:*

```bash
gcloud logging sinks describe abstract-org-audit-sink --organization=ORG_ID --format="value(writerIdentity)"
```

*One folder:*

```bash
gcloud logging sinks describe abstract-org-audit-sink --folder=FOLDER_ID --format="value(writerIdentity)"
```

*One project:*

```bash
gcloud logging sinks describe abstract-org-audit-sink --project=SOURCE_PROJECT_ID --format="value(writerIdentity)"
```

The Terraform template that does the same: [`gcp-source-audit-logs-organization`](../../templates/gcp/gcp-source-audit-logs-organization/README.md) (organization), [`gcp-source-audit-logs-folder`](../../templates/gcp/gcp-source-audit-logs-folder/README.md) (folder), [`gcp-source-audit-logs-project`](../../templates/gcp/gcp-source-audit-logs-project/README.md) (project).

### How you know it worked

The sink is listed with destination pubsub.googleapis.com/projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs and, at the organization or a folder, includeChildren True. It sends nothing until the next step.

### If it does not

| If | Then |
|---|---|
| PERMISSION_DENIED creating the sink | Logs Configuration Writer is missing at the organization, folder or project of the sink. The permissions step checks and grants it. |
| A sink already sends audit logs to another topic | Tell whoever owns it before you add a second; two pipelines double the volume. The guided script's step 4 finds and reports it. |

Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Logging query language](https://docs.cloud.google.com/logging/docs/view/logging-query-language) · [gcloud logging sinks create](https://docs.cloud.google.com/sdk/gcloud/reference/logging/sinks/create)

## Let the sink publish to the topic

*Step 8 · guided script step 4*

The sink's writer identity holds no permissions until you grant it Pub/Sub Publisher on the topic. The console does not do it for you when the topic is in another project, and a sink without it looks healthy and sends nothing. This is the step most often missed.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/logging.configWriter` Logs Configuration Writer | the organization, folder or project of the sink | required | create the log sink (step 4) |
| You, or whoever runs the setup | `roles/pubsub.admin` Pub/Sub Admin | the logging project | required | create the topic and subscription, and grant on them (steps 4 and 5) |

### Google Cloud console

Open [Pub/Sub topics](https://console.cloud.google.com/cloudpubsub/topic/list?project=LOGGING_PROJECT_ID).

Tick the abstract-audit-logs checkbox. If the info panel is hidden, click **Show info panel**. On its **Permissions** tab click **Add principal**. In **New principals** enter the writer identity without serviceAccount: in front (WRITER_IDENTITY, from service- onwards). In **Role** pick Pub/Sub Publisher, and click **Save**.

*Screenshot in the app: Grant access to abstract-audit-logs with the sink's writer identity and the Pub/Sub Publisher role.*

> Google's console grants this for you only when the sink and the topic are in the same project. Here they are not, so this grant is yours to make.

### Command line

```bash
gcloud pubsub topics add-iam-policy-binding abstract-audit-logs --member=WRITER_IDENTITY --role=roles/pubsub.publisher --project=LOGGING_PROJECT_ID
```

Check the topic's policy lists the writer identity as a publisher:

```bash
gcloud pubsub topics get-iam-policy abstract-audit-logs --project=LOGGING_PROJECT_ID
```

### How you know it worked

The topic's policy lists the writer identity under roles/pubsub.publisher. Within a few minutes, any admin action inside your scope lands on the topic.

### If it does not

| If | Then |
|---|---|
| The sink shows errors, or Google emails about a failed export | The publisher grant is missing, or went to another topic. Grant it on abstract-audit-logs in LOGGING_PROJECT_ID. |

Google documentation: [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth) · [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#dest-auth) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles)

## Deploy the pipeline with Infrastructure Manager

*Step 9 · guided script step 4 · only with Infrastructure Manager*

One deployment creates the topic, the subscription, the sink, the sink's publisher grant, and Abstract's service account with Subscriber on the subscription: everything the other paths build by hand except the key, which stays out of Terraform state. It deploys from the public templates repository at a release tag, so a later merge never changes what you deployed. Not yet run end to end against a live organization: treat your first preview as the test, and read it before you apply.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, to deploy with Infrastructure Manager | `roles/config.admin` Cloud Infrastructure Manager Admin | the logging project | required | create previews and deployments |
| You, to deploy with Infrastructure Manager | `roles/iam.serviceAccountUser` Service Account User | the Infrastructure Manager service account | required | start a deployment that runs as the Infrastructure Manager service account |

### Infrastructure Manager

Lists such as log_categories cannot go in --input-values, so your values go in a .tfvars file that gcloud reads. Copy the example of the template for your scope, from the top folder of the templates repository:

*The whole organization:*

```bash
cp templates/gcp/gcp-source-audit-logs-organization/terraform.tfvars.example abstract.tfvars
```

*One folder:*

```bash
cp templates/gcp/gcp-source-audit-logs-folder/terraform.tfvars.example abstract.tfvars
```

*One project:*

```bash
cp templates/gcp/gcp-source-audit-logs-project/terraform.tfvars.example abstract.tfvars
```

Edit abstract.tfvars in the Cloud Shell editor or any editor: set the organization, folder or project ID and log_project = "LOGGING_PROJECT_ID", then the log categories for the audit level you chose (below). The repository's .gitignore keeps *.tfvars out of git.

*Admin activity only:* Admin activity only:

*Admin activity only:*

```text
log_categories = ["admin_activity", "system_event", "policy_denied"]
```

*Admin activity, identity and data changes (recommended):* Recommended: the identity services and the template's default Data Access services (BigQuery, Cloud Storage, Cloud KMS):

*Admin activity, identity and data changes (recommended):*

```text
log_categories = ["admin_activity", "system_event", "policy_denied", "identity_access", "data_access_all"]
```

*Everything:* Everything: every service's Data Access logs, so the service list is emptied and the volume acknowledged. All three lines:

*Everything:*

```text
log_categories = ["admin_activity", "system_event", "policy_denied", "identity_access", "data_access_all"]
```

*Everything:*

```text
data_access_services = []
```

*Everything:*

```text
acknowledge_high_volume = true
```

Deploy a release tag, never a branch: a branch deploys whatever was merged since. List the tags; the last one is the newest, your RELEASE_TAG:

```bash
git ls-remote --tags --sort=v:refname https://github.com/IamABS3C/abstract-cloud-templates
```

Preview it. This is terraform plan, run by Infrastructure Manager:

*The whole organization:*

```bash
gcloud infra-manager previews create projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-organization --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
```

*One folder:*

```bash
gcloud infra-manager previews create projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-folder --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
```

*One project:*

```bash
gcloud infra-manager previews create projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-project --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
```

Wait for SUCCEEDED, then download the plan; the JSON copy reads in any editor.

```bash
gcloud infra-manager previews describe projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --format="value(state,errorCode)"
```

```bash
gcloud infra-manager previews export projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --file=abstract-preview
```

Read it, then apply. The same command updates the deployment later.

*The whole organization:*

```bash
gcloud infra-manager deployments apply projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-organization --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
```

*One folder:*

```bash
gcloud infra-manager deployments apply projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-folder --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
```

*One project:*

```bash
gcloud infra-manager deployments apply projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-project --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
```

Read the result. ACTIVE is done; FAILED says why in stateDetail, errorCode and tfErrors.

```bash
gcloud infra-manager deployments describe projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --format="yaml(state,stateDetail,errorCode,tfErrors,latestRevision)"
```

The Terraform template that does the same: [`gcp-source-audit-logs-organization`](../../templates/gcp/gcp-source-audit-logs-organization/README.md) (organization), [`gcp-source-audit-logs-folder`](../../templates/gcp/gcp-source-audit-logs-folder/README.md) (folder), [`gcp-source-audit-logs-project`](../../templates/gcp/gcp-source-audit-logs-project/README.md) (project).

### How you know it worked

The deployment is ACTIVE, and the subscription, sink and grants are in place: the checks of the command line path read them back.

### If it does not

| If | Then |
|---|---|
| FAILED with a 403 in tfErrors | The Infrastructure Manager service account lacks a role. Check it with the --for infra-manager-sa --check command in the Infrastructure Manager roles step. |
| UREQ_PROJECT_BILLING_NOT_OPEN, or the APIs never turn on | The logging project has no open billing account. Link one; Cloud Build cannot run without it. |
| blueprint fetch failed, invalid path | The --git-source-directory or --git-source-ref is wrong. List the tags again and check the folder name. |

Google documentation: [Deploy infrastructure using Infrastructure Manager](https://docs.cloud.google.com/infrastructure-manager/docs/deploy-resources) · [Preview a deployment](https://docs.cloud.google.com/infrastructure-manager/docs/preview-deployment) · [Export and view preview results](https://docs.cloud.google.com/infrastructure-manager/docs/export-view-preview-results) · [Troubleshoot deployment errors](https://docs.cloud.google.com/infrastructure-manager/docs/troubleshoot-deployments) · [Infrastructure Manager locations](https://docs.cloud.google.com/infrastructure-manager/docs/locations) · [gcloud infra-manager deployments apply](https://docs.cloud.google.com/sdk/gcloud/reference/infra-manager/deployments/apply)

## Abstract's service account and key

*Step 10 · guided script step 5*

A service account with exactly one permission, read the one subscription, and a JSON key for it. The key is the only secret in this setup: Abstract's Pub/Sub source signs in with it today.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/iam.securityReviewer` Security Reviewer | the organization, folder or project of the sink | required | read IAM policies and the audit settings (steps 2, 5 and 6) |
| You, or whoever runs the setup | `roles/pubsub.admin` Pub/Sub Admin | the logging project | required | create the topic and subscription, and grant on them (steps 4 and 5) |
| You, or whoever runs the setup | `roles/iam.serviceAccountAdmin` Service Account Admin | the logging project | required | create Abstract's service accounts (steps 5 and 7) |
| You, or whoever runs the setup | `roles/iam.serviceAccountKeyAdmin` Service Account Key Admin | the logging project | required | create the key Abstract signs in with (steps 5 and 7) |

### Google Cloud console

Open [Create service account](https://console.cloud.google.com/iam-admin/serviceaccounts/create?project=LOGGING_PROJECT_ID).

Enter abstract-pubsub-reader as the name; the console makes the ID abstract-pubsub-reader from it. Click **Done** without granting any project role: its one permission goes on the subscription.

Open [Subscriptions](https://console.cloud.google.com/cloudpubsub/subscription/list?project=LOGGING_PROJECT_ID).

Tick abstract-audit-logs-sub. On the info panel's **Permissions** tab click **Add principal**. In **New principals** enter abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com, in **Role** pick Pub/Sub Subscriber (not Publisher, not Editor), and click **Save**.

Open [Service accounts](https://console.cloud.google.com/iam-admin/serviceaccounts?project=LOGGING_PROJECT_ID).

Click abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com, then the **Keys** tab. Click **Add key**, select **Create new key**, select **JSON**, and click **Create**. The browser downloads the key; it cannot be downloaded again.

*Screenshot in the app: The service account's Keys tab with the Add key menu open on Create new key.*

> **Warning.** The key is the only secret in this setup. Keep it out of email and chat, and delete it once Abstract has it.

Key refused by an organization policy? An Organization Policy Administrator opens **Organization policies** for LOGGING_PROJECT_ID, clicks the constraint the error names, clicks **Manage policy**, selects **Override parent's policy**, clicks **Add a rule**, sets **Enforcement** to off, and clicks **Set policy**. It can take up to 15 minutes to apply; then create the key again.

### Command line

```bash
gcloud iam service-accounts create abstract-pubsub-reader --display-name="Abstract Pub/Sub reader" --project=LOGGING_PROJECT_ID
```

Subscriber on the subscription only. Not Publisher, not on the project.

```bash
gcloud pubsub subscriptions add-iam-policy-binding abstract-audit-logs-sub --member=serviceAccount:abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com --role=roles/pubsub.subscriber --project=LOGGING_PROJECT_ID
```

The key, in ~/abstract-keys, outside any repository and readable only by you. In Cloud Shell, download it to your computer straight away: a temporary session takes it with it when it ends.

```bash
mkdir -p -m 700 ~/abstract-keys
```

```bash
(umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-pubsub-key.json --iam-account=abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com)
```

```bash
cloudshell download ~/abstract-keys/abstract-pubsub-key.json
```

### Infrastructure Manager

The deployment made the service account and its Subscriber grant. The key is made here, outside Terraform, so it never sits in Terraform state. Written readable only by you:

```bash
mkdir -p -m 700 ~/abstract-keys
```

```bash
(umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-pubsub-key.json --iam-account=abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com)
```

```bash
cloudshell download ~/abstract-keys/abstract-pubsub-key.json
```

### How you know it worked

The service account has no project roles, it is listed under Pub/Sub Subscriber on abstract-audit-logs-sub, and you have one JSON file.

### If it does not

| If | Then |
|---|---|
| Key creation is refused, naming constraints/iam.disableServiceAccountKeyCreation or constraints/iam.managed.disableServiceAccountKeyCreation | An organization policy forbids keys. An Organization Policy Administrator overrides that constraint for LOGGING_PROJECT_ID only, then you create the key again. |

Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#managed-constraints) · [Create organization policies](https://docs.cloud.google.com/organization-policy/create-organization-policies) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

## Turn on Data Access logs

*Step 11 · guided script step 6 · only for: Admin activity, identity and data changes (recommended) or Everything*

Admin Activity, System Event and Policy Denied logs are always on. Data Access logs are off for every service except BigQuery until you turn them on, and it takes two switches: this one makes Google write them, and the sink's filter routes them. One without the other silently delivers nothing. Changing them edits the IAM policy of the organization, folder or project, so it needs Security Admin (or Organization Administrator) there.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/iam.securityReviewer` Security Reviewer | the organization, folder or project of the sink | required | read IAM policies and the audit settings (steps 2, 5 and 6) |
| You, or whoever runs the setup | `roles/iam.securityAdmin` Security Admin | the organization, folder or project of the sink | optional | turn on Data Access logs (step 6). Powerful: it can change IAM anywhere at the scope |

### Google Cloud console

Open [Audit logs](https://console.cloud.google.com/iam-admin/audit).

*The whole organization:* Select your organization in the resource picker.

*One folder:* Select your folder (FOLDER_ID) in the resource picker.

*One project:* Select SOURCE_PROJECT_ID in the resource picker.

*Admin activity, identity and data changes (recommended):* In the **Data access audit logs configuration** table, use the **Filter** to find each service: BigQuery, Cloud Storage, Cloud Key Management Service (KMS), Identity and Access Management (IAM) and Security Token Service. Tick its row; in the info panel's **Permission types** tab tick **Admin read** and **Data write**, and click **Save**.

*Admin activity, identity and data changes (recommended):* *Screenshot in the app: Audit logs with the IAM API row ticked and Admin read and Data write selected in the Permission types tab.*

*Everything:* Click **Set default configuration**. Tick **Admin read**, **Data read** and **Data write**, and click **Save**. This applies to every service.

*Everything:* Exempt the service accounts that read data as their job (a loader, a backup agent; never a person): on the **Exempted principals** tab, add each, and click **Save**.

> The table shows the effective setting, the one set here combined with any set above it: a type turned on at a parent shows as on, and cannot be turned off here.

> *Admin activity, identity and data changes (recommended):* The sink you created routes these same services, so nothing else needs changing. If you tick other services here, add them to the sink's filter too, or Google writes and bills logs the sink never sends.

### Command line

gcloud has no command that changes only the audit settings: uploading a policy file replaces the whole policy, every role binding included. The guided script's step 6 changes the audit settings alone, keeps a copy of what was there first, and records what it added so clean-up can take back exactly that:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
```

> *Admin activity, identity and data changes (recommended):* Service-account token minting is logged through the IAM API (iam.googleapis.com), though its events carry iamcredentials.googleapis.com. Google's pages describe those entries both as Admin Read and as Data Read; add Data Read for iam.googleapis.com if you need every SignBlob and GenerateIdToken call.

> **Warning.** *Everything:* Data Read on every service can multiply log volume by ten or more on a BigQuery- or Storage-heavy estate. Exempt the service accounts that read data as their job (a loader, a backup agent), never a person.

### Infrastructure Manager

A separate template, so deleting the collector can never take the audit settings with it. It writes the audit configuration authoritatively for the services it names, so its tfvars must say so with acknowledge_authoritative_overwrite = true. Copy its example and edit it:

```bash
cp templates/gcp/gcp-foundation-data-access-audit-logs/terraform.tfvars.example data-access.tfvars
```

*Admin activity, identity and data changes (recommended):* Edit data-access.tfvars: set scope and the organization, folder or project ID, and acknowledge_authoritative_overwrite = true. Then the services. An empty list means every service (allServices), so for the recommended level name them:

*Admin activity, identity and data changes (recommended):*

```text
services = ["bigquery.googleapis.com", "storage.googleapis.com", "cloudkms.googleapis.com", "iam.googleapis.com", "sts.googleapis.com"]
```

*Admin activity, identity and data changes (recommended):*

```text
log_types = ["ADMIN_READ", "DATA_WRITE"]
```

*Everything:* Edit data-access.tfvars: set scope and the organization, folder or project ID, and acknowledge_authoritative_overwrite = true. For every service, leave services empty and acknowledge Data Read:

*Everything:*

```text
log_types = ["ADMIN_READ", "DATA_WRITE", "DATA_READ"]
```

*Everything:*

```text
acknowledge_data_read = true
```

```bash
gcloud infra-manager deployments apply projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-data-access --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-foundation-data-access-audit-logs --git-source-ref=RELEASE_TAG --inputs-file=data-access.tfvars
```

> The Infrastructure Manager service account needs Security Admin at the scope for this one deployment (the optional row of the Infrastructure Manager roles step). Take it back afterwards.

The Terraform template that does the same: [`gcp-foundation-data-access-audit-logs`](../../templates/gcp/gcp-foundation-data-access-audit-logs/README.md).

### How you know it worked

The audit settings at the organization, folder or project show the log types for the services you chose, and the sink's filter routes the same services. The guided script checks both switches with --step 6 --check.

### If it does not

| If | Then |
|---|---|
| Admin events arrive, Data Access events do not | Only one switch is on. This step makes Google write them; the sink filter routes them. Check both. |
| Volume is far higher than expected | Data Read is on for a BigQuery- or Storage-heavy project. Exempt the loader accounts, or name services instead of all of them. |

Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#project-and-organization) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts) · [google_organization_iam](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_organization_iam)

## Alerts for a stalled pipeline

*Step 12 · guided script step 8 · optional*

A stopped pipeline is silent. If the sink cannot publish, Cloud Logging drops the entry: no retry, no backfill. Three alerts catch it: nothing published to the topic for a while (the one that catches a sink at the organization or a folder that cannot publish, because Google does not report its sink-error metric for those), the subscription's oldest unacknowledged message older than an hour (Abstract stopped reading), and sink export errors (reported for a sink in a project).

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/serviceusage.serviceUsageAdmin` Service Usage Admin | the logging project | required | turn on the APIs (steps 3, 7 and 8) |
| You, or whoever runs the setup | `roles/monitoring.editor` Monitoring Editor | the logging project | optional | create the health alerts (step 8) |

### Google Cloud console

The guided script's step 8 and the Terraform template create three alerts at once. In the console, the most important one, Abstract has stopped reading:

Open [Alerting](https://console.cloud.google.com/monitoring/alerting?project=LOGGING_PROJECT_ID).

Click **Create policy**, then **Select a metric**. Pick the Pub/Sub subscription resource and its oldest unacknowledged message age metric (pubsub.googleapis.com/subscription/oldest_unacked_message_age), click **Apply**, and add a filter for subscription_id abstract-audit-logs-sub. Click **Next**.

Leave **Condition type** at **Threshold**. Set **Threshold position** to **Above threshold** and **Threshold value** to 3600 (seconds). Click **Next**.

Under **Notifications and name**, choose a notification channel for ALERT_EMAIL, give the policy a name under **Alert name**, and click **Create policy**.

### Command line

The guided script's step 8 creates the alerts and an email channel, asking first:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
```

### Infrastructure Manager

The alerts need a notification channel that already exists. The guided script's step 8 makes the email channel and the alerts together, and is the simpler way. To keep the alerts in Terraform, list your channels, copy the name of the one for ALERT_EMAIL, and put it in notification_channels in alerts.tfvars:

```bash
gcloud beta monitoring channels list --project=LOGGING_PROJECT_ID --format="value(name,displayName)"
```

```bash
cp templates/gcp/gcp-monitoring-pipeline-health-alerts/terraform.tfvars.example alerts.tfvars
```

```text
notification_channels = ["projects/LOGGING_PROJECT_ID/notificationChannels/CHANNEL_ID"]
```

```bash
gcloud infra-manager deployments apply projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-alerts --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-monitoring-pipeline-health-alerts --git-source-ref=RELEASE_TAG --inputs-file=alerts.tfvars
```

The Terraform template that does the same: [`gcp-monitoring-pipeline-health-alerts`](../../templates/gcp/gcp-monitoring-pipeline-health-alerts/README.md).

### How you know it worked

Both policies are listed under Monitoring, Alerting, with your email as the notification channel.

Google documentation: [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog) · [Troubleshoot routing and storing logs](https://docs.cloud.google.com/logging/docs/export/troubleshoot) · [Create and manage notification channels](https://docs.cloud.google.com/monitoring/support/notification-options)

## Prove logs arrive

*Step 13 · guided script step 9*

Before you involve Abstract, prove Google's side: make a harmless admin change inside your scope and watch for it on a probe subscription of your own. Never pull from Abstract's subscription: acknowledging a message there deletes it before Abstract reads it. A new sink takes about 3 to 5 minutes to start routing.

### Who needs what

| Who | Role | Where | Needed | For |
|---|---|---|---|---|
| You, or whoever runs the setup | `roles/logging.configWriter` Logs Configuration Writer | the organization, folder or project of the sink | required | create the log sink (step 4) |
| You, or whoever runs the setup | `roles/pubsub.admin` Pub/Sub Admin | the logging project | required | create the topic and subscription, and grant on them (steps 4 and 5) |

### Google Cloud console

Open [Subscriptions](https://console.cloud.google.com/cloudpubsub/subscription?project=LOGGING_PROJECT_ID).

Make a probe subscription of your own, so nothing is taken from Abstract's: **Create subscription**, **Subscription ID** abstract-probe, topic projects/LOGGING_PROJECT_ID/topics/abstract-audit-logs, **Delivery type** **Pull**, and under **Expiration period** select **Expire after this many days of inactivity** with 1 day. Click **Create**.

Make a harmless admin change inside your scope: in TEST_PROJECT_ID, create a Pub/Sub topic named abstract-probe-topic, then delete it.

Open [Create topic in the test project](https://console.cloud.google.com/cloudpubsub/topic/create?project=TEST_PROJECT_ID).

Wait two minutes. Open abstract-probe from the subscriptions list, go to its **Messages** tab and click **Pull**. One pull often returns nothing at low volume: click **Pull** several times. Look for abstract-probe-topic in a message: protoPayload.methodName says what was done, protoPayload.authenticationInfo.principalEmail who did it.

Delete the abstract-probe subscription when you are done.

### Command line

The guided script's step 9 does all of this and reports either way. By hand, first the probe subscription, created before the test event:

```bash
gcloud pubsub subscriptions create abstract-probe --topic=abstract-audit-logs --expiration-period=1d --message-retention-duration=10m --project=LOGGING_PROJECT_ID
```

A harmless admin change inside your scope:

```bash
gcloud pubsub topics create abstract-probe-topic --project=TEST_PROJECT_ID
```

```bash
gcloud pubsub topics delete abstract-probe-topic --project=TEST_PROJECT_ID
```

Wait two minutes, then count the test events on the probe subscription. Message data arrives base64-encoded, so the command decodes it first. A busy organization sends many other events: run it again, a minute apart, until the number is above 0.

```bash
gcloud pubsub subscriptions pull abstract-probe --limit=1000 --auto-ack --format="value(message.data.decode(base64))" --project=LOGGING_PROJECT_ID | grep -c abstract-probe-topic
```

Then remove the probe subscription.

```bash
gcloud pubsub subscriptions delete abstract-probe --project=LOGGING_PROJECT_ID
```

### Infrastructure Manager

The guided script's step 9 does all of this and reports either way. By hand, first the probe subscription, created before the test event:

```bash
gcloud pubsub subscriptions create abstract-probe --topic=abstract-audit-logs --expiration-period=1d --message-retention-duration=10m --project=LOGGING_PROJECT_ID
```

A harmless admin change inside your scope:

```bash
gcloud pubsub topics create abstract-probe-topic --project=TEST_PROJECT_ID
```

```bash
gcloud pubsub topics delete abstract-probe-topic --project=TEST_PROJECT_ID
```

Wait two minutes, then count the test events on the probe subscription. Message data arrives base64-encoded, so the command decodes it first. A busy organization sends many other events: run it again, a minute apart, until the number is above 0.

```bash
gcloud pubsub subscriptions pull abstract-probe --limit=1000 --auto-ack --format="value(message.data.decode(base64))" --project=LOGGING_PROJECT_ID | grep -c abstract-probe-topic
```

Then remove the probe subscription.

```bash
gcloud pubsub subscriptions delete abstract-probe --project=LOGGING_PROJECT_ID
```

### How you know it worked

A count above 0. The cloud side is done.

### If it does not

| If | Then |
|---|---|
| Nothing after 10 minutes | Read the sink's errors (Logging, Log Router, the sink's menu, or the Troubleshoot routing page). A permission or publish error means the publisher grant is missing or went on another topic. |
| The test project is outside the scope | The sink only sees projects under the organization, folder or project it is at. Use a project inside it. |
| The sink is at the organization or a folder | Check includeChildren is True; without it only the organization's or folder's own logs route. |

Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Troubleshoot routing and storing logs](https://docs.cloud.google.com/logging/docs/export/troubleshoot)

## Connect Abstract

*Step 14 · guided script step 10*

Three fields. Two are filled in wrong more often than you would expect: the project is the logging project that holds the subscription, never a project the logs come from, and the subscription is its short name.

### Google Cloud console

In Abstract, open Integrations and add GCP Pub/Sub Source. Fill in Project ID with LOGGING_PROJECT_ID, Subscription ID with abstract-audit-logs-sub, and Credentials with the JSON key file. Save; Abstract checks the credentials against the subscription.

> **Warning.** Then delete the key file from your computer and from Cloud Shell. If someone else fills in the form, hand the file over through a password manager or a secret-sharing tool, never email or chat.

### Command line

In Abstract, open Integrations and add GCP Pub/Sub Source. Fill in Project ID with LOGGING_PROJECT_ID, Subscription ID with abstract-audit-logs-sub, and Credentials with the JSON key file. Save; Abstract checks the credentials against the subscription.

Then delete the key file, here and on your computer:

```bash
rm -f ~/abstract-keys/abstract-pubsub-key.json
```

### Infrastructure Manager

In Abstract, open Integrations and add GCP Pub/Sub Source. Fill in Project ID with LOGGING_PROJECT_ID, Subscription ID with abstract-audit-logs-sub, and Credentials with the JSON key file. Save; Abstract checks the credentials against the subscription.

Then delete the key file, here and on your computer:

```bash
rm -f ~/abstract-keys/abstract-pubsub-key.json
```

### How you know it worked

Events appear in Abstract within a few minutes. If the integration saves and nothing appears after 15 minutes, run the probe in the step before again: events on the probe and none in Abstract is a field or credential problem here; nothing on the probe is the cloud side.

### If it does not

| If | Then |
|---|---|
| Abstract shows a permission error on save | The key is for another account, Publisher was granted instead of Subscriber, or the full projects/…/subscriptions/… path was pasted instead of the short name. |

Google documentation: [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

## Keep it healthy

*Step 15*

Three habits keep the pipeline from decaying: rotate the key, watch the volume in the first week, and know where to look first when something stops.

### Google Cloud console

Rotate the key every 90 days, or when someone who handled it leaves: on **Service accounts**, open abstract-pubsub-reader, **Keys** tab, create a new JSON key as before, update the credentials in Abstract, then delete the old key on the same tab.

Open [Service accounts](https://console.cloud.google.com/iam-admin/serviceaccounts?project=LOGGING_PROJECT_ID).

Watch the volume in the first week: in **Logs Explorer** at your organization, query logName:"data_access". If one service account dominates, exempt it in the audit settings; if one service does and you do not need its reads, name services instead of all of them.

Sink problems show on **Log Router** as a Cloud Logging sink configuration error, and in a daily email titled [ACTION REQUIRED] Cloud Logging sink configuration error. The sink's **More actions** menu has **Troubleshoot sink**.

### Command line

Rotate the key every 90 days, or when someone who handled it leaves: make a new key as in the key step, update the credentials in Abstract, then delete the old key. List the keys to find the old one's ID:

```bash
gcloud iam service-accounts keys list --iam-account=abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com --managed-by=user
```

To remove everything this setup made and start again, list it first; nothing is deleted without --confirm:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --teardown
```

### Infrastructure Manager

Rotate the key every 90 days, or when someone who handled it leaves: make a new key as in the key step, update the credentials in Abstract, then delete the old key. List the keys to find the old one's ID:

```bash
gcloud iam service-accounts keys list --iam-account=abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com --managed-by=user
```

To remove everything this setup made and start again, list it first; nothing is deleted without --confirm:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --teardown
```

### How you know it worked

One user-managed key on the reader account, younger than 90 days.

### If it does not

| If | Then |
|---|---|
| Events stopped after a month | The subscription expired. Set it to never expire. |
| Events arrive in Abstract with empty fields | Check the integration's version in Abstract before anything else. |

Google documentation: [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Alerting overview](https://docs.cloud.google.com/monitoring/alerts)
