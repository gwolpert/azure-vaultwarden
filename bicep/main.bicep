// ========================================
// Main Bicep Template for Vaultwarden on Azure Container Apps
// ========================================

targetScope = 'subscription'

// Parameters
@description('The name of the resource group')
param resourceGroupName string = 'rg-vaultwarden'

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
var uniqueSuffix = uniqueString(subscription().subscriptionId, resourceGroupName, location)
var namingPrefix = 'vw-${environmentName}'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
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
      }
    ]
  }
}

// Deploy Storage Account for persistent data
module storageAccount 'br/public:avm/res/storage/storage-account:0.9.1' = {
  scope: rg
  name: 'storage-deployment'
  params: {
    name: '${namingPrefix}st${uniqueSuffix}'
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

// Deploy Container App Environment
module containerAppEnv 'br/public:avm/res/app/managed-environment:0.5.2' = {
  scope: rg
  name: 'containerapp-env-deployment'
  params: {
    name: '${namingPrefix}-env'
    location: location
    infrastructureSubnetId: vnet.outputs.subnetResourceIds[0]
    internal: false
    zoneRedundant: false
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
  }
}

// Deploy Log Analytics Workspace
module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.3.4' = {
  scope: rg
  name: 'log-analytics-deployment'
  params: {
    name: '${namingPrefix}-logs'
    location: location
  }
}

// Deploy Container App for Vaultwarden
module containerApp 'br/public:avm/res/app/container-app:0.8.0' = {
  scope: rg
  name: 'vaultwarden-containerapp-deployment'
  params: {
    name: '${namingPrefix}-app'
    location: location
    environmentId: containerAppEnv.outputs.resourceId
    containers: [
      {
        name: 'vaultwarden'
        image: 'vaultwarden/server:${vaultwardenImageTag}'
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        env: [
          {
            name: 'DOMAIN'
            value: domainName != '' ? domainName : 'https://${namingPrefix}-app.${containerAppEnv.outputs.defaultDomain}'
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
            name: 'ADMIN_TOKEN'
            secretRef: 'admin-token'
          }
        ]
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
      secureList: [
        {
          name: 'admin-token'
          value: adminToken != '' ? adminToken : 'disabled'
        }
        {
          name: 'storage-account-key'
          value: storageAccount.outputs.primaryKey
        }
      ]
    }
    managedIdentities: {
      systemAssigned: true
    }
    ingress: {
      external: true
      targetPort: 80
      transport: 'http'
      allowInsecure: false
      traffic: [
        {
          latestRevision: true
          weight: 100
        }
      ]
    }
    scaleMinReplicas: 1
    scaleMaxReplicas: 3
    storages: [
      {
        name: 'vaultwarden-storage'
        azureFile: {
          shareName: 'vaultwarden-data'
          accountName: storageAccount.outputs.name
          accountKey: storageAccount.outputs.primaryKey
          accessMode: 'ReadWrite'
        }
      }
    ]
  }
  dependsOn: [
    storageAccount
  ]
}

// Outputs
output resourceGroupName string = rg.name
output vaultwardenUrl string = 'https://${containerApp.outputs.fqdn}'
output storageAccountName string = storageAccount.outputs.name
output containerAppName string = containerApp.outputs.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.outputs.resourceId
