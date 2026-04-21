// ========================================
// Storage Account Module
// ========================================
// Hosts the Azure Files share that backs persistent Vaultwarden data
// (ATTACHMENTS_FOLDER and SENDS_FOLDER). The share is mounted at /data
// inside the container so both /data/attachments and /data/sends are durable.
// The account is locked down: public network access is disabled and the only
// data-plane path is a Files private endpoint deployed into the application
// VNet's private-endpoints subnet, with DNS resolved through the linked
// privatelink.file.<storage-suffix> Private DNS Zone.

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('Resource ID of the subnet that will host the Storage Account private endpoint NIC. Required because public access to the storage data plane is disabled.')
param privateEndpointSubnetResourceId string

@description('Resource ID of the privatelink.file.<storage-suffix> Private DNS Zone linked to the consuming VNet. Used to register the Storage Files private endpoint so callers inside the VNet resolve the account to its private IP.')
param privateDnsZoneResourceId string

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
    // Public network access is disabled. The only data-plane path into the
    // account is the Files private endpoint deployed below into the
    // private-endpoints subnet of the application VNet. The "AzureServices"
    // bypass still allows trusted Azure platform services (e.g. ARM
    // deployments and diagnostic pipelines) to function.
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices, Logging, Metrics'
      ipRules: []
      virtualNetworkRules: []
    }
    privateEndpoints: [
      {
        name: '${storageAccountName}-file-pe'
        service: 'file'
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
