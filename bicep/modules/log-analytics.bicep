// ========================================
// Log Analytics Workspace Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

// Build the full Log Analytics Workspace name using naming convention
// Pattern: {baseName}-log
var logAnalyticsWorkspaceName = '${baseName}-log'

// Deploy Log Analytics Workspace
module logAnalyticsDeployment 'br/public:avm/res/operational-insights/workspace:0.3.4' = {
  name: 'log-analytics-deployment'
  params: {
    name: logAnalyticsWorkspaceName
    location: location
  }
}

output name string = logAnalyticsDeployment.outputs.name
output resourceId string = logAnalyticsDeployment.outputs.resourceId
