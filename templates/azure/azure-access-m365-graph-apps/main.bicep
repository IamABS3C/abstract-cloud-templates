// =============================================================================
//  Abstract Security - Microsoft 365 API and Microsoft Graph API app registrations
//
//  The two-app model: one Entra app per integration, each consented only to the
//  API its own integration calls.
//    App 1  Microsoft 365 API integration (microsoft_365_api)
//           Office 365 Management APIs: ActivityFeed.Read, ActivityFeed.ReadDlp
//    App 2  Microsoft Graph API integration (microsoft_graph_api)
//           Microsoft Graph: the application permissions its switches use
//  Separate apps keep each credential to its own API, let each secret rotate on
//  its own schedule, and make Entra sign-in logs name the integration that called.
//
//  Both apps are single tenant. Every permission is an APPLICATION permission and
//  grantAdminConsent (default true) consents to each one, as one app role
//  assignment per permission, on the Microsoft service principal.
//
//  The apps are tenant-wide Entra objects. The deployment needs a resource group
//  only as somewhere to run: nothing is created in it, and deleting it does not
//  delete the apps.
//
//  NO SECRET IS CREATED. The Microsoft Graph Bicep extension cannot create client
//  secrets, and a secret in a deployment output would sit in deployment history.
//  Add one to each app in the Entra admin center (the abstractOnboarding output
//  names the place) and type it straight into Abstract.
//
//  Deploy with Azure CLI or Azure PowerShell: Microsoft Graph Bicep does not
//  compile to plain ARM, so there is no portal button. az deployment group
//  what-if does not show Microsoft Graph resources.
//
//    az deployment group create -g <any resource group> --template-file main.bicep
// =============================================================================
targetScope = 'resourceGroup'

extension microsoftGraphV1

@description('Display name of App 1, the app the Microsoft 365 API integration signs in as.')
param m365AppDisplayName string = 'Abstract - Microsoft 365'

@description('Tenant-wide unique key of App 1 (Microsoft Graph uniqueName). It makes a redeploy update the same app instead of creating another. Immutable once the app exists.')
param m365AppUniqueName string = 'abstract-microsoft-365'

@description('Display name of App 2, the app the Microsoft Graph API integration signs in as.')
param graphAppDisplayName string = 'Abstract - Microsoft Graph'

@description('Tenant-wide unique key of App 2 (Microsoft Graph uniqueName). Immutable once the app exists.')
param graphAppUniqueName string = 'abstract-microsoft-graph'

@description('Office 365 Management APIs application permissions for App 1. ActivityFeed.Read delivers Audit.AzureActiveDirectory, Audit.Exchange, Audit.SharePoint and Audit.General; ActivityFeed.ReadDlp delivers DLP.All, which can include the detected sensitive values.')
@allowed([
  'ActivityFeed.Read'
  'ActivityFeed.ReadDlp'
])
param m365Permissions array = [
  'ActivityFeed.Read'
  'ActivityFeed.ReadDlp'
]

@description('Microsoft Graph application permissions for App 2. The default is every permission a Microsoft Graph API 1.8.3 switch uses. Leave one out only with the switch that needs it, since Abstract checks each switch that is on against the API when the integration is saved.')
@allowed([
  'AuditLog.Read.All'
  'Policy.Read.All'
  'Directory.Read.All'
  'SecurityAlert.Read.All'
  'SecurityIncident.Read.All'
  'DeviceManagementApps.Read.All'
  'DeviceManagementManagedDevices.Read.All'
  'IdentityRiskEvent.Read.All'
  'IdentityRiskyUser.Read.All'
  'ServiceHealth.Read.All'
  'SecurityIdentitiesHealth.Read.All'
  'SecurityEvents.Read.All'
  'Reports.Read.All'
  'AiEnterpriseInteraction.Read.All'
  'User.Read.All'
  'RoleManagement.Read.Directory'
  'Application.Read.All'
  'GroupMember.Read.All'
  'Device.Read.All'
])
param graphPermissions array = [
  'AuditLog.Read.All'
  'Policy.Read.All'
  'Directory.Read.All'
  'SecurityAlert.Read.All'
  'SecurityIncident.Read.All'
  'DeviceManagementApps.Read.All'
  'DeviceManagementManagedDevices.Read.All'
  'IdentityRiskEvent.Read.All'
  'IdentityRiskyUser.Read.All'
  'ServiceHealth.Read.All'
  'SecurityIdentitiesHealth.Read.All'
  'SecurityEvents.Read.All'
  'Reports.Read.All'
  'AiEnterpriseInteraction.Read.All'
  'User.Read.All'
  'RoleManagement.Read.Directory'
  'Application.Read.All'
  'GroupMember.Read.All'
  'Device.Read.All'
]

@description('Grant tenant-wide admin consent to every permission (one app role assignment each). Needs a Privileged Role Administrator or Global Administrator deployer. Off: the apps are created with their permissions listed but not consented; an administrator consents later with the adminConsentUrls output.')
param grantAdminConsent bool = true

var graphAppId = '00000003-0000-0000-c000-000000000000'
var o365ManagementAppId = 'c5393580-f805-4401-95e8-94b7a6ef2fc2' // Office 365 Management APIs

// Role ids by permission value, read from both Microsoft service principals. First-party role ids are the same in
// every tenant. Loaded at compile time so the length of every loop is known when the deployment starts.
var ids = loadJsonContent('../_modules/microsoft-app-permission-ids.json')
var m365RoleIds = [for p in m365Permissions: ids.office365Management[p]]
var graphRoleIds = [for p in graphPermissions: ids.graph[p]]

resource graphSp 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: graphAppId
}

resource o365ManagementSp 'Microsoft.Graph/servicePrincipals@v1.0' existing = {
  appId: o365ManagementAppId
}

// ---------------------------------------------------------------- App 1: Microsoft 365 API
resource m365App 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: m365AppUniqueName
  displayName: m365AppDisplayName
  signInAudience: 'AzureADMyOrg'
  tags: [
    'abstract:microsoft-365-api'
  ]
  requiredResourceAccess: [
    {
      resourceAppId: o365ManagementAppId
      resourceAccess: [for id in m365RoleIds: { id: id, type: 'Role' }]
    }
  ]
}

resource m365AppSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: m365App.appId
}

resource m365Consent 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for id in m365RoleIds: if (grantAdminConsent) {
  appRoleId: id
  principalId: m365AppSp.id
  resourceId: o365ManagementSp.id
}]

// ---------------------------------------------------------------- App 2: Microsoft Graph API
resource graphApp 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: graphAppUniqueName
  displayName: graphAppDisplayName
  signInAudience: 'AzureADMyOrg'
  tags: [
    'abstract:microsoft-graph-api'
  ]
  requiredResourceAccess: [
    {
      resourceAppId: graphAppId
      resourceAccess: [for id in graphRoleIds: { id: id, type: 'Role' }]
    }
  ]
}

resource graphAppSp 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: graphApp.appId
}

resource graphConsent 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for id in graphRoleIds: if (grantAdminConsent) {
  appRoleId: id
  principalId: graphAppSp.id
  resourceId: graphSp.id
}]

// ---------------------------------------------------------------- Outputs: ids and places, never a secret
var secretPlace = 'Entra admin center > App registrations > All applications > {0} > Certificates & secrets > New client secret. Copy the Value straight into the Client Secret field of the Abstract {1} integration; Entra shows it once.'

output tenantId string = tenant().tenantId
output m365ClientId string = m365App.appId
output graphClientId string = graphApp.appId
output m365ServicePrincipalId string = m365AppSp.id
output graphServicePrincipalId string = graphAppSp.id
output grantedM365Permissions array = grantAdminConsent ? m365Permissions : []
output grantedGraphPermissions array = grantAdminConsent ? graphPermissions : []
output adminConsentUrls object = {
  m365: '${environment().authentication.loginEndpoint}${tenant().tenantId}/adminconsent?client_id=${m365App.appId}'
  graph: '${environment().authentication.loginEndpoint}${tenant().tenantId}/adminconsent?client_id=${graphApp.appId}'
}
output abstractOnboarding object = {
  microsoft_365_api: {
    tenantDomain: 'Your initial *.onmicrosoft.com domain: az rest --method get --url https://graph.microsoft.com/v1.0/organization --query "value[0].verifiedDomains[?isInitial].name" -o tsv'
    tenantId: tenant().tenantId
    clientId: m365App.appId
    clientSecret: format(secretPlace, m365AppDisplayName, 'Microsoft 365 API')
  }
  microsoft_graph_api: {
    tenantId: tenant().tenantId
    clientId: graphApp.appId
    clientSecret: format(secretPlace, graphAppDisplayName, 'Microsoft Graph API')
    switches: 'Turn on only the switches whose permissions are in grantedGraphPermissions.'
  }
}
