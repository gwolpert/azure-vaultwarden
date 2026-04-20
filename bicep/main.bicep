// ========================================
// Main Bicep Template for Vaultwarden on Azure App Service
// ========================================

targetScope = 'subscription'

// Parameters
@description('The name of the resource group (without -rg suffix). Must be lowercase letters, numbers, and hyphens only. Min 3 characters, max 22 characters. Must contain at least 1 alphanumeric character.')
@minLength(3)
@maxLength(22)
param resourceGroupName string = 'vaultwarden-dev'

@description('The Azure region where resources will be deployed')
param location string = 'northeurope'

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

@description('Vaultwarden container image tag. Pinned to a specific version by default; bump only after reviewing the upstream release notes at https://github.com/dani-garcia/vaultwarden/releases.')
param vaultwardenImageTag string = '1.35.7'

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

@description('PostgreSQL administrator login password')
@secure()
param postgresqlAdminPassword string

@description('Enable a CanNotDelete lock on the PostgreSQL server. Requires Microsoft.Authorization/locks/write permission on the deploying principal.')
param enablePostgresqlLock bool = false

@description('CIDR for the entire virtual network. Override to avoid conflicts when peering with other networks.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('CIDR for the App Service delegated subnet. Must be inside vnetAddressPrefix.')
param appServiceSubnetAddressPrefix string = '10.0.0.0/24'

@description('CIDR for the PostgreSQL Flexible Server delegated subnet. Must be inside vnetAddressPrefix.')
param postgresqlSubnetAddressPrefix string = '10.0.1.0/24'

@description('IPv4 addresses or CIDR ranges allowed to reach the Key Vault data plane. Trusted Azure services (e.g. App Service Key Vault references, ARM template deployments) keep working through the AzureServices bypass. Pass the CI/CD runner public IP from your pipeline to allow the deployment to manage secrets, then remove it after deploy.')
param keyVaultAllowedIpAddresses array = []

@description('IPv4 addresses or CIDR ranges allowed to reach the App Service SCM (Kudu) admin/management surface. The Vaultwarden /admin web route is protected separately by the argon2id-hashed ADMIN_TOKEN; per-URL-path IP restrictions are not supported by Azure App Service on Linux.')
param adminAllowedIpAddresses array = []

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

// Deploy Virtual Network with subnets for App Service and PostgreSQL
module vnet 'modules/vnet.bicep' = {
  scope: rg
  name: 'vnet-deployment'
  params: {
    baseName: resourceGroupName
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    appServiceSubnetAddressPrefix: appServiceSubnetAddressPrefix
    postgresqlSubnetAddressPrefix: postgresqlSubnetAddressPrefix
  }
}

// Deploy Private DNS Zone for PostgreSQL Flexible Server
module privateDnsZone 'modules/private-dns-zone.bicep' = {
  scope: rg
  name: 'private-dns-zone-deployment'
  params: {
    vnetResourceId: vnet.outputs.resourceId
  }
}

// Deploy Azure Database for PostgreSQL Flexible Server
module postgresql 'modules/postgresql.bicep' = {
  scope: rg
  name: 'postgresql-deployment'
  params: {
    baseName: resourceGroupName
    location: location
    delegatedSubnetResourceId: vnet.outputs.postgresqlSubnetResourceId
    privateDnsZoneResourceId: privateDnsZone.outputs.resourceId
    administratorLoginPassword: postgresqlAdminPassword
    keyVaultName: keyVault.outputs.name
    enablePostgresqlLock: enablePostgresqlLock
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
  }
}

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
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    allowedIpAddresses: keyVaultAllowedIpAddresses
    // Grant the App Service subnet network-level access to the vault via its
    // Microsoft.KeyVault service endpoint. This is required for App Service
    // Key Vault references to resolve at runtime, because those references
    // do not use the "AzureServices" trusted-services bypass.
    allowedSubnetResourceIds: [
      vnet.outputs.appServiceSubnetResourceId
    ]
  }
}

// Hash admin token with argon2id and store directly in Key Vault (only if provided)
module hashAdminToken 'modules/hash-admin-token.bicep' = if (adminToken != '') {
  scope: rg
  name: 'hash-admin-token-deployment'
  params: {
    baseName: resourceGroupName
    adminToken: adminToken
    keyVaultName: keyVault.outputs.name
    location: location
  }
}

// Deploy Storage Account hosting the Azure Files share for persistent Vaultwarden data (attachments and sends)
module storageAccount 'modules/storage-account.bicep' = {
  scope: rg
  name: 'storage-account-deployment'
  params: {
    baseName: resourceGroupName
    location: location
    appServiceSubnetResourceId: vnet.outputs.appServiceSubnetResourceId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
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
    subnetResourceId: vnet.outputs.appServiceSubnetResourceId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    domainName: domainName
    signupsAllowed: signupsAllowed
    vaultwardenImageTag: vaultwardenImageTag
    adminTokenSecretUri: adminToken != '' ? hashAdminToken!.outputs.adminTokenSecretUri : ''
    databaseUrlSecretUri: postgresql.outputs.databaseUrlSecretUri
    adminAllowedIpAddresses: adminAllowedIpAddresses
    storageAccountName: storageAccount.outputs.name
    dataFileShareName: storageAccount.outputs.dataFileShareName
  }
}

// Grant App Service managed identity access to Key Vault secrets (always needed for DATABASE_URL)
module keyVaultRoleAssignment 'modules/role-assignment.bicep' = {
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
output appServiceName string = appService.outputs.name
output appServicePlanName string = appServicePlan.outputs.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.outputs.resourceId
output keyVaultName string = keyVault.outputs.name
output postgresqlServerName string = postgresql.outputs.name
output storageAccountName string = storageAccount.outputs.name
output dataFileShareName string = storageAccount.outputs.dataFileShareName
