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

   Open the guided setup in Cloud Shell, sign in, and take stock of what you already have. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes. Every command from here on runs from the top folder of the templates repository.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Anywhere else, the clone line fetches it; without it the scripts are not found ("no such file or directory").

   ```bash
   gcloud auth login
   gcloud auth application-default login
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one.

2. **Check first.** Cloud admin, in Cloud Shell.

   Script steps 1 and 2: confirm who you are signed in as, choose your scope, and check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) on the organization or folder; Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

3. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before script step 4 builds anything.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation means: ask for an exception on this project before you go on.

4. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4: create the topic and subscription in the logging project, then the organization sink, and let the sink's writer identity (the Google-managed account the sink publishes as) publish to the topic. That last grant is the step most often missed; without it the sink looks healthy and sends nothing.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to your organization. It copies the Admin Activity, System Event and Policy audit logs of every project, including ones created later, and changes nothing inside those projects. A sink that already sends to the same topic is reused, and its filter is only ever extended.

   Template: [All Google Cloud audit logs to Abstract: organization sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-organization)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=&lt;logging-project-id> lists the sink's writer identity under roles/pubsub.publisher.

5. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository, and leaves Cloud Shell in script step 10.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys.

6. **Set up (optional).** Cloud admin, in Cloud Shell.

   Script step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. Either alone does nothing.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-*.json.

   *Optional:* Skip unless you need to know who read or changed data in BigQuery, Cloud Storage or Cloud KMS. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs).

7. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the two read-only scopes the script prints.

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the two read-only Reports scopes only, until a super admin removes the entry.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again until it does.

8. **Set up (optional).** Cloud admin, in Cloud Shell.

   Send Security Command Center findings to their own topic and subscription. Open the template's Cloud Shell tutorial and follow it. Abstract collects these findings but does not store them yet: the GCP Pub/Sub Source parser keeps only Cloud Audit Log records, and a findings parser is pending. Ask Abstract before you count on findings in search or detections.

   > **This changes:** Adds a Security Command Center notification config, abstract-findings, to your organization.

   *Optional:* Skip unless you have Security Command Center (Premium or Enterprise).

   Template: [Security Command Center findings to Abstract: notification feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-security-command-center-findings)

   **Check:** gcloud scc notifications list --organization=&lt;org-id> shows abstract-findings, and gcloud pubsub subscriptions describe abstract-audit-logs-sub-scc --project=&lt;logging-project-id> finds the subscription.

9. **Set up (optional).** Cloud admin, in Cloud Shell.

   Send asset and IAM policy changes from an organization asset feed to their own topic. Open the template's Cloud Shell tutorial and follow it. Abstract stores them only through their own GCP Pub/Sub Source integration, on abstract-asset-changes-sub, with the template's parsers/cloud-asset-inventory.yml attached; the managed parser keeps only Cloud Audit Log records. Never attach that parser to the audit-log integration: it would replace the managed one there.

   > **This changes:** Adds a Cloud Asset Inventory feed, abstract-asset-feed, to your organization.

   *Optional:* Skip unless you want a record of every IAM policy and resource change across the organization.

   Template: [Asset and IAM changes to Abstract: asset feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-asset-and-iam-changes)

   **Check:** gcloud asset feeds list --organization=&lt;org-id> shows abstract-asset-feed, and gcloud pubsub subscriptions describe abstract-asset-changes-sub --project=&lt;logging-project-id> finds the subscription.

10. **Set up (optional).** Cloud admin, in Cloud Shell.

   Notify a topic for each new object in that bucket, so Abstract fetches it. Open the template's Cloud Shell tutorial and follow it. Abstract stores the objects' content only once a parser for their format is attached to this subscription's own integration; the managed GCP Pub/Sub Source parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product.

   > **This changes:** Adds a Pub/Sub notification to each bucket you name, and lets Abstract's reader account read their objects.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

   **Check:** gcloud storage buckets notifications list gs://&lt;your-bucket> shows a notification on the topic abstract-gcs-notifications.

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a filtered sink for network threat logs. Open the template's Cloud Shell tutorial and follow it. Abstract does not store these logs yet: the managed parser keeps only Cloud Audit Log records, and a parser for them is being built. Ask Abstract before you count on them in search or detections.

   > **This changes:** Adds a second log sink, abstract-network-threats-sink, to your organization.

   *Optional:* Skip unless you want firewall, Cloud DNS, load balancer and Cloud IDS logs. Each one must also be switched on at its source.

   Template: [Firewall, DNS and IDS logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

   **Check:** gcloud logging sinks describe abstract-network-threats-sink --organization=&lt;org-id> shows the sink and its Pub/Sub destination.

12. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a sink on the billing account. Open the template's Cloud Shell tutorial and follow it.

   > **This changes:** Adds a log sink, abstract-billing-audit-sink, to the billing account.

   *Optional:* Skip unless you want billing account audit logs. A billing account sits outside the organization, so it needs its own sink.

   Template: [Billing account audit logs to Abstract: billing sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-billing-account-logs)

   **Check:** gcloud logging sinks describe abstract-billing-audit-sink --billing-account=&lt;billing-account-id> shows the sink and its Pub/Sub destination.

13. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a second sink that writes the same logs to a Cloud Storage bucket. Open the template's Cloud Shell tutorial and follow it.

   > **This changes:** Adds a second log sink, abstract-org-audit-sink-archive, to your organization, and a bucket for it.

   *Optional:* Skip unless you need to keep logs for evidence or backfill. It is not the detection path; files land minutes to hours later.

   Template: [Archive Google Cloud logs to Cloud Storage: second sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-archive-log-bucket)

   **Check:** gcloud logging sinks describe abstract-org-audit-sink-archive --organization=&lt;org-id> points at your bucket, and gcloud storage ls gs://&lt;your-bucket> lists log files within a few hours.

14. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending.

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

15. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

16. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form and the commands below. The key files exist only in this Cloud Shell session, which is temporary, so download them to the computer you use for Abstract, with your answers file: the clean-up needs it to know what the setup made. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ```

   **Check:** Your browser saves abstract-pubsub-key.json, .abstract-gcp-setup.env (a hidden file on macOS and Linux), and abstract-workspace-key.json if you set up Workspace.

17. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4.

18. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

19. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then run the clean-up mode with the answers file you downloaded (upload it to Cloud Shell first). Without --confirm it only lists, by name, what it would delete. It removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project &lt;logging-project-id> lists what carries the setup's names and deletes nothing. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
   ```

   **Check:** Every item shows as removed, and --remove --project &lt;logging-project-id> then finds nothing that carries the setup's names.

## Send audit logs from one Google Cloud folder

**Fits when:** Abstract should see one business unit or environment, held in one folder.

**Why this way:** A folder sink covers every project in the folder, including ones created later, without organization-wide rights.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=1). To send someone this plan, share this link.

**Not chosen:** The organization sink: you asked for one folder.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell, sign in, and take stock of what you already have. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes. Every command from here on runs from the top folder of the templates repository.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Anywhere else, the clone line fetches it; without it the scripts are not found ("no such file or directory").

   ```bash
   gcloud auth login
   gcloud auth application-default login
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one.

2. **Check first.** Cloud admin, in Cloud Shell.

   Script steps 1 and 2: confirm who you are signed in as, choose your scope, and check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) on the organization or folder; Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

3. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before script step 4 builds anything.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation means: ask for an exception on this project before you go on.

4. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4, with the folder you chose in script step 1: create the topic and subscription, then the folder sink, and let the sink's writer identity (the Google-managed account the sink publishes as) publish to the topic.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to your folder. It copies the audit logs of every project in the folder, including ones created later, and changes nothing inside those projects.

   Template: [One folder's audit logs to Abstract: folder sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-folder)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=&lt;logging-project-id> lists the sink's writer identity under roles/pubsub.publisher.

5. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository, and leaves Cloud Shell in script step 10.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys.

6. **Set up (optional).** Cloud admin, in Cloud Shell.

   Script step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. Either alone does nothing.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-*.json.

   *Optional:* Skip unless you need to know who read or changed data in BigQuery, Cloud Storage or Cloud KMS. It adds volume and cost.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs).

7. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the two read-only scopes the script prints.

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the two read-only Reports scopes only, until a super admin removes the entry.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again until it does.

8. **Set up (optional).** Cloud admin, in Cloud Shell.

   Notify a topic for each new object in that bucket, so Abstract fetches it. Open the template's Cloud Shell tutorial and follow it. Abstract stores the objects' content only once a parser for their format is attached to this subscription's own integration; the managed GCP Pub/Sub Source parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product.

   > **This changes:** Adds a Pub/Sub notification to each bucket you name, and lets Abstract's reader account read their objects.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

   **Check:** gcloud storage buckets notifications list gs://&lt;your-bucket> shows a notification on the topic abstract-gcs-notifications.

9. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending.

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

10. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

11. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form and the commands below. The key files exist only in this Cloud Shell session, which is temporary, so download them to the computer you use for Abstract, with your answers file: the clean-up needs it to know what the setup made. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ```

   **Check:** Your browser saves abstract-pubsub-key.json, .abstract-gcp-setup.env (a hidden file on macOS and Linux), and abstract-workspace-key.json if you set up Workspace.

12. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4.

13. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

14. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then run the clean-up mode with the answers file you downloaded (upload it to Cloud Shell first). Without --confirm it only lists, by name, what it would delete. It removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project &lt;logging-project-id> lists what carries the setup's names and deletes nothing. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
   ```

   **Check:** Every item shows as removed, and --remove --project &lt;logging-project-id> then finds nothing that carries the setup's names.

## Send audit logs from one Google Cloud project, as a pilot

**Fits when:** You want to try Abstract on one project before covering more.

**Why this way:** The smallest change that proves the whole path. Move to the organization plan when the pilot is done.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=2). To send someone this plan, share this link.

**Not chosen:** The organization sink: it needs organization rights you may not have for a pilot.

1. **Check first.** Cloud admin, in Cloud Shell, or any terminal with gcloud.

   Open the guided setup in Cloud Shell, sign in, and take stock of what you already have. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes. Every command from here on runs from the top folder of the templates repository.

   *Note:* Opened Cloud Shell from the button? You are already in the repository: skip the git clone line, and the next line moves you to its top folder (the button opens in tools/gcp-guided-setup). Anywhere else, the clone line fetches it; without it the scripts are not found ("no such file or directory").

   ```bash
   gcloud auth login
   gcloud auth application-default login
   git clone https://github.com/IamABS3C/abstract-cloud-templates && cd abstract-cloud-templates
   cd "$(git rev-parse --show-toplevel)"
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ```

   **Check:** The audit prints your organization and lists the log sinks set on it. If one already sends audit logs to a topic, tell whoever owns it before you add a second. Sinks on a folder or a project are listed by script step 4, at your scope, before it adds one.

2. **Check first.** Cloud admin, in Cloud Shell.

   Script steps 1 and 2: confirm who you are signed in as, choose your scope, and check you hold the rights the sink needs before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) on the organization or folder; Organization Admin does not include it. Your rights in the logging project, and the organization policy that can block the service-account key (iam.disableServiceAccountKeyCreation), are checked in script step 3, once that project is chosen.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Script step 2 shows a ✓ for creating the log sink at your scope. A ✗ names the role you lack and the command an admin runs to grant it. A ! saying the logging project is not checked yet is expected the first time.

3. **Foundation.** Cloud admin, in Cloud Shell.

   Script step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here. The script then checks your rights in the project and whether an organization policy blocks the service-account key, before script step 4 builds anything.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** Script step 3 shows a ✓ for the active project, the Pub/Sub, Logging, IAM and Resource Manager APIs, building the pipeline in the project, and "service-account keys are allowed". A ✗ on iam.disableServiceAccountKeyCreation means: ask for an exception on this project before you go on.

4. **Set up.** Cloud admin, in Cloud Shell.

   Script step 4, with the project you chose in script step 1: create the topic and subscription, then the project sink, and let the sink's writer identity (the Google-managed account the sink publishes as) publish to the topic.

   > **This changes:** Adds a log sink, abstract-org-audit-sink, to the project you chose. It copies that project's audit logs and changes nothing else in it.

   Template: [One project's audit logs to Abstract: project sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** Script step 4 shows a ✓ for the sink sending to the topic, covering child projects (not shown for a project sink), and "the sink's own identity can publish". To see the grant yourself, gcloud pubsub topics get-iam-policy abstract-audit-logs --project=&lt;logging-project-id> lists the sink's writer identity under roles/pubsub.publisher.

5. **Set up.** Cloud admin, in Cloud Shell.

   Script step 5: create the service account Abstract signs in as. It can read only the one subscription. Its key is written to ~/abstract-keys, outside any repository, and leaves Cloud Shell in script step 10.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** Script step 5 shows a ✓ for the account, for reading abstract-audit-logs-sub, for "no project-wide roles", and for a key file in ~/abstract-keys.

6. **Set up (optional).** Cloud admin, in Cloud Shell.

   Script step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. Either alone does nothing.

   > **This changes:** Changes the audit settings (auditConfigs) at your organization, folder or project, so Google writes Data Access logs for the services you choose, and extends the sink's filter. Role bindings are untouched. A copy of the earlier settings is saved first, as abstract-audit-config-backup-*.json.

   *Optional:* Skip unless you need to know who read or changed data in BigQuery, Cloud Storage or Cloud KMS. It adds volume and cost.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Script step 6 shows a ✓ for switch 1 (Data Access is generated for each service you chose) and for switch 2 (the sink routes Data Access logs).

7. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Script step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the two read-only scopes the script prints.

   > **This changes:** Domain-wide delegation lets the new service account read your Workspace audit reports as the admin you name, for the two read-only Reports scopes only, until a super admin removes the entry.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** Script step 7 shows a ✓ "delegation works: the Reports API answered as" your admin. The delegation can take a few minutes after the super admin saves it; run script step 7 again until it does.

8. **Set up (optional).** Cloud admin, in Cloud Shell.

   Notify a topic for each new object in that bucket, so Abstract fetches it. Open the template's Cloud Shell tutorial and follow it. Abstract stores the objects' content only once a parser for their format is attached to this subscription's own integration; the managed GCP Pub/Sub Source parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product.

   > **This changes:** Adds a Pub/Sub notification to each bucket you name, and lets Abstract's reader account read their objects.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

   **Check:** gcloud storage buckets notifications list gs://&lt;your-bucket> shows a notification on the topic abstract-gcs-notifications.

9. **Verify (optional).** Cloud admin, in Cloud Shell.

   Script step 8 creates three alerts and an email channel in the logging project, so you hear when the pipeline stops sending.

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Script step 8 shows a ✓ for 3 Abstract alert policies. In the Google Cloud console, Monitoring, then Alerting, lists three "Abstract log pipeline" policies that send to your email.

10. **Verify.** Cloud admin, in Cloud Shell.

   Script step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** Script step 9 shows a ✓ "the test event arrived on abstract-audit-logs", usually within five minutes. If not, it prints the command that reads the sink's errors.

11. **Verify.** Cloud admin, in Cloud Shell.

   Script step 10 prints the values for the Abstract form and the commands below. The key files exist only in this Cloud Shell session, which is temporary, so download them to the computer you use for Abstract, with your answers file: the clean-up needs it to know what the setup made. If someone else fills in the Abstract form, hand the key over through your password manager or secret-sharing tool, never by email or chat.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   cloudshell download ~/abstract-keys/abstract-pubsub-key.json
   ls ~/abstract-keys/abstract-workspace-key.json 2>/dev/null && cloudshell download ~/abstract-keys/abstract-workspace-key.json
   cloudshell download ~/.abstract-gcp-setup.env
   ```

   **Check:** Your browser saves abstract-pubsub-key.json, .abstract-gcp-setup.env (a hidden file on macOS and Linux), and abstract-workspace-key.json if you set up Workspace.

12. **Verify.** Abstract admin, in Abstract console.

   Add the integration with the values script step 10 printed. Once it saves, delete every copy of the key: the Cloud admin runs rm -f ~/abstract-keys/abstract-pubsub-key.json in Cloud Shell, and you delete the downloaded file.

   In Abstract, add the **GCP Pub/Sub Source** integration and fill in:

   - **Project ID:** The logging project ID script step 10 prints. It is the project that holds the subscription, not the projects the logs come from.
   - **Subscription ID:** abstract-audit-logs-sub, the short name only, not projects/…/subscriptions/…
   - **Credentials:** Upload abstract-pubsub-key.json, the key you downloaded.

   **Check:** Events from this integration appear in Abstract's event search within a few minutes. They include the test events script step 9 wrote (abstract-probe-…), which waited on the subscription with everything else sent since script step 4.

13. **Verify (optional).** Abstract admin, in Abstract console.

   Add the Workspace integration with the values script step 10 printed. Once it saves, delete every copy of the Workspace key: rm -f ~/abstract-keys/abstract-workspace-key.json in Cloud Shell, and the downloaded file.

   *Optional:* Skip unless you set up Google Workspace in script step 7.

   In Abstract, add the **Google Workspace Audit Log Integration** and fill in:

   - **Admin Email:** The Workspace admin email you gave script step 7.
   - **Credentials:** Upload abstract-workspace-key.json, the key you downloaded.
   - **Application Name:** Every application is selected by default. To start small, keep Login, Admin, Token, SAML, User Accounts and Groups.

   **Check:** Google Workspace login events appear in Abstract's event search. Google publishes some Workspace reports hours late, so allow a few hours before deciding it failed.

14. **Clean up.** Cloud admin, in Cloud Shell.

   Delete the integrations in Abstract first, so they stop reading. Then run the clean-up mode with the answers file you downloaded (upload it to Cloud Shell first). Without --confirm it only lists, by name, what it would delete. It removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project &lt;logging-project-id> lists what carries the setup's names and deletes nothing. If you set up Workspace, a Workspace super admin also removes its domain-wide delegation entry.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
   ```

   **Check:** Every item shows as removed, and --remove --project &lt;logging-project-id> then finds nothing that carries the setup's names.

## Not covered yet

- The guided setup script covers the core pipeline. The optional sources run from their own Cloud Shell tutorials (Terraform).
- The Terraform template for Data Access logs sets them at the organization only. On a folder or project plan, script step 6 sets them at your scope.
- Security Command Center findings and network threat logs are collected but not stored until Abstract ships parsers for them.
