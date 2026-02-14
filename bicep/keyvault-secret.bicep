// Module for creating Key Vault secret at resource group scope
targetScope = 'resourceGroup'

@description('The name of the Key Vault')
param keyVaultName string

@description('The admin token to store')
@secure()
param adminToken string

// Reference the existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Create the admin token secret
resource adminTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'vaultwarden-admin-token'
  properties: {
    value: adminToken
  }
}

output secretUri string = adminTokenSecret.properties.secretUri
