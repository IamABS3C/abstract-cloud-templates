# Set up Microsoft Azure

<!-- Generated from tools/guides/azure.yml by `python -m tools.templates generate`. Do not edit. -->

Azure cannot send its logs straight to a third party, so every Azure log source goes through an Event Hub in your subscription: Azure writes to the hub, and Abstract reads from it with a listen-only key. You deploy the hub first, point your sources at it, then add one Azure Event Hub integration in Abstract per hub. Sending events the other way, from Abstract into Microsoft Sentinel or an Event Hub of yours, is a separate setup further down the same questions.

Answer the questions below. Each answer leads to the next question or to one plan: the steps in order, from checking what you have to cleaning it all up. The same questions are in the [onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure), which gives each plan a link you can share.

## What do you want to set up?

- **Send Azure logs to Abstract** → [How much of Azure should send logs?](#how-much-of-azure-should-send-logs)
  Activity Log, resource logs and Entra ID sign-in and audit logs, through an Event Hub.
- **Send events from Abstract into Microsoft Sentinel** → [Abstract writes to Sentinel as an Entra app registration. Who creates it?](#abstract-writes-to-sentinel-as-an-entra-app-registration-who-creates-it)
- **Send events from Abstract into an Event Hub of yours** → [Send Abstract events to an Event Hub of yours](#send-abstract-events-to-an-event-hub-of-yours)
- **Give Abstract API access in each subscription, with an app registration** → [Must every control in your estate arrive through Azure Policy?](#must-every-control-in-your-estate-arrive-through-azure-policy)
  For Abstract integrations that read the Microsoft Graph or Microsoft 365 APIs. Event Hub collection needs none of this.

## How much of Azure should send logs?

- **Every subscription under a management group (recommended)** → [Send logs from every Azure subscription, by Policy](#send-logs-from-every-azure-subscription-by-policy)
  Today's subscriptions and every one added later. Best for more than about three subscriptions, or an estate that will grow.
- **One subscription, as a pilot** → [Send the Activity Log from one Azure subscription, as a pilot](#send-the-activity-log-from-one-azure-subscription-as-a-pilot)
  Proves the pipeline. Nothing extends it to other subscriptions.
- **Only Entra ID sign-in and audit logs** → [Send Entra ID sign-in and audit logs only](#send-entra-id-sign-in-and-audit-logs-only)

## Abstract writes to Sentinel as an Entra app registration. Who creates it?

- **I create the app registration myself (recommended for production)** → [Send Abstract events to Microsoft Sentinel, with your app registration](#send-abstract-events-to-microsoft-sentinel-with-your-app-registration)
- **The template creates it, from the Azure CLI** → [Send Abstract events to Sentinel, app created by Graph](#send-abstract-events-to-sentinel-app-created-by-graph)
  Uses Microsoft Graph as you, the person deploying. No standing privileged identity.
- **The template creates it, from the Azure portal** → [Send Abstract events to Sentinel, app created in the portal](#send-abstract-events-to-sentinel-app-created-in-the-portal)
  For portal-only teams and labs. Needs a privileged managed identity you create first.

## Must every control in your estate arrive through Azure Policy?

- **No (most estates)** → [Abstract API access to new subscriptions, by Logic App](#abstract-api-access-to-new-subscriptions-by-logic-app)
  One Logic App creates the app registrations, so there is one identity to audit.
- **Yes, governance requires Azure Policy** → [Abstract API access to every subscription, by Policy](#abstract-api-access-to-every-subscription-by-policy)

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Foundation.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Event Hub first, in a resource group of its own. It creates the namespace, one hub per log source, an abstract consumer group, a listen-only key named abstract-access, and the storage account Abstract keeps its place in.

   Template: [Azure first step: Event Hub that receives all logs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-foundation-event-hub)

   **Check:** The namespace is Active, and each hub has a consumer group named abstract.

3. **Set up.** Cloud admin with rights on the management group, in Azure portal (Deploy to Azure) or Cloud Shell.

   Assign the Policy at the management group, pointing at the Event Hub. Start with enforcementMode DoNotEnforce to see what it would change, then switch it to Default. Existing subscriptions are brought in by a remediation task; new ones join on their own.

   Template: [All Azure logs to Abstract: every subscription by Policy](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-all-logs-management-group-policy)

   **Check:** One assignment per log type exists, each with a managed identity, and the remediation tasks succeed.

4. **Set up (optional).** Cloud admin with an Entra ID role that can manage diagnostic settings, in Cloud Shell.

   Entra ID logs belong to the tenant, not a subscription, so no Policy reaches them. One CLI deploy creates the tenant's diagnostic setting, pointing at the identity hub.

   *Optional:* Recommended. Sign-in and audit logs carry most identity detections. Skip only if they already stream to another Event Hub you will use.

   Template: [Entra ID sign-in and audit logs to Abstract](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-entra-id-logs-tenant)

   **Check:** The setting abstract-entra-logstream exists and points at the identity hub.

5. **Verify.** Abstract admin, in Abstract console, then Azure portal.

   Add one Azure Event Hub integration in Abstract for each hub. The Event Hub deploy's abstractOnboarding output lists every value: namespace, hub, consumer group, storage account and container. It also says where in the portal to copy the two connection strings; paste them straight into Abstract and nowhere else.

   **Check:** Each integration saves without errors.

6. **Verify (optional).** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Add the health alerts, so you hear when Abstract stops reading while logs keep arriving.

   *Optional:* Recommended for production. Event Hubs reports no consumer lag, so without these a stalled feed fails silently.

   Template: [Azure alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-monitoring-event-hub-health-alerts)

   **Check:** The alert rules exist and send to your action group.

7. **Verify.** Cloud admin and Abstract admin, in Azure portal, then Abstract.

   In the namespace's Metrics, Incoming Messages should be non-zero once a source points at the hub, and Outgoing Messages should follow it. In Abstract, the Azure integrations should show events within 15 minutes. Entra ID can take longer when there are few sign-ins.

   **Check:** Outgoing tracks Incoming with no lasting gap, and events appear in Abstract.

8. **Clean up.** Cloud admin, in Abstract console, then Cloud Shell.

   Remove in this order, so nothing keeps sending to a hub that is gone. First delete the integrations in Abstract. Then delete the Policy assignments. Deleting an assignment does NOT remove the diagnostic settings it already deployed, so delete those next: the subscription setting abstract-activity-logs in each subscription, and the resource-level settings named abstract-logstream that the remediation created. If you turned on SQL auditing or Defender for Cloud export, delete those assignments too, and the rg-abstract-defender-export resource group. Then the Entra setting, if you added it. Last, the Event Hub's resource group.

   ```bash
   az policy assignment list --scope /providers/Microsoft.Management/managementGroups/<mg-id> --query "[?starts_with(name, 'abs-')].name" -o tsv
   az policy assignment delete --name <assignment-name> --scope /providers/Microsoft.Management/managementGroups/<mg-id>
   az monitor diagnostic-settings subscription delete --name abstract-activity-logs --subscription <subscription-id> --yes
   az rest --method delete --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings/abstract-entra-logstream?api-version=2017-04-01"
   az group delete --name <event-hub-resource-group>
   ```

   **Check:** The namespace is gone and no diagnostic setting points at it.

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Foundation.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Event Hub first, in a resource group of its own. It creates the namespace, one hub per log source, an abstract consumer group, a listen-only key named abstract-access, and the storage account Abstract keeps its place in.

   Template: [Azure first step: Event Hub that receives all logs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-foundation-event-hub)

   **Check:** The namespace is Active, and each hub has a consumer group named abstract.

3. **Set up.** Cloud admin with Owner or Monitoring Contributor on the subscription, in Azure portal (Deploy to Azure) or Cloud Shell.

   Point this subscription's Activity Log at the Event Hub. Redeploying replaces the setting's category list instead of adding to it, so read the current one first (the check-first commands show it).

   Template: [Activity Log to Abstract: one subscription](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-activity-log-subscription)

   **Check:** The setting abstract-activity-logs exists, pointing at the activity hub.

4. **Set up (optional).** Cloud admin with an Entra ID role that can manage diagnostic settings, in Cloud Shell.

   Entra ID logs belong to the tenant, not a subscription, so no Policy reaches them. One CLI deploy creates the tenant's diagnostic setting, pointing at the identity hub.

   *Optional:* Recommended. Sign-in and audit logs carry most identity detections. Skip only if they already stream to another Event Hub you will use.

   Template: [Entra ID sign-in and audit logs to Abstract](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-entra-id-logs-tenant)

   **Check:** The setting abstract-entra-logstream exists and points at the identity hub.

5. **Verify.** Abstract admin, in Abstract console, then Azure portal.

   Add one Azure Event Hub integration in Abstract for each hub. The Event Hub deploy's abstractOnboarding output lists every value: namespace, hub, consumer group, storage account and container. It also says where in the portal to copy the two connection strings; paste them straight into Abstract and nowhere else.

   **Check:** Each integration saves without errors.

6. **Verify (optional).** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Add the health alerts, so you hear when Abstract stops reading while logs keep arriving.

   *Optional:* Recommended for production. Event Hubs reports no consumer lag, so without these a stalled feed fails silently.

   Template: [Azure alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-monitoring-event-hub-health-alerts)

   **Check:** The alert rules exist and send to your action group.

7. **Verify.** Cloud admin and Abstract admin, in Azure portal, then Abstract.

   In the namespace's Metrics, Incoming Messages should be non-zero once a source points at the hub, and Outgoing Messages should follow it. In Abstract, the Azure integrations should show events within 15 minutes. Entra ID can take longer when there are few sign-ins.

   **Check:** Outgoing tracks Incoming with no lasting gap, and events appear in Abstract.

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Foundation.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Event Hub first, in a resource group of its own. It creates the namespace, one hub per log source, an abstract consumer group, a listen-only key named abstract-access, and the storage account Abstract keeps its place in.

   Template: [Azure first step: Event Hub that receives all logs](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-foundation-event-hub)

   **Check:** The namespace is Active, and each hub has a consumer group named abstract.

3. **Set up.** Cloud admin with an Entra ID role that can manage diagnostic settings, in Cloud Shell.

   Entra ID logs belong to the tenant, so this is one CLI deploy at tenant scope, pointing at the identity hub. It cannot be done by Policy.

   Template: [Entra ID sign-in and audit logs to Abstract](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-source-entra-id-logs-tenant)

   **Check:** The setting abstract-entra-logstream exists and points at the identity hub.

4. **Verify.** Abstract admin, in Abstract console, then Azure portal.

   Add one Azure Event Hub integration in Abstract for each hub. The Event Hub deploy's abstractOnboarding output lists every value: namespace, hub, consumer group, storage account and container. It also says where in the portal to copy the two connection strings; paste them straight into Abstract and nowhere else.

   **Check:** Each integration saves without errors.

5. **Verify (optional).** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Add the health alerts, so you hear when Abstract stops reading while logs keep arriving.

   *Optional:* Recommended for production. Event Hubs reports no consumer lag, so without these a stalled feed fails silently.

   Template: [Azure alerts when the Abstract feed stalls](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-monitoring-event-hub-health-alerts)

   **Check:** The alert rules exist and send to your action group.

6. **Verify.** Cloud admin and Abstract admin, in Azure portal, then Abstract.

   In the namespace's Metrics, Incoming Messages should be non-zero once a source points at the hub, and Outgoing Messages should follow it. In Abstract, the Azure integrations should show events within 15 minutes. Entra ID can take longer when there are few sign-ins.

   **Check:** Outgoing tracks Incoming with no lasting gap, and events appear in Abstract.

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

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=1.0). To send someone this plan, share this link.

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Foundation.** Entra admin, in Entra admin center.

   Create an app registration for Abstract and a client secret. Keep the client ID, tenant ID and secret for the last step; the secret is shown only once.

3. **Set up.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Sentinel destination in the workspace's resource group. For principalId give the app's Enterprise Application object ID, not its client ID (az ad sp show --id <client-id> --query id -o tsv). It creates the data collection endpoint and rule and the custom Abstract table, and grants your app Monitoring Metrics Publisher on the rule.

   Template: [Abstract to Microsoft Sentinel: with your app registration](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel)

   **Check:** The abstractSentinelOnboarding output lists the endpoint, the rule's immutable ID and the stream name.

4. **Set up (optional).** Cloud admin, in Azure portal (Deploy to Azure).

   Install the Abstract content into the same workspace.

   *Optional:* Skip unless you want Abstract's analytics rules, workbooks and hunting queries in a lab or private workspace. It is not the Content Hub solution.

   Template: [Sentinel content for Abstract data: rules and workbooks](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-content-pack)

5. **Verify.** Abstract admin, in Abstract console, then Log Analytics.

   Add the Azure Sentinel destination in Abstract with the app's tenant ID, client ID and secret, and the endpoint, rule ID and stream name from the deploy's outputs. Send a test, then query the custom table in the workspace.

   **Check:** Rows from Abstract appear in the custom table within a few minutes.

6. **Clean up.** Cloud admin and Entra admin, in Abstract console, then Azure.

   Delete the destination in Abstract first. Then delete the data collection rule and endpoint (the resources this deploy created), and the custom table only if you no longer need its data. Last, delete the app registration in Entra if nothing else uses it.

   **Check:** Abstract shows no Sentinel destination, and the app registration is gone.

## Send Abstract events to Sentinel, app created by Graph

**Fits when:** Production, when the template should create the app registration and you deploy from the Azure CLI.

**Why this way:** The app is created as you, through Microsoft Graph, so no standing privileged identity has to exist first.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=1.1). To send someone this plan, share this link.

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Set up.** Cloud admin who can create app registrations, in Cloud Shell.

   Deploy the Graph variant. It creates the app and its service principal, then the same ingestion stack.

   Template: [Abstract to Sentinel: app registration created by Graph](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-app-by-graph)

   **Check:** The outputs list the client ID, tenant ID, endpoint, rule ID and stream name.

3. **Set up (optional).** Cloud admin, in Azure portal (Deploy to Azure).

   Install the Abstract content into the same workspace.

   *Optional:* Skip unless you want Abstract's analytics rules, workbooks and hunting queries in a lab or private workspace. It is not the Content Hub solution.

   Template: [Sentinel content for Abstract data: rules and workbooks](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-content-pack)

4. **Verify.** Abstract admin, in Abstract console, then Log Analytics.

   Add the Azure Sentinel destination in Abstract with the app's tenant ID, client ID and secret, and the endpoint, rule ID and stream name from the deploy's outputs. Send a test, then query the custom table in the workspace.

   **Check:** Rows from Abstract appear in the custom table within a few minutes.

5. **Clean up.** Cloud admin and Entra admin, in Abstract console, then Azure.

   Delete the destination in Abstract first. Then delete the data collection rule and endpoint (the resources this deploy created), and the custom table only if you no longer need its data. Last, delete the app registration in Entra if nothing else uses it.

   **Check:** Abstract shows no Sentinel destination, and the app registration is gone.

## Send Abstract events to Sentinel, app created in the portal

**Fits when:** Portal-only teams and labs.

**Why this way:** A deployment script creates the app and its secret, so the whole setup runs from the portal wizard.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=1.2). To send someone this plan, share this link.

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Set up.** Cloud admin, in Azure portal (Deploy to Azure).

   Create the managed identity the template asks for first, with the Graph permission to create applications. Then deploy. With Key Vault, the secret is stored there and never shown.

   *Note:* Delete or strip that managed identity's Graph permission after the deploy; it can create applications in your tenant.

   Template: [Abstract to Sentinel: app registration created by script](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-app-by-script)

   **Check:** The outputs list the client ID and the Key Vault URI that holds the secret.

3. **Set up (optional).** Cloud admin, in Azure portal (Deploy to Azure).

   Install the Abstract content into the same workspace.

   *Optional:* Skip unless you want Abstract's analytics rules, workbooks and hunting queries in a lab or private workspace. It is not the Content Hub solution.

   Template: [Sentinel content for Abstract data: rules and workbooks](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-sentinel-content-pack)

4. **Verify.** Abstract admin, in Abstract console, then Log Analytics.

   Add the Azure Sentinel destination in Abstract with the app's tenant ID, client ID and secret, and the endpoint, rule ID and stream name from the deploy's outputs. Send a test, then query the custom table in the workspace.

   **Check:** Rows from Abstract appear in the custom table within a few minutes.

5. **Clean up.** Cloud admin and Entra admin, in Abstract console, then Azure.

   Delete the destination in Abstract first. Then delete the data collection rule and endpoint (the resources this deploy created), and the custom table only if you no longer need its data. Last, delete the app registration in Entra if nothing else uses it.

   **Check:** Abstract shows no Sentinel destination, and the app registration is gone.

## Send Abstract events to an Event Hub of yours

**Fits when:** Another tool reads from an Event Hub, and Abstract should deliver processed events there.

**Why this way:** A namespace and one hub with a send-only key, so Abstract can write and nothing else.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=2). To send someone this plan, share this link.

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Set up.** Cloud admin, in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Event Hub destination in a resource group of its own.

   Template: [Abstract to your Event Hub: namespace and hub](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-destination-event-hub)

   **Check:** The namespace is Active and the hub exists.

3. **Verify.** Abstract admin, in Abstract console.

   Add the Azure Event Hub destination in Abstract with the namespace and hub from the outputs, and the send rule's connection string from the portal (Shared access policies). Send a test event.

   **Check:** Incoming Messages on the hub rise when Abstract sends.

4. **Clean up.** Cloud admin, in Abstract console, then Cloud Shell.

   Delete the destination in Abstract first, then the resource group.

   ```bash
   az group delete --name <destination-resource-group>
   ```

   **Check:** The namespace is gone.

## Abstract API access to new subscriptions, by Logic App

**Fits when:** Abstract reads the Microsoft Graph or Microsoft 365 APIs in each subscription, and Policy is not mandated.

**Why this way:** One Logic App with one pre-consented identity creates the app registration when a subscription is created or tagged, so there is one identity to audit.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=3.0). To send someone this plan, share this link.

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Set up.** Cloud admin and Entra admin (for consent), in Azure portal (Deploy to Azure) or Cloud Shell.

   Deploy the Logic App, then grant its identity the Graph permissions the nextSteps output lists.

   Template: [Abstract access to new subscriptions: app registrations by Logic App](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-access-app-registration-logic-app)

3. **Verify.** Cloud admin, then Abstract admin, in Azure portal, then Abstract console.

   Create or tag one test subscription and confirm its app registration appears in Entra. Add the matching Abstract integration with that app's tenant ID, client ID and credential.

   **Check:** The app registration exists with a role on the test subscription only, and the integration saves.

4. **Clean up.** Cloud admin and Entra admin, in Azure, then Entra admin center.

   Delete the Logic App's resource group, then the app registrations it created (one per subscription) if Abstract no longer uses them.

   **Check:** The workflows are gone and no Abstract app registration remains.

## Abstract API access to every subscription, by Policy

**Fits when:** Abstract reads the Microsoft Graph or Microsoft 365 APIs, and governance requires every control to arrive by Azure Policy.

**Why this way:** Policy cannot create Entra objects, so the assignment runs a deployment script as a pre-consented identity in each subscription.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/azure?a=3.1). To send someone this plan, share this link.

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

   **Check:** You know which subscriptions and management groups are in scope, and whether anything already streams to an Event Hub.

2. **Set up.** Cloud admin with rights on the management group, and Entra admin (for consent), in Azure portal (Deploy to Azure) or Cloud Shell.

   Assign the Policy with enforcementMode DoNotEnforce first, check what it reports, then switch it to Default.

   Template: [Abstract access to every subscription: app registrations by Policy](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/azure/azure-access-app-registration-management-group-policy)

   **Check:** The assignment exists with a managed identity.

3. **Verify.** Cloud admin, then Abstract admin, in Azure portal, then Abstract console.

   Create or tag one test subscription and confirm its app registration appears in Entra. Add the matching Abstract integration with that app's tenant ID, client ID and credential.

   **Check:** The app registration exists with a role on the test subscription only, and the integration saves.

4. **Clean up.** Cloud admin and Entra admin, in Cloud Shell, then Entra admin center.

   Delete the Policy assignment first, then the app registrations it created, if Abstract no longer uses them.

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
