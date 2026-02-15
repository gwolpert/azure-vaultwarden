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

// Variables
// Using official Microsoft Azure resource abbreviations:
// https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations
var resourceGroupNameWithSuffix = '${resourceGroupName}-rg'
var namingPrefix = resourceGroupName
// Storage account: Must be 3-24 chars, lowercase letters and numbers only
// Official abbreviation: 'st' (not 'sa')
// Pattern: {resourceGroupName without dashes}st
// Example: vaultwarden-dev -> vaultwardendevst (16 chars)
// Max base name: 22 chars (e.g., vaultwarden-production = 21 chars -> vaultwardenproductionst = 23 chars)
// NOTE: The resourceGroupName parameter constraint (@minLength(3), @maxLength(22)) combined with
// the 'st' suffix ensures the final storage account name is 5-24 chars (safe within 3-24 limit).
// Only lowercase letters, numbers, and hyphens are allowed in resourceGroupName, and hyphens are
// removed, ensuring the final name contains only valid characters (lowercase letters and numbers).
// toLower() ensures lowercase conversion even if user provides uppercase in resourceGroupName.
var storageAccountName = toLower('${replace(resourceGroupName, '-', '')}st')

// Key Vault: Must be 3-24 chars, alphanumeric and hyphens allowed
// Official abbreviation: 'kv'
// Pattern: {resourceGroupName without dashes}kv (hyphens removed for consistency with storage account)
// Example: vaultwarden-dev -> vaultwardendevkv (16 chars)
// Max base name: 22 chars (e.g., vaultwarden-production = 21 chars -> vaultwardenproductionkv = 23 chars)
var keyVaultName = '${replace(resourceGroupName, '-', '')}kv'

// App Service Plan name
// Official abbreviation: 'asp'
var appServicePlanName = '${namingPrefix}-asp'

// App Service name
// Official abbreviation: 'app'
var appServiceName = '${namingPrefix}-app'

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
module vnet 'br/public:avm/res/network/virtual-network:0.1.8' = {
  scope: rg
  name: 'vnet-deployment'
  params: {
    name: '${namingPrefix}-vnet'
    location: location
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {
        name: 'app-service-subnet'
        addressPrefix: '10.0.0.0/24'
        delegations: [
          {
            name: 'MicrosoftWebServerFarms'
            properties: {
              serviceName: 'Microsoft.Web/serverFarms'
            }
          }
        ]
      }
    ]
  }
}

// Deploy Storage Account for persistent data
module storageAccount 'br/public:avm/res/storage/storage-account:0.9.1' = {
  scope: rg
  name: 'storage-deployment'
  params: {
    name: storageAccountName
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    fileServices: {
      shares: [
        {
          name: 'vaultwarden-data'
          accessTier: 'TransactionOptimized'
        }
      ]
    }
  }
}

// Get storage account keys using listKeys function
resource storageAccountResource 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  scope: rg
  #disable-next-line BCP334 // resourceGroupName constraints (@minLength(3) + @maxLength(22)) with 'st' suffix ensure 5-24 char storage name
  name: storageAccountName
  dependsOn: [
    storageAccount
  ]
}

// Deploy Log Analytics Workspace
module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.3.4' = {
  scope: rg
  name: 'log-analytics-deployment'
  params: {
    name: '${namingPrefix}-log'
    location: location
  }
}

// Deploy App Service Plan (S1 SKU for VNet integration and production features)
module appServicePlan 'br/public:avm/res/web/serverfarm:0.6.0' = {
  scope: rg
  name: 'app-service-plan-deployment'
  params: {
    name: appServicePlanName
    location: location
    skuName: 'S1'
    kind: 'linux'
    reserved: true  // Required for Linux
  }
}

// Deploy Key Vault for secrets management
module keyVault 'br/public:avm/res/key-vault/vault:0.6.2' = {
  scope: rg
  name: 'keyvault-deployment'
  params: {
    name: keyVaultName
    location: location
    sku: 'standard'
    enableRbacAuthorization: true
    enableVaultForDeployment: false
    enableVaultForDiskEncryption: false
    enableVaultForTemplateDeployment: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store admin token in Key Vault (only if provided) using a separate module
module keyVaultSecret 'keyvault-secret.bicep' = if (adminToken != '') {
  scope: rg
  name: 'keyvault-secret-deployment'
  params: {
    keyVaultName: keyVault.outputs.name
    adminToken: adminToken
  }
}

// Deploy App Service (Web App for Containers)
module appService 'br/public:avm/res/web/site:0.21.0' = {
  scope: rg
  name: 'app-service-deployment'
  params: {
    name: appServiceName
    location: location
    kind: 'app,linux,container'
    serverFarmResourceId: appServicePlan.outputs.resourceId
    managedIdentities: {
      systemAssigned: true
    }
    virtualNetworkSubnetId: vnet.outputs.subnetResourceIds[0]
    siteConfig: {
      linuxFxVersion: 'DOCKER|vaultwarden/server:${vaultwardenImageTag}'
      alwaysOn: true
      appSettings: concat([
        {
          name: 'DOMAIN'
          value: domainName != '' ? domainName : 'https://${appServiceName}.azurewebsites.net'
        }
        {
          name: 'SIGNUPS_ALLOWED'
          value: string(signupsAllowed)
        }
        {
          name: 'ENABLE_DB_WAL'
          value: 'true'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
      ], adminToken != '' ? [
        {
          name: 'ADMIN_TOKEN'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.uri}secrets/vaultwarden-admin-token)'
        }
      ] : [])
      azureStorageAccounts: {
        'vaultwarden-data': {
          type: 'AzureFiles'
          accountName: storageAccountName
          shareName: 'vaultwarden-data'
          mountPath: '/data'
          accessKey: storageAccountResource.listKeys().keys[0].value
        }
      }
    }
    httpsOnly: true
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
        logCategoriesAndGroups: [
          {
            categoryGroup: 'allLogs'
          }
        ]
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
      }
    ]
  }
}

// Grant App Service managed identity access to Key Vault secrets
module keyVaultRoleAssignment 'role-assignment.bicep' = if (adminToken != '') {
  scope: rg
  name: 'keyvault-role-assignment-deployment'
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: appService.outputs.systemAssignedMIPrincipalId
  }
}

// Outputs
output resourceGroupName string = rg.name
output vaultwardenUrl string = 'https://${appService.outputs.defaultHostname}'
output storageAccountName string = storageAccountName
output appServiceName string = appService.outputs.name
output appServicePlanName string = appServicePlan.outputs.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.outputs.resourceId
output keyVaultName string = keyVault.outputs.name
