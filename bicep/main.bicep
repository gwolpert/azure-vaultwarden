// ========================================
// Main Bicep Template for Vaultwarden on Azure Container Apps
// ========================================

targetScope = 'subscription'

// Parameters
@description('The name of the resource group (without -rg suffix). Min 3 characters (the value is used to build the storage account name as {resourceGroupName without dashes}st, which must be 3-24 characters). Must contain at least 1 alphanumeric character. Max 22 characters to ensure storage/keyvault names stay within Azure limits.')
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
// NOTE: The resourceGroupName must contain at least 1 alphanumeric character to ensure the storage account name is at least 3 chars
var storageAccountNameBase = toLower(replace(resourceGroupName, '-', ''))
var storageAccountName = '${storageAccountNameBase}st'

// Assert that storage account name is valid (3-24 characters)
assert storageAccountNameWithinLimits = length(storageAccountName) >= 3 && length(storageAccountName) <= 24

// Key Vault: Must be 3-24 chars, alphanumeric and hyphens allowed
// Official abbreviation: 'kv'
// Pattern: {resourceGroupName without dashes}kv (hyphens removed for consistency with storage account)
// Example: vaultwarden-dev -> vaultwardendevkv (16 chars)
// Max base name: 22 chars (e.g., vaultwarden-production = 21 chars -> vaultwardenproductionkv = 23 chars)
var keyVaultName = '${replace(resourceGroupName, '-', '')}kv'

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

// Deploy Virtual Network
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
        name: 'container-apps-subnet'
        addressPrefix: '10.0.0.0/23'
        delegations: [
          {
            name: 'MicrosoftAppEnvironments'
            properties: {
              serviceName: 'Microsoft.App/environments'
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
  #disable-next-line BCP334 // The assert above ensures the storage account name meets Azure's 3-24 character requirement
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

// Deploy Container App Environment
// NOTE: Azure Container Apps automatically creates a managed infrastructure resource group
// with the "ME_" prefix (e.g., ME_vaultwarden-dev-cae). This resource group contains
// infrastructure components like load balancers and public IPs managed by Azure.
// The infrastructureResourceGroup parameter exists in the API but is currently not
// supported/functional in the AVM module. This is expected behavior and the managed
// resource group is required for Container Apps to function.
// See: https://github.com/Azure/bicep/issues/11221
module containerAppEnv 'br/public:avm/res/app/managed-environment:0.5.2' = {
  scope: rg
  name: 'containerapp-env-deployment'
  params: {
    name: '${namingPrefix}-cae'
    location: location
    infrastructureSubnetId: vnet.outputs.subnetResourceIds[0]
    internal: false
    zoneRedundant: false
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
  }
}

// Deploy storage for Container App Environment
module containerAppEnvStorage 'managed-environment-storage.bicep' = {
  scope: rg
  name: 'containerapp-env-storage-deployment'
  params: {
    managedEnvironmentName: containerAppEnv.outputs.name
    storageName: 'vaultwarden-storage'
    storageAccountName: storageAccountName
    storageAccountKey: storageAccountResource.listKeys().keys[0].value
    shareName: 'vaultwarden-data'
    accessMode: 'ReadWrite'
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

// Deploy Container App for Vaultwarden
module containerApp 'br/public:avm/res/app/container-app:0.8.0' = {
  scope: rg
  name: 'vaultwarden-containerapp-deployment'
  params: {
    name: '${namingPrefix}-ca'
    location: location
    environmentResourceId: containerAppEnv.outputs.resourceId
    containers: [
      {
        name: 'vaultwarden'
        image: 'vaultwarden/server:${vaultwardenImageTag}'
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        env: concat([
          {
            name: 'DOMAIN'
            value: domainName != '' ? domainName : 'https://${namingPrefix}-ca.${containerAppEnv.outputs.defaultDomain}'
          }
          {
            name: 'SIGNUPS_ALLOWED'
            value: string(signupsAllowed)
          }
          {
            name: 'ENABLE_DB_WAL'
            value: 'true'
          }
        ], adminToken != '' ? [
          {
            name: 'ADMIN_TOKEN'
            secretRef: 'admin-token'
          }
        ] : [])
        volumeMounts: [
          {
            volumeName: 'vaultwarden-data'
            mountPath: '/data'
          }
        ]
      }
    ]
    volumes: [
      {
        name: 'vaultwarden-data'
        storageType: 'AzureFile'
        storageName: 'vaultwarden-storage'
      }
    ]
    secrets: {
      secureList: adminToken != '' ? [
        {
          name: 'admin-token'
          keyVaultUrl: '${keyVault.outputs.uri}secrets/vaultwarden-admin-token'
          identity: 'system'
        }
        {
          name: 'storage-account-key'
          value: storageAccountResource.listKeys().keys[0].value
        }
      ] : [
        {
          name: 'storage-account-key'
          value: storageAccountResource.listKeys().keys[0].value
        }
      ]
    }
    managedIdentities: {
      systemAssigned: true
    }
    ingressExternal: true
    ingressTargetPort: 80
    ingressTransport: 'http'
    ingressAllowInsecure: false
    trafficWeight: 100
    trafficLatestRevision: true
    scaleMinReplicas: 1
    scaleMaxReplicas: 3
  }
  dependsOn: [
    containerAppEnvStorage
  ]
}

// Grant Container App managed identity access to Key Vault secrets
module keyVaultRoleAssignment 'role-assignment.bicep' = if (adminToken != '') {
  scope: rg
  name: 'keyvault-role-assignment-deployment'
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: containerApp.outputs.systemAssignedMIPrincipalId
  }
}

// Outputs
output resourceGroupName string = rg.name
output vaultwardenUrl string = 'https://${containerApp.outputs.fqdn}'
output storageAccountName string = storageAccountName
output containerAppName string = containerApp.outputs.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.outputs.resourceId
output keyVaultName string = keyVault.outputs.name
