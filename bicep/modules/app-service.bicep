// ========================================
// App Service Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('Resource ID of the App Service Plan')
param appServicePlanResourceId string

@description('Resource ID of the subnet for VNet integration')
param subnetResourceId string

@description('Resource ID of the Log Analytics Workspace')
param logAnalyticsWorkspaceResourceId string

@description('The domain name for Vaultwarden')
param domainName string

@description('Allow new user signups')
param signupsAllowed bool

@description('Vaultwarden container image tag')
param vaultwardenImageTag string

@description('Admin token configuration (URI to Key Vault secret)')
param adminTokenSecretUri string = ''

@description('Database URL configuration (URI to Key Vault secret)')
param databaseUrlSecretUri string

@description('Name of the Storage Account hosting the Vaultwarden data file share. The account must live in the same resource group as this App Service.')
param storageAccountName string

@description('Name of the file share inside the storage account that holds persistent Vaultwarden data (attachments and sends).')
param dataFileShareName string

@description('Path inside the container where the data share is mounted. Vaultwarden stores attachments and sends as subdirectories under this path.')
param dataMountPath string = '/data'

@description('Per-user total attachment storage limit in kilobytes. The default of 1024000 KB (1000 MiB) caps each user\'s cumulative attachment storage.')
@minValue(1)
param userAttachmentLimitKB int = 1024000

@description('Per-organization total attachment storage limit in kilobytes. The default of 262144000 KB (250 GiB) caps the total attachment storage for an entire organization.')
@minValue(1)
param orgAttachmentLimitKB int = 262144000

@description('IPv4 addresses or CIDR ranges allowed to reach the App Service SCM (Kudu) admin surface. Empty = no IP restriction. See README for the /admin web-route limitation.')
param adminAllowedIpAddresses array = []

// Build SCM IP restriction rules from the admin allow-list. When the list is empty
// we leave SCM rules unset so the platform default (Allow) remains.
var scmIpSecurityRestrictions = [for (ip, i) in adminAllowedIpAddresses: {
  ipAddress: ip
  action: 'Allow'
  priority: 100 + i
  name: 'AllowAdminIp${i}'
  description: 'Allow access to Kudu/SCM admin surface'
}]
var hasAdminIpAllowList = !empty(adminAllowedIpAddresses)

// Build the full App Service name using naming convention
// Official abbreviation: 'app'
var appServiceName = '${baseName}-app'

// Reference the existing storage account so we can read its primary access key
// for the Azure Files SMB mount. The Web Apps `azurestorageaccounts` siteConfig
// requires the raw access key — Key Vault references are not supported there.
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Deploy App Service (Web App for Containers)
module appServiceDeployment 'br/public:avm/res/web/site:0.22.0' = {
  name: '${deployment().name}-avm'
  params: {
    name: appServiceName
    location: location
    kind: 'app,linux,container'
    serverFarmResourceId: appServicePlanResourceId
    managedIdentities: {
      systemAssigned: true
    }
    virtualNetworkSubnetResourceId: subnetResourceId
    siteConfig: {
      linuxFxVersion: 'DOCKER|vaultwarden/server:${vaultwardenImageTag}'
      alwaysOn: true
      // Route all outbound traffic through the VNet integration. Required so
      // Key Vault reference resolution (ADMIN_TOKEN, DATABASE_URL) exits via
      // the App Service subnet and matches the Microsoft.KeyVault service
      // endpoint rule on the Key Vault firewall. Without this, Key Vault
      // references fail at runtime with "site was denied access to Key
      // Vault reference's vault".
      vnetRouteAllEnabled: true
      scmIpSecurityRestrictionsUseMain: false
      scmIpSecurityRestrictionsDefaultAction: hasAdminIpAllowList ? 'Deny' : 'Allow'
      scmIpSecurityRestrictions: hasAdminIpAllowList ? scmIpSecurityRestrictions : null
      appSettings: concat([
        {
          name: 'DOMAIN'
          value: domainName != '' ? domainName : 'https://${appServiceName}.azurewebsites.net'
        }
        {
          name: 'SIGNUPS_ALLOWED'
          value: string(signupsAllowed)
        }
        {
          name: 'DATABASE_URL'
          value: '@Microsoft.KeyVault(SecretUri=${databaseUrlSecretUri})'
        }
        {
          name: 'IP_HEADER'
          value: 'X-Client-IP'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        // Persist Vaultwarden attachments and sends on the Azure Files share
        // mounted at dataMountPath instead of the ephemeral container disk.
        {
          name: 'ATTACHMENTS_FOLDER'
          value: '${dataMountPath}/attachments'
        }
        {
          name: 'SENDS_FOLDER'
          value: '${dataMountPath}/sends'
        }
        // Cap the total cumulative attachment storage per user (default
        // 1000 MiB ≈ 1 GB) and per organisation (default 250 GiB). These are
        // quotas on *all* attachments a user/org has, not on a single file.
        {
          name: 'USER_ATTACHMENT_LIMIT'
          value: string(userAttachmentLimitKB)
        }
        {
          name: 'ORG_ATTACHMENT_LIMIT'
          value: string(orgAttachmentLimitKB)
        }
      ], adminTokenSecretUri != '' ? [
        {
          name: 'ADMIN_TOKEN'
          value: '@Microsoft.KeyVault(SecretUri=${adminTokenSecretUri})'
        }
      ] : [])
    }
    httpsOnly: true
    // Mount the data Azure Files share into the container so Vaultwarden
    // writes ATTACHMENTS_FOLDER and SENDS_FOLDER to durable, VNet-restricted
    // storage instead of the ephemeral container disk. The Web Apps
    // `azurestorageaccounts` config does not accept Key Vault references,
    // so the access key is read directly from the storage account using
    // listKeys() at deploy time.
    configs: [
      {
        name: 'azurestorageaccounts'
        properties: {
          'vaultwarden-data': {
            type: 'AzureFiles'
            accountName: storageAccountName
            shareName: dataFileShareName
            mountPath: dataMountPath
            protocol: 'Smb'
            // Select the access key by name so we don't depend on array order.
            accessKey: filter(storageAccount.listKeys().keys, k => k.keyName == 'key1')[0].value
          }
        }
      }
    ]
    diagnosticSettings: [
      {
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

output name string = appServiceDeployment.outputs.name
output resourceId string = appServiceDeployment.outputs.resourceId
output defaultHostname string = appServiceDeployment.outputs.defaultHostname
output systemAssignedMIPrincipalId string = appServiceDeployment.outputs.systemAssignedMIPrincipalId!
