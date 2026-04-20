// ========================================
// Main Bicep Template for Vaultwarden on Azure App Service
// ========================================

targetScope = 'resourceGroup'

// Parameters
@description('The base name for resources (without suffixes). Must be lowercase letters, numbers, and hyphens only. Min 3 characters, max 22 characters. Must contain at least 1 alphanumeric character.')
@minLength(3)
@maxLength(22)
param baseName string = 'vaultwarden'

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

@description('IPv4 addresses or CIDR ranges allowed to reach the App Service SCM (Kudu) admin/management surface. The Vaultwarden /admin web route is protected separately by the argon2id-hashed ADMIN_TOKEN; per-URL-path IP restrictions are not supported by Azure App Service on Linux.')
param adminAllowedIpAddresses array = []

// Variables
// Inherit the deployment region from the target resource group so callers
// only need to pick the resource group when deploying.
var location = resourceGroup().location

// Deploy Virtual Network with subnets for App Service and PostgreSQL
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    baseName: baseName
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    appServiceSubnetAddressPrefix: appServiceSubnetAddressPrefix
    postgresqlSubnetAddressPrefix: postgresqlSubnetAddressPrefix
  }
}

// Deploy Private DNS Zone for PostgreSQL Flexible Server
module privateDnsZone 'modules/private-dns-zone.bicep' = {
  name: 'private-dns-zone-deployment'
  params: {
    vnetResourceId: vnet.outputs.resourceId
  }
}

// Deploy Azure Database for PostgreSQL Flexible Server
module postgresql 'modules/postgresql.bicep' = {
  name: 'postgresql-deployment'
  params: {
    baseName: baseName
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
  name: 'log-analytics-deployment'
  params: {
    baseName: baseName
    location: location
  }
}

// Deploy App Service Plan (Default: B1 SKU for cost-effectiveness with VNet integration support)
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'app-service-plan-deployment'
  params: {
    baseName: baseName
    location: location
    skuName: appServicePlanSkuName
  }
}

// Deploy Key Vault for secrets management
module keyVault 'modules/key-vault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    baseName: baseName
    location: location
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
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
  name: 'hash-admin-token-deployment'
  params: {
    baseName: baseName
    adminToken: adminToken
    keyVaultName: keyVault.outputs.name
    location: location
  }
}

// Deploy Storage Account hosting the Azure Files share for persistent Vaultwarden data (attachments and sends)
module storageAccount 'modules/storage-account.bicep' = {
  name: 'storage-account-deployment'
  params: {
    baseName: baseName
    location: location
    appServiceSubnetResourceId: vnet.outputs.appServiceSubnetResourceId
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
  }
}

// Deploy App Service (Web App for Containers)
module appService 'modules/app-service.bicep' = {
  name: 'app-service-deployment'
  params: {
    baseName: baseName
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
  name: 'keyvault-role-assignment-deployment'
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: appService.outputs.systemAssignedMIPrincipalId!
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output vaultwardenUrl string = 'https://${appService.outputs.defaultHostname}'
output appServiceName string = appService.outputs.name
output appServicePlanName string = appServicePlan.outputs.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.outputs.resourceId
output keyVaultName string = keyVault.outputs.name
output postgresqlServerName string = postgresql.outputs.name
output storageAccountName string = storageAccount.outputs.name
output dataFileShareName string = storageAccount.outputs.dataFileShareName
