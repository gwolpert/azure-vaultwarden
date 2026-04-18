// Module for creating Key Vault secrets within a Key Vault
// Deployed at resource group scope to match the Key Vault's scope
targetScope = 'resourceGroup'

@description('The name of the Key Vault')
param keyVaultName string

@description('Whether an admin token was provided')
param hasAdminToken bool = false

@description('The admin token to store (optional)')
@secure()
param adminToken string = ''

@description('The database connection string to store')
@secure()
param databaseUrl string

// Reference the existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Create the admin token secret (only if provided)
resource adminTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = if (hasAdminToken) {
  parent: keyVault
  name: 'vaultwarden-admin-token'
  properties: {
    value: adminToken
  }
}

// Create the database URL secret
resource databaseUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'vaultwarden-database-url'
  properties: {
    value: databaseUrl
  }
}

output adminTokenSecretUri string = hasAdminToken ? adminTokenSecret!.properties.secretUri : ''
output databaseUrlSecretUri string = databaseUrlSecret.properties.secretUri
