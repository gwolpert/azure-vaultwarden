// ========================================
// Main Bicep Template for Vaultwarden on Azure App Service
// ========================================

targetScope = 'subscription'

// Parameters
@description('The name of the resource group (without -rg suffix). Must be lowercase letters, numbers, and hyphens only. Min 3 characters, max 22 characters. Must contain at least 1 alphanumeric character. The value is used to build the storage account name as {resourceGroupName without dashes}st (e.g., "vaultwarden-dev" becomes "vaultwardendevst"), resulting in a 5-24 character storage account name.')
@minLength(3)
@maxLength(22)
param resourceGroupName string = 'vaultwarden-dev'

@description('The Azure region where resources will be deployed')
param location string = 'eastus'

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environmentName string = 'dev'

@description('The domain name for Vaultwarden (e.g., https://vault.example.com)')
param domainName string = ''

@description('Admin token for Vaultwarden admin panel (leave empty to disable admin panel)')
@secure()
param adminToken string = ''

@description('Allow new user signups')
param signupsAllowed bool = false

@description('Vaultwarden container image tag')
param vaultwardenImageTag string = 'latest'

@description('App Service Plan SKU (default: B1 for cost-effectiveness with VNet support. Options: B1, B2, B3, S1, S2, S3, P1v3, P2v3, P3v3)')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v3'
  'P2v3'
  'P3v3'
])
param appServicePlanSkuName string = 'B1'

// Variables
var resourceGroupNameWithSuffix = '${resourceGroupName}-rg'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupNameWithSuffix
  location: location
  tags: {
    Application: 'Vaultwarden'
    Environment: environmentName
    ManagedBy: 'Bicep'
  }
}

// Deploy Virtual Network with subnet for App Service VNet Integration
module vnet 'modules/vnet.bicep' = {
  scope: rg
  name: 'vnet-deployment'
  params: {
    baseName: resourceGroupName
    location: location
  }
}

// Deploy Storage Account with lock to prevent accidental deletion
module storageAccount 'modules/storage-account.bicep' = {
  scope: rg
  name: 'storage-deployment'
  params: {
    baseName: resourceGroupName
    location: location
    subnetResourceId: vnet.outputs.subnetResourceIds[0]
  }
}

// Deploy Recovery Services Vault for backup
module recoveryServicesVault 'modules/recovery-vault.bicep' = {
  scope: rg
  name: 'recovery-vault-deployment'
  params: {
    baseName: resourceGroupName
    location: location
  }
  dependsOn: [
    storageAccount
  ]
}

// Note: File share backup protection must be configured post-deployment using Azure CLI or Portal
// This is because the backup protection container registration requires the storage account to be
// fully provisioned and accessible, which is better handled as a post-deployment step.
//
// When using GitHub Actions, backup protection is automatically enabled as part of the workflow.
//
// For manual deployments, use the provided script:
//    ./enable-backup-protection.sh \
//      {resourceGroupName}-rg \
//      {storageAccountName} \
//      {resourceGroupName}-rsv \
//      vaultwarden-data
//
// Or use Azure CLI commands directly:
//
// 1. Register the storage account with the Recovery Services Vault:
//    az backup container register \
//      --resource-group {resourceGroupName}-rg \
//      --vault-name {resourceGroupName}-rsv \
//      --backup-management-type AzureStorage \
//      --workload-type AzureFileShare \
//      --storage-account /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}-rg/providers/Microsoft.Storage/storageAccounts/{storageAccountName}
//
// 2. Enable protection for the file share:
//    az backup protection enable-for-azurefileshare \
//      --resource-group {resourceGroupName}-rg \
//      --vault-name {resourceGroupName}-rsv \
//      --policy-name vaultwarden-daily-backup-policy \
//      --storage-account {storageAccountName} \
//      --azure-file-share vaultwarden-data
//
// See docs/BACKUP_PROTECTION.md for detailed instructions.

// Deploy Log Analytics Workspace
module logAnalyticsWorkspace 'modules/log-analytics.bicep' = {
  scope: rg
  name: 'log-analytics-deployment'
  params: {
    baseName: resourceGroupName
    location: location
  }
}

// Deploy App Service Plan (Default: B1 SKU for cost-effectiveness with VNet integration support)
module appServicePlan 'modules/app-service-plan.bicep' = {
  scope: rg
  name: 'app-service-plan-deployment'
  params: {
    baseName: resourceGroupName
    location: location
    skuName: appServicePlanSkuName
  }
}

// Deploy Key Vault for secrets management
module keyVault 'modules/key-vault.bicep' = {
  scope: rg
  name: 'keyvault-deployment'
  params: {
    baseName: resourceGroupName
    location: location
  }
}

// Store admin token in Key Vault (only if provided) using a separate module
module keyVaultSecret 'modules/keyvault-secret.bicep' = if (adminToken != '') {
  scope: rg
  name: 'keyvault-secret-deployment'
  params: {
    keyVaultName: keyVault.outputs.name
    adminToken: adminToken
  }
}

// Deploy App Service (Web App for Containers)
module appService 'modules/app-service.bicep' = {
  scope: rg
  name: 'app-service-deployment'
  params: {
    baseName: resourceGroupName
    location: location
    appServicePlanResourceId: appServicePlan.outputs.resourceId
    subnetResourceId: vnet.outputs.subnetResourceIds[0]
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    storageAccountName: storageAccount.outputs.name
    storageAccountKey: storageAccount.outputs.primaryKey
    domainName: domainName
    signupsAllowed: signupsAllowed
    vaultwardenImageTag: vaultwardenImageTag
    adminTokenSecretUri: adminToken != '' ? '${keyVault.outputs.uri}secrets/vaultwarden-admin-token/' : ''
  }
  dependsOn: adminToken != '' ? [keyVaultSecret] : []
}

// Grant App Service managed identity access to Key Vault secrets
module keyVaultRoleAssignment 'modules/role-assignment.bicep' = if (adminToken != '') {
  scope: rg
  name: 'keyvault-role-assignment-deployment'
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: appService.outputs.systemAssignedMIPrincipalId!
  }
}

// Outputs
output resourceGroupName string = rg.name
output vaultwardenUrl string = 'https://${appService.outputs.defaultHostname}'
output storageAccountName string = storageAccount.outputs.name
output appServiceName string = appService.outputs.name
output appServicePlanName string = appServicePlan.outputs.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.outputs.resourceId
output keyVaultName string = keyVault.outputs.name
output recoveryServicesVaultName string = recoveryServicesVault.outputs.name
output backupPolicyName string = 'vaultwarden-daily-backup-policy'
