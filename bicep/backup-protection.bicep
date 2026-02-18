// ========================================
// Backup Protection Module for Azure File Share
// ========================================

@description('Name of the Recovery Services Vault')
param vaultName string

@description('Name of the resource group containing the storage account')
param resourceGroupName string

@description('Name of the storage account to register')
param storageAccountName string

@description('Resource ID of the storage account')
param storageAccountResourceId string

// Variables for backup configuration
var backupFabric = 'Azure'
var backupManagementType = 'AzureStorage'

// Register the storage account with the Recovery Services Vault as a protection container
resource protectionContainer 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers@2023-01-01' = {
  name: '${vaultName}/${backupFabric}/storagecontainer;Storage;${resourceGroupName};${storageAccountName}'
  properties: {
    backupManagementType: backupManagementType
    containerType: 'StorageContainer'
    sourceResourceId: storageAccountResourceId
  }
}

// Enable backup protection for the vaultwarden-data file share
resource protectedItem 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-01-01' = {
  parent: protectionContainer
  name: 'AzureFileShare;vaultwarden-data'
  properties: {
    protectedItemType: 'AzureFileShareProtectedItem'
    sourceResourceId: storageAccountResourceId
    policyId: resourceId('Microsoft.RecoveryServices/vaults/backupPolicies', vaultName, 'vaultwarden-daily-backup-policy')
  }
}
