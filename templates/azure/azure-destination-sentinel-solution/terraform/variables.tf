variable "resource_group_name" {
  type        = string
  description = "The resource group to deploy into. It must already exist. New workspace: it holds the workspace. Existing workspace: it must be the workspace's own resource group. Example: abstract-sentinel."
}

variable "extra_parameters" {
  type        = any
  default     = {}
  description = "Optional. Any parameter of ../azuredeploy.json by its exact name, sent as given and overriding the variable of the same name. Values may mix types. Default: none. Example: { enableAsim = true, asimSchemas = [\"Authentication\"] }."

  validation {
    condition     = can(keys(var.extra_parameters))
    error_message = "extra_parameters must be an object of parameter names, for example { enableAsim = true }."
  }
}

variable "location" {
  type        = string
  default     = ""
  description = "Azure region of a new workspace, and of the Data Collection Endpoint and Rule. Change it only when the resource group's region is not where the data should live; every Abstract resource must sit in the workspace's region, and moving it later means a new workspace. Find it: Azure portal > Resource groups > your group > Overview > Location. Default: the resource group's region. Example: eastus."
}

variable "createWorkspace" {
  type        = bool
  default     = true
  description = "true creates a Log Analytics workspace and switches Microsoft Sentinel on. Set false to use a workspace that already runs Sentinel in this resource group; nothing about that workspace (SKU, retention, daily cap, network) is changed. Find it: Azure portal > Microsoft Sentinel lists every workspace that runs Sentinel, with its resource group. Default: true. Example: false. A new workspace is a new billable resource; pointing Abstract at a second workspace splits your data."
}

variable "workspaceName" {
  type        = string
  default     = ""
  description = "Name of the workspace. New workspace: leave empty to generate abstract-sentinel-<hash>, or give a name of 4 to 63 letters, digits and hyphens. Existing workspace: its exact name, which must be in this resource group, or the deployment fails. Find it: Azure portal > Log Analytics workspaces > Name. Default: empty. Example: sentinel-prod."
}

variable "workspaceRetentionDays" {
  type        = number
  default     = 90
  description = "Interactive retention of a new workspace, 7 to 730 days. Used only when createWorkspace is true; an existing workspace is never changed. Raise it when policy needs searchable data longer. Find the current value: Azure portal > Log Analytics workspaces > the workspace > Usage and estimated costs > Data retention. Default: 90. Example: 180. Microsoft Sentinel includes 90 days; each day above that is billed per GB retained."
}

variable "existingWorkspaceLocation" {
  type        = string
  default     = ""
  description = "Region of the existing workspace, when it differs from location. The Data Collection Endpoint and Rule must be in the workspace's region; a mismatch fails the deployment. Leave empty for a new workspace, or when the workspace is in location. Find it: Azure portal > Log Analytics workspaces > the workspace > Overview > Location. Default: empty. Example: eastus2."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags on every resource the template creates that supports tags. Set them when your policy requires tags such as owner or cost centre; Azure Policy can deny an untagged deployment. Find what is required: Azure portal > Policy > Assignments on this subscription. Default: none. Example: {\"owner\": \"secops\"}."
}

variable "principalId" {
  type        = string
  default     = ""
  description = "Object ID of the service principal Abstract signs in as. It gets Monitoring Metrics Publisher on the Data Collection Rule only, which is all the Logs Ingestion API needs. Find it: Microsoft Entra ID > Enterprise applications > the Abstract app > Overview > Object ID. Not the Application (client) ID, which fails with PrincipalNotFound or grants nothing. Default: empty, which skips the grant: Abstract then gets HTTP 403 until you grant the role yourself. Example: the object ID GUID shown on that page."
}

variable "dataCollectionEndpointName" {
  type        = string
  default     = "abstract-dce"
  description = "Name of the Data Collection Endpoint Abstract sends to. Change it when a resource of that name already exists in the resource group for something else: a same-named endpoint is updated in place. Find existing ones: Azure portal > Monitor > Data Collection Endpoints. Default: abstract-dce. Example: abstract-dce-prod. Its URL is the output dataCollectionEndpointUrl."
}

variable "dataCollectionRuleName" {
  type        = string
  default     = "abstract-dcr"
  description = "Name of the Data Collection Rule. Keep the name across redeploys: the rule then keeps its immutable ID and Abstract keeps sending. A new name creates a second rule with a new ID, which the Abstract destination must then be changed to, and a same-named rule made for something else is replaced. Find existing ones: Azure portal > Monitor > Data Collection Rules. Default: abstract-dcr. Example: abstract-dcr-prod."
}

variable "customTablePlan" {
  type        = string
  default     = "Keep"
  description = "Table plan of AbstractEventLogs_CL. Keep leaves an existing table's plan alone and creates a new table as Analytics, so a redeploy never changes cost by accident. Analytics runs analytics rules and this content; Basic is cheaper with limited queries; Auxiliary is the data lake tier, cheapest, with no analytics rules or alerts on it. A plan set here applies to the whole table. Find the current plan: Log Analytics workspaces > the workspace > Tables > AbstractEventLogs_CL > Plan. Default: Keep. Example: Analytics."
}

variable "customTableRetentionDays" {
  type        = number
  default     = 0
  description = "Total retention of AbstractEventLogs_CL in days, 0 to 4383. 0 sends no retention: an existing table keeps its own, a new one takes the workspace's. Shortening it deletes data older than the new value; lengthening it bills each extra GB-day. Find the current value: Log Analytics workspaces > the workspace > Tables > AbstractEventLogs_CL > Total retention. Default: 0. Example: 365."
}

variable "enableDcrErrorLogs" {
  type        = bool
  default     = true
  description = "Send the Data Collection Rule's ingestion errors (rejected requests, malformed rows, transformation and limit errors) to the DCRLogErrors table. Leave it on: the ingestion API answers 204 before it validates, so without it data Azure drops is invisible to you and to Abstract. Turn it off only if another diagnostic setting already collects these errors. Where it lands: Logs > DCRLogErrors. Default: true. Example: true. Cost: only the error rows."
}

variable "enableAsim" {
  type        = bool
  default     = false
  description = "Also write each event into the Microsoft ASim table for its schema (ASimAuthenticationEventLogs, ASimNetworkSessionLogs and the others in asimSchemas), mapped from the Abstract Common Schema. Turn it on so Microsoft's ASIM analytics rules, hunting queries and workbooks see Abstract data. Expect new alerts, and duplicates where a Microsoft connector already collects the same vendor. Without excludeAsimFromAbstractTable each mapped event is stored and billed twice. Needs Microsoft Sentinel on the workspace. Find the tables: Logs > Tables > ASim*. Default: false. Example: true."
}

variable "asimSchemas" {
  type        = list(string)
  default     = ["*"]
  description = "ASIM schemas to write when enableAsim is on: ['*'] for all eight (AuditEvent, Authentication, Dns, FileEvent, NetworkSession, ProcessEvent, RegistryEvent, WebSession), or a list of names. Narrow it to bring ASIM in one schema at a time. Each schema is one dataflow of the 20 a rule allows. Default: ['*']. Example: ['Authentication', 'NetworkSession']."
}

variable "excludeAsimFromAbstractTable" {
  type        = bool
  default     = false
  description = "Store once. With enableAsim on, an event an ASIM dataflow takes is not also written to AbstractEventLogs_CL, so it is stored and billed once, in its ASim table. Turn it on once your content reads the ASim tables; this solution's rules and parser already do. Content of your own that reads only AbstractEventLogs_CL stops seeing those events. Default: false. Example: true."
}

variable "lakeTableName" {
  type        = string
  default     = ""
  description = "Name of a second custom table on the Auxiliary (data lake) plan, for events nothing in Sentinel needs to alert on. Set it with lakeCategories to cut cost: lake rows cost about 0.15 USD per GB at eastus list price against about 4.30 in the Analytics tier, but analytics rules, ASIM parsers and this content do not run on them, and the /query API returns no rows for them (use the /search API or a KQL job). Must end in _CL. Default: empty, lake route off. Example: AbstractLake_CL."
}

variable "lakeCategories" {
  type        = list(string)
  default     = []
  description = "Abstract Common Schema event categories sent to the lake table instead of AbstractEventLogs_CL. An event matches when its event.category contains one of them. Events an ASIM dataflow takes never go to the lake. Find the categories in your data: in Abstract, the event.category field of the events you route. Default: empty, lake route off. Example: ['network', 'dns']."
}

variable "lakeRetentionDays" {
  type        = number
  default     = 365
  description = "Total retention of the lake table in days, 30 to 4383. Used only when the lake route is on. Lake retention is billed per GB-month at the data lake rate. Default: 365. Example: 730."
}

variable "nativeVendors" {
  type        = list(string)
  default     = []
  description = "Vendors and Microsoft tables the rule also writes to, one dataflow each of the 20 a rule allows, so Microsoft's own Content hub content works unchanged on Abstract-delivered data. Supported: okta (OktaV2_CL, created if missing), crowdstrike-hosts (CrowdStrikeHostsV2_CL, created if missing), csl-cef (CEF lines into CommonSecurityLog), csl-acs (Cisco ASA, Fortinet FortiGate and F5 ASM into CommonSecurityLog), syslog (Linux, Nutanix and Infoblox lines into Syslog), aws-cloudtrail (AWSCloudTrail), and the ASIM schemas asim-alert (Abstract findings into ASimAlertEventLogs), asim-dhcp (ASimDhcpEventLogs) and asim-user-management (ASimUserManagementActivityLogs). Use a vendor entry instead of, not as well as, Microsoft's own connector for that vendor, or every event arrives twice. When two entries select the same event it goes to one table only, the first in this order: asim-alert, okta, crowdstrike-hosts, aws-cloudtrail, csl-cef, csl-acs, syslog, asim-dhcp, asim-user-management. So Infoblox DHCP lines stay in Syslog, and CloudTrail and Okta user changes stay in AWSCloudTrail and OktaV2_CL. An unsupported name stops the deployment before any change. Default: none. Example: ['okta', 'csl-cef']."
}

variable "oktaDomain" {
  type        = string
  default     = ""
  description = "Your Okta org domain, written to the DomainName column of OktaV2_CL as Microsoft's own Okta connector does. Used only with okta in nativeVendors. Microsoft's Okta content does not filter on it, so empty works, but the column is then empty. Quotes, spaces, backslashes, | and ; stop the deployment. Find it: the address you sign in to Okta with, without https://. Default: empty. Example: example.okta.com."
}

variable "excludeNativeVendorsFromAsim" {
  type        = bool
  default     = true
  description = "Stores each vendor event in one place. With a vendor in nativeVendors, an event that vendor's table takes is not also written to the ASim tables or the lake, and, with excludeAsimFromAbstractTable on, not to AbstractEventLogs_CL either. Without it the same Okta event lands in both ASimAuditEventLogs and OktaV2_CL and is billed twice. Turn it off only if you need that vendor in Microsoft's ASIM content as well as in the vendor's own solution. With it on, this solution's two analytics rules, the connector tile and ASim_AbstractEvent read that vendor's table, so they still see its events, but Microsoft's own ASIM rules and parsers do not. Find what a vendor lane takes: Logs, then query the vendor table, for example OktaV2_CL. Default: true. Example: true."
}

variable "deployDataConnectors" {
  type        = bool
  default     = true
  description = "Install the data connector tile Abstract Security (Security Data Pipeline). Its status counts Abstract rows in AbstractEventLogs_CL and the ASim tables. Turn it off only if you do not want the tile. Find it after deployment: Microsoft Sentinel > Data connectors. Default: true. Example: true. No ingestion cost."
}

variable "deployParsers" {
  type        = bool
  default     = true
  description = "Install the workspace function ASim_AbstractEvent, which reads every Abstract event wherever the routes stored it and gives it ASIM column names. The hunting queries and the Pipeline Overview and Value & ROI workbooks read it, so turning it off breaks them. Find it after deployment: Logs > Functions > ASim_AbstractEvent. Default: true. Example: true."
}

variable "deployAnalyticsRules" {
  type        = bool
  default     = true
  description = "Install the analytics rules Abstract Security - Finding, Abstract Security - High or Critical event and Abstract - Repeated auth failures followed by success. Each is on or off as enabledAnalyticsRules says. They read the tables directly and call no workspace function. Find them: Microsoft Sentinel > Analytics. Default: true. Example: true."
}

variable "enabledAnalyticsRules" {
  type        = list(string)
  default     = []
  description = "The analytics rules to turn on: finding (one incident per Abstract finding), high-or-critical (high or critical Abstract events) and repeated-auth-failures (failed sign-ins followed by a success). Every deployment sets each rule on or off from this list, so choose the rules here rather than in Microsoft Sentinel > Analytics, or the next deployment turns them off. An enabled rule runs every hour and can create incidents. Default: none. Example: ['finding']."
}

variable "deployHuntingQueries" {
  type        = bool
  default     = true
  description = "Install the hunting queries Rare or newly-seen product activity, High cumulative-risk identities and Daily value & reduction summary. Find them: Microsoft Sentinel > Hunting > Queries. Default: true. Example: true. They run only when someone runs them."
}

variable "deployWorkbooks" {
  type        = bool
  default     = true
  description = "Install the workbooks Pipeline Overview, Value & ROI, Data Health and Cost by Table (the Sentinel Discovery workbook has its own switch). Find them: Microsoft Sentinel > Workbooks > My workbooks. Default: true. Example: true. They query only when opened."
}

variable "deployDiscovery" {
  type        = bool
  default     = false
  description = "Also run the Sentinel discovery inventory against this workspace (template azure-destination-sentinel-discovery as a module): a managed identity with read-only roles, a storage account for the report, and two short deployment scripts. Off by default because it adds roles and runs for 5 to 15 minutes. Find the output: the storage account in this resource group, container sentinel-discovery. Default: false. Example: false."
}

variable "deployDiscoveryWorkbook" {
  type        = bool
  default     = true
  description = "Install the Sentinel Discovery workbook, which inventories the workspace (tables, connectors, rules, cost). Find it: Microsoft Sentinel > Workbooks > My workbooks. Default: true. Example: true."
}

variable "deployAutomationRules" {
  type        = bool
  default     = true
  description = "Install the automation rule Tag & prioritize Abstract-originated incidents, which labels incidents from this solution's rules. It is on or off as enableAutomationRules says. Find it: Microsoft Sentinel > Automation. Default: true. Example: true."
}

variable "enableAutomationRules" {
  type        = bool
  default     = false
  description = "Turn on the automation rules this deployment installs: Tag & prioritize Abstract-originated incidents and, with deployPlaybookAutomationRules, Run ASTRO Verdict and Tune at source. Every deployment sets them on or off from this value, so set it here rather than in Microsoft Sentinel > Automation, or the next deployment turns them off. Default: false. Example: true."
}

variable "deployPlaybooks" {
  type        = bool
  default     = true
  description = "Install the playbooks Abstract-Enrich-Incident, Abstract-Verdict and Abstract-Tune-At-Source (Logic Apps with a Sentinel API connection). They call the Abstract API with the key in keyVaultSecretUri. After deployment grant each playbook's managed identity Key Vault Secrets User on that secret and Microsoft Sentinel Responder on the workspace, or runs fail. Find them: Microsoft Sentinel > Automation > Active playbooks. Default: true. Example: true. Logic App runs are billed per action."
}

variable "deployPlaybookAutomationRules" {
  type        = bool
  default     = false
  description = "Install the automation rules Run ASTRO Verdict and Tune at source, which run two of the playbooks (on or off as enableAutomationRules says). Needs deployPlaybooks, and Microsoft Sentinel Automation Contributor on this resource group granted to Azure Security Insights (app id 98785600-1bb7-4fb9-b9fa-19afe2c8a360) about 10 minutes before the deployment; without it the deployment fails with \"Missing required permissions for Microsoft Sentinel on the playbook resource\". Find the grant: Resource groups > this group > Access control (IAM) > Role assignments. Default: false. Example: true."
}

variable "abstractBaseUrl" {
  type        = string
  default     = "https://api.abstractsecurity.app"
  description = "Abstract API base URL the playbooks call. Change it only for a non-production Abstract environment. Find it: the address of your Abstract API, as given by Abstract. Default: https://api.abstractsecurity.app. Example: https://api.abstractsecurity.app."
}

variable "abstractVendorAccountId" {
  type        = string
  default     = ""
  description = "Abstract vendor account ID the playbooks send as x-as-vendor-account-id, which selects your tenant in Abstract. Find it: in Abstract, your account settings, or ask Abstract. Default: empty, to set later in each playbook's parameters; until then the playbooks' Abstract calls fail. Example: AbCdEf1234."
}

variable "keyVaultSecretUri" {
  type        = string
  default     = ""
  description = "URI of the Key Vault secret holding the Abstract API key. The playbooks read it at run time, so the key is never stored in the deployment or its history. Find it: Key vaults > the vault > Secrets > the secret > Secret Identifier. Default: empty, to set later; until then the playbooks' Abstract calls fail. Example: https://myvault.vault.azure.net/secrets/abstract-api-key."
}

variable "lookbackHours" {
  type        = number
  default     = 24
  description = "How many hours of Abstract data the Abstract-Enrich-Incident playbook reads around an incident. Raise it for slow-moving investigations; a longer window makes each run slower. Default: 24. Example: 72."
}
