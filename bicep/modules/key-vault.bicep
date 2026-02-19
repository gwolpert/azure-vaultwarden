// ========================================
// Key Vault Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

// Build the full Key Vault name using naming convention
// Key Vault: Must be 3-24 chars, alphanumeric and hyphens allowed
// Official abbreviation: 'kv'
// Pattern: {baseName without dashes}kv (hyphens removed for consistency with storage account)
// Example: vaultwarden-dev -> vaultwardendevkv (16 chars)
// Max base name: 22 chars (e.g., vaultwarden-production = 21 chars -> vaultwardenproductionkv = 23 chars)
var keyVaultName = '${replace(baseName, '-', '')}kv'

// Deploy Key Vault for secrets management
module keyVaultDeployment 'br/public:avm/res/key-vault/vault:0.6.2' = {
  name: '${deployment().name}-key-vault'
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

output name string = keyVaultDeployment.outputs.name
output resourceId string = keyVaultDeployment.outputs.resourceId
output uri string = keyVaultDeployment.outputs.uri
