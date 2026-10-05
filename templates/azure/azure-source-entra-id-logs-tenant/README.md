# Entra ID logs

<!-- Generated from template.yml by `python -m tools.templates generate`. Do not edit. -->

Entra ID activity logs are a single tenant-level diagnostic setting on the microsoft.aadiam provider, not Azure Monitor resource logs. Azure Policy cannot manage them, and a portal deployment at tenant scope is still pending proof, so for now one CLI command onboards identity telemetry for the whole organisation.

**Cloud:** azure · **Role:** source · **Scope:** tenant

## When to use

Always, and early: sign-in and audit logs carry the identity detections customers care about.

**Not for:** Microsoft Graph API or Microsoft 365 unified-audit collection, which are API-pull integrations behind an app registration and use no Event Hub.

## Deploy

From a shell, in this folder:

```bash
./deploy.sh
```

## Prerequisites

- The Event Hub namespace exists in the same Entra tenant as the logs
- Entra ID P1 or P2 for ProvisioningLogs and MicrosoftGraphActivityLogs, P2 for the ID Protection risk categories; AuditLogs and SignInLogs are available on Free
- At most 5 diagnostic settings on the tenant, including existing exports
- Expect 24 hours to 3 days before first data; there is no backfill
- A redeploy replaces the named diagnostic setting's category list rather than merging it; read it back first: az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"

## Cost

The setting is free; volume into the hub is the charge. MicrosoftGraphActivityLogs grows steeply with user count and can dominate a namespace, so size for it deliberately.

## Parameters

| Name | Type | Required | Description | Find it |
|---|---|---|---|---|
| `settingName` | string | no | Name of the Entra ID diagnostic setting. Multiple settings are allowed, so this can sit alongside a setting you already send to another SIEM. |  |
| `eventHubAuthorizationRuleId` | string | yes | Resource ID of an Event Hubs namespace authorization rule with Send rights. Use the abstractDiagnosticsAuthRuleId output of main.bicep. Find it with: az eventhubs namespace authorization-rule list -g RESOURCE_GROUP --namespace-name NAMESPACE --query [].id -o tsv | `az eventhubs namespace authorization-rule list -g <resource-group> --namespace-name <namespace> --query "[?name=='abstract-diagnostics-send'].id" -o tsv` |
| `eventHubName` | string | no | Event Hub that receives the Entra ID stream. Give identity its own hub so it can be partitioned and scaled independently of resource logs. | `az eventhubs eventhub list -g <resource-group> --namespace-name <namespace> --query [].name -o tsv` |
| `entraLogCategories` | array | no | Entra ID log categories to stream. Defaults to the security-relevant set that every Abstract Entra detection is built on. Licensing / availability notes (revised 2026-08-26 against Microsoft's own licensing table - the previous note overstated the P1 requirement): AuditLogs, SignInLogs - available on Entra ID FREE. Microsoft's monitoring-and-health licensing table lists both as "Yes" for Free and for P1/P2. NonInteractiveUserSignInLogs, ServicePrincipalSignInLogs, ManagedIdentitySignInLogs - NO documented P1/P2 requirement exists for these as diagnostic-setting EXPORT categories. All 80 files in Microsoft's identity/monitoring-health docs were checked. The real P1/P2 gate people are thinking of is on DOWNLOADING sign-in logs via the Microsoft Graph API, which is a different operation. Treat a P1 claim here as unverified. ProvisioningLogs - P1/P2 (Free = "No" in the licensing table), and only populated when you provision via Entra MicrosoftGraphActivityLogs - P1/P2, explicitly stated RiskyUsers, UserRiskEvents, RiskyServicePrincipals, ServicePrincipalRiskEvents, RiskyAgents, AgentRiskEvents - Entra ID Protection (P2) ADFSSignInLogs - only when AD FS is in use NetworkAccessTrafficLogs, EnrichedOffice365AuditLogs, RemoteNetworkHealthLogs - only with Global Secure Access / Entra Internet Access + Private Access MicrosoftGraphActivityLogs - high volume; the single best source for "what did this token actually do". At 100k users Microsoft publishes ~1,000 GiB/month and ~4.8M Event Hubs messages/month. Size for it. MicrosoftServicePrincipalSignInLogs - preview, VERY high volume, first-party service-to-service. Microsoft advises against acting on it. Off by default here. CustomSecurityAttributeAuditLogs - needs Attribute Log Administrator, and Microsoft recommends keeping it separate from the directory audit stream. B2CRequestLogs - Azure AD B2C tenants only. Selecting a category your tenant does not license or use is harmless - it simply produces no records. Note the corollary, which is a silent-failure shape: a category can be selectable and emit nothing forever because the underlying PRODUCT is not in use (NetworkAccessTrafficLogs without Global Secure Access is the common case), and that is indistinguishable from a broken pipeline unless you know to expect it. Volume: Microsoft states non-interactive and service-principal sign-ins "can be 5 to 10 times larger than the interactive user sign-ins". Per-event sizes are ~2 KB for audit and ~11.5 KB for sign-ins; a 100,000-user tenant runs about 1.5 million events per day. |  |

## Permissions

- **Security Administrator (Entra directory role, not Azure RBAC)** on The Entra tenant: Deployer: Create or edit the tenant diagnostic setting; subscription or management-group ownership does not grant it.
- **Attribute Log Administrator (Entra directory role)** on The Entra tenant: Deployer: Only for CustomSecurityAttributeAuditLogs.
- **listKeys on the Event Hub authorization rule** on The Event Hubs namespace: Deployer: Creating a setting that streams to an Event Hub requires ListKey on the target rule.
- **Send on the Event Hub authorization rule** on The namespace or the hub: Azure Monitor: The streaming mechanism writes with the key of the referenced rule.

## Creates

- One tenant-level Entra ID diagnostic setting (default name abstract-entra-logstream) streaming the chosen categories to the identity hub

## Never touches

- The Event Hub and its authorization rule, which must already exist
- Other Entra ID diagnostic settings with different names, such as one sending to another SIEM
- Azure Monitor resource logs and subscription Activity Log settings
- Conditional Access, users, groups and every other Entra ID configuration

## Outputs

- `diagnosticSettingName`
- `eventHubName`
- `streamedCategories`
- `abstractOnboarding`

## Verify

| Check | Command | Healthy when |
|---|---|---|
| The diagnostic setting exists and lists the expected categories | `az rest --method get --url "https://management.azure.com/providers/microsoft.aadiam/diagnosticSettings?api-version=2017-04-01"` | The named setting is present with the intended category list and the correct hub. |
| Messages are arriving on the identity hub specifically |  | Incoming Messages non-zero on the identity hub; zero for under 24 hours is expected. |
| Sign-in events parse as Entra events, not generic Activity Log |  | A sampled sign-in event has user, IP and result populated. |
