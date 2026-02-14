// ========================================
// Managed Environment Storage Module
// ========================================

@description('The name of the Container Apps Managed Environment')
param managedEnvironmentName string

@description('The name of the storage')
param storageName string

@description('The name of the storage account')
param storageAccountName string

@description('The storage account key')
@secure()
param storageAccountKey string

@description('The name of the file share')
param shareName string

@description('The access mode for the storage')
@allowed([
  'ReadOnly'
  'ReadWrite'
])
param accessMode string = 'ReadWrite'

resource storage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  name: '${managedEnvironmentName}/${storageName}'
  properties: {
    azureFile: {
      accountName: storageAccountName
      accountKey: storageAccountKey
      shareName: shareName
      accessMode: accessMode
    }
  }
}

output name string = storage.name
output resourceId string = storage.id
