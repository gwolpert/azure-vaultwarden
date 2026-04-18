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

@description('Admin token hash for Vaultwarden admin panel (argon2id hash, empty to disable)')
@secure()
param adminTokenHash string = ''

@description('Database connection URL for PostgreSQL')
@secure()
param databaseUrl string

// Build the full App Service name using naming convention
// Official abbreviation: 'app'
var appServiceName = '${baseName}-app'

// Deploy App Service (Web App for Containers)
module appServiceDeployment 'br/public:avm/res/web/site:0.21.0' = {
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
          value: databaseUrl
        }
        {
          name: 'IP_HEADER'
          value: 'X-Client-IP'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
      ], adminTokenHash != '' ? [
        {
          name: 'ADMIN_TOKEN'
          value: adminTokenHash
        }
      ] : [])
    }
    httpsOnly: true
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalyticsWorkspaceResourceId
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
