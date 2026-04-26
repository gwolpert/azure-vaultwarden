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

@description('Resource ID of the subnet that will host the Key Vault private endpoint NIC. Required because public access to the vault data plane is disabled.')
param privateEndpointSubnetResourceId string

@description('Resource ID of the privatelink.vaultcore.azure.net Private DNS Zone linked to the consuming VNet. Used to register the Key Vault private endpoint so callers inside the VNet resolve the vault to its private IP.')
param privateDnsZoneResourceId string

@description('Resource tags applied to the Key Vault.')
param tags object = {}

// Build the full Key Vault name using naming convention
// Key Vault: Must be 3-24 chars, alphanumeric and hyphens allowed
// Official abbreviation: 'kv'
// Pattern: {baseName without dashes}kv (hyphens removed for valid Key Vault naming)
// Example: vaultwarden-dev -> vaultwardendevkv (16 chars)
// Max base name: 22 chars (e.g., vaultwarden-production = 21 chars -> vaultwardenproductionkv = 23 chars)
var keyVaultName = '${replace(baseName, '-', '')}kv'

// Deploy Key Vault for secrets management.
// Public network access is disabled; the only data-plane path into the vault
// is the private endpoint deployed below into the private-endpoints subnet of
// the application VNet. The "AzureServices" bypass still allows trusted
// Azure platform services to reach the vault when needed.
module keyVaultDeployment 'br/public:avm/res/key-vault/vault:0.13.3' = {
  name: '${deployment().name}-key-vault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    sku: 'standard'
    enableRbacAuthorization: true
    enableVaultForDeployment: false
    enableVaultForDiskEncryption: false
    // Runtime resolution of `@Microsoft.KeyVault(...)` references uses the App
    // Service's managed identity (Key Vault Secrets User RBAC role), not the
    // legacy "deployment" access policy path, so this flag adds no value here
    // and is left disabled to minimize the data-plane attack surface.
    enableVaultForTemplateDeployment: false
    // Soft delete is on by default; purge protection guards Vaultwarden's
    // database connection string and admin-token secrets against accidental
    // (or malicious) hard-delete during the soft-delete window. NOTE: this
    // is a one-way switch — once enabled it cannot be disabled on the vault.
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    privateEndpoints: [
      {
        name: '${keyVaultName}-pe'
        // Override the auto-generated NIC name (which would otherwise be
        // '<peName>.nic.<guid>') so it follows the project's naming convention.
        customNetworkInterfaceName: '${keyVaultName}-pe-nic'
        service: 'vault'
        subnetResourceId: privateEndpointSubnetResourceId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZoneResourceId
            }
          ]
        }
      }
    ]
    diagnosticSettings: empty(logAnalyticsWorkspaceResourceId) ? [] : [
      {
        name: 'kv-diagnostics'
        workspaceResourceId: logAnalyticsWorkspaceResourceId
        logAnalyticsDestinationType: 'Dedicated'
        logCategoriesAndGroups: [
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
