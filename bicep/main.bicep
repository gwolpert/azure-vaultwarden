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
param location string = 'westeurope'

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

@description('PostgreSQL administrator login password')
@secure()
param postgresqlAdminPassword string

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
  }
}

// Hash admin token with argon2id using a deployment script (only if provided)
module hashAdminToken 'modules/hash-admin-token.bicep' = if (adminToken != '') {
  scope: rg
  name: 'hash-admin-token-deployment'
  params: {
    adminToken: adminToken
    location: location
  }
}

// Store secrets in Key Vault (database URL is always stored, admin token only if provided)
module keyVaultSecrets 'modules/keyvault-secret.bicep' = {
  scope: rg
  name: 'keyvault-secrets-deployment'
  params: {
    keyVaultName: keyVault.outputs.name
    adminToken: adminToken != '' ? hashAdminToken!.outputs.hashedToken : ''
    databaseUrl: postgresql.outputs.connectionString
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
    adminTokenSecretUri: adminToken != '' ? keyVaultSecrets.outputs.adminTokenSecretUri : ''
    databaseUrlSecretUri: keyVaultSecrets.outputs.databaseUrlSecretUri
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
