// ========================================
// Key Vault Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('Resource ID of the Log Analytics Workspace to send Key Vault audit logs and metrics to. Leave empty to disable monitoring.')
param logAnalyticsWorkspaceResourceId string = ''

@description('IPv4 addresses or CIDR ranges that are allowed to reach the Key Vault data plane. Trusted Azure services keep working through the AzureServices bypass. Leave empty to deny all public IPs.')
param allowedIpAddresses array = []

// Build the full Key Vault name using naming convention
// Key Vault: Must be 3-24 chars, alphanumeric and hyphens allowed
// Official abbreviation: 'kv'
// Pattern: {baseName without dashes}kv (hyphens removed for valid Key Vault naming)
// Example: vaultwarden-dev -> vaultwardendevkv (16 chars)
// Max base name: 22 chars (e.g., vaultwarden-production = 21 chars -> vaultwardenproductionkv = 23 chars)
var keyVaultName = '${replace(baseName, '-', '')}kv'

var ipRules = [for ip in allowedIpAddresses: {
  value: ip
}]

// Deploy Key Vault for secrets management
module keyVaultDeployment 'br/public:avm/res/key-vault/vault:0.13.3' = {
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
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: ipRules
    }
    diagnosticSettings: empty(logAnalyticsWorkspaceResourceId) ? [] : [
      {
        name: 'kv-diagnostics'
        workspaceResourceId: logAnalyticsWorkspaceResourceId
        logCategoriesAndGroups: [
          {
            categoryGroup: 'audit'
          }
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

output name string = keyVaultDeployment.outputs.name
output resourceId string = keyVaultDeployment.outputs.resourceId
output uri string = keyVaultDeployment.outputs.uri
