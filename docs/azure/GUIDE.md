# Set up Microsoft Azure

<!-- Generated from tools/guides/azure.yml by `python -m tools.templates generate`. Do not edit. -->

Azure cannot send its logs straight to a third party, so every Azure log source goes through an Event Hub in your subscription: Azure writes to the hub, and Abstract reads from it with a listen-only key. You deploy the hub first, point your sources at it, then add one Azure EventHub integration in Abstract per hub. Sending events the other way, from Abstract into Microsoft Sentinel or an Event Hub of yours, is a separate job: choose "Send data out of Abstract" below.

Answer the questions below. Each answer leads to the next question or to one plan: the steps in order, from checking what you have to cleaning it all up. The same questions are in the [onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure), which gives each plan a link you can share.

## What do you want to set up?

- **Send Azure logs to Abstract** → [How much of Azure should send logs?](#how-much-of-azure-should-send-logs)
  Activity Log, resource logs and Entra ID sign-in and audit logs, through an Event Hub.
- **Send data out of Abstract, into Microsoft Sentinel or an Event Hub of yours** → [Send data out of Abstract: where should Abstract deliver its events?](#send-data-out-of-abstract-where-should-abstract-deliver-its-events)
  The other direction. Nothing here collects Azure logs.
- **Give Abstract API access in each subscription, with an app registration** → [Does your organization require every Azure change to be made through Azure Policy?](#does-your-organization-require-every-azure-change-to-be-made-through-azure-policy)
  For Abstract integrations that read the Microsoft Graph or Microsoft 365 APIs. Each subscription gets its own Entra app, with a role on that subscription and Graph read permissions, which are always tenant-wide. Event Hub collection needs none of this.

## How much of Azure should send logs?

- **Every subscription under a management group (recommended)** → [Send logs from every Azure subscription, by Policy](#send-logs-from-every-azure-subscription-by-policy)
  Today's subscriptions and every one added later. Best for more than about three subscriptions, or an estate that will grow.
- **One subscription, as a pilot** → [Send the Activity Log from one Azure subscription, as a pilot](#send-the-activity-log-from-one-azure-subscription-as-a-pilot)
  Proves the pipeline. Nothing extends it to other subscriptions.
- **Only Entra ID sign-in and audit logs** → [Send Entra ID sign-in and audit logs only](#send-entra-id-sign-in-and-audit-logs-only)

## Send data out of Abstract: where should Abstract deliver its events?

Abstract writes processed events to a system of yours. This does not bring any Azure logs into Abstract.

- **Microsoft Sentinel** → [Abstract writes to Sentinel as an Entra app registration. Who creates it?](#abstract-writes-to-sentinel-as-an-entra-app-registration-who-creates-it)
- **An Event Hub of yours, for another tool to read** → [Send Abstract events to an Event Hub of yours](#send-abstract-events-to-an-event-hub-of-yours)

## Abstract writes to Sentinel as an Entra app registration. Who creates it?

- **I create the app registration myself (recommended for production)** → [Send Abstract events to Microsoft Sentinel, with your app registration](#send-abstract-events-to-microsoft-sentinel-with-your-app-registration)
- **The template creates it, from the Azure CLI** → [Send Abstract events to Sentinel, app created by Graph](#send-abstract-events-to-sentinel-app-created-by-graph)
  Uses Microsoft Graph as you, the person deploying. No standing privileged identity.
- **The template creates it, from the Azure portal** → [Send Abstract events to Sentinel, app created in the portal](#send-abstract-events-to-sentinel-app-created-in-the-portal)
  For portal-only teams and labs. You first create a managed identity holding Microsoft Graph Application.ReadWrite.All, which can add a credential to any app in your tenant: treat it as tier-0 and remove that permission after the deploy.

## Does your organization require every Azure change to be made through Azure Policy?

- **No (most organizations)** → [Abstract API access per subscription, by Logic App](#abstract-api-access-per-subscription-by-logic-app)
  One Logic App creates the app registrations, so there is one identity to audit.
- **Yes, every change must arrive by Azure Policy** → [Abstract API access to every subscription, by Policy](#abstract-api-access-to-every-subscription-by-policy)
  A Policy runs a script in each subscription as a managed identity that can grant itself any directory permission (tier-0), and each app it creates gets tenant-wide Microsoft Graph read permissions.

## Send logs from every Azure subscription, by Policy

**Fits when:** Several subscriptions, or an estate that will grow.

**Why this way:** One Policy assignment at a management group covers every subscription in it, including new ones, and puts a setting back if someone removes it.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=0.0). To send someone this plan, share this link.

**Not chosen:** The one-subscription template: it covers exactly one subscription, and nothing extends it to new ones.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Foundation.** Cloud admin, in Azure Cloud Shell (Bash).

   Azure only accepts a resource's logs into an Event Hub in the same region as the resource, so deploy one Event Hub namespace per region that holds resources, each in a resource group of its own. The first query lists those regions. In your main region, create the hubs activity, entra and resource (the Activity Log and Entra ID are not regional, so they need one hub each, in one place). In every other region, create only the resource hub; it is still named abs-prod-resource. In the portal form the field is "Log sources (comma-separated)": enter activity,entra,resource in the main region and resource elsewhere. The default, activity,entra,defender, creates no resource hub, and the Policy would then have nowhere to send resource logs. Last, read the two IDs the next steps need from each namespace.

   *Note:* Clean-up deletes these resource groups whole, so put nothing else in them.

   Template: [Azure first step: Event Hub that receives all logs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-foundation-event-hub)

   ```bash
   az graph query -q "resources | where location !in ('global', '') | summarize resources=count() by location" --management-groups <mg-id> -o table
   [ -d ~/abstract-cloud-templates ] || git clone --depth 1 https://github.com/IamABS3C/abstract-cloud-templates ~/abstract-cloud-templates
   cd ~/abstract-cloud-templates/templates/azure
   # Main region: Activity Log, Entra ID and that region's resource logs
   az group create --name rg-abstract-eh-<main-region> --location <main-region>
   ./azure-foundation-event-hub/deploy.sh rg-abstract-eh-<main-region> --parameters namespaceName=<unique-name> 'hubSources=["activity","entra","resource"]' --yes
   # Repeat for every other region the query listed: resource logs only
   az group create --name rg-abstract-eh-<region> --location <region>
   ./azure-foundation-event-hub/deploy.sh rg-abstract-eh-<region> --parameters namespaceName=<unique-name-for-region> 'hubSources=["resource"]' --yes
   # For each namespace: its Send rule ID (for the Policy) and its resource ID (for the grant)
   az eventhubs namespace authorization-rule show -g <resource-group> --namespace-name <namespace> -n abstract-diagnostics-send --query id -o tsv
   az eventhubs namespace show -g <resource-group> -n <namespace> --query id -o tsv
   ```

   **Check:** az eventhubs eventhub list -g &lt;resource-group> --namespace-name &lt;namespace> --query "[].name" -o tsv lists abs-prod-resource in every namespace, and also abs-prod-activity and abs-prod-entra in the main region's namespace.

3. **Set up.** Cloud admin with Owner on the management group, in Azure Cloud Shell (Bash), or the Azure portal (Deploy to Azure).

   Assign the Policy in report-only mode first. It writes no diagnostic setting yet: it only counts what it would change. Copy the report-only parameter file and edit it: activityLogAuthorizationRuleId is the main region's Send rule ID, and regions has one row per region, each with that region's Send rule ID and eventHubName abs-prod-resource. Leave effect AuditIfNotExists and enforcementMode DoNotEnforce. The script validates and previews, then asks before it deploys. In the portal, choose Rollout mode "Report first (recommended)" and add one row per region under "Regions — one row per region that holds resources".

   > **This changes:** Even report-only creates a custom policy definition and one assignment per log type, each with its own managed identity, and gives those identities Monitoring Contributor and Log Analytics Contributor on the whole management group &lt;mg-id>. No diagnostic setting is written yet.

   Template: [All Azure logs to Abstract: every subscription by Policy](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-all-logs-management-group-policy)

   ```bash
   cd ~/abstract-cloud-templates/templates/azure/azure-source-all-logs-management-group-policy
   cp examples/default.parameters.json abstract-policy.parameters.json
   # edit abstract-policy.parameters.json now: activityLogAuthorizationRuleId and the regions rows
   ./scripts/deploy-log-streams.sh -a Deploy -m <mg-id> -p abstract-policy.parameters.json
   ./scripts/deploy-log-streams.sh -a Status -m <mg-id>
   ```

   **Check:** Status lists abs-activitylog and one abs-r-… assignment per region, each with enforcement DoNotEnforce and an identity. After about 30 minutes its compliance summary shows nonCompliantResources: that count is how many resources Enforce and the remediation will change.

4. **Set up.** Cloud admin with Owner on the Event Hub resource groups, in Azure Cloud Shell (Bash).

   Before enforcing, give each Policy assignment's managed identity access to the Event Hubs. The template cannot do this, because the namespaces sit outside the management group's scope, and without it every setting the Policy writes fails. The identities already exist from the report-only step. Run the grant once per namespace, with the namespace resource ID from the first step. If you changed namePrefix from abs, add -x &lt;prefix>.

   > **This changes:** Gives every abs- Policy assignment identity the Azure Event Hubs Data Owner role on the namespace, which is broader than the listKeys right it needs.

   ```bash
   cd ~/abstract-cloud-templates/templates/azure/azure-source-all-logs-management-group-policy
   ./scripts/deploy-log-streams.sh -a Grant -m <mg-id> -n <namespace-resource-id>
   az role assignment list --scope <namespace-resource-id> --role "Azure Event Hubs Data Owner" --query "[].principalId" -o tsv
   ```

   **Check:** The script prints "granted" or "already present" for every assignment and no FAILED line, and the role assignment list shows one principal ID for each identity Status listed, on every namespace.

5. **Set up.** Cloud admin with Owner on the management group, in Azure Cloud Shell (Bash), or the Azure portal (Deploy to Azure).

   Switch the same assignments to Enforce by deploying again with effect DeployIfNotExists and enforcementMode Default. In the portal, deploy again with the same values and choose Rollout mode "Enforce — deploy the settings".

   > **This changes:** From now on Azure Policy writes a diagnostic setting on every subscription (abstract-activity-logs) and on every supported resource in the listed regions (abstract-logstream) that is created or changed under &lt;mg-id>, sending allLogs to your Event Hubs. Each subscription and resource allows at most 5 diagnostic settings, and existing exports count. Event Hub volume and cost follow the report-only count.

   ```bash
   cd ~/abstract-cloud-templates/templates/azure/azure-source-all-logs-management-group-policy
   sed -i 's/"AuditIfNotExists"/"DeployIfNotExists"/; s/"DoNotEnforce"/"Default"/' abstract-policy.parameters.json
   ./scripts/deploy-log-streams.sh -a Deploy -m <mg-id> -p abstract-policy.parameters.json
   ./scripts/deploy-log-streams.sh -a Status -m <mg-id>
   ```

   **Check:** Status shows enforcement Default on every abs- assignment.

6. **Set up.** Cloud admin with Owner on the management group, in Azure Cloud Shell (Bash).

   Bring in the subscriptions and resources that already exist. Policy only acts on resources that are created or changed, so without a remediation task your current estate never sends anything. The script creates one task per policy. It hides the errors of the tasks it creates, so read the task list to see that they ran.

   > **This changes:** This is the mass change. It writes abstract-activity-logs to every existing subscription and abstract-logstream to every existing supported resource under &lt;mg-id>, in every listed region. Run it only after reading the report-only count.

   ```bash
   cd ~/abstract-cloud-templates/templates/azure/azure-source-all-logs-management-group-policy
   ./scripts/deploy-log-streams.sh -a Remediate -m <mg-id>
   az policy remediation list --management-group <mg-id> --query "[].{name:name, state:provisioningState, ok:deploymentStatus.successfulDeployments, failed:deploymentStatus.failedDeployments}" -o table
   ./scripts/deploy-log-streams.sh -a Status -m <mg-id>
   ```

   **Check:** Every remediation task reaches Succeeded with failed 0 (they run for minutes to hours), and Status shows nonCompliantResources falling. Spot-check one resource: az monitor diagnostic-settings list --resource &lt;resource-id> shows abstract-logstream pointing at abs-prod-resource.

7. **Set up (optional).** Cloud admin with rights on the root management group, in Azure Cloud Shell (Bash).

   Make &lt;mg-id> the default management group for new subscriptions, so each one is covered as soon as it is created. The first command shows the current setting.

   > **This changes:** Changes where every new subscription in the tenant is placed, which also changes the Policies and roles they inherit.

   *Optional:* Skip if new subscriptions are already created in, or moved into, &lt;mg-id>. Azure puts a new subscription in the root management group by default, where this Policy does not reach it.

   ```bash
   az account management-group hierarchy-settings list --name <tenant-id>
   az account management-group hierarchy-settings create --name <tenant-id> --default-management-group /providers/Microsoft.Management/managementGroups/<mg-id>
   ```

   **Check:** hierarchy-settings list shows defaultManagementGroup ending in /&lt;mg-id>.

8. **Set up (optional).** Cloud admin who is an Entra Security Administrator and can deploy at tenant scope, in Azure Cloud Shell (Bash).

   Entra ID logs belong to the tenant, not a subscription, so no Policy reaches them. One CLI deploy creates the tenant's diagnostic setting, pointing at the abs-prod-entra hub. Run it without --yes first to preview, then with --yes. A tenant-scope deploy needs, besides the Entra role, the right to run deployments at the root scope "/" (for example Owner there, which a Global Administrator grants after elevating access). Expect 24 hours to 3 days before the first records arrive.

   *Optional:* Recommended. Sign-in and audit logs carry most identity detections. Skip only if they already stream to another Event Hub you will use.

   Template: [Entra ID sign-in and audit logs to Abstract](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-entra-id-logs-tenant)

   ```bash
   [ -d ~/abstract-cloud-templates ] || git clone --depth 1 https://github.com/IamABS3C/abstract-cloud-templates ~/abstract-cloud-templates
   cd ~/abstract-cloud-templates/templates/azure
   az eventhubs namespace authorization-rule show -g <resource-group> --namespace-name <namespace> -n abstract-diagnostics-send --query id -o tsv
   ./azure-source-entra-id-logs-tenant/deploy.sh <region> --parameters eventHubAuthorizationRuleId=<rule-id>
   ./azure-source-entra-id-logs-tenant/deploy.sh <region> --parameters eventHubAuthorizationRuleId=<rule-id> --yes
   ```

   **Check:** az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01" lists abstract-entra-logstream with eventHubName abs-prod-entra.

9. **Verify.** Abstract admin, with a Cloud admin to copy the key, in Abstract console, then the Azure portal.

   Add one Azure EventHub integration in Abstract for each hub, in every namespace. The connection string is the namespace's listen-only key abstract-access, and it is a secret: copy it in the Azure portal (Event Hubs namespace > Settings > Shared access policies > abstract-access > Connection string–primary key) and paste it straight into Abstract, never into a terminal, chat or ticket. The Event Hub deploys Standard tier, which needs no storage account in Abstract.

   ```bash
   az eventhubs eventhub list -g <resource-group> --namespace-name <namespace> --query "[].name" -o tsv
   ```

   In Abstract, add the **Azure EventHub** integration and fill in:

   - **Event Hubs Namespace Tier:** Standard, Premium, or Dedicated (high throughput)
   - **Authentication Method:** Connection String
   - **EventHub Name:** One hub per integration, from the first command (abs-prod-activity, abs-prod-entra, abs-prod-resource)
   - **EventHub Consumer Group:** abstract
   - **EventHub Connection String:** The abstract-access Connection string–primary key, copied in the portal
   - **Storage Blob Container Name (Basic tier only):** Leave empty
   - **Storage Account Connection String (Basic tier only):** Leave empty

   **Check:** Within minutes of saving, the namespace's Metrics show Outgoing Messages above zero for each hub that has Incoming Messages: that is Abstract reading.

10. **Verify (optional).** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Add the health alerts, so you hear when Abstract stops reading while logs keep arriving.

   *Optional:* Recommended for production. Event Hubs reports no consumer lag, so without these a stalled feed fails silently.

   Template: [Azure alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-monitoring-event-hub-health-alerts)

   **Check:** az monitor metrics alert list -g &lt;resource-group> --query "[?contains(name,'abstract-eh')].{name:name,enabled:enabled}" -o table shows four enabled metric alerts, and the Action Group's test notification arrives.

11. **Verify.** Cloud admin and Abstract admin, in Azure portal, then Abstract.

   In each namespace's Metrics, Incoming Messages should be non-zero once a source points at the hub, and Outgoing Messages should follow it. In Abstract, search the last 15 minutes for events from each Azure EventHub integration. Entra ID can take longer when there are few sign-ins.

   **Check:** Outgoing tracks Incoming on every hub with no lasting gap, and the Abstract search returns events for each integration, with cloud.project_id holding the subscription ID.

12. **Clean up.** Cloud admin, in Abstract console, then Cloud Shell.

   Remove in this order, so nothing keeps sending to a hub that is gone. First delete the integrations in Abstract. Then delete the Policy assignments. Deleting an assignment does NOT remove the diagnostic settings it already deployed, so delete those next: the subscription setting abstract-activity-logs in each subscription, and the resource-level settings named abstract-logstream that the remediation created. If you turned on SQL auditing or Defender for Cloud export, delete those assignments too, and the rg-abstract-defender-export resource group. Then the Entra setting, if you added it. Last, every Event Hub resource group, one per region.

   ```bash
   az policy assignment list --scope /providers/Microsoft.Management/managementGroups/<mg-id> --query "[?starts_with(name, 'abs-')].name" -o tsv
   az policy assignment delete --name <assignment-name> --scope /providers/Microsoft.Management/managementGroups/<mg-id>
   az monitor diagnostic-settings subscription delete --name abstract-activity-logs --subscription <subscription-id> --yes
   az rest --method delete --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings/abstract-entra-logstream?api-version=2017-04-01"
   az group delete --name <event-hub-resource-group>
   ```

   **Check:** Every namespace is gone and no diagnostic setting points at one.

## Send the Activity Log from one Azure subscription, as a pilot

**Fits when:** One subscription, a pilot, or no management-group rights yet.

**Why this way:** The smallest change that proves the whole path. Move to the Policy plan when the pilot is done.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=0.1). To send someone this plan, share this link.

**Not chosen:** The Policy plan: it needs rights on a management group you may not have for a pilot.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Foundation.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Event Hub first. It creates the namespace, one hub per log source (abs-prod-activity, abs-prod-entra and abs-prod-defender by default), an abstract consumer group, a listen-only key named abstract-access, a Send rule named abstract-diagnostics-send for Azure to write with, and a checkpoint storage account.

   *Note:* Put it in a resource group of its own. Clean-up deletes that resource group whole.

   Template: [Azure first step: Event Hub that receives all logs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-foundation-event-hub)

   **Check:** az eventhubs eventhub list -g &lt;resource-group> --namespace-name &lt;namespace> --query "[].name" -o tsv lists the hubs, and the namespace's Overview shows Status Active.

3. **Set up.** Cloud admin with Owner or Monitoring Contributor on the subscription, in Azure portal (Deploy to Azure) or Cloud Shell.

   Point this subscription's Activity Log at the abs-prod-activity hub, with the namespace's abstract-diagnostics-send rule ID. Redeploying replaces the setting's category list instead of adding to it, so read the current one first (the check-first commands show it).

   Template: [Activity Log to Abstract: one subscription](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-activity-log-subscription)

   **Check:** az monitor diagnostic-settings subscription list --query "value[?name=='abstract-activity-logs'].eventHubName" -o tsv prints abs-prod-activity.

4. **Set up (optional).** Cloud admin who is an Entra Security Administrator and can deploy at tenant scope, in Azure Cloud Shell (Bash).

   Entra ID logs belong to the tenant, not a subscription, so no Policy reaches them. One CLI deploy creates the tenant's diagnostic setting, pointing at the abs-prod-entra hub. Run it without --yes first to preview, then with --yes. A tenant-scope deploy needs, besides the Entra role, the right to run deployments at the root scope "/" (for example Owner there, which a Global Administrator grants after elevating access). Expect 24 hours to 3 days before the first records arrive.

   *Optional:* Recommended. Sign-in and audit logs carry most identity detections. Skip only if they already stream to another Event Hub you will use.

   Template: [Entra ID sign-in and audit logs to Abstract](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-entra-id-logs-tenant)

   ```bash
   [ -d ~/abstract-cloud-templates ] || git clone --depth 1 https://github.com/IamABS3C/abstract-cloud-templates ~/abstract-cloud-templates
   cd ~/abstract-cloud-templates/templates/azure
   az eventhubs namespace authorization-rule show -g <resource-group> --namespace-name <namespace> -n abstract-diagnostics-send --query id -o tsv
   ./azure-source-entra-id-logs-tenant/deploy.sh <region> --parameters eventHubAuthorizationRuleId=<rule-id>
   ./azure-source-entra-id-logs-tenant/deploy.sh <region> --parameters eventHubAuthorizationRuleId=<rule-id> --yes
   ```

   **Check:** az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01" lists abstract-entra-logstream with eventHubName abs-prod-entra.

5. **Verify.** Abstract admin, with a Cloud admin to copy the key, in Abstract console, then the Azure portal.

   Add one Azure EventHub integration in Abstract for each hub, in every namespace. The connection string is the namespace's listen-only key abstract-access, and it is a secret: copy it in the Azure portal (Event Hubs namespace > Settings > Shared access policies > abstract-access > Connection string–primary key) and paste it straight into Abstract, never into a terminal, chat or ticket. The Event Hub deploys Standard tier, which needs no storage account in Abstract.

   ```bash
   az eventhubs eventhub list -g <resource-group> --namespace-name <namespace> --query "[].name" -o tsv
   ```

   In Abstract, add the **Azure EventHub** integration and fill in:

   - **Event Hubs Namespace Tier:** Standard, Premium, or Dedicated (high throughput)
   - **Authentication Method:** Connection String
   - **EventHub Name:** One hub per integration, from the first command (abs-prod-activity, abs-prod-entra, abs-prod-resource)
   - **EventHub Consumer Group:** abstract
   - **EventHub Connection String:** The abstract-access Connection string–primary key, copied in the portal
   - **Storage Blob Container Name (Basic tier only):** Leave empty
   - **Storage Account Connection String (Basic tier only):** Leave empty

   **Check:** Within minutes of saving, the namespace's Metrics show Outgoing Messages above zero for each hub that has Incoming Messages: that is Abstract reading.

6. **Verify (optional).** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Add the health alerts, so you hear when Abstract stops reading while logs keep arriving.

   *Optional:* Recommended for production. Event Hubs reports no consumer lag, so without these a stalled feed fails silently.

   Template: [Azure alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-monitoring-event-hub-health-alerts)

   **Check:** az monitor metrics alert list -g &lt;resource-group> --query "[?contains(name,'abstract-eh')].{name:name,enabled:enabled}" -o table shows four enabled metric alerts, and the Action Group's test notification arrives.

7. **Verify.** Cloud admin and Abstract admin, in Azure portal, then Abstract.

   In each namespace's Metrics, Incoming Messages should be non-zero once a source points at the hub, and Outgoing Messages should follow it. In Abstract, search the last 15 minutes for events from each Azure EventHub integration. Entra ID can take longer when there are few sign-ins.

   **Check:** Outgoing tracks Incoming on every hub with no lasting gap, and the Abstract search returns events for each integration, with cloud.project_id holding the subscription ID.

8. **Clean up.** Cloud admin, in Abstract console, then Cloud Shell.

   Delete the integrations in Abstract first. Then the subscription's diagnostic setting, then the Entra setting if you added it, then the Event Hub's resource group.

   ```bash
   az monitor diagnostic-settings subscription delete --name abstract-activity-logs --subscription <subscription-id> --yes
   az rest --method delete --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings/abstract-entra-logstream?api-version=2017-04-01"
   az group delete --name <event-hub-resource-group>
   ```

   **Check:** The namespace is gone and no diagnostic setting points at it.

## Send Entra ID sign-in and audit logs only

**Fits when:** You want identity telemetry first, or Azure resource logs are covered elsewhere.

**Why this way:** One tenant-level setting covers every sign-in and audit event in the tenant.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=0.2). To send someone this plan, share this link.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Foundation.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Event Hub first. It creates the namespace, one hub per log source (abs-prod-activity, abs-prod-entra and abs-prod-defender by default), an abstract consumer group, a listen-only key named abstract-access, a Send rule named abstract-diagnostics-send for Azure to write with, and a checkpoint storage account.

   *Note:* Put it in a resource group of its own. Clean-up deletes that resource group whole.

   Template: [Azure first step: Event Hub that receives all logs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-foundation-event-hub)

   **Check:** az eventhubs eventhub list -g &lt;resource-group> --namespace-name &lt;namespace> --query "[].name" -o tsv lists the hubs, and the namespace's Overview shows Status Active.

3. **Set up.** Cloud admin who is an Entra Security Administrator and can deploy at tenant scope, in Azure Cloud Shell (Bash).

   Entra ID logs belong to the tenant, so this is one CLI deploy at tenant scope, pointing at the abs-prod-entra hub. It cannot be done by Policy. Run it without --yes first to preview, then with --yes. A tenant-scope deploy needs, besides the Entra role, the right to run deployments at the root scope "/" (for example Owner there, which a Global Administrator grants after elevating access). Expect 24 hours to 3 days before the first records arrive.

   Template: [Entra ID sign-in and audit logs to Abstract](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-entra-id-logs-tenant)

   ```bash
   [ -d ~/abstract-cloud-templates ] || git clone --depth 1 https://github.com/IamABS3C/abstract-cloud-templates ~/abstract-cloud-templates
   cd ~/abstract-cloud-templates/templates/azure
   az eventhubs namespace authorization-rule show -g <resource-group> --namespace-name <namespace> -n abstract-diagnostics-send --query id -o tsv
   ./azure-source-entra-id-logs-tenant/deploy.sh <region> --parameters eventHubAuthorizationRuleId=<rule-id>
   ./azure-source-entra-id-logs-tenant/deploy.sh <region> --parameters eventHubAuthorizationRuleId=<rule-id> --yes
   ```

   **Check:** az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01" lists abstract-entra-logstream with eventHubName abs-prod-entra.

4. **Verify.** Abstract admin, with a Cloud admin to copy the key, in Abstract console, then the Azure portal.

   Add one Azure EventHub integration in Abstract for each hub, in every namespace. The connection string is the namespace's listen-only key abstract-access, and it is a secret: copy it in the Azure portal (Event Hubs namespace > Settings > Shared access policies > abstract-access > Connection string–primary key) and paste it straight into Abstract, never into a terminal, chat or ticket. The Event Hub deploys Standard tier, which needs no storage account in Abstract.

   ```bash
   az eventhubs eventhub list -g <resource-group> --namespace-name <namespace> --query "[].name" -o tsv
   ```

   In Abstract, add the **Azure EventHub** integration and fill in:

   - **Event Hubs Namespace Tier:** Standard, Premium, or Dedicated (high throughput)
   - **Authentication Method:** Connection String
   - **EventHub Name:** One hub per integration, from the first command (abs-prod-activity, abs-prod-entra, abs-prod-resource)
   - **EventHub Consumer Group:** abstract
   - **EventHub Connection String:** The abstract-access Connection string–primary key, copied in the portal
   - **Storage Blob Container Name (Basic tier only):** Leave empty
   - **Storage Account Connection String (Basic tier only):** Leave empty

   **Check:** Within minutes of saving, the namespace's Metrics show Outgoing Messages above zero for each hub that has Incoming Messages: that is Abstract reading.

5. **Verify (optional).** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Add the health alerts, so you hear when Abstract stops reading while logs keep arriving.

   *Optional:* Recommended for production. Event Hubs reports no consumer lag, so without these a stalled feed fails silently.

   Template: [Azure alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-monitoring-event-hub-health-alerts)

   **Check:** az monitor metrics alert list -g &lt;resource-group> --query "[?contains(name,'abstract-eh')].{name:name,enabled:enabled}" -o table shows four enabled metric alerts, and the Action Group's test notification arrives.

6. **Verify.** Cloud admin and Abstract admin, in Azure portal, then Abstract.

   In each namespace's Metrics, Incoming Messages should be non-zero once a source points at the hub, and Outgoing Messages should follow it. In Abstract, search the last 15 minutes for events from each Azure EventHub integration. Entra ID can take longer when there are few sign-ins.

   **Check:** Outgoing tracks Incoming on every hub with no lasting gap, and the Abstract search returns events for each integration, with cloud.project_id holding the subscription ID.

7. **Clean up.** Cloud admin, in Abstract console, then Cloud Shell.

   Delete the integration in Abstract first. Then the Entra setting, then the Event Hub's resource group.

   ```bash
   az rest --method delete --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings/abstract-entra-logstream?api-version=2017-04-01"
   az group delete --name <event-hub-resource-group>
   ```

   **Check:** The namespace is gone and the Entra setting is no longer listed.

## Send Abstract events to Microsoft Sentinel, with your app registration

**Fits when:** Production, when your team creates the Entra app registration.

**Why this way:** No privileged identity is involved. The template builds the ingestion stack and gives your app the one role it needs.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=1.0.0). To send someone this plan, share this link.

**Not chosen:** The template-created app: needs either the Graph Bicep extension or a privileged managed identity.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Foundation.** Entra admin, with Key Vault Secrets Officer on a Key Vault, in Azure Cloud Shell (Bash), or the Entra admin center.

   Create an app registration for Abstract and a client secret. The script creates the app and its service principal and writes the secret straight into your Key Vault as abstract-sentinel-client-secret: it never prints the value. Keep the client ID and tenant ID it prints for the last step. The app needs no API permissions: its only right will be the role the next step grants on the data collection rule. Without a Key Vault, create the secret in the Entra admin center instead (App registrations > the app > Certificates & secrets > New client secret): the value is shown once, in the browser, and goes straight into Abstract.

   ```bash
   [ -d ~/abstract-cloud-templates ] || git clone --depth 1 https://github.com/IamABS3C/abstract-cloud-templates ~/abstract-cloud-templates
   cd ~/abstract-cloud-templates/templates/azure/azure-destination-sentinel
   ./scripts/new-app-registration.sh --app-name Abstract-Sentinel-App --keyvault <key-vault-name>
   ```

   **Check:** az ad sp show --id &lt;client-id> --query id -o tsv prints the Enterprise Application object ID the next step needs, az ad app credential list --id &lt;client-id> lists one secret, and az keyvault secret list --vault-name &lt;key-vault-name> --query "[].name" -o tsv lists abstract-sentinel-client-secret (names only, never the value).

3. **Set up.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Sentinel destination in the workspace's resource group. For principalId give the app's Enterprise Application object ID, not its client ID (az ad sp show --id &lt;client-id> --query id -o tsv). It creates the data collection endpoint and rule and the custom Abstract table, and grants your app Monitoring Metrics Publisher on the rule.

   Template: [Abstract to Microsoft Sentinel: with your app registration](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel)

   **Check:** The abstractSentinelOnboarding output lists the endpoint, the rule's immutable ID and the stream name, and rbac names your app's object ID.

4. **Set up (optional).** Cloud admin, in Azure portal (Deploy to Azure).

   Install the Abstract content into the same workspace. The two analytics rules and three automation rules arrive disabled.

   *Optional:* Skip unless you want Abstract's analytics rules, workbooks and hunting queries in a lab or private workspace. It is not the Content Hub solution.

   Template: [Sentinel content for Abstract data: rules and workbooks](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-content-pack)

   **Check:** In Microsoft Sentinel, Hunting lists Abstract_RareProduct, Abstract_HighRiskIdentities and Abstract_DailyValueSummary, and Analytics lists the two Abstract rules as disabled.

5. **Verify.** Abstract admin, in Abstract console, then Log Analytics.

   Add the Azure Sentinel Destination in Abstract with the values below, send a test, then query the custom table in the workspace.

   In Abstract, add the **Azure Sentinel Destination** integration and fill in:

   - **Client ID:** The app's Application (client) ID (clientId output, when the template created the app)
   - **Client Secret Value:** The client secret, copied in the browser and never printed in a terminal. From Key Vault: Azure portal > Key Vault > Secrets > abstract-sentinel-client-secret (or the secret the deploy output names) > current version > Show Secret Value. Or straight from the Entra admin center when you create it there.
   - **Application Tenant ID:** Your Entra tenant ID (applicationTenantId output)
   - **Data Collection Rule ID:** The dataCollectionRuleImmutableId output (dcr-…), not the rule's resource ID
   - **Data Collection Endpoint:** The dataCollectionEndpointUrl output
   - **Log Stream Name:** The logStreamName output

   **Check:** Rows from Abstract appear in the custom table within a few minutes.

6. **Clean up.** Cloud admin and Entra admin, in Abstract console, then Azure.

   Delete the destination in Abstract first. Then delete the data collection rule and endpoint (the resources this deploy created), and the custom table only if you no longer need its data. Last, delete the app registration in Entra if nothing else uses it.

   **Check:** Abstract shows no Sentinel destination, and az ad app show --id &lt;client-id> reports that the app does not exist.

## Send Abstract events to Sentinel, app created by Graph

**Fits when:** Production, when the template should create the app registration and you deploy from the Azure CLI.

**Why this way:** The app is created as you, through Microsoft Graph, so no standing privileged identity has to exist first.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=1.0.1). To send someone this plan, share this link.

**Not chosen:** Portal deployment: the Graph Bicep extension works only from the Azure CLI or PowerShell.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Set up.** Cloud admin who can create app registrations, in Cloud Shell.

   Deploy the Graph variant. It creates the app and its service principal, then the same ingestion stack. Leave automateSecret off unless you want a managed identity that can rotate this app's secret. With it off, create the secret in the Entra admin center (App registrations > the app > Certificates & secrets > New client secret) and copy it from the browser straight into Abstract. Do not run the secretCommand output: it prints the secret to the terminal.

   Template: [Abstract to Sentinel: app registration created by Graph](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-app-by-graph)

   **Check:** The outputs list the client ID, tenant ID, endpoint, rule ID and stream name.

3. **Set up (optional).** Cloud admin, in Azure portal (Deploy to Azure).

   Install the Abstract content into the same workspace. The two analytics rules and three automation rules arrive disabled.

   *Optional:* Skip unless you want Abstract's analytics rules, workbooks and hunting queries in a lab or private workspace. It is not the Content Hub solution.

   Template: [Sentinel content for Abstract data: rules and workbooks](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-content-pack)

   **Check:** In Microsoft Sentinel, Hunting lists Abstract_RareProduct, Abstract_HighRiskIdentities and Abstract_DailyValueSummary, and Analytics lists the two Abstract rules as disabled.

4. **Verify.** Abstract admin, in Abstract console, then Log Analytics.

   Add the Azure Sentinel Destination in Abstract with the values below, send a test, then query the custom table in the workspace.

   In Abstract, add the **Azure Sentinel Destination** integration and fill in:

   - **Client ID:** The app's Application (client) ID (clientId output, when the template created the app)
   - **Client Secret Value:** The client secret, copied in the browser and never printed in a terminal. From Key Vault: Azure portal > Key Vault > Secrets > abstract-sentinel-client-secret (or the secret the deploy output names) > current version > Show Secret Value. Or straight from the Entra admin center when you create it there.
   - **Application Tenant ID:** Your Entra tenant ID (applicationTenantId output)
   - **Data Collection Rule ID:** The dataCollectionRuleImmutableId output (dcr-…), not the rule's resource ID
   - **Data Collection Endpoint:** The dataCollectionEndpointUrl output
   - **Log Stream Name:** The logStreamName output

   **Check:** Rows from Abstract appear in the custom table within a few minutes.

5. **Clean up.** Cloud admin and Entra admin, in Abstract console, then Azure.

   Delete the destination in Abstract first. Then delete the data collection rule and endpoint (the resources this deploy created), and the custom table only if you no longer need its data. Last, delete the app registration in Entra if nothing else uses it.

   **Check:** Abstract shows no Sentinel destination, and az ad app show --id &lt;client-id> reports that the app does not exist.

## Send Abstract events to Sentinel, app created in the portal

**Fits when:** Portal-only teams and labs.

**Why this way:** A deployment script creates the app and its secret, so the whole setup runs from the portal wizard.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=1.0.2). To send someone this plan, share this link.

**Not chosen:** Production: it needs a privileged managed identity that outlives the deploy.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Set up.** Cloud admin, and a Global Administrator for the one-time consent, in Azure portal (Deploy to Azure).

   Create the managed identity the template asks for first, with the Microsoft Graph permission Application.ReadWrite.All, admin-consented. Then deploy. With Key Vault, the secret is stored there and never shown.

   > **This changes:** The managed identity holds Microsoft Graph Application.ReadWrite.All across your whole tenant: it can add a credential to any app, so treat it as tier-0. Remove that permission, or delete the identity, as soon as the deploy finishes.

   Template: [Abstract to Sentinel: app registration created by script](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-app-by-script)

   **Check:** The outputs list the client ID and the Key Vault URI that holds the secret.

3. **Set up (optional).** Cloud admin, in Azure portal (Deploy to Azure).

   Install the Abstract content into the same workspace. The two analytics rules and three automation rules arrive disabled.

   *Optional:* Skip unless you want Abstract's analytics rules, workbooks and hunting queries in a lab or private workspace. It is not the Content Hub solution.

   Template: [Sentinel content for Abstract data: rules and workbooks](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-content-pack)

   **Check:** In Microsoft Sentinel, Hunting lists Abstract_RareProduct, Abstract_HighRiskIdentities and Abstract_DailyValueSummary, and Analytics lists the two Abstract rules as disabled.

4. **Verify.** Abstract admin, in Abstract console, then Log Analytics.

   Add the Azure Sentinel Destination in Abstract with the values below, send a test, then query the custom table in the workspace.

   In Abstract, add the **Azure Sentinel Destination** integration and fill in:

   - **Client ID:** The app's Application (client) ID (clientId output, when the template created the app)
   - **Client Secret Value:** The client secret, copied in the browser and never printed in a terminal. From Key Vault: Azure portal > Key Vault > Secrets > abstract-sentinel-client-secret (or the secret the deploy output names) > current version > Show Secret Value. Or straight from the Entra admin center when you create it there.
   - **Application Tenant ID:** Your Entra tenant ID (applicationTenantId output)
   - **Data Collection Rule ID:** The dataCollectionRuleImmutableId output (dcr-…), not the rule's resource ID
   - **Data Collection Endpoint:** The dataCollectionEndpointUrl output
   - **Log Stream Name:** The logStreamName output

   **Check:** Rows from Abstract appear in the custom table within a few minutes.

5. **Clean up.** Cloud admin and Entra admin, in Abstract console, then Azure.

   Delete the destination in Abstract first. Then delete the data collection rule and endpoint (the resources this deploy created), and the custom table only if you no longer need its data. Last, delete the app registration in Entra if nothing else uses it.

   **Check:** Abstract shows no Sentinel destination, and az ad app show --id &lt;client-id> reports that the app does not exist.

## Send Abstract events to an Event Hub of yours

**Fits when:** Another tool reads from an Event Hub, and Abstract should deliver processed events there.

**Why this way:** A namespace and one hub with a send-only key, so Abstract can write and nothing else.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=1.1). To send someone this plan, share this link.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Set up.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Event Hub destination in a resource group of its own.

   Template: [Abstract to your Event Hub: namespace and hub](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-event-hub)

   **Check:** The namespace is Active, and the eventHubName and sendRuleName outputs are set.

3. **Verify.** Abstract admin, with a Cloud admin to copy the key, in Abstract console, then the Azure portal.

   Add the Azure EventHub Destination in Abstract with the hub name and the send-only connection string, then send a test event. Copy the connection string in the Azure portal (Event Hubs namespace > Settings > Shared access policies > abstract-send > Connection string–primary key) and paste it straight into Abstract; it is a secret, so never print it in a terminal.

   In Abstract, add the **Azure EventHub Destination** integration and fill in:

   - **EventHub Name:** The eventHubName output
   - **EventHub Connection String:** The abstract-send Connection string–primary key, copied in the portal

   **Check:** Incoming Messages on the hub rise when Abstract sends.

4. **Clean up.** Cloud admin, in Abstract console, then Cloud Shell.

   Delete the destination in Abstract first, then the resource group.

   ```bash
   az group delete --name <destination-resource-group>
   ```

   **Check:** The namespace is gone.

## Abstract API access per subscription, by Logic App

**Fits when:** Abstract reads the Microsoft Graph or Microsoft 365 APIs in each subscription, and Policy is not mandated.

**Why this way:** One Logic App with one pre-consented identity creates each subscription's app registration when you onboard it, so there is one identity to audit.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=2.0). To send someone this plan, share this link.

**Not chosen:** The Policy variant: it runs a privileged script inside every subscription.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Set up.** Cloud admin, and a Global Administrator for the one-time consent, in Azure Cloud Shell (Bash).

   First create the managed identity the Logic App runs as and consent its Graph permissions (bootstrap, once per tenant). Then deploy the Logic App with that identity and your central Key Vault, give the identity its roles on the vault and on each target subscription, tag the test subscription abstract-onboard=true (an untagged one is skipped, and the command still exits 0), and onboard it. Repeat the grant, tag and onboard commands for every other subscription, including each new one: nothing onboards a subscription on its own yet.

   > **This changes:** The identity holds Microsoft Graph Application.ReadWrite.All and AppRoleAssignment.ReadWrite.All for the whole tenant: it can grant itself any directory permission, so treat it as tier-0. Every app it creates gets tenant-wide Graph read permissions, and Owner on each target subscription is given to the identity.

   Template: [Abstract access to new subscriptions: app registrations by Logic App](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-access-app-registration-logic-app)

   ```bash
   [ -d ~/abstract-cloud-templates ] || git clone --depth 1 https://github.com/IamABS3C/abstract-cloud-templates ~/abstract-cloud-templates
   cd ~/abstract-cloud-templates/templates/azure/azure-access-app-registration-logic-app
   ./deploy.sh bootstrap -g rg-abstract-automation -l <region>
   ../_modules/deploy-appreg.sh -a DeployB -g rg-abstract-automation -k <key-vault-name>
   ./deploy.sh grant -g rg-abstract-automation -k <key-vault-name> -s <test-subscription-id>
   az tag update --resource-id /subscriptions/<test-subscription-id> --operation Merge --tags abstract-onboard=true
   ./deploy.sh onboard -g rg-abstract-automation -s <test-subscription-id>
   az ad app list --display-name Abstract-<test-subscription-id> --query "[].appId" -o tsv
   ```

   **Check:** onboard prints status onboarded (not skipped-not-tagged), and az ad app list returns one app ID for Abstract-&lt;test-subscription-id>. A consent shortfall returns HTTP 500 with the verified and expected counts and creates no secret.

3. **Verify.** Cloud admin, then Abstract admin, in Azure Cloud Shell, then Abstract console.

   Confirm the test subscription's app registration appears in Entra with its consent complete and its roles only on that subscription. Then add the matching Abstract integration with that app's tenant ID, client ID and secret. Copy the secret in the Azure portal: Key Vault > Secrets > the secret named for the subscription > current version > Show Secret Value, then copy it into Abstract. Never read it with a command that prints it.

   ```bash
   ./deploy.sh verify --app-id <app-id>   # from the template folder you deployed
   az role assignment list --all --assignee <app-id> --query "[].{role:roleDefinitionName, scope:scope}" -o table
   ```

   **Check:** verify reports no missing permissions, and the role list shows Reader and Azure Event Hubs Data Receiver on /subscriptions/&lt;test-subscription-id> only. The Graph permissions are tenant-wide by design.

4. **Clean up.** Cloud admin and Entra admin, in Azure, then Entra admin center.

   Delete the Logic App's resource group, then the app registrations it created (one per subscription) if Abstract no longer uses them, then the managed identity or its Graph permissions.

   **Check:** The workflows are gone and no Abstract app registration remains.

## Abstract API access to every subscription, by Policy

**Fits when:** Abstract reads the Microsoft Graph or Microsoft 365 APIs, and governance requires every control to arrive by Azure Policy.

**Why this way:** Policy cannot create Entra objects, so the assignment runs a deployment script as a pre-consented identity in each subscription.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=2.1). To send someone this plan, share this link.

**Not chosen:** The Logic App: preferred, but not delivered through Policy.

1. **Check first.** Cloud admin, in Azure Cloud Shell (Bash).

   Take stock first. These commands are read-only: who you are signed in as, your management groups and subscriptions, the diagnostic settings and Event Hub namespaces you already have, and whether Entra ID already streams its logs somewhere.

   ```bash
   az account show --query "{tenant:tenantId, user:user.name, subscription:name}" -o table
   az account management-group list --query "[].{name:name, displayName:displayName}" -o table
   az account list --query "[].{name:name, id:id, state:state}" -o table
   az monitor diagnostic-settings subscription list --query "value[].{name:name,hub:eventHubName,cats:logs[?enabled].category}" -o json
   az eventhubs namespace list --query "[].{name:name, group:resourceGroup, sku:sku.name}" -o table
   az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"
   ```

   **Check:** The output names the management group and subscriptions you will cover, and the diagnostic-settings and aadiam lists show any setting that already sends to an Event Hub (a non-empty hub or eventHubName). Note those: Azure allows at most 5 diagnostic settings per subscription, per resource and on the tenant.

2. **Set up.** Cloud admin with rights on the management group, and a Global Administrator for the one-time consent, in Azure Cloud Shell (Bash), then the Azure portal (Deploy to Azure).

   First create the managed identity and consent its Graph permissions (bootstrap, once per tenant). Then assign the Policy report-only (the DeployA command, or Rollout mode "Report only (recommended)" in the portal), check what it reports, and deploy again in the portal with "Enforce — create app registrations". Before remediating, tag each target subscription abstract-onboard=true (untagged ones are skipped), and give both identities their roles: the bootstrap identity runs the script, and the Policy assignment's own identity deploys it, so each needs Owner on every target subscription and Key Vault Secrets Officer on the central vault. Existing subscriptions are onboarded only by the remediate command.

   > **This changes:** The identity holds Microsoft Graph Application.ReadWrite.All and AppRoleAssignment.ReadWrite.All for the whole tenant: it can grant itself any directory permission, so treat it as tier-0. It and the Policy assignment identity each get Owner on every target subscription. With Enforce, each tagged subscription gets an Entra app with a client secret and tenant-wide Graph read permissions.

   Template: [Abstract access to every subscription: app registrations by Policy](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-access-app-registration-management-group-policy)

   ```bash
   [ -d ~/abstract-cloud-templates ] || git clone --depth 1 https://github.com/IamABS3C/abstract-cloud-templates ~/abstract-cloud-templates
   cd ~/abstract-cloud-templates/templates/azure/azure-access-app-registration-management-group-policy
   ./deploy.sh bootstrap -g rg-abstract-automation -l <region>
   ../_modules/deploy-appreg.sh -a DeployA -m <mg-id> -g rg-abstract-automation -k <key-vault-name>
   # read Policy > Compliance, then deploy again in the portal with Enforce. Then, per target subscription:
   az tag update --resource-id /subscriptions/<subscription-id> --operation Merge --tags abstract-onboard=true
   ./deploy.sh grant -g rg-abstract-automation -k <key-vault-name> -s <subscription-id>
   pid=$(az policy assignment show --name abs-appreg --scope /providers/Microsoft.Management/managementGroups/<mg-id> --query identity.principalId -o tsv)
   az role assignment create --assignee-object-id "$pid" --assignee-principal-type ServicePrincipal --role Owner --scope /subscriptions/<subscription-id>
   az role assignment create --assignee-object-id "$pid" --assignee-principal-type ServicePrincipal --role "Key Vault Secrets Officer" --scope "$(az keyvault show -n <key-vault-name> --query id -o tsv)"
   ./deploy.sh remediate -m <mg-id>
   az policy remediation list --management-group <mg-id> --query "[].{name:name, state:provisioningState, ok:deploymentStatus.successfulDeployments, failed:deploymentStatus.failedDeployments}" -o table
   ```

   **Check:** az role assignment list --assignee "$pid" --all --query "[].{role:roleDefinitionName, scope:scope}" -o table shows Owner on every target subscription and Key Vault Secrets Officer on the vault, the remediation task reaches Succeeded with failed 0, and az ad app list --display-name Abstract-&lt;subscription-id> returns an app for each tagged subscription.

3. **Verify.** Cloud admin, then Abstract admin, in Azure Cloud Shell, then Abstract console.

   Confirm the test subscription's app registration appears in Entra with its consent complete and its roles only on that subscription. Then add the matching Abstract integration with that app's tenant ID, client ID and secret. Copy the secret in the Azure portal: Key Vault > Secrets > the secret named for the subscription > current version > Show Secret Value, then copy it into Abstract. Never read it with a command that prints it.

   ```bash
   ./deploy.sh verify --app-id <app-id>   # from the template folder you deployed
   az role assignment list --all --assignee <app-id> --query "[].{role:roleDefinitionName, scope:scope}" -o table
   ```

   **Check:** verify reports no missing permissions, and the role list shows Reader and Azure Event Hubs Data Receiver on /subscriptions/&lt;test-subscription-id> only. The Graph permissions are tenant-wide by design.

4. **Clean up.** Cloud admin and Entra admin, in Cloud Shell, then Entra admin center.

   Delete the Policy assignment first, then the app registrations it created, if Abstract no longer uses them, then the managed identity or its Graph permissions.

   ```bash
   az policy assignment delete --name <assignment-name> --scope /providers/Microsoft.Management/managementGroups/<mg-id>
   ```

   **Check:** The assignment is gone and no Abstract app registration remains.

## Other templates

No plan above needs these on their own.

- [Read access to a Key Vault: one role assignment](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-access-key-vault-secrets-reader): A building block the Sentinel templates call for you. Deploy it alone only to grant one identity read access to an existing Key Vault.

## Not covered yet

- Entra ID logs cannot be set by Policy, and a portal deploy at tenant scope is not proven yet, so that step is CLI only.
- Removing the Policy plan's resource-level diagnostic settings is by hand: Azure keeps them after the assignment is deleted.
- Nothing onboards a new subscription to the Logic App automatically yet. enableEventTrigger only creates the Event Grid system topic; no event subscription is wired, and the workflow's plain HTTP trigger does not answer Event Grid's validation handshake, so onboard each subscription with ./deploy.sh onboard.
- The Abstract field labels come from the Azure EventHub integration 0.7.2. An older version may still ask for the storage fields on Standard tier.
