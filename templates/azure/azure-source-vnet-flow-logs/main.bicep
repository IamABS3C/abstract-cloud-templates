// =============================================================================
//  Abstract Security - virtual network flow logs to Blob Storage, announced on a queue
//
//  Flow logs never go through an Event Hub. Network Watcher writes each virtual
//  network's flow records to a storage account in the same region; this template
//  builds the rest of the path the Azure Network Flow Log integration
//  (azure_network_flow) reads:
//    1. a storage account kept for flow logs, with a queue (abstract-flowlogs)
//    2. an Event Grid system topic on the account and a subscription that puts one
//       message on the queue for every Blob Created event in the flow log container
//       (Event Grid schema: the integration reads eventType and data.url)
//    3. one virtual network flow log per virtual network in virtualNetworkIds,
//       created in the region's Network Watcher (a module in its resource group)
//  The integration reads the queue, then only the new part of each blob.
//
//  One deployment per region: a flow log's storage account must be in the
//  virtual network's region.
//
//    az deployment group create -g <resource-group in the region> \
//      --template-file main.bicep --parameters virtualNetworkIds='["<vnet-id>"]'
// =============================================================================
targetScope = 'resourceGroup'

@description('Region of the storage account, the Event Grid topic and the flow logs. Must be the region of every virtual network in virtualNetworkIds and of the Network Watcher.')
param location string = resourceGroup().location

@description('Resource IDs of the virtual networks to log, all in this region and this subscription. One flow log is created per network.')
param virtualNetworkIds array

@description('Storage account to create for the flow logs and the queue. Empty generates absflow<hash>. 3-24 lowercase letters and digits, globally unique.')
@maxLength(24)
param storageAccountName string = ''

@description('Queue the Event Grid subscription writes to. Enter it in the Queue Name field of the Abstract integration.')
param queueName string = 'abstract-flowlogs'

@description('Name of the Event Grid system topic on the storage account.')
param systemTopicName string = 'abstract-flowlogs-topic'

@description('Network Watcher of this region. Azure creates NetworkWatcher_<region> in NetworkWatcherRG the first time a virtual network is created in a region.')
param networkWatcherName string = 'NetworkWatcher_${location}'

@description('Resource group of the Network Watcher; the flow logs are created there.')
param networkWatcherResourceGroup string = 'NetworkWatcherRG'

@description('Days Azure keeps flow log files in the storage account (0 keeps them forever). Abstract reads each record within minutes of the write, so this is your own retention, not Abstract\'s.')
@minValue(0)
@maxValue(365)
param retentionDays int = 7

@description('Tags applied to the storage account and the Event Grid topic.')
param tags object = {}

// Network Watcher writes every virtual network flow log to this container; it is created on the first write.
var flowLogContainer = 'insights-logs-flowlogflowevent'
var accountName = empty(storageAccountName) ? take('absflow${uniqueString(resourceGroup().id, location)}', 24) : storageAccountName

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // The integration signs in with the account's connection string, which is a shared key.
    allowSharedKeyAccess: true
  }
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: account
  name: 'default'
}

resource queue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: queueName
}

resource topic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: systemTopicName
  location: location
  tags: tags
  properties: {
    source: account.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource toQueue 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2022-06-15' = {
  parent: topic
  name: queueName
  properties: {
    eventDeliverySchema: 'EventGridSchema'
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/${flowLogContainer}/'
    }
    destination: {
      endpointType: 'StorageQueue'
      properties: {
        resourceId: account.id
        queueName: queue.name
      }
    }
  }
}

module flowLogs 'flowlogs.bicep' = {
  name: 'abstract-vnet-flow-logs'
  scope: resourceGroup(networkWatcherResourceGroup)
  params: {
    location: location
    networkWatcherName: networkWatcherName
    virtualNetworkIds: virtualNetworkIds
    storageId: account.id
    retentionDays: retentionDays
  }
  dependsOn: [
    toQueue
  ]
}

output storageAccountName string = account.name
output containerName string = flowLogContainer
output queueName string = queue.name
output flowLogIds array = flowLogs.outputs.flowLogIds
output abstractOnboarding object = {
  integration: 'Azure Network Flow Log'
  storageAccountConnectionString: 'Portal: Storage accounts > ${account.name} > Security + networking > Access keys > key1 > Connection string. It is a secret: copy it from the portal straight into Abstract.'
  containerName: flowLogContainer
  queueName: queue.name
}
