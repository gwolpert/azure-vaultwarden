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
      ], adminTokenSecretUri != '' ? [
        {
          name: 'ADMIN_TOKEN'
          value: '@Microsoft.KeyVault(SecretUri=${adminTokenSecretUri})'
        }
      ] : [])
    }
    httpsOnly: true
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
