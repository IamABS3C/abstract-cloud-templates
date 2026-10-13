# Set up Google Cloud

<!-- Generated from tools/guides/gcp.yml by `python -m tools.templates generate`. Do not edit. -->

You end up with one log sink (a Cloud Logging rule that copies matching logs as they are written) that sends your Google Cloud audit logs to a Pub/Sub topic in a logging project (one project kept only for this pipeline), a subscription Abstract reads, and a service account that can read only that subscription. Everything runs from Cloud Shell with the guided setup script: it shows what it will do, asks before changing anything, and checks the result. Its ten parts are called script steps 1 to 10 below, to tell them apart from the numbered cards. Each step names the Terraform template that does the same thing, for teams that need infrastructure as code.

Answer the questions below. Each answer leads to the next question or to one plan: the steps in order, from checking what you have to cleaning it all up. The same questions are in the [onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp), which gives each plan a link you can share.

[![Open in Cloud Shell](https://gstatic.com/cloudssh/images/open-btn.svg)](https://shell.cloud.google.com/cloudshell/editor?cloudshell_git_repo=https://github.com/IamABS3C/abstract-cloud-templates&cloudshell_git_branch=main&cloudshell_workspace=tools/gcp-guided-setup&cloudshell_tutorial=WALKTHROUGH.md)

The button opens the guided setup in Cloud Shell, with every step below in a side panel.

## How much of Google Cloud should send logs to Abstract?

The sink's scope decides what is covered. Projects created later inside the scope are included automatically.

- **The whole organization (recommended)** → [Send audit logs from your whole Google Cloud organization](#send-audit-logs-from-your-whole-google-cloud-organization)
  Every project, including ones created later. Needs Logs Configuration Writer on the organization.
- **One folder** → [Send audit logs from one Google Cloud folder](#send-audit-logs-from-one-google-cloud-folder)
  Every project in that folder. Projects outside it are not covered.
- **One project, as a pilot** → [Send audit logs from one Google Cloud project, as a pilot](#send-audit-logs-from-one-google-cloud-project-as-a-pilot)
  Only that project. Good for a first test; switch to the organization later.

## Send audit logs from your whole Google Cloud organization

**Fits when:** You want every project covered, including ones created later.

**Why this way:** One aggregated sink at the organization covers everything by containment, so nothing needs repeating when projects are added.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=0). To send someone this plan, share this link.

**Not chosen:** A folder or project sink: it would miss projects outside it.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before script step 10, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose your scope (the organization, a folder or a project). The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes. Script step 1 asks its questions, so it is the last line of this block.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, folder or project you chose. At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before script step 4 builds anything.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4: create the topic and subscription in the logging project, then the organization sink, and let the sink's writer identity (the Google-managed account the sink publishes as) publish to the topic. That last grant is the step most often missed; without it the sink looks healthy and sends nothing.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to your organization. It copies the Admin Activity, System Event and Policy Denied audit logs of every project, including ones created later, and changes nothing inside those projects. A sink that already sends to the same topic is reused, and its filter is only ever extended.

   Template: [All Google Cloud audit logs to Abstract: organization sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-organization)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=LOGGING_PROJECT_ID (your logging project's ID) lists the sink's writer identity under roles/pubsub.publisher.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)

6. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository. In a temporary Cloud Shell session, download the key as soon as script step 5 makes it, with cloudshell download ~/abstract-keys/abstract-pubsub-key.json, so a session that ends early does not take it with it. Script step 10 prints the same line again.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

7. **Set up (optional).** Cloud admin, in Cloud Shell.

   Script step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. For most services either alone does nothing; BigQuery writes its Data Access logs by default, so it needs only the routing switch. Keep the suggested services: iam.googleapis.com and sts.googleapis.com record identity, and the script routes their events (as iamcredentials.googleapis.com and sts.googleapis.com) for you.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-….json beside your answers file (your home folder).

   *Optional:* Recommended for identity: this is where service account impersonation, token minting and Workload Identity Federation (GitHub Actions, AWS, Azure) are recorded. Also records who read or changed data in BigQuery, Cloud Storage and Cloud KMS. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs for each of them, naming iamcredentials.googleapis.com and sts.googleapis.com).

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)

8. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

9. **Set up (optional).** Cloud admin, in Cloud Shell.

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

10. **Set up (optional).** Cloud admin, in Cloud Shell.

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

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   This step uses Terraform, because the guided script builds only the streaming pipeline, and the archive is a second sink with a bucket (and an optional retention lock) of its own, which the template creates. The commands below open the template's tutorial in Cloud Shell's tutorial pane, one command per block: it copies the streaming sink's filter, keeps the Terraform state in a bucket so it outlives the session, has you fill in terraform.tfvars, and applies only the plan you previewed. Abstract does not read the archive today.

   > **This changes:** Adds a second log sink, abstract-org-audit-sink-archive, to your organization, and a bucket for it.

   *Optional:* Skip unless you need to keep logs as evidence in Cloud Storage; Abstract does not read the archive today. It is not the detection path; files land minutes to hours later.

   Template: [Archive Google Cloud logs to Cloud Storage: second sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-archive-log-bucket)

   ```bash
   cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-archive-log-bucket"
   cloudshell launch-tutorial TUTORIAL.md
   ```

   **Check:** gcloud logging sinks describe abstract-org-audit-sink-archive --organization=ORG_ID, with your organization's ID, points at your bucket, and gcloud storage ls gs://YOUR_BUCKET lists log files within a few hours.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Bucket Lock](https://docs.cloud.google.com/storage/docs/bucket-lock) · [Write tutorials in Cloud Shell](https://docs.cloud.google.com/shell/docs/cloud-shell-tutorials/tutorials)

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

   Script step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)

14. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form, and a cloudshell download line for each file to take with you: the key, your answers file, and the backup of your earlier audit settings if script step 6 changed them. If you ran the setup in Cloud Shell, run those lines, or the ones below, to download the files to the computer you use for Abstract: a session opened from the button is temporary, and the clean-up needs the answers file to know what the setup made. On your own computer the files are already there. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat.

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

   **Check:** Events from this integration appear in Abstract's event search within a few minutes. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4. Connect Abstract within 7 days of script step 4: the subscription keeps unread events for 7 days, and older ones are lost.

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

18. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

19. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Send audit logs from one Google Cloud folder

**Fits when:** Abstract should see one business unit or environment, held in one folder.

**Why this way:** A folder sink covers every project in the folder, including ones created later, without organization-wide rights.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=1). To send someone this plan, share this link.

**Not chosen:** The organization sink: you asked for one folder.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before script step 10, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose your scope (the organization, a folder or a project). The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes. Script step 1 asks its questions, so it is the last line of this block.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, folder or project you chose. At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before script step 4 builds anything.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4, with the folder you chose in script step 1: create the topic and subscription, then the folder sink, and let the sink's writer identity (the Google-managed account the sink publishes as) publish to the topic.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to your folder. It copies the audit logs of every project in the folder, including ones created later, and changes nothing inside those projects.

   Template: [One folder's audit logs to Abstract: folder sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-folder)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=LOGGING_PROJECT_ID (your logging project's ID) lists the sink's writer identity under roles/pubsub.publisher.

   Google documentation: [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks) · [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#dest-auth) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)

6. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository. In a temporary Cloud Shell session, download the key as soon as script step 5 makes it, with cloudshell download ~/abstract-keys/abstract-pubsub-key.json, so a session that ends early does not take it with it. Script step 10 prints the same line again.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

7. **Set up (optional).** Cloud admin, in Cloud Shell.

   Script step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. For most services either alone does nothing; BigQuery writes its Data Access logs by default, so it needs only the routing switch. Keep the suggested services: iam.googleapis.com and sts.googleapis.com record identity, and the script routes their events (as iamcredentials.googleapis.com and sts.googleapis.com) for you.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-….json beside your answers file (your home folder).

   *Optional:* Recommended for identity: this is where service account impersonation, token minting and Workload Identity Federation (GitHub Actions, AWS, Azure) are recorded. Also records who read or changed data in BigQuery, Cloud Storage and Cloud KMS. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs for each of them, naming iamcredentials.googleapis.com and sts.googleapis.com).

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)

8. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

9. **Set up (optional).** Cloud admin, in Cloud Shell.

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

10. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending. Google's backlog page recommends the regional metrics. We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

   Google documentation: [Alerting overview](https://docs.cloud.google.com/monitoring/alerts) · [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

11. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)

12. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form, and a cloudshell download line for each file to take with you: the key, your answers file, and the backup of your earlier audit settings if script step 6 changed them. If you ran the setup in Cloud Shell, run those lines, or the ones below, to download the files to the computer you use for Abstract: a session opened from the button is temporary, and the clean-up needs the answers file to know what the setup made. On your own computer the files are already there. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   ```

   **Check:** Script step 10 prints the Project ID, the Subscription ID and the key file for the Abstract form, a cloudshell download line for each file, and, if --grant added roles for this setup, the command that takes each one back once Abstract shows events.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

13. **Verify.** Cloud admin, in Cloud Shell.

   Download the files script step 10 listed to the computer you use for Abstract, if you ran the setup in Cloud Shell. Each line asks your browser to save one file and changes nothing in Google Cloud; a line whose file does not exist does nothing.

   ```bash
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ls ~/abstract-audit-config-backup-*.json 2>/dev/null && cloudshell download ~/abstract-audit-config-backup-*.json
   ```

   **Check:** Your browser saves abstract-pubsub-key.json and your answers file (.abstract-gcp-setup.env), plus abstract-workspace-key.json if you set up Workspace, and abstract-audit-config-backup-….json if script step 6 changed your audit settings. Keep the answers file and the backup until you have cleaned up.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

14. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4. Connect Abstract within 7 days of script step 4: the subscription keeps unread events for 7 days, and older ones are lost.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

15. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

   Google documentation: [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

16. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

17. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Send audit logs from one Google Cloud project, as a pilot

**Fits when:** You want to try Abstract on one project before covering more.

**Why this way:** The smallest change that proves the whole path. Move to the organization plan when the pilot is done.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=2). To send someone this plan, share this link.

**Not chosen:** The organization sink: it needs organization rights you may not have for a pilot.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell and sign in. The sign-in is the last line on purpose: it waits for you to open a link and paste back a code, so nothing may follow it in the same paste. Every command from here on runs from the top folder of the templates repository.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Google opens a repository that is not its own in a temporary Cloud Shell that starts signed out, so sign in before anything else runs; the guided script also offers to sign in, or switch account, on its first screen. When a temporary session ends, your answers, the key and the backup of your audit settings go with it. If your run may pause before script step 10, open Cloud Shell from the Google Cloud console instead, where your home folder is kept, and run every line, git clone included. Anywhere else, the clone line fetches the repository; without it the scripts are not found ("no such file or directory").

   ```bash
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   gcloud auth login --update-adc
   ```

   **Check:** gcloud prints "You are now logged in as" and your account. If it shows another account, run the sign-in line again and choose the right one in the browser.

   Google documentation: [Open in Cloud Shell](https://docs.cloud.google.com/shell/docs/open-in-cloud-shell#required_url_parameter) · [Use Cloud Shell](https://docs.cloud.google.com/shell/docs/using-cloud-shell#choose_ephemeral_mode) · [gcloud auth login](https://docs.cloud.google.com/sdk/gcloud/reference/auth/login)

2. **Check first.** Cloud admin, in Cloud Shell.

   Take stock of what you already have, then script step 1: confirm who you are signed in as and choose your scope (the organization, a folder or a project). The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes. Script step 1 asks its questions, so it is the last line of this block.

   ```bash
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one. Script step 1 shows a ✓ for your account, your organization and the scope you chose.

   Google documentation: [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations) · [Aggregated sinks overview](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks_overview)

3. **Check first.** Cloud admin, in Cloud Shell.

   Script step 2: check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) at your scope: the organization, folder or project you chose. At the organization, Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation, or its managed successor iam.managed.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen. Missing a role? The guided script lists every role it needs, what each is for and whether it is required, with --grant and the email of the person who runs the setup (add --check to see which they hold, changing nothing); run without --check by someone who can set IAM policy at your scope, it grants them one binding at a time and records each, so the clean-up can list the command that takes it back.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

   Google documentation: [Cloud Logging roles and permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/logging#logging.configWriter) · [Access control with IAM](https://docs.cloud.google.com/logging/docs/access-control) · [Method: organizations.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/organizations/testIamPermissions) · [Method: folders.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/folders/testIamPermissions) · [Method: projects.testIamPermissions](https://docs.cloud.google.com/resource-manager/reference/rest/v3/projects/testIamPermissions) · [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access#grant-single-role)

4. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before script step 4 builds anything.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation or iam.managed.disableServiceAccountKeyCreation means: ask for an exception on this project, on whichever of the two the script marks ✗ (an exception on one does not lift the other), before you go on.

   Google documentation: [Create projects](https://docs.cloud.google.com/resource-manager/docs/creating-managing-projects) · [Enable and disable services](https://docs.cloud.google.com/service-usage/docs/enable-disable#enabling) · [Enable, disable, or change billing for a project](https://docs.cloud.google.com/billing/docs/how-to/modify-project#enable_billing_for_an_existing_project) · [Restrict IAM service account usage](https://docs.cloud.google.com/organization-policy/restrict-service-accounts#boolean_constraints) · [Organization policy constraints](https://docs.cloud.google.com/organization-policy/reference/org-policy-constraints)

5. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4, with the project you chose in script step 1: create the topic and subscription, then the project sink, and let the sink's writer identity (the Google-managed account the sink publishes as) publish to the topic.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to the project you chose. It copies that project's audit logs and changes nothing else in it.

   Template: [One project's audit logs to Abstract: project sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=LOGGING_PROJECT_ID (your logging project's ID) lists the sink's writer identity under roles/pubsub.publisher.

   Google documentation: [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#creating_sink) · [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic) · [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)

6. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository. In a temporary Cloud Shell session, download the key as soon as script step 5 makes it, with cloudshell download ~/abstract-keys/abstract-pubsub-key.json, so a session that ends early does not take it with it. Script step 10 prints the same line again.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating) · [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

7. **Set up (optional).** Cloud admin, in Cloud Shell.

   Script step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. For most services either alone does nothing; BigQuery writes its Data Access logs by default, so it needs only the routing switch. Keep the suggested services: iam.googleapis.com and sts.googleapis.com record identity, and the script routes their events (as iamcredentials.googleapis.com and sts.googleapis.com) for you.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-….json beside your answers file (your home folder).

   *Optional:* Recommended for identity: this is where service account impersonation, token minting and Workload Identity Federation (GitHub Actions, AWS, Azure) are recorded. Also records who read or changed data in BigQuery, Cloud Storage and Cloud KMS. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs for each of them, naming iamcredentials.googleapis.com and sts.googleapis.com).

   Google documentation: [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types) · [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds) · [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)

8. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the one read-only scope the script prints (admin.reports.audit.readonly).

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the one read-only Reports scope (admin.reports.audit.readonly) only, until a super admin removes the entry.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again with --check at the end until it does. Check before you upload or delete the key: the check signs in with the key file.

   Google documentation: [Create service accounts](https://docs.cloud.google.com/iam/docs/service-accounts-create#creating) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes)

9. **Set up (optional).** Cloud admin, in Cloud Shell.

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

10. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending. Google's backlog page recommends the regional metrics. We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

   Google documentation: [Alerting overview](https://docs.cloud.google.com/monitoring/alerts) · [Create metric-threshold alerting policies](https://docs.cloud.google.com/monitoring/alerts/using-alerting-ui) · [Monitor Pub/Sub in Cloud Monitoring](https://docs.cloud.google.com/pubsub/docs/monitoring#monitoring_the_backlog). We alert on the global oldest_unacked_message_age anyway: measured on a live subscription it reported every minute, while the regional metric wrote 8 points in 24 hours (docs/public/gcp/TROUBLESHOOTING.md, the backlog check).

11. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Pull subscriptions](https://docs.cloud.google.com/pubsub/docs/pull) · [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)

12. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form, and a cloudshell download line for each file to take with you: the key, your answers file, and the backup of your earlier audit settings if script step 6 changed them. If you ran the setup in Cloud Shell, run those lines, or the ones below, to download the files to the computer you use for Abstract: a session opened from the button is temporary, and the clean-up needs the answers file to know what the setup made. On your own computer the files are already there. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   ```

   **Check:** Script step 10 prints the Project ID, the Subscription ID and the key file for the Abstract form, a cloudshell download line for each file, and, if --grant added roles for this setup, the command that takes each one back once Abstract shows events.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

13. **Verify.** Cloud admin, in Cloud Shell.

   Download the files script step 10 listed to the computer you use for Abstract, if you ran the setup in Cloud Shell. Each line asks your browser to save one file and changes nothing in Google Cloud; a line whose file does not exist does nothing.

   ```bash
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ls ~/abstract-audit-config-backup-*.json 2>/dev/null && cloudshell download ~/abstract-audit-config-backup-*.json
   ```

   **Check:** Your browser saves abstract-pubsub-key.json and your answers file (.abstract-gcp-setup.env), plus abstract-workspace-key.json if you set up Workspace, and abstract-audit-config-backup-….json if script step 6 changed your audit settings. Keep the answers file and the backup until you have cleaned up.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

14. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4. Connect Abstract within 7 days of script step 4: the subscription keeps unread events for 7 days, and older ones are lost.

   Google documentation: [View logs routed to Pub/Sub](https://docs.cloud.google.com/logging/docs/export/pubsub) · [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

15. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

   Google documentation: [Choose Reports API scopes](https://developers.google.com/workspace/admin/reports/auth#scopes) · [Best practices for managing service account keys](https://docs.cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys)

16. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then list what the clean-up would remove; this deletes nothing. It reads your answers file, ~/.abstract-gcp-setup.env. In the session where you ran the setup it is already there. In a new Cloud Shell session, upload the copy you downloaded (More, then Upload); if it is saved under another name, put that path after --state. The clean-up removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project LOGGING_PROJECT_ID lists what carries the setup's names and deletes nothing.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
   ```

   **Check:** One line per item, marked would remove, kept or by hand, in the logging project you expect. If a name is not one this setup made, stop: the answers file is the wrong one.

   Google documentation: [Manage files with Cloud Shell](https://docs.cloud.google.com/shell/docs/uploading-and-downloading-files)

17. **Clean up.** Cloud admin, in Cloud Shell.

   When the list is right, remove it. Anything that existed before you started, such as Data Access audit settings, is listed by hand with the command to change it, never removed. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry. To start again from scratch instead, --teardown lists everything the setup and the templates make across your organization, whatever the answers file recorded, and deletes it only with --teardown --confirm, after you type the organization ID; projects and Terraform state are listed with their commands, never deleted.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
   ```

   **Check:** Every item shows as removed, kept or by hand; act on each by-hand line. Then --remove --project LOGGING_PROJECT_ID (your logging project's ID) finds nothing that carries the setup's names, except what you chose to keep.

   Google documentation: [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects) · [Create access credentials](https://developers.google.com/workspace/guides/create-credentials#set-up-domain-wide-delegation) · [Create and delete service account keys](https://docs.cloud.google.com/iam/docs/keys-create-delete#creating)

## Not collected by Abstract yet

Abstract does not keep these records today, so deploying one of these templates costs money in the cloud and adds nothing in Abstract.

- [Firewall, DNS and IDS logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs): A second sink for firewall, Cloud DNS, load balancer (Cloud Armor) and Cloud IDS logs. Abstract's Google Cloud integration keeps only Cloud Audit Logs, and these are not, so it discards them. Each of these sources is also switched on at its own source, by the team that owns it; whether that is per project, per network or for the whole organization is in docs/gcp/FILTERS.md, Where each source is turned on.
- [Security Command Center findings to Abstract: notification feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-security-command-center-findings): Security Command Center findings, through a notification config to their own topic. Abstract's Google Cloud integration keeps only Cloud Audit Logs, which SCC findings are not.
- [Asset and IAM changes to Abstract: asset feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-asset-and-iam-changes): Resource and IAM-policy changes, from an organization asset feed to their own topic. Abstract's Google Cloud integration keeps only Cloud Audit Logs, which these change records are not.

## Not covered yet

- The guided setup script covers the core pipeline. The optional sources that use Terraform say so, and why, in their first sentence.
