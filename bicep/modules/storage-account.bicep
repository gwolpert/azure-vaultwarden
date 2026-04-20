// ========================================
// Storage Account Module
// ========================================
// Hosts the Azure Files share that backs the Vaultwarden ATTACHMENTS_FOLDER.
// The account is locked down to the App Service subnet via a Microsoft.Storage
// service endpoint and has public network access denied for everything else.

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('Resource ID of the App Service subnet that is allowed to reach the storage account data plane via the Microsoft.Storage service endpoint.')
param appServiceSubnetResourceId string

@description('Resource ID of the Log Analytics Workspace to send Storage diagnostic metrics to. Leave empty to disable monitoring.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Name of the Azure Files share used for Vaultwarden attachments. Must be 3-63 lowercase alphanumeric/hyphen characters.')
@minLength(3)
@maxLength(63)
param attachmentsFileShareName string = 'vaultwarden-attachments'

@description('Quota (in GB) for the attachments file share. Must be between 1 and 5120 (standard) — controls maximum total storage for attachments. Sized for ~100 users × 1000 MiB each plus headroom.')
@minValue(1)
@maxValue(5120)
param attachmentsFileShareQuotaGB int = 250

// Build the full Storage Account name using naming convention.
// Storage Account: must be 3-24 chars, lowercase letters and numbers only.
// Official abbreviation: 'st'
// Pattern: {baseName without dashes}st (hyphens removed for valid storage naming).
// Example: vaultwarden-dev -> vaultwardendevst (16 chars).
// Max base name: 22 chars (e.g. vaultwarden-production = 21 chars -> vaultwardenproductionst = 23 chars).
var storageAccountName = '${replace(baseName, '-', '')}st'

// Deploy Azure Storage Account using the latest Azure Verified Module
module storageAccountDeployment 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: '${deployment().name}-storage-account'
  params: {
    name: storageAccountName
    location: location
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    // NOTE: Must be 'Enabled' for service-endpoint based virtualNetworkRules
    // to be honored. Setting this to 'Disabled' would force the use of a
    // private endpoint and would also block the App Service subnet — defeating
    // the purpose. Public traffic is still denied because networkAcls below
    // sets defaultAction to 'Deny' and only the App Service subnet is allow-
    // listed via a Microsoft.Storage service endpoint.
    publicNetworkAccess: 'Enabled'
    // Lock the data plane to the App Service subnet only. The "AzureServices,
    // Logging, Metrics" bypass keeps diagnostic and platform telemetry flowing
    // to Log Analytics without exposing the data plane to the public internet.
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices, Logging, Metrics'
      ipRules: []
      virtualNetworkRules: [
        {
          id: appServiceSubnetResourceId
          action: 'Allow'
        }
      ]
    }
    // File service hosting the attachments share. Soft-delete on shares gives
    // us 7-day recovery for accidentally deleted attachments.
    fileServices: {
      shareDeleteRetentionPolicy: {
        enabled: true
        days: 7
      }
      diagnosticSettings: empty(logAnalyticsWorkspaceResourceId) ? [] : [
        {
          name: 'st-file-diagnostics'
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
      shares: [
        {
          name: attachmentsFileShareName
          accessTier: 'Hot'
          enabledProtocols: 'SMB'
          shareQuota: attachmentsFileShareQuotaGB
        }
      ]
    }
    // Account-level diagnostic settings (metrics-only, per the AVM type).
    diagnosticSettings: empty(logAnalyticsWorkspaceResourceId) ? [] : [
      {
        name: 'st-diagnostics'
        workspaceResourceId: logAnalyticsWorkspaceResourceId
        logAnalyticsDestinationType: 'Dedicated'
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
      }
    ]
  }
}

output name string = storageAccountDeployment.outputs.name
output resourceId string = storageAccountDeployment.outputs.resourceId
output attachmentsFileShareName string = attachmentsFileShareName
