// ========================================
// Storage Account Module
// ========================================
// Hosts the Azure Files share that backs persistent Vaultwarden data
// (ATTACHMENTS_FOLDER and SENDS_FOLDER).  The share is mounted at /data
// inside the container so both /data/attachments and /data/sends are durable.
// The account is locked down to the App Service subnet via a Microsoft.Storage
// service endpoint.  The public endpoint is enabled (required for service-
// endpoint rules) but the storage firewall denies all other traffic by default.

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('Resource ID of the App Service subnet that is allowed to reach the storage account data plane via the Microsoft.Storage service endpoint.')
param appServiceSubnetResourceId string

@description('Resource ID of the Log Analytics Workspace to send Storage diagnostic metrics to. Leave empty to disable monitoring.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Name of the Azure Files share used for persistent Vaultwarden data (attachments and sends). Must be 3-63 lowercase alphanumeric/hyphen characters.')
@minLength(3)
@maxLength(63)
param dataFileShareName string = 'vaultwarden-data'

@description('Quota (in GB) for the data file share. Must be between 1 and 5120 (standard) — controls maximum total storage for attachments and sends combined. Sized for ~100 users × 1000 MiB attachments each plus headroom; Send files are ephemeral and typically consume only a small fraction (~10 %) of the total.')
@minValue(1)
@maxValue(5120)
param dataFileShareQuotaGB int = 250

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
    skuName: 'Standard_GRS'
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
    // Restrict the data plane so that only the App Service subnet (via service
    // endpoint) and trusted Azure services can reach it. The "AzureServices"
    // bypass allows ARM deployments and platform-level diagnostics to function;
    // "Logging, Metrics" ensures Storage Analytics telemetry flows to Log
    // Analytics. No public internet traffic is admitted.
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
    // File service hosting the data share. Soft-delete on shares gives
    // us 7-day recovery for accidentally deleted data.
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
          name: dataFileShareName
          accessTier: 'Hot'
          enabledProtocols: 'SMB'
          shareQuota: dataFileShareQuotaGB
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
output dataFileShareName string = dataFileShareName
