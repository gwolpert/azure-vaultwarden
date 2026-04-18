// ========================================
// Virtual Network Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

// Build the full VNet name using naming convention
var vnetName = '${baseName}-vnet'

// Deploy Virtual Network with subnets for App Service and PostgreSQL
module vnetDeployment 'br/public:avm/res/network/virtual-network:0.8.0' = {
  name: '${deployment().name}-vnet'
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {
        name: 'app-service-snet'
        addressPrefix: '10.0.0.0/24'
        delegation: 'Microsoft.Web/serverFarms'
      }
      {
        name: 'postgresql-snet'
        addressPrefix: '10.0.1.0/24'
        delegation: 'Microsoft.DBforPostgreSQL/flexibleServers'
      }
    ]
  }
}

output name string = vnetDeployment.outputs.name
output resourceId string = vnetDeployment.outputs.resourceId
output subnetResourceIds array = vnetDeployment.outputs.subnetResourceIds
output appServiceSubnetResourceId string = vnetDeployment.outputs.subnetResourceIds[0]
output postgresqlSubnetResourceId string = vnetDeployment.outputs.subnetResourceIds[1]
