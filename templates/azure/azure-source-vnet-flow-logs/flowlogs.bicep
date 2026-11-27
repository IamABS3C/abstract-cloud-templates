// One virtual network flow log per network, in the region's Network Watcher. Called by main.bicep with the
// Network Watcher's resource group as its scope.
targetScope = 'resourceGroup'

param location string
param networkWatcherName string
param virtualNetworkIds array
param storageId string
param retentionDays int

resource watcher 'Microsoft.Network/networkWatchers@2024-05-01' existing = {
  name: networkWatcherName
}

resource flowLog 'Microsoft.Network/networkWatchers/flowLogs@2024-05-01' = [for id in virtualNetworkIds: {
  parent: watcher
  name: take('abstract-${last(split(id, '/'))}', 80)
  location: location
  properties: {
    targetResourceId: id
    storageId: storageId
    enabled: true
    format: {
      type: 'JSON'
      version: 2
    }
    retentionPolicy: {
      days: retentionDays
      enabled: retentionDays > 0
    }
  }
}]

output flowLogIds array = [for (id, i) in virtualNetworkIds: flowLog[i].id]
