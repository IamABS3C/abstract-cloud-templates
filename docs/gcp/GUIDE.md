# Set up Google Cloud

<!-- Generated from tools/guides/gcp.yml by `python -m tools.templates generate`. Do not edit. -->

You end up with a log sink (a Cloud Logging rule that copies matching logs as they are written) that sends your Google Cloud audit logs, IAM and identity logs included, to a Pub/Sub topic in a logging project (one project kept only for this pipeline), a subscription Abstract reads, and a service account that can read only that subscription. Then, if you want them: Google Workspace, network logs (firewall, Cloud DNS, VPC Flow, Cloud NAT), Cloud Asset changes and Security Command Center findings. Choose how to deploy (the guided setup script in Cloud Shell, Terraform, or Infrastructure Manager) and what sends logs (the organization, one or more folders, or one or more projects). The guided script's ten parts are called script steps 1 to 10 below, to tell them apart from the numbered cards.

Answer the questions below. Each answer leads to the next question or to one plan: the steps in order, from checking what you have to cleaning it all up. The same questions are in the [onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp), which gives each plan a link you can share.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/IamABS3C/abstract-cloud-templates&cloudshell_git_branch=main&cloudshell_workspace=tools/gcp-guided-setup&cloudshell_tutorial=WALKTHROUGH.md)

The button opens the guided setup in Cloud Shell, with every step below in a side panel.

## How do you want to deploy?

All three were deployed against a test organization in October 2026, and Abstract stored the audit logs each one sent. They build the same topic, subscription, sink and service account, with the same names.

- **The guided script in Cloud Shell (recommended)** → [How much of Google Cloud should send logs to Abstract?](#how-much-of-google-cloud-should-send-logs-to-abstract)
  A menu that asks before each change, prints every command and checks each result. The only method that takes several folders, or several projects, in one run.
- **Terraform** → [Send logs with Terraform](#send-logs-with-terraform)
  The templates in this repository, with the state in a Cloud Storage bucket you own. One sink per template: the organization, one folder or one project.
- **Infrastructure Manager** → [Send logs with Infrastructure Manager](#send-logs-with-infrastructure-manager)
  Google's managed Terraform, deploying the same templates from the public repository at a release tag, with the state kept for you. Needs billing on the logging project, because it runs on Cloud Build.

## How much of Google Cloud should send logs to Abstract?

Script step 1 asks the same, with checkbox lists for folders and projects.

- **The whole organization (recommended)** → [Send logs from your whole Google Cloud organization, with the guided script](#send-logs-from-your-whole-google-cloud-organization-with-the-guided-script)
  Every project, including ones created later. Needs Logs Configuration Writer on the organization.
- **One or more folders** → [Send logs from one or more Google Cloud folders, with the guided script](#send-logs-from-one-or-more-google-cloud-folders-with-the-guided-script)
  One sink in each folder you tick, covering every project in it and its subfolders, including ones created later. A folder inside another ticked folder is left out: its parent's sink covers it.
- **One or more projects** → [With several projects, one sink or one in each?](#with-several-projects-one-sink-or-one-in-each)
  Only the projects you tick. Projects created later are not covered until you tick them in script step 1.

## With several projects, one sink or one in each?

With one project ticked, script step 1 makes a sink in that project and does not ask.

- **One organization sink filtered to them (recommended)** → [Send logs from chosen projects through one filtered organization sink, with the guided script](#send-logs-from-chosen-projects-through-one-filtered-organization-sink-with-the-guided-script)
  Option A. One sink and one grant to look after. Needs Logs Configuration Writer at the organization.
- **One sink in each project** → [Send logs from one project, or one sink in each project, with the guided script](#send-logs-from-one-project-or-one-sink-in-each-project-with-the-guided-script)
  Option B. Needs Logs Configuration Writer on each project only. Also the plan for a single project.

## Send logs from your whole Google Cloud organization, with the guided script

**Fits when:** You want every project covered, including ones created later.

**Why this way:** One aggregated sink at the organization covers everything by containment, so nothing needs repeating when projects are added.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=0.0). To send someone this plan, share this link.

**Not chosen:** A folder or project sink: it would miss projects outside it.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository, whichever way you deploy.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before you finish, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose what sends logs. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Script step 1 offers the whole organization, one or more folders (a checkbox list of every folder and subfolder, its path shown), or one or more projects (a checkbox list: numbers or ranges tick and untick, a ticks all shown, n none, f every project in a folder, and any other text searches). With several projects it asks for one organization sink filtered to them, or one sink in each. Whichever way you deploy, this records your scope in the answers file, ~/.abstract-gcp-setup.env. Script step 1 asks its questions, so it is the last line of this block.

   *Note:* Run the script with no options for its menu instead: a runs the guided setup from the start, 1 to 10 one step, p the organization policy review, s what is supported where, i every saved name, ID and account, g checks or grants roles for someone, c checks everything and changes nothing, x cleans up, q quits.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose, and warns that projects created later are not covered until you tick them, if you chose projects.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, each folder, or each project you chose (with one organization sink filtered to projects, the organization). At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here, whatever your scope: the topics, the subscriptions, Abstract's service accounts and the health alerts. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before anything is built.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Check first (optional).** Cloud admin, in Cloud Shell.

   Review the organization policies that can block or change this setup. --policies (menu p) reads the effective policy at the organization, the logging project and every folder or project you chose, and sorts each into BLOCKS (the service-account key constraints), CHECK (restricted services, CMEK-only services, resource locations, allowed member domains, key expiry, Pub/Sub in-transit regions), info (cross-project service accounts, key exposure response, serial-port logging) and RECOMMEND (no audit logging exemptions, no automatic grants to default service accounts, Kubernetes cloud logging). It never changes a policy.

   *Optional:* Recommended in any organization with security policies. It reads and changes nothing, so it is safe to run before anything is built.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --policies
   ```

   **Check:** Every BLOCKS line shows ✓. A ✗ there names the constraint and where it is enforced: ask its owner for an exception on the logging project before you go on. CHECK lines say what to confirm.

   Google documentation: [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints)

6. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4: create the topic and subscription in the logging project, then the organization sink, and let the sink's writer identity (the Google-managed account the sink publishes as) publish to the topic. That last grant is the step most often missed; without it the sink looks healthy and sends nothing. The script offers the topics and subscriptions you already have before it creates new ones; Enter creates new.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to your organization. It copies the Admin Activity, System Event and Policy Denied audit logs of every project, including ones created later, and changes nothing inside those projects. A sink that already sends to the same topic is reused, and its filter is only ever extended.

   Template: [All Google Cloud audit logs to Abstract: organization sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-organization)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=LOGGING_PROJECT_ID (your logging project's ID) lists the sink's writer identity under roles/pubsub.publisher.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)

7. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as, or choose one you already have. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository. In a temporary Cloud Shell session, download the key as soon as script step 5 makes it, with cloudshell download ~/abstract-keys/abstract-pubsub-key.json, so a session that ends early does not take it with it. Script step 10 prints the same line again.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys. A new account is not grantable for a few seconds; the script retries the grant on its own.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

8. **Set up.** Cloud admin, in Cloud Shell.

   Script step 6, IAM and Data Access logs: turn on the IAM and identity logs (iam.googleapis.com and sts.googleapis.com, Admin Read) and any Data Access logs you choose, and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. For most services either alone does nothing; BigQuery writes its Data Access logs by default, so it needs only the routing switch. The script routes the identity events (as iamcredentials.googleapis.com and sts.googleapis.com) for you.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-….json beside your answers file (your home folder).

   *Note:* IAM and identity logs are on by default: this is where service account impersonation, token minting and Workload Identity Federation (GitHub Actions, AWS, Azure) are recorded, and their volume is low. BigQuery, Cloud Storage and Cloud KMS Data Access logs, which record who read or changed data, are optional and add volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs for each of them, naming iamcredentials.googleapis.com and sts.googleapis.com).

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)

9. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* The script's answer defaults to yes. Skip it (answer n) only if you do not use Google Workspace. Workspace sign-in, admin and token logs reach Abstract through its own Google Workspace integration, not through Pub/Sub.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

10. **Set up (optional).** Cloud admin, and the network owner, in Cloud Shell.

   This step uses Terraform, because the guided setup script builds only the audit-log sink, and this is a second sink with its own filter and topic. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block. Each network log is turned on where the resource lives, by its owner: firewall rule logging per rule, DNS query logging per network, VPC Flow Logs per subnet (or for a project or the organization), Cloud NAT logging per gateway, in the project that owns the network (the host project with Shared VPC); docs/gcp/FILTERS.md, Where each source is turned on, has each one. The tutorial checks each one read-only and routes the categories Abstract keeps: firewall, dns_queries, vpc_flows and nat_flows.

   > **This changes:** Adds a log sink, abstract-network-threats-sink, at the scope you set, and a topic, a subscription and a reader account for it in the logging project. It turns no network logging on.

   *Optional:* Skip unless you want firewall, Cloud DNS, VPC Flow or Cloud NAT logs in Abstract. Abstract keeps them only on a GCP Pub/Sub Source configuration of their own that runs the extended GCP Pub/Sub parser (the Abstract card below); load balancer (Cloud Armor) and Cloud IDS records are not kept.

   Template: [Network logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-network-threats-sink --organization=ORG_ID, with your organization's ID (--folder=FOLDER_ID or --project=PROJECT_ID for those scopes), shows a filter naming the categories you chose and the abstract-network-threats topic.

   Google documentation: [VPC firewall rules logging overview](https://docs.cloud.google.com/firewall/docs/vpc-firewall-rules-logging-overview) · [Use logging and monitoring](https://docs.cloud.google.com/dns/docs/monitoring#using_logging) · [VPC Flow Logs](https://docs.cloud.google.com/vpc/docs/flow-logs) · [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because Cloud Asset Inventory publishes through an organization feed of its own, not a log sink, and the guided setup script builds only the sink. The commands below open the template's tutorial in Cloud Shell's tutorial pane. Feed names are unique in an organization: a second deployment in the same organization sets its own feed_id. The first apply waits 60 seconds for the Cloud Asset Inventory service agent before granting it publisher on the topic, and the feed's first message is a plain-text greeting the extended parser drops.

   > **This changes:** Adds an asset feed, abstract-asset-feed, to your organization, a topic and subscription for it in the logging project, and lets Abstract's existing reader account read that subscription.

   *Optional:* Organization only: the feed is set on the organization. Skip unless you want IAM policy changes with the policy before and after, which Abstract keeps on a configuration of their own that runs the extended GCP Pub/Sub parser (gcp.asset_inventory, action iam_policy_grant, iam_policy_revoke or iam_policy_change).

   Template: [Asset and IAM changes to Abstract: asset feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-asset-and-iam-changes)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-asset-and-iam-changes"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud asset feeds list --organization=ORG_ID, with your organization's ID, lists abstract-asset-feed (or your feed_id) publishing to the abstract-asset-changes topic.

   Google documentation: [Monitor asset changes with Pub/Sub](https://docs.cloud.google.com/asset-inventory/docs/monitor-asset-changes#create_feeds) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

12. **Set up (optional).** Cloud admin, with a Security Command Center admin, in Cloud Shell.

   This step uses Terraform, because Security Command Center publishes through a notification config of its own, not a log sink, and the guided setup script builds only the sink. Whoever applies needs Security Center Notification Configurations Editor (roles/securitycenter.notificationConfigEditor) at the organization. Right after Security Command Center is activated, the create can answer 400 "Precondition check failed" and still create the config: the tutorial lists the configs and imports it into the state.

   > **This changes:** Adds a Security Command Center notification config, abstract-findings, to your organization, a topic and subscription for it in the logging project, and lets Abstract's existing reader account read that subscription.

   *Optional:* Organization only. Needs Security Command Center Standard or Premium active at the organization (tested with Premium); an organization still on legacy Security Command Center gets 400 "Security Command Center Legacy has been permanently disabled". Abstract keeps the findings on a configuration of their own that runs the extended GCP Pub/Sub parser (gcp.scc_findings).

   Template: [Security Command Center findings to Abstract: notification feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-security-command-center-findings)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-security-command-center-findings"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud scc notifications list --organization=ORG_ID --location=global, with your organization's ID, lists abstract-findings.

   Google documentation: [Enable finding notifications for Pub/Sub](https://docs.cloud.google.com/security-command-center/docs/how-to-notifications) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

13. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the guided script builds only the audit-log pipeline, and watching a bucket needs a notification on each bucket and a grant in each project that owns one, which the template sets from your list. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed. It notifies a topic for each new object, so Abstract fetches it. Abstract stores the objects' content only once a parser for their format is attached to this subscription's own integration; the managed GCP Pub/Sub Source parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product.

   > **This changes:** Adds a Pub/Sub notification to each bucket you name, and lets Abstract's reader account read their objects.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-cloud-storage-bucket-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud storage buckets notifications list gs://YOUR_BUCKET, with your bucket's name, shows a notification on the topic abstract-gcs-notifications.

   Google documentation: [Pub/Sub notifications for Cloud Storage](https://docs.cloud.google.com/storage/docs/pubsub-notifications) · [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

14. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because a billing account is not inside your organization, so the guided script's sink cannot reach it: the template puts a sink on the billing account itself. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed.

   > **This changes:** Adds a log sink, abstract-billing-audit-sink, to the billing account.

   *Optional:* Skip unless you want billing account audit logs. An organization sink routes the organization and the folders and projects under it; a billing account is a separate resource, so its logs are collected with a sink created on the billing account itself.

   Template: [Billing account audit logs to Abstract: billing sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-billing-account-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-billing-account-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-billing-audit-sink --billing-account=BILLING_ACCOUNT_ID, with your billing account's ID, shows the sink and its Pub/Sub destination.

   Google documentation: [gcloud logging sinks create](https://docs.cloud.google.com/sdk/gcloud/reference/logging/sinks/create#--billing-account) · [Cloud Billing audit logging](https://docs.cloud.google.com/billing/docs/audit-logging) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

15. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the guided script builds only the streaming pipeline, and the archive is a second sink with a bucket (and an optional retention lock) of its own, which the template creates. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it copies the streaming sink's filter, keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed. Abstract does not read the archive today.

   > **This changes:** Adds a second log sink, abstract-org-audit-sink-archive, to your organization, and a bucket for it.

   *Optional:* Organization only, a second sink at the organization. Skip unless you need to keep logs as evidence in Cloud Storage; Abstract does not read the archive today. It is not the detection path; files land minutes to hours later.

   Template: [Archive Google Cloud logs to Cloud Storage: second sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-archive-log-bucket)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-archive-log-bucket"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-org-audit-sink-archive --organization=ORG_ID, with your organization's ID, points at your bucket, and gcloud storage ls gs://YOUR_BUCKET lists log files within a few hours.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Bucket Lock](https://docs.cloud.google.com/storage/docs/bucket-lock) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

16. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending. Google's backlog page recommends the regional metrics. We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

   Google documentation: [Alerting overview](https://docs.cloud.google.com/monitoring/alerts) · [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

17. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope (with one organization sink filtered to projects, in one of the ticked projects) and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)

18. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form, and a cloudshell download line for each file to take with you: the key, your answers file, and the backup of your earlier audit settings if script step 6 changed them. If you ran the setup in Cloud Shell, run those lines, or the ones below, to download the files to the computer you use for Abstract: a session opened from the button is temporary, and the clean-up needs the answers file to know what the setup made. On your own computer the files are already there. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat. Menu i shows every name, ID and account the setup uses, at any time.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   ```

   **Check:** Script step 10 prints the Project ID, the Subscription ID and the key file for the Abstract form, a cloudshell download line for each file, and, if --grant added roles for this setup, the command that takes each one back once Abstract shows events.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

19. **Verify.** Cloud admin, in Cloud Shell.

   Download the files script step 10 listed to the computer you use for Abstract, if you ran the setup in Cloud Shell. Each line asks your browser to save one file and changes nothing in Google Cloud; a line whose file does not exist does nothing.

   ```bash
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ls ~/abstract-audit-config-backup-*.json 2>/dev/null && cloudshell download ~/abstract-audit-config-backup-*.json
   ```

   **Check:** Your browser saves abstract-pubsub-key.json and your answers file (.abstract-gcp-setup.env), plus abstract-workspace-key.json if you set up Workspace, and abstract-audit-config-backup-….json if script step 6 changed your audit settings. Keep the answers file and the backup until you have cleaned up.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

20. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes, parsed as Cloud Audit Logs, IAM and identity logs included. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4. Connect Abstract within 7 days of script step 4: the subscription keeps unread events for 7 days, and older ones are lost.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

21. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

   Google documentation: [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

22. **Verify (optional).** Abstract admin, in Abstract console.

   Add one GCP Pub/Sub Source configuration for each of those subscriptions: one configuration per subscription, never on the audit-log configuration, and no separate integration for findings or assets. Then ask Abstract to apply the extended GCP Pub/Sub parser to each. The managed parser as shipped keeps Cloud Audit Logs only (in a test it stored none of 9,639 network log entries it pulled); the extended parser, a dispatcher with audit, network, asset and Security Command Center sub-parsers in YAML, is not in the managed integration yet, so until it is, Abstract applies it to the configuration's parsers. Each template's tutorial prints its values in its Connect Abstract step.

   *Optional:* Skip unless you deployed the network, asset or Security Command Center template.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** Your logging project's ID, the same as the audit-log configuration's.
   - **Subscription ID:** abstract-network-threats-sub, abstract-asset-changes-sub or abstract-audit-logs-sub-scc, one per configuration.
   - **Credentials:** For the network subscription, abstract-network-key.json, the key of its own reader account (abstract-net-threat-reader), made in its tutorial. For the asset and Security Command Center subscriptions, a key of the audit-log reader account, which the templates let read them.

   **Check:** In Abstract's event search, network logs appear as gcp.vpc_flows, gcp.firewall, gcp.nat_flows and gcp.dns_queries, asset changes as gcp.asset_inventory with action iam_policy_grant, iam_policy_revoke or iam_policy_change, and findings as gcp.scc_findings. Nothing from these subscriptions appears while the configuration runs only the managed parser.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

23. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

24. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. What you deployed from a template (network, asset, Security Command Center, bucket, billing or archive) comes off with To remove it later in that template's tutorial. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Send logs from one or more Google Cloud folders, with the guided script

**Fits when:** Abstract should see one or more business units or environments, each held in a folder.

**Why this way:** A folder sink covers every project in the folder and its subfolders, including ones created later, without organization-wide rights.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=0.1). To send someone this plan, share this link.

**Not chosen:** The organization sink: you asked for some folders, not all of them.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository, whichever way you deploy.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before you finish, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose what sends logs. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Script step 1 offers the whole organization, one or more folders (a checkbox list of every folder and subfolder, its path shown), or one or more projects (a checkbox list: numbers or ranges tick and untick, a ticks all shown, n none, f every project in a folder, and any other text searches). With several projects it asks for one organization sink filtered to them, or one sink in each. Whichever way you deploy, this records your scope in the answers file, ~/.abstract-gcp-setup.env. Script step 1 asks its questions, so it is the last line of this block.

   *Note:* Run the script with no options for its menu instead: a runs the guided setup from the start, 1 to 10 one step, p the organization policy review, s what is supported where, i every saved name, ID and account, g checks or grants roles for someone, c checks everything and changes nothing, x cleans up, q quits.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose, and warns that projects created later are not covered until you tick them, if you chose projects.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, each folder, or each project you chose (with one organization sink filtered to projects, the organization). At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here, whatever your scope: the topics, the subscriptions, Abstract's service accounts and the health alerts. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before anything is built.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Check first (optional).** Cloud admin, in Cloud Shell.

   Review the organization policies that can block or change this setup. --policies (menu p) reads the effective policy at the organization, the logging project and every folder or project you chose, and sorts each into BLOCKS (the service-account key constraints), CHECK (restricted services, CMEK-only services, resource locations, allowed member domains, key expiry, Pub/Sub in-transit regions), info (cross-project service accounts, key exposure response, serial-port logging) and RECOMMEND (no audit logging exemptions, no automatic grants to default service accounts, Kubernetes cloud logging). It never changes a policy.

   *Optional:* Recommended in any organization with security policies. It reads and changes nothing, so it is safe to run before anything is built.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --policies
   ```

   **Check:** Every BLOCKS line shows ✓. A ✗ there names the constraint and where it is enforced: ask its owner for an exception on the logging project before you go on. CHECK lines say what to confirm.

   Google documentation: [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints)

6. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4, with the folders you ticked in script step 1: create the topic and subscription, then one sink in each folder, and let each sink's writer identity (the Google-managed account a sink publishes as) publish to the topic. Every folder sink sends to the one topic.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to each folder you ticked. It copies the audit logs of every project in the folder, including ones created later, and changes nothing inside those projects.

   Template: [One folder's audit logs to Abstract: folder sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-folder)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=LOGGING_PROJECT_ID (your logging project's ID) lists the sink's writer identity under roles/pubsub.publisher.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)

7. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as, or choose one you already have. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository. In a temporary Cloud Shell session, download the key as soon as script step 5 makes it, with cloudshell download ~/abstract-keys/abstract-pubsub-key.json, so a session that ends early does not take it with it. Script step 10 prints the same line again.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys. A new account is not grantable for a few seconds; the script retries the grant on its own.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

8. **Set up.** Cloud admin, in Cloud Shell.

   Script step 6, IAM and Data Access logs: turn on the IAM and identity logs (iam.googleapis.com and sts.googleapis.com, Admin Read) and any Data Access logs you choose, and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. For most services either alone does nothing; BigQuery writes its Data Access logs by default, so it needs only the routing switch. The script routes the identity events (as iamcredentials.googleapis.com and sts.googleapis.com) for you.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-….json beside your answers file (your home folder).

   *Note:* IAM and identity logs are on by default: this is where service account impersonation, token minting and Workload Identity Federation (GitHub Actions, AWS, Azure) are recorded, and their volume is low. BigQuery, Cloud Storage and Cloud KMS Data Access logs, which record who read or changed data, are optional and add volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs for each of them, naming iamcredentials.googleapis.com and sts.googleapis.com).

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)

9. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* The script's answer defaults to yes. Skip it (answer n) only if you do not use Google Workspace. Workspace sign-in, admin and token logs reach Abstract through its own Google Workspace integration, not through Pub/Sub.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

10. **Set up (optional).** Cloud admin, and the network owner, in Cloud Shell.

   This step uses Terraform, because the guided setup script builds only the audit-log sink, and this is a second sink with its own filter and topic. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block. Set sink_scope to folder and folder_id to the folder. A deployment makes one sink: for several folders, set folder_id to a folder that holds them all, or use the organization. Each network log is turned on where the resource lives, by its owner, in the project that owns the network (the host project with Shared VPC). The tutorial checks each one read-only and routes the categories Abstract keeps: firewall, dns_queries, vpc_flows and nat_flows.

   > **This changes:** Adds a log sink, abstract-network-threats-sink, to the folder, and a topic, a subscription and a reader account for it in the logging project. It turns no network logging on.

   *Optional:* Skip unless you want firewall, Cloud DNS, VPC Flow or Cloud NAT logs in Abstract. Abstract keeps them only on a GCP Pub/Sub Source configuration of their own that runs the extended GCP Pub/Sub parser (the Abstract card below); load balancer (Cloud Armor) and Cloud IDS records are not kept.

   Template: [Network logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

   Set: `sink_scope` = `folder`

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-network-threats-sink --organization=ORG_ID, with your organization's ID (--folder=FOLDER_ID or --project=PROJECT_ID for those scopes), shows a filter naming the categories you chose and the abstract-network-threats topic.

   Google documentation: [VPC firewall rules logging overview](https://docs.cloud.google.com/firewall/docs/vpc-firewall-rules-logging-overview) · [Use logging and monitoring](https://docs.cloud.google.com/dns/docs/monitoring#using_logging) · [VPC Flow Logs](https://docs.cloud.google.com/vpc/docs/flow-logs) · [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the guided script builds only the audit-log pipeline, and watching a bucket needs a notification on each bucket and a grant in each project that owns one, which the template sets from your list. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed. It notifies a topic for each new object, so Abstract fetches it. Abstract stores the objects' content only once a parser for their format is attached to this subscription's own integration; the managed GCP Pub/Sub Source parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product.

   > **This changes:** Adds a Pub/Sub notification to each bucket you name, and lets Abstract's reader account read their objects.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-cloud-storage-bucket-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud storage buckets notifications list gs://YOUR_BUCKET, with your bucket's name, shows a notification on the topic abstract-gcs-notifications.

   Google documentation: [Pub/Sub notifications for Cloud Storage](https://docs.cloud.google.com/storage/docs/pubsub-notifications) · [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

12. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending. Google's backlog page recommends the regional metrics. We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

   Google documentation: [Alerting overview](https://docs.cloud.google.com/monitoring/alerts) · [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

13. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope (with one organization sink filtered to projects, in one of the ticked projects) and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)

14. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form, and a cloudshell download line for each file to take with you: the key, your answers file, and the backup of your earlier audit settings if script step 6 changed them. If you ran the setup in Cloud Shell, run those lines, or the ones below, to download the files to the computer you use for Abstract: a session opened from the button is temporary, and the clean-up needs the answers file to know what the setup made. On your own computer the files are already there. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat. Menu i shows every name, ID and account the setup uses, at any time.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   ```

   **Check:** Script step 10 prints the Project ID, the Subscription ID and the key file for the Abstract form, a cloudshell download line for each file, and, if --grant added roles for this setup, the command that takes each one back once Abstract shows events.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

15. **Verify.** Cloud admin, in Cloud Shell.

   Download the files script step 10 listed to the computer you use for Abstract, if you ran the setup in Cloud Shell. Each line asks your browser to save one file and changes nothing in Google Cloud; a line whose file does not exist does nothing.

   ```bash
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ls ~/abstract-audit-config-backup-*.json 2>/dev/null && cloudshell download ~/abstract-audit-config-backup-*.json
   ```

   **Check:** Your browser saves abstract-pubsub-key.json and your answers file (.abstract-gcp-setup.env), plus abstract-workspace-key.json if you set up Workspace, and abstract-audit-config-backup-….json if script step 6 changed your audit settings. Keep the answers file and the backup until you have cleaned up.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

16. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes, parsed as Cloud Audit Logs, IAM and identity logs included. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4. Connect Abstract within 7 days of script step 4: the subscription keeps unread events for 7 days, and older ones are lost.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

17. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

   Google documentation: [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

18. **Verify (optional).** Abstract admin, in Abstract console.

   Add one GCP Pub/Sub Source configuration for each of those subscriptions: one configuration per subscription, never on the audit-log configuration, and no separate integration for findings or assets. Then ask Abstract to apply the extended GCP Pub/Sub parser to each. The managed parser as shipped keeps Cloud Audit Logs only (in a test it stored none of 9,639 network log entries it pulled); the extended parser, a dispatcher with audit, network, asset and Security Command Center sub-parsers in YAML, is not in the managed integration yet, so until it is, Abstract applies it to the configuration's parsers. Each template's tutorial prints its values in its Connect Abstract step.

   *Optional:* Skip unless you deployed the network, asset or Security Command Center template.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** Your logging project's ID, the same as the audit-log configuration's.
   - **Subscription ID:** abstract-network-threats-sub, abstract-asset-changes-sub or abstract-audit-logs-sub-scc, one per configuration.
   - **Credentials:** For the network subscription, abstract-network-key.json, the key of its own reader account (abstract-net-threat-reader), made in its tutorial. For the asset and Security Command Center subscriptions, a key of the audit-log reader account, which the templates let read them.

   **Check:** In Abstract's event search, network logs appear as gcp.vpc_flows, gcp.firewall, gcp.nat_flows and gcp.dns_queries, asset changes as gcp.asset_inventory with action iam_policy_grant, iam_policy_revoke or iam_policy_change, and findings as gcp.scc_findings. Nothing from these subscriptions appears while the configuration runs only the managed parser.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

19. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

20. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. What you deployed from a template (network, asset, Security Command Center, bucket, billing or archive) comes off with To remove it later in that template's tutorial. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Send logs from chosen projects through one filtered organization sink, with the guided script

**Fits when:** Abstract should see a set of projects, and you can create a sink at the organization.

**Why this way:** One organization sink whose filter names only the ticked projects: one sink and one grant to look after, however many projects. Projects created later are not covered until you tick them in script step 1.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=0.2.0). To send someone this plan, share this link.

**Not chosen:** One sink in each project: more sinks and more grants to keep, for the same coverage.

**Not chosen:** The organization sink unfiltered: it would send every project.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository, whichever way you deploy.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before you finish, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose what sends logs. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Script step 1 offers the whole organization, one or more folders (a checkbox list of every folder and subfolder, its path shown), or one or more projects (a checkbox list: numbers or ranges tick and untick, a ticks all shown, n none, f every project in a folder, and any other text searches). With several projects it asks for one organization sink filtered to them, or one sink in each. Whichever way you deploy, this records your scope in the answers file, ~/.abstract-gcp-setup.env. Script step 1 asks its questions, so it is the last line of this block.

   *Note:* Run the script with no options for its menu instead: a runs the guided setup from the start, 1 to 10 one step, p the organization policy review, s what is supported where, i every saved name, ID and account, g checks or grants roles for someone, c checks everything and changes nothing, x cleans up, q quits.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose, and warns that projects created later are not covered until you tick them, if you chose projects.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, each folder, or each project you chose (with one organization sink filtered to projects, the organization). At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here, whatever your scope: the topics, the subscriptions, Abstract's service accounts and the health alerts. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before anything is built.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Check first (optional).** Cloud admin, in Cloud Shell.

   Review the organization policies that can block or change this setup. --policies (menu p) reads the effective policy at the organization, the logging project and every folder or project you chose, and sorts each into BLOCKS (the service-account key constraints), CHECK (restricted services, CMEK-only services, resource locations, allowed member domains, key expiry, Pub/Sub in-transit regions), info (cross-project service accounts, key exposure response, serial-port logging) and RECOMMEND (no audit logging exemptions, no automatic grants to default service accounts, Kubernetes cloud logging). It never changes a policy.

   *Optional:* Recommended in any organization with security policies. It reads and changes nothing, so it is safe to run before anything is built.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --policies
   ```

   **Check:** Every BLOCKS line shows ✓. A ✗ there names the constraint and where it is enforced: ask its owner for an exception on the logging project before you go on. CHECK lines say what to confirm.

   Google documentation: [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints)

6. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4, with the projects you ticked in script step 1: create the topic and subscription, then one organization sink whose filter routes only those projects' logs, and let the sink's writer identity publish to the topic. Needs Logs Configuration Writer at the organization.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to your organization, filtered to the projects you ticked. It copies their audit logs and changes nothing inside them. A sink that already routes every project is never narrowed: the script asks for a sink of its own instead.

   Template: [All Google Cloud audit logs to Abstract: organization sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-organization)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic and "the sink's own identity can publish", and a line naming the projects the filter is limited to. Menu i lists the ticked projects.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth) · [Logging query language](https://docs.cloud.google.com/logging/docs/view/logging-query-language) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription)

7. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as, or choose one you already have. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository. In a temporary Cloud Shell session, download the key as soon as script step 5 makes it, with cloudshell download ~/abstract-keys/abstract-pubsub-key.json, so a session that ends early does not take it with it. Script step 10 prints the same line again.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys. A new account is not grantable for a few seconds; the script retries the grant on its own.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

8. **Set up.** Cloud admin, in Cloud Shell.

   Script step 6, IAM and Data Access logs, as in the other plans. With one filtered organization sink, switch 1 (the audit settings) is set in each ticked project, so Data Access is not turned on, and paid for, in projects the sink never routes. Switch 2 extends the organization sink's filter, still limited to the ticked projects.

   > **This changes:** Changes the audit settings (auditConfigs) in each ticked project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, beside your answers file.

   *Note:* IAM and identity logs are on by default: this is where service account impersonation, token minting and Workload Identity Federation (GitHub Actions, AWS, Azure) are recorded, and their volume is low. BigQuery, Cloud Storage and Cloud KMS Data Access logs, which record who read or changed data, are optional and add volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs for each of them, naming iamcredentials.googleapis.com and sts.googleapis.com).

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)

9. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* The script's answer defaults to yes. Skip it (answer n) only if you do not use Google Workspace. Workspace sign-in, admin and token logs reach Abstract through its own Google Workspace integration, not through Pub/Sub.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

10. **Set up (optional).** Cloud admin, and the network owner, in Cloud Shell.

   This step uses Terraform, because the guided setup script builds only the audit-log sink, and this is a second sink with its own filter and topic. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block. A project sink takes one project per deployment (sink_scope project, with acknowledge_pilot_scope = true): deploy it in the project that owns the network, the host project with Shared VPC. The tutorial checks each network log read-only and routes the categories Abstract keeps: firewall, dns_queries, vpc_flows and nat_flows.

   > **This changes:** Adds a log sink, abstract-network-threats-sink, to the project, and a topic, a subscription and a reader account for it in the logging project. It turns no network logging on.

   *Optional:* Skip unless you want firewall, Cloud DNS, VPC Flow or Cloud NAT logs in Abstract. Abstract keeps them only on a GCP Pub/Sub Source configuration of their own that runs the extended GCP Pub/Sub parser (the Abstract card below); load balancer (Cloud Armor) and Cloud IDS records are not kept.

   Template: [Network logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

   Set: `sink_scope` = `project`

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-network-threats-sink --organization=ORG_ID, with your organization's ID (--folder=FOLDER_ID or --project=PROJECT_ID for those scopes), shows a filter naming the categories you chose and the abstract-network-threats topic.

   Google documentation: [VPC firewall rules logging overview](https://docs.cloud.google.com/firewall/docs/vpc-firewall-rules-logging-overview) · [Use logging and monitoring](https://docs.cloud.google.com/dns/docs/monitoring#using_logging) · [VPC Flow Logs](https://docs.cloud.google.com/vpc/docs/flow-logs) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#creating_sink) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the guided script builds only the audit-log pipeline, and watching a bucket needs a notification on each bucket and a grant in each project that owns one, which the template sets from your list. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed. It notifies a topic for each new object, so Abstract fetches it. Abstract stores the objects' content only once a parser for their format is attached to this subscription's own integration; the managed GCP Pub/Sub Source parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product.

   > **This changes:** Adds a Pub/Sub notification to each bucket you name, and lets Abstract's reader account read their objects.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-cloud-storage-bucket-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud storage buckets notifications list gs://YOUR_BUCKET, with your bucket's name, shows a notification on the topic abstract-gcs-notifications.

   Google documentation: [Pub/Sub notifications for Cloud Storage](https://docs.cloud.google.com/storage/docs/pubsub-notifications) · [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

12. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending. Google's backlog page recommends the regional metrics. We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

   Google documentation: [Alerting overview](https://docs.cloud.google.com/monitoring/alerts) · [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

13. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope (with one organization sink filtered to projects, in one of the ticked projects) and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)

14. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form, and a cloudshell download line for each file to take with you: the key, your answers file, and the backup of your earlier audit settings if script step 6 changed them. If you ran the setup in Cloud Shell, run those lines, or the ones below, to download the files to the computer you use for Abstract: a session opened from the button is temporary, and the clean-up needs the answers file to know what the setup made. On your own computer the files are already there. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat. Menu i shows every name, ID and account the setup uses, at any time.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   ```

   **Check:** Script step 10 prints the Project ID, the Subscription ID and the key file for the Abstract form, a cloudshell download line for each file, and, if --grant added roles for this setup, the command that takes each one back once Abstract shows events.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

15. **Verify.** Cloud admin, in Cloud Shell.

   Download the files script step 10 listed to the computer you use for Abstract, if you ran the setup in Cloud Shell. Each line asks your browser to save one file and changes nothing in Google Cloud; a line whose file does not exist does nothing.

   ```bash
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ls ~/abstract-audit-config-backup-*.json 2>/dev/null && cloudshell download ~/abstract-audit-config-backup-*.json
   ```

   **Check:** Your browser saves abstract-pubsub-key.json and your answers file (.abstract-gcp-setup.env), plus abstract-workspace-key.json if you set up Workspace, and abstract-audit-config-backup-….json if script step 6 changed your audit settings. Keep the answers file and the backup until you have cleaned up.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

16. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes, parsed as Cloud Audit Logs, IAM and identity logs included. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4. Connect Abstract within 7 days of script step 4: the subscription keeps unread events for 7 days, and older ones are lost.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

17. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

   Google documentation: [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

18. **Verify (optional).** Abstract admin, in Abstract console.

   Add one GCP Pub/Sub Source configuration for each of those subscriptions: one configuration per subscription, never on the audit-log configuration, and no separate integration for findings or assets. Then ask Abstract to apply the extended GCP Pub/Sub parser to each. The managed parser as shipped keeps Cloud Audit Logs only (in a test it stored none of 9,639 network log entries it pulled); the extended parser, a dispatcher with audit, network, asset and Security Command Center sub-parsers in YAML, is not in the managed integration yet, so until it is, Abstract applies it to the configuration's parsers. Each template's tutorial prints its values in its Connect Abstract step.

   *Optional:* Skip unless you deployed the network, asset or Security Command Center template.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** Your logging project's ID, the same as the audit-log configuration's.
   - **Subscription ID:** abstract-network-threats-sub, abstract-asset-changes-sub or abstract-audit-logs-sub-scc, one per configuration.
   - **Credentials:** For the network subscription, abstract-network-key.json, the key of its own reader account (abstract-net-threat-reader), made in its tutorial. For the asset and Security Command Center subscriptions, a key of the audit-log reader account, which the templates let read them.

   **Check:** In Abstract's event search, network logs appear as gcp.vpc_flows, gcp.firewall, gcp.nat_flows and gcp.dns_queries, asset changes as gcp.asset_inventory with action iam_policy_grant, iam_policy_revoke or iam_policy_change, and findings as gcp.scc_findings. Nothing from these subscriptions appears while the configuration runs only the managed parser.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

19. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

20. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. What you deployed from a template (network, asset, Security Command Center, bucket, billing or archive) comes off with To remove it later in that template's tutorial. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Send logs from one project, or one sink in each project, with the guided script

**Fits when:** You want one project as a pilot, or several projects without organization-level rights.

**Why this way:** A sink in each project needs Logs Configuration Writer on that project only. Every sink sends to the one topic. Move to the organization plan when the pilot is done.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=0.2.1). To send someone this plan, share this link.

**Not chosen:** The organization sink, filtered or not: it needs organization rights you may not have.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository, whichever way you deploy.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before you finish, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose what sends logs. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Script step 1 offers the whole organization, one or more folders (a checkbox list of every folder and subfolder, its path shown), or one or more projects (a checkbox list: numbers or ranges tick and untick, a ticks all shown, n none, f every project in a folder, and any other text searches). With several projects it asks for one organization sink filtered to them, or one sink in each. Whichever way you deploy, this records your scope in the answers file, ~/.abstract-gcp-setup.env. Script step 1 asks its questions, so it is the last line of this block.

   *Note:* Run the script with no options for its menu instead: a runs the guided setup from the start, 1 to 10 one step, p the organization policy review, s what is supported where, i every saved name, ID and account, g checks or grants roles for someone, c checks everything and changes nothing, x cleans up, q quits.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose, and warns that projects created later are not covered until you tick them, if you chose projects.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, each folder, or each project you chose (with one organization sink filtered to projects, the organization). At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here, whatever your scope: the topics, the subscriptions, Abstract's service accounts and the health alerts. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before anything is built.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Check first (optional).** Cloud admin, in Cloud Shell.

   Review the organization policies that can block or change this setup. --policies (menu p) reads the effective policy at the organization, the logging project and every folder or project you chose, and sorts each into BLOCKS (the service-account key constraints), CHECK (restricted services, CMEK-only services, resource locations, allowed member domains, key expiry, Pub/Sub in-transit regions), info (cross-project service accounts, key exposure response, serial-port logging) and RECOMMEND (no audit logging exemptions, no automatic grants to default service accounts, Kubernetes cloud logging). It never changes a policy.

   *Optional:* Recommended in any organization with security policies. It reads and changes nothing, so it is safe to run before anything is built.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --policies
   ```

   **Check:** Every BLOCKS line shows ✓. A ✗ there names the constraint and where it is enforced: ask its owner for an exception on the logging project before you go on. CHECK lines say what to confirm.

   Google documentation: [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints)

6. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4, with the projects you ticked in script step 1: create the topic and subscription, then a sink in each project, and let each sink's writer identity (the Google-managed account a sink publishes as) publish to the topic.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to each project you ticked. It copies that project's audit logs and changes nothing else in it.

   Template: [One project's audit logs to Abstract: project sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=LOGGING_PROJECT_ID (your logging project's ID) lists the sink's writer identity under roles/pubsub.publisher.

   Google documentation: [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#creating_sink) · [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)

7. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as, or choose one you already have. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository. In a temporary Cloud Shell session, download the key as soon as script step 5 makes it, with cloudshell download ~/abstract-keys/abstract-pubsub-key.json, so a session that ends early does not take it with it. Script step 10 prints the same line again.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys. A new account is not grantable for a few seconds; the script retries the grant on its own.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

8. **Set up.** Cloud admin, in Cloud Shell.

   Script step 6, IAM and Data Access logs: turn on the IAM and identity logs (iam.googleapis.com and sts.googleapis.com, Admin Read) and any Data Access logs you choose, and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. For most services either alone does nothing; BigQuery writes its Data Access logs by default, so it needs only the routing switch. The script routes the identity events (as iamcredentials.googleapis.com and sts.googleapis.com) for you.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-….json beside your answers file (your home folder).

   *Note:* IAM and identity logs are on by default: this is where service account impersonation, token minting and Workload Identity Federation (GitHub Actions, AWS, Azure) are recorded, and their volume is low. BigQuery, Cloud Storage and Cloud KMS Data Access logs, which record who read or changed data, are optional and add volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs for each of them, naming iamcredentials.googleapis.com and sts.googleapis.com).

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)

9. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* The script's answer defaults to yes. Skip it (answer n) only if you do not use Google Workspace. Workspace sign-in, admin and token logs reach Abstract through its own Google Workspace integration, not through Pub/Sub.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

10. **Set up (optional).** Cloud admin, and the network owner, in Cloud Shell.

   This step uses Terraform, because the guided setup script builds only the audit-log sink, and this is a second sink with its own filter and topic. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block. A project sink takes one project per deployment (sink_scope project, with acknowledge_pilot_scope = true): deploy it in the project that owns the network, the host project with Shared VPC. The tutorial checks each network log read-only and routes the categories Abstract keeps: firewall, dns_queries, vpc_flows and nat_flows.

   > **This changes:** Adds a log sink, abstract-network-threats-sink, to the project, and a topic, a subscription and a reader account for it in the logging project. It turns no network logging on.

   *Optional:* Skip unless you want firewall, Cloud DNS, VPC Flow or Cloud NAT logs in Abstract. Abstract keeps them only on a GCP Pub/Sub Source configuration of their own that runs the extended GCP Pub/Sub parser (the Abstract card below); load balancer (Cloud Armor) and Cloud IDS records are not kept.

   Template: [Network logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

   Set: `sink_scope` = `project`

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-network-threats-sink --organization=ORG_ID, with your organization's ID (--folder=FOLDER_ID or --project=PROJECT_ID for those scopes), shows a filter naming the categories you chose and the abstract-network-threats topic.

   Google documentation: [VPC firewall rules logging overview](https://docs.cloud.google.com/firewall/docs/vpc-firewall-rules-logging-overview) · [Use logging and monitoring](https://docs.cloud.google.com/dns/docs/monitoring#using_logging) · [VPC Flow Logs](https://docs.cloud.google.com/vpc/docs/flow-logs) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#creating_sink) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the guided script builds only the audit-log pipeline, and watching a bucket needs a notification on each bucket and a grant in each project that owns one, which the template sets from your list. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed. It notifies a topic for each new object, so Abstract fetches it. Abstract stores the objects' content only once a parser for their format is attached to this subscription's own integration; the managed GCP Pub/Sub Source parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product.

   > **This changes:** Adds a Pub/Sub notification to each bucket you name, and lets Abstract's reader account read their objects.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-cloud-storage-bucket-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud storage buckets notifications list gs://YOUR_BUCKET, with your bucket's name, shows a notification on the topic abstract-gcs-notifications.

   Google documentation: [Pub/Sub notifications for Cloud Storage](https://docs.cloud.google.com/storage/docs/pubsub-notifications) · [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

12. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending. Google's backlog page recommends the regional metrics. We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

   Google documentation: [Alerting overview](https://docs.cloud.google.com/monitoring/alerts) · [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

13. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope (with one organization sink filtered to projects, in one of the ticked projects) and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)

14. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form, and a cloudshell download line for each file to take with you: the key, your answers file, and the backup of your earlier audit settings if script step 6 changed them. If you ran the setup in Cloud Shell, run those lines, or the ones below, to download the files to the computer you use for Abstract: a session opened from the button is temporary, and the clean-up needs the answers file to know what the setup made. On your own computer the files are already there. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat. Menu i shows every name, ID and account the setup uses, at any time.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   ```

   **Check:** Script step 10 prints the Project ID, the Subscription ID and the key file for the Abstract form, a cloudshell download line for each file, and, if --grant added roles for this setup, the command that takes each one back once Abstract shows events.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

15. **Verify.** Cloud admin, in Cloud Shell.

   Download the files script step 10 listed to the computer you use for Abstract, if you ran the setup in Cloud Shell. Each line asks your browser to save one file and changes nothing in Google Cloud; a line whose file does not exist does nothing.

   ```bash
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ls ~/abstract-audit-config-backup-*.json 2>/dev/null && cloudshell download ~/abstract-audit-config-backup-*.json
   ```

   **Check:** Your browser saves abstract-pubsub-key.json and your answers file (.abstract-gcp-setup.env), plus abstract-workspace-key.json if you set up Workspace, and abstract-audit-config-backup-….json if script step 6 changed your audit settings. Keep the answers file and the backup until you have cleaned up.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

16. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes, parsed as Cloud Audit Logs, IAM and identity logs included. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4. Connect Abstract within 7 days of script step 4: the subscription keeps unread events for 7 days, and older ones are lost.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

17. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

   Google documentation: [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

18. **Verify (optional).** Abstract admin, in Abstract console.

   Add one GCP Pub/Sub Source configuration for each of those subscriptions: one configuration per subscription, never on the audit-log configuration, and no separate integration for findings or assets. Then ask Abstract to apply the extended GCP Pub/Sub parser to each. The managed parser as shipped keeps Cloud Audit Logs only (in a test it stored none of 9,639 network log entries it pulled); the extended parser, a dispatcher with audit, network, asset and Security Command Center sub-parsers in YAML, is not in the managed integration yet, so until it is, Abstract applies it to the configuration's parsers. Each template's tutorial prints its values in its Connect Abstract step.

   *Optional:* Skip unless you deployed the network, asset or Security Command Center template.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** Your logging project's ID, the same as the audit-log configuration's.
   - **Subscription ID:** abstract-network-threats-sub, abstract-asset-changes-sub or abstract-audit-logs-sub-scc, one per configuration.
   - **Credentials:** For the network subscription, abstract-network-key.json, the key of its own reader account (abstract-net-threat-reader), made in its tutorial. For the asset and Security Command Center subscriptions, a key of the audit-log reader account, which the templates let read them.

   **Check:** In Abstract's event search, network logs appear as gcp.vpc_flows, gcp.firewall, gcp.nat_flows and gcp.dns_queries, asset changes as gcp.asset_inventory with action iam_policy_grant, iam_policy_revoke or iam_policy_change, and findings as gcp.scc_findings. Nothing from these subscriptions appears while the configuration runs only the managed parser.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

19. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

20. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. What you deployed from a template (network, asset, Security Command Center, bucket, billing or archive) comes off with To remove it later in that template's tutorial. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Send logs with Terraform

**Fits when:** Your team requires infrastructure as code, with the state in a bucket you own.

**Why this way:** Each template is the same pipeline the guided script builds, with the same names, as a Terraform root you can review, plan and apply. Script steps 1 to 3 above still record your scope and make the logging project; each template's tutorial reads them.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=1). To send someone this plan, share this link.

**Not chosen:** Several folders or several projects in one run: a template makes one sink, at one scope. Use the guided script for those.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository, whichever way you deploy.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before you finish, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose what sends logs. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Script step 1 offers the whole organization, one or more folders (a checkbox list of every folder and subfolder, its path shown), or one or more projects (a checkbox list: numbers or ranges tick and untick, a ticks all shown, n none, f every project in a folder, and any other text searches). With several projects it asks for one organization sink filtered to them, or one sink in each. Whichever way you deploy, this records your scope in the answers file, ~/.abstract-gcp-setup.env. Script step 1 asks its questions, so it is the last line of this block.

   *Note:* Run the script with no options for its menu instead: a runs the guided setup from the start, 1 to 10 one step, p the organization policy review, s what is supported where, i every saved name, ID and account, g checks or grants roles for someone, c checks everything and changes nothing, x cleans up, q quits.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose, and warns that projects created later are not covered until you tick them, if you chose projects.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, each folder, or each project you chose (with one organization sink filtered to projects, the organization). At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here, whatever your scope: the topics, the subscriptions, Abstract's service accounts and the health alerts. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before anything is built.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Check first (optional).** Cloud admin, in Cloud Shell.

   Review the organization policies that can block or change this setup. --policies (menu p) reads the effective policy at the organization, the logging project and every folder or project you chose, and sorts each into BLOCKS (the service-account key constraints), CHECK (restricted services, CMEK-only services, resource locations, allowed member domains, key expiry, Pub/Sub in-transit regions), info (cross-project service accounts, key exposure response, serial-port logging) and RECOMMEND (no audit logging exemptions, no automatic grants to default service accounts, Kubernetes cloud logging). It never changes a policy.

   *Optional:* Recommended in any organization with security policies. It reads and changes nothing, so it is safe to run before anything is built.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --policies
   ```

   **Check:** Every BLOCKS line shows ✓. A ✗ there names the constraint and where it is enforced: ask its owner for an exception on the logging project before you go on. CHECK lines say what to confirm.

   Google documentation: [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints)

6. **Set up.** Cloud admin, in Cloud Shell.

   Open the audit-log template for your scope in Cloud Shell's tutorial pane, and follow its Terraform instead section: keep the state in a bucket, fill in terraform.tfvars, preview, apply exactly what you previewed, then Connect Abstract, which prints the values and makes the key with gcloud, so no key sits in the state. The commands below are for the organization; for one folder or one project, put gcp-source-audit-logs-folder or gcp-source-audit-logs-project in the cd line instead. The default log_categories route the Cloud Audit Logs and the IAM and identity logs (identity_access).

   > **This changes:** Adds a log sink, abstract-org-audit-sink, at the organization, folder or project you chose, a topic and subscription in the logging project, and Abstract's reader account with Subscriber on that subscription only.

   Templates, one per source:

   - [All Google Cloud audit logs to Abstract: organization sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-organization)
   - [One folder's audit logs to Abstract: folder sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-folder)
   - [One project's audit logs to Abstract: project sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-project)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-organization"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** The tutorial's Verify section shows the sink at your scope sending to abstract-audit-logs, and the sink's writer identity under roles/pubsub.publisher on the topic. Tested on one folder: Abstract stored audit logs only from the project in that folder.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

7. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the audit settings are switch 1 of two: this template sets them, and the audit-log template's identity_access and data_access_all categories route the logs (switch 2). The commands below open its tutorial. It keeps its own state, so removing a collector never strips your Data Access audit logging.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you name. Role bindings are untouched. The tutorial saves a copy of the earlier settings first.

   *Optional:* Recommended for identity. The audit-log template already routes the IAM and identity logs; this template makes Google write them, and any Data Access logs you choose (BigQuery, Cloud Storage, Cloud KMS), at your scope. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-foundation-data-access-audit-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** The tutorial's Verify section shows Data Access log types on each service you named, at your scope.

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

8. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* The script's answer defaults to yes. Skip it (answer n) only if you do not use Google Workspace. Workspace sign-in, admin and token logs reach Abstract through its own Google Workspace integration, not through Pub/Sub.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

9. **Set up (optional).** Cloud admin, and the network owner, in Cloud Shell.

   This step uses Terraform, because the guided setup script builds only the audit-log sink, and this is a second sink with its own filter and topic. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block. Each network log is turned on where the resource lives, by its owner: firewall rule logging per rule, DNS query logging per network, VPC Flow Logs per subnet (or for a project or the organization), Cloud NAT logging per gateway, in the project that owns the network (the host project with Shared VPC); docs/gcp/FILTERS.md, Where each source is turned on, has each one. The tutorial checks each one read-only and routes the categories Abstract keeps: firewall, dns_queries, vpc_flows and nat_flows.

   > **This changes:** Adds a log sink, abstract-network-threats-sink, at the scope you set, and a topic, a subscription and a reader account for it in the logging project. It turns no network logging on.

   *Optional:* Skip unless you want firewall, Cloud DNS, VPC Flow or Cloud NAT logs in Abstract. Abstract keeps them only on a GCP Pub/Sub Source configuration of their own that runs the extended GCP Pub/Sub parser (the Abstract card below); load balancer (Cloud Armor) and Cloud IDS records are not kept.

   Template: [Network logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-network-threats-sink --organization=ORG_ID, with your organization's ID (--folder=FOLDER_ID or --project=PROJECT_ID for those scopes), shows a filter naming the categories you chose and the abstract-network-threats topic.

   Google documentation: [VPC firewall rules logging overview](https://docs.cloud.google.com/firewall/docs/vpc-firewall-rules-logging-overview) · [Use logging and monitoring](https://docs.cloud.google.com/dns/docs/monitoring#using_logging) · [VPC Flow Logs](https://docs.cloud.google.com/vpc/docs/flow-logs) · [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

10. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because Cloud Asset Inventory publishes through an organization feed of its own, not a log sink, and the guided setup script builds only the sink. The commands below open the template's tutorial in Cloud Shell's tutorial pane. Feed names are unique in an organization: a second deployment in the same organization sets its own feed_id. The first apply waits 60 seconds for the Cloud Asset Inventory service agent before granting it publisher on the topic, and the feed's first message is a plain-text greeting the extended parser drops.

   > **This changes:** Adds an asset feed, abstract-asset-feed, to your organization, a topic and subscription for it in the logging project, and lets Abstract's existing reader account read that subscription.

   *Optional:* Organization only: the feed is set on the organization. Skip unless you want IAM policy changes with the policy before and after, which Abstract keeps on a configuration of their own that runs the extended GCP Pub/Sub parser (gcp.asset_inventory, action iam_policy_grant, iam_policy_revoke or iam_policy_change).

   Template: [Asset and IAM changes to Abstract: asset feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-asset-and-iam-changes)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-asset-and-iam-changes"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud asset feeds list --organization=ORG_ID, with your organization's ID, lists abstract-asset-feed (or your feed_id) publishing to the abstract-asset-changes topic.

   Google documentation: [Monitor asset changes with Pub/Sub](https://docs.cloud.google.com/asset-inventory/docs/monitor-asset-changes#create_feeds) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

11. **Set up (optional).** Cloud admin, with a Security Command Center admin, in Cloud Shell.

   This step uses Terraform, because Security Command Center publishes through a notification config of its own, not a log sink, and the guided setup script builds only the sink. Whoever applies needs Security Center Notification Configurations Editor (roles/securitycenter.notificationConfigEditor) at the organization. Right after Security Command Center is activated, the create can answer 400 "Precondition check failed" and still create the config: the tutorial lists the configs and imports it into the state.

   > **This changes:** Adds a Security Command Center notification config, abstract-findings, to your organization, a topic and subscription for it in the logging project, and lets Abstract's existing reader account read that subscription.

   *Optional:* Organization only. Needs Security Command Center Standard or Premium active at the organization (tested with Premium); an organization still on legacy Security Command Center gets 400 "Security Command Center Legacy has been permanently disabled". Abstract keeps the findings on a configuration of their own that runs the extended GCP Pub/Sub parser (gcp.scc_findings).

   Template: [Security Command Center findings to Abstract: notification feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-security-command-center-findings)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-security-command-center-findings"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud scc notifications list --organization=ORG_ID --location=global, with your organization's ID, lists abstract-findings.

   Google documentation: [Enable finding notifications for Pub/Sub](https://docs.cloud.google.com/security-command-center/docs/how-to-notifications) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

12. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the guided script builds only the audit-log pipeline, and watching a bucket needs a notification on each bucket and a grant in each project that owns one, which the template sets from your list. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed. It notifies a topic for each new object, so Abstract fetches it. Abstract stores the objects' content only once a parser for their format is attached to this subscription's own integration; the managed GCP Pub/Sub Source parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product.

   > **This changes:** Adds a Pub/Sub notification to each bucket you name, and lets Abstract's reader account read their objects.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-cloud-storage-bucket-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud storage buckets notifications list gs://YOUR_BUCKET, with your bucket's name, shows a notification on the topic abstract-gcs-notifications.

   Google documentation: [Pub/Sub notifications for Cloud Storage](https://docs.cloud.google.com/storage/docs/pubsub-notifications) · [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

13. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because a billing account is not inside your organization, so the guided script's sink cannot reach it: the template puts a sink on the billing account itself. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed.

   > **This changes:** Adds a log sink, abstract-billing-audit-sink, to the billing account.

   *Optional:* Skip unless you want billing account audit logs. An organization sink routes the organization and the folders and projects under it; a billing account is a separate resource, so its logs are collected with a sink created on the billing account itself.

   Template: [Billing account audit logs to Abstract: billing sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-billing-account-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-billing-account-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-billing-audit-sink --billing-account=BILLING_ACCOUNT_ID, with your billing account's ID, shows the sink and its Pub/Sub destination.

   Google documentation: [gcloud logging sinks create](https://docs.cloud.google.com/sdk/gcloud/reference/logging/sinks/create#--billing-account) · [Cloud Billing audit logging](https://docs.cloud.google.com/billing/docs/audit-logging) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

14. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the guided script builds only the streaming pipeline, and the archive is a second sink with a bucket (and an optional retention lock) of its own, which the template creates. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it copies the streaming sink's filter, keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed. Abstract does not read the archive today.

   > **This changes:** Adds a second log sink, abstract-org-audit-sink-archive, to your organization, and a bucket for it.

   *Optional:* Organization only, a second sink at the organization. Skip unless you need to keep logs as evidence in Cloud Storage; Abstract does not read the archive today. It is not the detection path; files land minutes to hours later.

   Template: [Archive Google Cloud logs to Cloud Storage: second sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-archive-log-bucket)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-archive-log-bucket"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-org-audit-sink-archive --organization=ORG_ID, with your organization's ID, points at your bucket, and gcloud storage ls gs://YOUR_BUCKET lists log files within a few hours.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Bucket Lock](https://docs.cloud.google.com/storage/docs/bucket-lock) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

15. **Verify (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because you chose it for the pipeline too: the alerts template creates the same three alerts and email channel as script step 8, in the logging project. The commands below open its tutorial. Google's backlog page recommends the regional metrics. We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-monitoring-pipeline-health-alerts"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

   Google documentation: [Alerting overview](https://docs.cloud.google.com/monitoring/alerts) · [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

16. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values the audit-log tutorial's Connect Abstract step printed (terraform output abstract_onboarding) and the key it made. Once it saves, delete every copy of the key, as that step says.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** project_id from terraform output abstract_onboarding, your logging project.
   - **Subscription ID:** subscription_id from the same output, abstract-audit-logs-sub unless you renamed it. The short name only.
   - **Credentials:** Upload abstract-pubsub-key.json, the key the Connect Abstract step made.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes, parsed as Cloud Audit Logs, IAM and identity logs included. Connect Abstract within 7 days of the apply: the subscription keeps unread events for 7 days, and older ones are lost.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

17. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

   Google documentation: [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

18. **Verify (optional).** Abstract admin, in Abstract console.

   Add one GCP Pub/Sub Source configuration for each of those subscriptions: one configuration per subscription, never on the audit-log configuration, and no separate integration for findings or assets. Then ask Abstract to apply the extended GCP Pub/Sub parser to each. The managed parser as shipped keeps Cloud Audit Logs only (in a test it stored none of 9,639 network log entries it pulled); the extended parser, a dispatcher with audit, network, asset and Security Command Center sub-parsers in YAML, is not in the managed integration yet, so until it is, Abstract applies it to the configuration's parsers. Each template's tutorial prints its values in its Connect Abstract step.

   *Optional:* Skip unless you deployed the network, asset or Security Command Center template.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** Your logging project's ID, the same as the audit-log configuration's.
   - **Subscription ID:** abstract-network-threats-sub, abstract-asset-changes-sub or abstract-audit-logs-sub-scc, one per configuration.
   - **Credentials:** For the network subscription, abstract-network-key.json, the key of its own reader account (abstract-net-threat-reader), made in its tutorial. For the asset and Security Command Center subscriptions, a key of the audit-log reader account, which the templates let read them.

   **Check:** In Abstract's event search, network logs appear as gcp.vpc_flows, gcp.firewall, gcp.nat_flows and gcp.dns_queries, asset changes as gcp.asset_inventory with action iam_policy_grant, iam_policy_revoke or iam_policy_change, and findings as gcp.scc_findings. Nothing from these subscriptions appears while the configuration runs only the managed parser.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

19. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then, in each template folder you applied, follow To remove it later at the end of its tutorial, with the same backend.tf: the sources first, the audit-log template last. It says what terraform destroy refuses on purpose (the topic, the subscription and the sink carry prevent_destroy, so a stray destroy cannot drop logs Abstract has not read) and the gcloud commands that remove them. Then the two cards below remove what the guided script made, such as the Workspace account and the roles --grant added.

   **Check:** terraform state list, in each template folder, prints nothing, and gcloud logging sinks list at your scope no longer lists abstract-org-audit-sink.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

20. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

21. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. What you deployed from a template (network, asset, Security Command Center, bucket, billing or archive) comes off with To remove it later in that template's tutorial. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Send logs with Infrastructure Manager

**Fits when:** You want Terraform without running it yourself, with the state kept by Google and every deployment on record.

**Why this way:** Infrastructure Manager deploys the audit-log template from the public templates repository at a release tag, so a later merge never changes what you deployed. Tested on one folder: the preview listed 11 resources to create and none to destroy, the deployment applied as ACTIVE, and Abstract stored the audit logs it sent. docs/gcp/DEPLOY-INFRA-MANAGER.md has every command written out, and the step-by-step page fills in your values.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=2). To send someone this plan, share this link.

**Not chosen:** Several folders or several projects in one deployment: a template makes one sink, at one scope. Use the guided script for those.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository, whichever way you deploy.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before you finish, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose what sends logs. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Script step 1 offers the whole organization, one or more folders (a checkbox list of every folder and subfolder, its path shown), or one or more projects (a checkbox list: numbers or ranges tick and untick, a ticks all shown, n none, f every project in a folder, and any other text searches). With several projects it asks for one organization sink filtered to them, or one sink in each. Whichever way you deploy, this records your scope in the answers file, ~/.abstract-gcp-setup.env. Script step 1 asks its questions, so it is the last line of this block.

   *Note:* Run the script with no options for its menu instead: a runs the guided setup from the start, 1 to 10 one step, p the organization policy review, s what is supported where, i every saved name, ID and account, g checks or grants roles for someone, c checks everything and changes nothing, x cleans up, q quits.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose, and warns that projects created later are not covered until you tick them, if you chose projects.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, each folder, or each project you chose (with one organization sink filtered to projects, the organization). At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here, whatever your scope: the topics, the subscriptions, Abstract's service accounts and the health alerts. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before anything is built.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Check first (optional).** Cloud admin, in Cloud Shell.

   Review the organization policies that can block or change this setup. --policies (menu p) reads the effective policy at the organization, the logging project and every folder or project you chose, and sorts each into BLOCKS (the service-account key constraints), CHECK (restricted services, CMEK-only services, resource locations, allowed member domains, key expiry, Pub/Sub in-transit regions), info (cross-project service accounts, key exposure response, serial-port logging) and RECOMMEND (no audit logging exemptions, no automatic grants to default service accounts, Kubernetes cloud logging). It never changes a policy.

   *Optional:* Recommended in any organization with security policies. It reads and changes nothing, so it is safe to run before anything is built.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --policies
   ```

   **Check:** Every BLOCKS line shows ✓. A ✗ there names the constraint and where it is enforced: ask its owner for an exception on the logging project before you go on. CHECK lines say what to confirm.

   Google documentation: [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints)

6. **Foundation.** Cloud admin, and an Owner of the logging project, in Cloud Shell.

   Check and grant your own roles for Infrastructure Manager: turning on its APIs, creating the service account it runs as, acting as that account, and creating previews and deployments. Replace YOUR_EMAIL with your account. Someone who can set IAM policy on the logging project runs it; anyone else is handed the commands. The logging project needs open billing: Infrastructure Manager runs on Cloud Build, and a project without billing reports the APIs on and enables nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant YOUR_EMAIL --for infra-manager
   ```

   **Check:** Run it again with --check at the end: every required role shows ✓.

   Google documentation: [Access control with IAM](https://docs.cloud.google.com/infrastructure-manager/docs/access-control) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project)

7. **Foundation.** Cloud admin, and someone who can set IAM policy at your scope, in Cloud Shell.

   Create the service account Infrastructure Manager runs as, then grant it its roles. Replace LOGGING_PROJECT_ID with your logging project's ID. The Logs Configuration Writer grant goes on the organization, folder or project of the sink, and is the one that gets missed: without it the apply fails after the topic and subscription already exist. --grant asks before each role.

   ```bash
   gcloud iam service-accounts create infra-manager-abstract --display-name="Infra Manager - Abstract" --project=LOGGING_PROJECT_ID
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant serviceAccount:infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --for infra-manager-sa
   ```

   **Check:** Run the --grant line again with --check at the end: every required role shows ✓.

   Google documentation: [Configure the service account](https://docs.cloud.google.com/infrastructure-manager/docs/configure-service-account) · [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Manage access to service accounts](https://docs.cloud.google.com/iam/docs/manage-access-service-accounts)

8. **Set up.** Cloud admin, in Cloud Shell.

   Write your values in abstract.tfvars, because lists such as log_categories cannot go in --input-values. The commands below are for the organization; for one folder or one project, copy the example of gcp-source-audit-logs-folder or gcp-source-audit-logs-project instead, and use that folder in the preview and apply. Set the organization, folder or project ID and log_project. The repository's .gitignore keeps *.tfvars out of git.

   Templates, one per source:

   - [All Google Cloud audit logs to Abstract: organization sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-organization)
   - [One folder's audit logs to Abstract: folder sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-folder)
   - [One project's audit logs to Abstract: project sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-project)

   ```bash
   cp templates/gcp/gcp-source-audit-logs-organization/terraform.tfvars.example abstract.tfvars
   cloudshell edit abstract.tfvars
   ```

   **Check:** abstract.tfvars names your organization, folder or project ID and your logging project, and no placeholder in capitals is left in it.

   Google documentation: [Deploy infrastructure using Infrastructure Manager](https://docs.cloud.google.com/infrastructure-manager/docs/deploy-resources) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode)

9. **Set up.** Cloud admin, in Cloud Shell.

   Preview: this is terraform plan, run by Infrastructure Manager. List the release tags (the last one is the newest; use it as RELEASE_TAG), then create the preview. Replace LOGGING_PROJECT_ID and INFRA_MANAGER_REGION, a region your organization allows; with a folder or project, change the --git-source-directory to that template's folder. Deploy a release tag, never a branch: a branch deploys whatever was merged since.

   ```bash
   git ls-remote --tags --sort=v:refname https://github.com/IamABS3C/abstract-cloud-templates
   gcloud infra-manager previews create projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-organization --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
   ```

   **Check:** gcloud infra-manager previews describe with the same preview name shows SUCCEEDED.

   Google documentation: [Preview a deployment](https://docs.cloud.google.com/infrastructure-manager/docs/preview-deployment) · [Infrastructure Manager locations](https://docs.cloud.google.com/infrastructure-manager/docs/locations)

10. **Set up.** Cloud admin, in Cloud Shell.

   Export the preview and read it before you apply: the sink at the scope you chose, include_children true at an organization or folder, and the filter you expect, which decides both coverage and bill. Google exports it twice, as a binary plan and as JSON; the JSON reads in any editor.

   ```bash
   gcloud infra-manager previews export projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/previews/abstract-preview --file=abstract-preview
   ```

   **Check:** The plan creates the topic, the subscription, the sink, the sink's publisher grant and Abstract's reader account with Subscriber on the subscription, and destroys nothing.

   Google documentation: [Export and view preview results](https://docs.cloud.google.com/infrastructure-manager/docs/export-view-preview-results)

11. **Set up.** Cloud admin, in Cloud Shell.

   Apply, with the same source and values as the preview, then read the result. The same apply command updates the deployment later. Infrastructure Manager makes no key for Abstract, so make it with gcloud (next card); a key made in Terraform would sit in its state.

   ```bash
   gcloud infra-manager deployments apply projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --service-account=projects/LOGGING_PROJECT_ID/serviceAccounts/infra-manager-abstract@LOGGING_PROJECT_ID.iam.gserviceaccount.com --git-source-repo=https://github.com/IamABS3C/abstract-cloud-templates --git-source-directory=templates/gcp/gcp-source-audit-logs-organization --git-source-ref=RELEASE_TAG --inputs-file=abstract.tfvars
   gcloud infra-manager deployments describe projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --format="yaml(state,stateDetail,errorCode,tfErrors,latestRevision)"
   ```

   **Check:** The state is ACTIVE. FAILED names why in stateDetail, errorCode and tfErrors; a 403 there is a role the service account lacks: run the --for infra-manager-sa line again with --check at the end to name it.

   Google documentation: [Deploy infrastructure using Infrastructure Manager](https://docs.cloud.google.com/infrastructure-manager/docs/deploy-resources) · [gcloud infra-manager deployments apply](https://docs.cloud.google.com/sdk/gcloud/reference/infra-manager/deployments/apply) · [Troubleshoot deployment errors](https://docs.cloud.google.com/infrastructure-manager/docs/troubleshoot-deployments)

12. **Set up.** Cloud admin, in Cloud Shell.

   Make Abstract's key, once, as a file only you can read, outside any repository, and download it if you are in Cloud Shell. Replace LOGGING_PROJECT_ID. This adds one key to the reader account the deployment made; anyone holding the file can read the subscription.

   ```bash
   mkdir -m 700 -p ~/abstract-keys
   (umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-pubsub-key.json --iam-account=abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com --project=LOGGING_PROJECT_ID)
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ```

   **Check:** gcloud prints "created key" for the account, and your browser saves abstract-pubsub-key.json.

   Google documentation: [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

13. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the audit settings are switch 1 of two: this template sets them, and the audit-log template's identity_access and data_access_all categories route the logs (switch 2). The commands below open its tutorial. It keeps its own state, so removing a collector never strips your Data Access audit logging.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you name. Role bindings are untouched. The tutorial saves a copy of the earlier settings first.

   *Optional:* Recommended for identity. The audit-log template already routes the IAM and identity logs; this template makes Google write them, and any Data Access logs you choose (BigQuery, Cloud Storage, Cloud KMS), at your scope. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-foundation-data-access-audit-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** The tutorial's Verify section shows Data Access log types on each service you named, at your scope.

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

14. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* The script's answer defaults to yes. Skip it (answer n) only if you do not use Google Workspace. Workspace sign-in, admin and token logs reach Abstract through its own Google Workspace integration, not through Pub/Sub.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

15. **Set up (optional).** Cloud admin, and the network owner, in Cloud Shell.

   This step uses Terraform, because the guided setup script builds only the audit-log sink, and this is a second sink with its own filter and topic. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block. Each network log is turned on where the resource lives, by its owner: firewall rule logging per rule, DNS query logging per network, VPC Flow Logs per subnet (or for a project or the organization), Cloud NAT logging per gateway, in the project that owns the network (the host project with Shared VPC); docs/gcp/FILTERS.md, Where each source is turned on, has each one. The tutorial checks each one read-only and routes the categories Abstract keeps: firewall, dns_queries, vpc_flows and nat_flows.

   > **This changes:** Adds a log sink, abstract-network-threats-sink, at the scope you set, and a topic, a subscription and a reader account for it in the logging project. It turns no network logging on.

   *Optional:* Skip unless you want firewall, Cloud DNS, VPC Flow or Cloud NAT logs in Abstract. Abstract keeps them only on a GCP Pub/Sub Source configuration of their own that runs the extended GCP Pub/Sub parser (the Abstract card below); load balancer (Cloud Armor) and Cloud IDS records are not kept.

   Template: [Network logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-network-threats-sink --organization=ORG_ID, with your organization's ID (--folder=FOLDER_ID or --project=PROJECT_ID for those scopes), shows a filter naming the categories you chose and the abstract-network-threats topic.

   Google documentation: [VPC firewall rules logging overview](https://docs.cloud.google.com/firewall/docs/vpc-firewall-rules-logging-overview) · [Use logging and monitoring](https://docs.cloud.google.com/dns/docs/monitoring#using_logging) · [VPC Flow Logs](https://docs.cloud.google.com/vpc/docs/flow-logs) · [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

16. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because Cloud Asset Inventory publishes through an organization feed of its own, not a log sink, and the guided setup script builds only the sink. The commands below open the template's tutorial in Cloud Shell's tutorial pane. Feed names are unique in an organization: a second deployment in the same organization sets its own feed_id. The first apply waits 60 seconds for the Cloud Asset Inventory service agent before granting it publisher on the topic, and the feed's first message is a plain-text greeting the extended parser drops.

   > **This changes:** Adds an asset feed, abstract-asset-feed, to your organization, a topic and subscription for it in the logging project, and lets Abstract's existing reader account read that subscription.

   *Optional:* Organization only: the feed is set on the organization. Skip unless you want IAM policy changes with the policy before and after, which Abstract keeps on a configuration of their own that runs the extended GCP Pub/Sub parser (gcp.asset_inventory, action iam_policy_grant, iam_policy_revoke or iam_policy_change).

   Template: [Asset and IAM changes to Abstract: asset feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-asset-and-iam-changes)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-asset-and-iam-changes"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud asset feeds list --organization=ORG_ID, with your organization's ID, lists abstract-asset-feed (or your feed_id) publishing to the abstract-asset-changes topic.

   Google documentation: [Monitor asset changes with Pub/Sub](https://docs.cloud.google.com/asset-inventory/docs/monitor-asset-changes#create_feeds) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

17. **Set up (optional).** Cloud admin, with a Security Command Center admin, in Cloud Shell.

   This step uses Terraform, because Security Command Center publishes through a notification config of its own, not a log sink, and the guided setup script builds only the sink. Whoever applies needs Security Center Notification Configurations Editor (roles/securitycenter.notificationConfigEditor) at the organization. Right after Security Command Center is activated, the create can answer 400 "Precondition check failed" and still create the config: the tutorial lists the configs and imports it into the state.

   > **This changes:** Adds a Security Command Center notification config, abstract-findings, to your organization, a topic and subscription for it in the logging project, and lets Abstract's existing reader account read that subscription.

   *Optional:* Organization only. Needs Security Command Center Standard or Premium active at the organization (tested with Premium); an organization still on legacy Security Command Center gets 400 "Security Command Center Legacy has been permanently disabled". Abstract keeps the findings on a configuration of their own that runs the extended GCP Pub/Sub parser (gcp.scc_findings).

   Template: [Security Command Center findings to Abstract: notification feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-security-command-center-findings)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-security-command-center-findings"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud scc notifications list --organization=ORG_ID --location=global, with your organization's ID, lists abstract-findings.

   Google documentation: [Enable finding notifications for Pub/Sub](https://docs.cloud.google.com/security-command-center/docs/how-to-notifications) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

18. **Verify.** Abstract admin, in Abstract console.

   Add the integration with your logging project's ID, the subscription and the key. Once it saves, delete every copy of the key: rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** Your logging project's ID, where the deployment lives.
   - **Subscription ID:** abstract-audit-logs-sub, unless you renamed it in abstract.tfvars. The short name only.
   - **Credentials:** Upload abstract-pubsub-key.json, the key the card above made.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes, parsed as Cloud Audit Logs, IAM and identity logs included. Connect Abstract within 7 days of the apply: the subscription keeps unread events for 7 days, and older ones are lost.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

19. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

   Google documentation: [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

20. **Verify (optional).** Abstract admin, in Abstract console.

   Add one GCP Pub/Sub Source configuration for each of those subscriptions: one configuration per subscription, never on the audit-log configuration, and no separate integration for findings or assets. Then ask Abstract to apply the extended GCP Pub/Sub parser to each. The managed parser as shipped keeps Cloud Audit Logs only (in a test it stored none of 9,639 network log entries it pulled); the extended parser, a dispatcher with audit, network, asset and Security Command Center sub-parsers in YAML, is not in the managed integration yet, so until it is, Abstract applies it to the configuration's parsers. Each template's tutorial prints its values in its Connect Abstract step.

   *Optional:* Skip unless you deployed the network, asset or Security Command Center template.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** Your logging project's ID, the same as the audit-log configuration's.
   - **Subscription ID:** abstract-network-threats-sub, abstract-asset-changes-sub or abstract-audit-logs-sub-scc, one per configuration.
   - **Credentials:** For the network subscription, abstract-network-key.json, the key of its own reader account (abstract-net-threat-reader), made in its tutorial. For the asset and Security Command Center subscriptions, a key of the audit-log reader account, which the templates let read them.

   **Check:** In Abstract's event search, network logs appear as gcp.vpc_flows, gcp.firewall, gcp.nat_flows and gcp.dns_queries, asset changes as gcp.asset_inventory with action iam_policy_grant, iam_policy_revoke or iam_policy_change, and findings as gcp.scc_findings. Nothing from these subscriptions appears while the configuration runs only the managed parser.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

21. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then delete the deployment's record with --delete-policy=abandon, which leaves every resource in place: the topic, the subscription and the sink carry prevent_destroy, so a plain delete's Terraform destroy is refused. Then remove the resources themselves with the gcloud commands in DEPLOY-INFRA-MANAGER.md, Teardown, or let --teardown find them across your organization and list them before it deletes anything.

   ```bash
   gcloud infra-manager deployments delete projects/LOGGING_PROJECT_ID/locations/INFRA_MANAGER_REGION/deployments/abstract-log-export --delete-policy=abandon
   ```

   **Check:** gcloud infra-manager deployments list --location=INFRA_MANAGER_REGION --project=LOGGING_PROJECT_ID no longer lists abstract-log-export.

   Google documentation: [Deploy infrastructure using Infrastructure Manager](https://docs.cloud.google.com/infrastructure-manager/docs/deploy-resources) · [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks)

22. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

23. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. What you deployed from a template (network, asset, Security Command Center, bucket, billing or archive) comes off with To remove it later in that template's tutorial. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Not covered yet

- The guided setup script builds the audit-log pipeline and Workspace. The other sources use Terraform, and say so, and why, in their first sentence.
- Network logs, Cloud Asset changes and Security Command Center findings are kept only by the extended GCP Pub/Sub parser, which is not in Abstract's managed integration yet: until it is, Abstract applies it to each such configuration's parsers.
