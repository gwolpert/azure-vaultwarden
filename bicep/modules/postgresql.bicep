// ========================================
// Azure Database for PostgreSQL Flexible Server Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('The resource ID of the delegated subnet for PostgreSQL')
param delegatedSubnetResourceId string

@description('The resource ID of the private DNS zone for PostgreSQL')
param privateDnsZoneResourceId string

@description('Administrator login name for the PostgreSQL server')
param administratorLogin string = 'vaultwardenadmin'

@description('Administrator login password for the PostgreSQL server')
@secure()
param administratorLoginPassword string

@description('The name of the Key Vault to store the database URL in')
param keyVaultName string

// Build the full PostgreSQL server name using naming convention
// PostgreSQL Flexible Server: Must be 3-63 chars, lowercase letters, numbers, and hyphens
// Pattern: {baseName}-psql
var postgresqlServerName = '${baseName}-psql'

// Database name for Vaultwarden
var databaseName = 'vaultwarden'

// Reference the existing Key Vault to store the database URL
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Deploy Azure Database for PostgreSQL Flexible Server using AVM
module postgresqlDeployment 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.4.0' = {
  name: '${deployment().name}-postgresql'
  params: {
    name: postgresqlServerName
    location: location
    skuName: 'Standard_B1ms'
    tier: 'Burstable'
    version: '16'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    passwordAuth: 'Enabled'
    storageSizeGB: 32
    delegatedSubnetResourceId: delegatedSubnetResourceId
    privateDnsZoneArmResourceId: privateDnsZoneResourceId
    highAvailability: 'Disabled'
    backupRetentionDays: 7
    databases: [
      {
        name: databaseName
        charset: 'UTF8'
        collation: 'en_US.utf8'
      }
    ]
    lock: {
      kind: 'CanNotDelete'
      name: 'postgresql-lock'
    }
  }
}

// Build the connection string for Vaultwarden and store directly in Key Vault
// Format: postgresql://user:password@host:5432/dbname
resource databaseUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'vaultwarden-database-url'
  properties: {
    value: 'postgresql://${uriComponent(administratorLogin)}:${uriComponent(administratorLoginPassword)}@${postgresqlDeployment.outputs.fqdn}:5432/${databaseName}?sslmode=require'
  }
}

output name string = postgresqlDeployment.outputs.name
output resourceId string = postgresqlDeployment.outputs.resourceId
output fqdn string = postgresqlDeployment.outputs.fqdn
output databaseUrlSecretUri string = databaseUrlSecret.properties.secretUri
