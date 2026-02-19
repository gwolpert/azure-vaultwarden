// ========================================
// Backup Protection Module for Azure File Share
// ========================================

@description('Name of the Recovery Services Vault')
param vaultName string

@description('Name of the resource group containing the storage account')
param resourceGroupName string

@description('Name of the storage account to register')
param storageAccountName string

@description('Fully qualified resource ID of the storage account')
param storageAccountResourceId string

@description('Name of the file share to protect')
param fileShareName string

// Variables for backup configuration
var backupFabric = 'Azure'
var backupManagementType = 'AzureStorage'
// Use the fully qualified resource ID passed from the storage account module
var storageAccountId = storageAccountResourceId
var fileShareResourceId = '${storageAccountId}/fileServices/default/shares/${fileShareName}'

// Register the storage account with the Recovery Services Vault as a protection container
resource protectionContainer 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers@2023-01-01' = {
  name: '${vaultName}/${backupFabric}/storagecontainer;Storage;${resourceGroupName};${storageAccountName}'
  properties: {
    backupManagementType: backupManagementType
    containerType: 'StorageContainer'
    sourceResourceId: storageAccountId
  }
}

// Enable backup protection for the file share
resource protectedItem 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-01-01' = {
  parent: protectionContainer
  name: 'AzureFileShare;${fileShareName}'
  properties: {
    protectedItemType: 'AzureFileShareProtectedItem'
    sourceResourceId: fileShareResourceId
    policyId: '${resourceId('Microsoft.RecoveryServices/vaults', vaultName)}/backupPolicies/vaultwarden-daily-backup-policy'
  }
}
