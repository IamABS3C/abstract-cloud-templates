# Set up Google Cloud

<!-- Generated from tools/guides/gcp.yml by `python -m tools.templates generate`. Do not edit. -->

You end up with one log sink that copies your Google Cloud audit logs to a Pub/Sub topic in a logging project, a subscription Abstract reads, and a service account that can read only that subscription. Everything runs from Cloud Shell with the guided setup script: it shows what it will do, asks before changing anything, and checks the result. Each step names the Terraform template that does the same thing, for teams that need infrastructure as code.

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

1. **Check first.** Cloud admin, in Cloud Shell.

   Open the guided setup in Cloud Shell, sign in, and take stock of what you already have. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes.

   ```bash
   gcloud auth login
   gcloud auth application-default login
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ```

   **Check:** The audit prints your organization and lists any sinks that already export logs.

2. **Check first.** Cloud admin, in Cloud Shell.

   Steps 1 and 2 of the guided setup: confirm who you are signed in as, choose your scope, and check you hold every permission before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) on the organization or folder; Organization Admin does not include it.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Every permission row is green, or you know who to ask.

3. **Foundation.** Cloud admin, in Cloud Shell.

   Step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** The project is active and the Pub/Sub, Logging, IAM and Resource Manager APIs are on.

4. **Set up.** Cloud admin, in Cloud Shell.

   Step 4: create the topic and subscription in the logging project, then the organization sink, and let the sink's identity publish to the topic. That last grant is the step most often missed; without it the sink looks healthy and sends nothing.

   Template: [All Google Cloud audit logs to Abstract: organization sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-organization)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** The sink includes child projects, points at the topic, and its identity can publish.

5. **Set up.** Cloud admin, in Cloud Shell.

   Step 5: create the service account Abstract signs in as. It can read only the one subscription. The key is written to ~/abstract-keys, outside any repository.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** The account exists, can read the subscription, and holds no project-wide role.

6. **Set up (optional).** Cloud admin, in Cloud Shell.

   Step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. Either alone does nothing.

   *Optional:* Skip unless you need to know who read or changed data in BigQuery, Cloud Storage or Cloud KMS. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Both switches report on for each service you chose.

7. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the two read-only scopes the script prints.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** The script reads one page from the Reports API as the new account.

8. **Set up (optional).** Cloud admin, in Cloud Shell.

   Send Security Command Center findings to their own topic and subscription. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you have Security Command Center (Premium or Enterprise) and want its findings in Abstract.

   Template: [Security Command Center findings to Abstract: notification feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-security-command-center-findings)

9. **Set up (optional).** Cloud admin, in Cloud Shell.

   Send asset and IAM policy changes from an organization asset feed to their own topic. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want a record of every IAM policy and resource change across the organization.

   Template: [Asset and IAM changes to Abstract: asset feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-asset-and-iam-changes)

10. **Set up (optional).** Cloud admin, in Cloud Shell.

   Notify a topic for each new object in that bucket, so Abstract fetches it. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a filtered sink for network threat logs. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want firewall, Cloud DNS, load balancer and Cloud IDS logs. Each one must also be switched on at its source.

   Template: [Firewall, DNS and IDS logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

12. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a sink on the billing account. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want billing account audit logs. A billing account sits outside the organization, so it needs its own sink.

   Template: [Billing account audit logs to Abstract: billing sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-billing-account-logs)

13. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a second sink that writes the same logs to a Cloud Storage bucket. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you need to keep logs for evidence or backfill. It is not the detection path; files land minutes to hours later.

   Template: [Archive Google Cloud logs to Cloud Storage: second sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-archive-log-bucket)

14. **Verify (optional).** Cloud admin, in Cloud Shell.

   Step 8 creates three alerts and an email channel, so you hear when the pipeline stops sending.

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Three "Abstract log pipeline" alert policies exist, sending to your email.

15. **Verify.** Cloud admin, in Cloud Shell.

   Step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** The probe event arrives, usually within five minutes.

16. **Verify.** Abstract admin, in Abstract console.

   Step 10 prints the exact values. In Abstract, add the Google Cloud Pub/Sub integration with the project that holds the subscription (not the projects the logs come from), the subscription's short name, and the key file. Then delete the key file from Cloud Shell. If you set up Workspace, add the Google Workspace integration the same way. Last, download your answers: the Cloud Shell session is temporary, and the clean-up needs them to know what the setup made.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   cloudshell download ~/.abstract-gcp-setup.env
   ```

   **Check:** Events appear in Abstract under vendor GCP within a few minutes. Re-check the cloud side any time with --check.

17. **Clean up.** Cloud admin, in Cloud Shell.

   To remove the setup, run the clean-up mode with the answers file you downloaded (upload it to Cloud Shell first). Without --confirm it only lists, by name, what it would delete. It removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project <logging-project-id> lists what carries the setup's names and deletes nothing. Delete the integration in Abstract first, so it stops reading.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
   ```

   **Check:** Every item shows as removed, and --remove --project <logging-project-id> then finds nothing that carries the setup's names.

## Send audit logs from one Google Cloud folder

**Fits when:** Abstract should see one business unit or environment, held in one folder.

**Why this way:** A folder sink covers every project in the folder, including ones created later, without organization-wide rights.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=1). To send someone this plan, share this link.

**Not chosen:** The organization sink: you asked for one folder.

1. **Check first.** Cloud admin, in Cloud Shell.

   Open the guided setup in Cloud Shell, sign in, and take stock of what you already have. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes.

   ```bash
   gcloud auth login
   gcloud auth application-default login
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ```

   **Check:** The audit prints your organization and lists any sinks that already export logs.

2. **Check first.** Cloud admin, in Cloud Shell.

   Steps 1 and 2 of the guided setup: confirm who you are signed in as, choose your scope, and check you hold every permission before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) on the organization or folder; Organization Admin does not include it.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Every permission row is green, or you know who to ask.

3. **Foundation.** Cloud admin, in Cloud Shell.

   Step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** The project is active and the Pub/Sub, Logging, IAM and Resource Manager APIs are on.

4. **Set up.** Cloud admin, in Cloud Shell.

   Step 4, with the folder you chose in step 1: create the topic and subscription, then the folder sink, and let the sink's identity publish to the topic.

   Template: [One folder's audit logs to Abstract: folder sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-folder)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** The sink includes child projects, points at the topic, and its identity can publish.

5. **Set up.** Cloud admin, in Cloud Shell.

   Step 5: create the service account Abstract signs in as. It can read only the one subscription. The key is written to ~/abstract-keys, outside any repository.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** The account exists, can read the subscription, and holds no project-wide role.

6. **Set up (optional).** Cloud admin, in Cloud Shell.

   Step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. Either alone does nothing.

   *Optional:* Skip unless you need to know who read or changed data in BigQuery, Cloud Storage or Cloud KMS. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Both switches report on for each service you chose.

7. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the two read-only scopes the script prints.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** The script reads one page from the Reports API as the new account.

8. **Set up (optional).** Cloud admin, in Cloud Shell.

   Send Security Command Center findings to their own topic and subscription. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you have Security Command Center (Premium or Enterprise) and want its findings in Abstract.

   Template: [Security Command Center findings to Abstract: notification feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-security-command-center-findings)

9. **Set up (optional).** Cloud admin, in Cloud Shell.

   Send asset and IAM policy changes from an organization asset feed to their own topic. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want a record of every IAM policy and resource change across the organization.

   Template: [Asset and IAM changes to Abstract: asset feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-asset-and-iam-changes)

10. **Set up (optional).** Cloud admin, in Cloud Shell.

   Notify a topic for each new object in that bucket, so Abstract fetches it. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a filtered sink for network threat logs. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want firewall, Cloud DNS, load balancer and Cloud IDS logs. Each one must also be switched on at its source.

   Template: [Firewall, DNS and IDS logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

12. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a sink on the billing account. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want billing account audit logs. A billing account sits outside the organization, so it needs its own sink.

   Template: [Billing account audit logs to Abstract: billing sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-billing-account-logs)

13. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a second sink that writes the same logs to a Cloud Storage bucket. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you need to keep logs for evidence or backfill. It is not the detection path; files land minutes to hours later.

   Template: [Archive Google Cloud logs to Cloud Storage: second sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-archive-log-bucket)

14. **Verify (optional).** Cloud admin, in Cloud Shell.

   Step 8 creates three alerts and an email channel, so you hear when the pipeline stops sending.

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Three "Abstract log pipeline" alert policies exist, sending to your email.

15. **Verify.** Cloud admin, in Cloud Shell.

   Step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** The probe event arrives, usually within five minutes.

16. **Verify.** Abstract admin, in Abstract console.

   Step 10 prints the exact values. In Abstract, add the Google Cloud Pub/Sub integration with the project that holds the subscription (not the projects the logs come from), the subscription's short name, and the key file. Then delete the key file from Cloud Shell. If you set up Workspace, add the Google Workspace integration the same way. Last, download your answers: the Cloud Shell session is temporary, and the clean-up needs them to know what the setup made.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   cloudshell download ~/.abstract-gcp-setup.env
   ```

   **Check:** Events appear in Abstract under vendor GCP within a few minutes. Re-check the cloud side any time with --check.

17. **Clean up.** Cloud admin, in Cloud Shell.

   To remove the setup, run the clean-up mode with the answers file you downloaded (upload it to Cloud Shell first). Without --confirm it only lists, by name, what it would delete. It removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project <logging-project-id> lists what carries the setup's names and deletes nothing. Delete the integration in Abstract first, so it stops reading.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
   ```

   **Check:** Every item shows as removed, and --remove --project <logging-project-id> then finds nothing that carries the setup's names.

## Send audit logs from one Google Cloud project, as a pilot

**Fits when:** You want to try Abstract on one project before covering more.

**Why this way:** The smallest change that proves the whole path. Move to the organization plan when the pilot is done.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/gcp?a=2). To send someone this plan, share this link.

**Not chosen:** The organization sink: it needs organization rights you may not have for a pilot.

1. **Check first.** Cloud admin, in Cloud Shell.

   Open the guided setup in Cloud Shell, sign in, and take stock of what you already have. The estate audit is read-only: it lists your organization, folders, projects, existing log sinks, Pub/Sub topics and audit settings. Nothing changes.

   ```bash
   gcloud auth login
   gcloud auth application-default login
   ./tools/gcp-guided-setup/audit-gcp-estate.sh
   ```

   **Check:** The audit prints your organization and lists any sinks that already export logs.

2. **Check first.** Cloud admin, in Cloud Shell.

   Steps 1 and 2 of the guided setup: confirm who you are signed in as, choose your scope, and check you hold every permission before anything is created. The one people lack is Logs Configuration Writer (roles/logging.configWriter) on the organization or folder; Organization Admin does not include it.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
   ```

   **Check:** Every permission row is green, or you know who to ask.

3. **Foundation.** Cloud admin, in Cloud Shell.

   Step 3: create a dedicated logging project, or choose one you already use for security tooling, and turn on its APIs. Keep it separate from workload projects. Everything Abstract reads lives here.

   Template: [Google Cloud first step: logging project and APIs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-logging-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
   ```

   **Check:** The project is active and the Pub/Sub, Logging, IAM and Resource Manager APIs are on.

4. **Set up.** Cloud admin, in Cloud Shell.

   Step 4, with the project you chose in step 1: create the topic and subscription, then the project sink, and let the sink's identity publish to the topic.

   Template: [One project's audit logs to Abstract: project sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-audit-logs-project)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
   ```

   **Check:** The sink points at the topic and its identity can publish.

5. **Set up.** Cloud admin, in Cloud Shell.

   Step 5: create the service account Abstract signs in as. It can read only the one subscription. The key is written to ~/abstract-keys, outside any repository.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
   ```

   **Check:** The account exists, can read the subscription, and holds no project-wide role.

6. **Set up (optional).** Cloud admin, in Cloud Shell.

   Step 6: turn on Data Access audit logs and route them. Both switches are needed: the audit settings make Google write the logs, and the sink filter sends them. Either alone does nothing.

   *Optional:* Skip unless you need to know who read or changed data in BigQuery, Cloud Storage or Cloud KMS. It adds volume and cost.

   Template: [Turn on Data Access audit logs: organization, folder or project](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-foundation-data-access-audit-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
   ```

   **Check:** Both switches report on for each service you chose.

7. **Set up (optional).** Cloud admin and a Workspace super admin, in Cloud Shell, then admin.google.com.

   Step 7: create the Workspace reader account. A Workspace super admin then allows it in admin.google.com, under Security, Access and data control, API controls, Domain-wide delegation, with the Client ID and the two read-only scopes the script prints.

   *Optional:* Skip unless you use Google Workspace and want its sign-in, admin and token logs.

   Template: [Google Workspace audit logs to Abstract: Reports API](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-google-workspace-logs)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 7
   ```

   **Check:** The script reads one page from the Reports API as the new account.

8. **Set up (optional).** Cloud admin, in Cloud Shell.

   Send Security Command Center findings to their own topic and subscription. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you have Security Command Center (Premium or Enterprise) and want its findings in Abstract.

   Template: [Security Command Center findings to Abstract: notification feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-security-command-center-findings)

9. **Set up (optional).** Cloud admin, in Cloud Shell.

   Send asset and IAM policy changes from an organization asset feed to their own topic. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want a record of every IAM policy and resource change across the organization.

   Template: [Asset and IAM changes to Abstract: asset feed](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-asset-and-iam-changes)

10. **Set up (optional).** Cloud admin, in Cloud Shell.

   Notify a topic for each new object in that bucket, so Abstract fetches it. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless another product already writes logs to a Cloud Storage bucket and you want them in Abstract.

   Template: [Cloud Storage bucket logs to Abstract: object notifications](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-cloud-storage-bucket-logs)

11. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a filtered sink for network threat logs. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want firewall, Cloud DNS, load balancer and Cloud IDS logs. Each one must also be switched on at its source.

   Template: [Firewall, DNS and IDS logs to Abstract: filtered sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-network-threat-logs)

12. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a sink on the billing account. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you want billing account audit logs. A billing account sits outside the organization, so it needs its own sink.

   Template: [Billing account audit logs to Abstract: billing sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-source-billing-account-logs)

13. **Set up (optional).** Cloud admin, in Cloud Shell.

   Add a second sink that writes the same logs to a Cloud Storage bucket. Open the template's Cloud Shell tutorial and follow it.

   *Optional:* Skip unless you need to keep logs for evidence or backfill. It is not the detection path; files land minutes to hours later.

   Template: [Archive Google Cloud logs to Cloud Storage: second sink](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-archive-log-bucket)

14. **Verify (optional).** Cloud admin, in Cloud Shell.

   Step 8 creates three alerts and an email channel, so you hear when the pipeline stops sending.

   *Optional:* Recommended for production. Skip only for a short pilot.

   Template: [Google Cloud alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/gcp/gcp-monitoring-pipeline-health-alerts)

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 8
   ```

   **Check:** Three "Abstract log pipeline" alert policies exist, sending to your email.

15. **Verify.** Cloud admin, in Cloud Shell.

   Step 9 writes a harmless admin event inside your scope and waits for it on a probe subscription of its own. It never reads Abstract's subscription. A new sink needs about three minutes before it routes anything, so wait five before deciding it failed.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
   ```

   **Check:** The probe event arrives, usually within five minutes.

16. **Verify.** Abstract admin, in Abstract console.

   Step 10 prints the exact values. In Abstract, add the Google Cloud Pub/Sub integration with the project that holds the subscription (not the projects the logs come from), the subscription's short name, and the key file. Then delete the key file from Cloud Shell. If you set up Workspace, add the Google Workspace integration the same way. Last, download your answers: the Cloud Shell session is temporary, and the clean-up needs them to know what the setup made.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
   cloudshell download ~/.abstract-gcp-setup.env
   ```

   **Check:** Events appear in Abstract under vendor GCP within a few minutes. Re-check the cloud side any time with --check.

17. **Clean up.** Cloud admin, in Cloud Shell.

   To remove the setup, run the clean-up mode with the answers file you downloaded (upload it to Cloud Shell first). Without --confirm it only lists, by name, what it would delete. It removes only what the guided setup recorded creating, and never the logging project. Lost the file? --remove --project <logging-project-id> lists what carries the setup's names and deletes nothing. Delete the integration in Abstract first, so it stops reading.

   ```bash
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
   ./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
   ```

   **Check:** Every item shows as removed, and --remove --project <logging-project-id> then finds nothing that carries the setup's names.

## Not covered yet

- The guided setup script covers the core pipeline. The optional sources run from their own Cloud Shell tutorials (Terraform).
