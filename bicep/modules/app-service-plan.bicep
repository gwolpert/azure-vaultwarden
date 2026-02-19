// ========================================
// App Service Plan Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('App Service Plan SKU')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v3'
  'P2v3'
  'P3v3'
])
param skuName string

// Build the full App Service Plan name using naming convention
// Official abbreviation: 'asp'
var appServicePlanName = '${baseName}-asp'

// Deploy App Service Plan
module appServicePlanDeployment 'br/public:avm/res/web/serverfarm:0.6.0' = {
  name: '${deployment().name}-app-service-plan'
  params: {
    name: appServicePlanName
    location: location
    skuName: skuName
    skuCapacity: 1  // Sets initial instance count to 1. Auto-scaling is only available on Standard (S1+) and Premium tiers; the default B1 (Basic) plan does not support auto-scaling. Manual scaling of instance count is possible on all tiers.
    kind: 'linux'
    reserved: true  // Required for Linux
  }
}

output name string = appServicePlanDeployment.outputs.name
output resourceId string = appServicePlanDeployment.outputs.resourceId
