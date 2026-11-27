Abstract Security for Microsoft Sentinel
========================================

This solution includes material derived from Microsoft Azure Sentinel content.

content/native-vendors.json, vendor "okta":
  The Data Collection Rule transformation that maps an Okta System Log record into the
  OktaV2_CL table, and the OktaV2_CL table schema, are copied unchanged from Microsoft's
  "Okta Single Sign-On" solution in the Azure/Azure-Sentinel repository, at commit
  f6cc4352c34b84d781735967808cfc953376e7f2:
    Solutions/Okta Single Sign-On/Data Connectors/OktaNativePollerConnectorV2/OktaSSOv2_DCR.json
    Solutions/Okta Single Sign-On/Data Connectors/OktaNativePollerConnectorV2/OktaSSOv2_Tables.json
  Abstract added a prefix that selects Okta events from the Abstract stream and unpacks
  event.original into the columns of Microsoft's input stream, and pointed Microsoft's one
  reference to `source` at that prefix.

content/native-lanes.generated.json, lane "crowdstrike-hosts":
  The Data Collection Rule transformation that maps a CrowdStrike Hosts record into the
  CrowdStrikeHostsV2_CL table, and the CrowdStrikeHostsV2_CL table schema, are copied unchanged
  from Microsoft's "CrowdStrike Falcon Endpoint Protection" solution in the Azure/Azure-Sentinel
  repository, at commit c0c2dc267d7b5840299e76e195b0407f3f9c92c8:
    Solutions/CrowdStrike Falcon Endpoint Protection/Data Connectors/CrowdStrikeAPI_ccp/CrowdStrikeAPI_DCR.json
    Solutions/CrowdStrike Falcon Endpoint Protection/Data Connectors/CrowdStrikeAPI_ccp/CrowdStrikeAPI_CrowdStrikeHostsV2_table.json
  Abstract added a prefix that selects CrowdStrike host records from the Abstract stream and
  unpacks event.original into the columns of Microsoft's input stream, and pointed Microsoft's
  one reference to `source` at that prefix.

content/native-lanes.generated.json, lane "csl-cef":
  The mapping of CEF keys to CommonSecurityLog columns is from Microsoft's published page
  https://learn.microsoft.com/en-us/azure/sentinel/cef-name-mapping (retrieved 2026-11-08).

content/native-lanes.generated.json, lanes "crowdstrike-fdr-audit", "-file", "-network", "-process", "-auth", "-dns",
"-registry" and "-user":
  The Data Collection Rule transformations that map CrowdStrike Falcon Data Replicator events into
  the eight ASim tables, and the routing of each event_simpleName to one of them, are copied unchanged
  from Microsoft's "CrowdStrike Falcon Endpoint Protection" solution in the Azure/Azure-Sentinel
  repository, at commit 3aadb1e4e481e2254fec50259123955ed04ded96:
    Solutions/CrowdStrike Falcon Endpoint Protection/Data Connectors/CrowdstrikeReplicatorCLv2/CSFDRv2_Deploymnet/azuredeploy_cdfdrv2_connector.json
    Solutions/CrowdStrike Falcon Endpoint Protection/Data Connectors/CrowdstrikeReplicatorCLv2/CrowdstrikeFalconAPISentinelConn/QueueTriggerCS/EventsToTableMapping.json
  Abstract added a prefix that selects the FDR events routed to each table and unpacks
  event.original into the columns of Microsoft's input stream (AdditionalFields carries the whole
  record), and pointed Microsoft's one reference to `source` at that prefix.

content/native-lanes.generated.json, lane "aws-vpcflow":
  The Data Collection Rule transformation that maps a VPC Flow Logs record into AWSVPCFlow is copied
  unchanged from Microsoft's "AWS VPC Flow Logs" solution in the Azure/Azure-Sentinel repository, at
  commit 3aadb1e4e481e2254fec50259123955ed04ded96:
    Solutions/AWS VPC Flow Logs/Data Connectors/AWSVPCFlowLogs_CCP/AWSVPCFlowLogs_DCR.json
  Abstract added a prefix that splits the version 2 flow log line in event.original into the
  columns of Microsoft's input stream by position.

content/native-lanes.generated.json, lanes "cisco-umbrella-web", "cisco-umbrella-dns" and
"cisco-umbrella-firewall":
  The Data Collection Rule transformations that map Cisco Umbrella web, DNS and cloud firewall
  records into CiscoUmbrellaWebTraffic_CL, CiscoUmbrellaDNS_CL and CiscoUmbrellaCloudFirewall_CL,
  and those table schemas, are copied unchanged from Microsoft's "CiscoUmbrella" solution in the
  Azure/Azure-Sentinel repository, at commit 3aadb1e4e481e2254fec50259123955ed04ded96:
    Solutions/CiscoUmbrella/Data Connectors/CiscoUmbrella_CCP/CiscoUmbrella_DCR.json
    Solutions/CiscoUmbrella/Data Connectors/CiscoUmbrella_CCP/CiscoUmbrellaWebTraffic_table.json
    Solutions/CiscoUmbrella/Data Connectors/CiscoUmbrella_CCP/CiscoUmbrellaDNS_table.json
    Solutions/CiscoUmbrella/Data Connectors/CiscoUmbrella_CCP/CiscoUmbrellaCloudFirewall_table.json
  Abstract added a prefix that takes the quoted fields of the CSV line in event.original, in
  order, into the columns of Microsoft's input stream.

That material is licensed under the MIT License:

    MIT License

    Copyright (c) Microsoft Corporation. All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE

Trademarks
----------
Microsoft, Azure, Microsoft Defender, Microsoft Entra and Microsoft Sentinel are trademarks of the Microsoft group of companies. Okta and CrowdStrike are trademarks of their respective owners.
