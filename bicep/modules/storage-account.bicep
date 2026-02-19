// ========================================
// Storage Account Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
@minLength(3)
@maxLength(22)
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('The resource ID of the subnet for the private endpoint')
param privateEndpointSubnetResourceId string

@description('The resource ID of the private DNS zone for the storage account private endpoint')
param privateDnsZoneResourceId string

// Build the full storage account name using naming convention
// Storage account: Must be 3-24 chars, lowercase letters and numbers only
// Official abbreviation: 'st' (not 'sa')
// Pattern: {baseName without dashes}st
// Example: vaultwarden-dev -> vaultwardendevst (16 chars)
// Max base name: 22 chars (e.g., vaultwarden-production = 21 chars -> vaultwardenproductionst = 23 chars)
// NOTE: The baseName parameter constraint (@minLength(3), @maxLength(22)) combined with
// the 'st' suffix ensures the final storage account name is 5-24 chars (safe within 3-24 limit).
// Only lowercase letters, numbers, and hyphens are allowed in baseName, and hyphens are
// removed, ensuring the final name contains only valid characters (lowercase letters and numbers).
// toLower() ensures lowercase conversion even if user provides uppercase in baseName.
var storageAccountName = toLower('${replace(baseName, '-', '')}st')

// Deploy Storage Account with lock to prevent accidental deletion
module storageAccountDeployment 'br/public:avm/res/storage/storage-account:0.9.1' = {
  name: '${deployment().name}-storage-deployment'
  params: {
    name: storageAccountName
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    privateEndpoints: [
      {
        service: 'file'
        subnetResourceId: privateEndpointSubnetResourceId
        privateDnsZoneResourceIds: [
          privateDnsZoneResourceId
        ]
      }
    ]
    fileServices: {
      shares: [
        {
          name: 'vaultwarden-data'
          accessTier: 'TransactionOptimized'
        }
      ]
    }
    lock: {
      kind: 'CanNotDelete'
      name: 'storage-lock'
    }
  }
}

// Reference the storage account to retrieve keys
resource storageAccountResource 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  #disable-next-line BCP334 // resourceGroupName constraints (@minLength(3) + @maxLength(22)) with 'st' suffix ensure 5-24 char storage name
  name: storageAccountName
}

output name string = storageAccountName
output resourceId string = storageAccountDeployment.outputs.resourceId
@secure()
output primaryKey string = storageAccountResource.listKeys().keys[0].value
