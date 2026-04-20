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

@description('Name of the Storage Account hosting the Vaultwarden attachments file share. The account must live in the same resource group as this App Service.')
param attachmentsStorageAccountName string

@description('Name of the file share inside the storage account that holds Vaultwarden attachments.')
param attachmentsFileShareName string

@description('Path inside the container where the attachments share is mounted (and what ATTACHMENTS_FOLDER points to).')
param attachmentsMountPath string = '/data/attachments'

@description('Per-user attachment storage limit in kilobytes. The default of 20480 KB (20 MB) caps the maximum file a user can upload.')
@minValue(1)
param userAttachmentLimitKB int = 20480

@description('Per-organization attachment storage limit in kilobytes. The default of 20480 KB (20 MB) caps the maximum file an org member can upload.')
@minValue(1)
param orgAttachmentLimitKB int = 20480

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
resource attachmentsStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: attachmentsStorageAccountName
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
        // Persist Vaultwarden attachments on the Azure Files share mounted at
        // attachmentsMountPath instead of the ephemeral container disk.
        {
          name: 'ATTACHMENTS_FOLDER'
          value: attachmentsMountPath
        }
        // Caps each upload at the configured size (default 20 MB) by limiting
        // the per-user / per-org total attachment quota. Vaultwarden does not
        // expose a per-file size knob, so the storage quota doubles as the
        // per-upload limit.
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
    // Mount the attachments Azure Files share into the container so Vaultwarden
    // writes ATTACHMENTS_FOLDER to durable, VNet-restricted storage instead of
    // the ephemeral container disk. The Web Apps `azurestorageaccounts` config
    // does not accept Key Vault references, so the access key is read directly
    // from the storage account using listKeys() at deploy time.
    configs: [
      {
        name: 'azurestorageaccounts'
        properties: {
          'vaultwarden-attachments': {
            type: 'AzureFiles'
            accountName: attachmentsStorageAccountName
            shareName: attachmentsFileShareName
            mountPath: attachmentsMountPath
            protocol: 'Smb'
            accessKey: attachmentsStorageAccount.listKeys().keys[0].value
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
