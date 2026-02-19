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

// Deploy Virtual Network with subnet for App Service VNet Integration
module vnetDeployment 'br/public:avm/res/network/virtual-network:0.1.8' = {
  name: '${deployment().name}-vnet'
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {
        name: 'app-service-subnet'
        addressPrefix: '10.0.0.0/24'
        delegations: [
          {
            name: 'MicrosoftWebServerFarms'
            properties: {
              serviceName: 'Microsoft.Web/serverFarms'
            }
          }
        ]
      }
      {
        name: 'private-endpoint-subnet'
        addressPrefix: '10.0.1.0/24'
        privateEndpointNetworkPolicies: 'Disabled'
      }
    ]
  }
}

output name string = vnetDeployment.outputs.name
output resourceId string = vnetDeployment.outputs.resourceId
output subnetResourceIds array = vnetDeployment.outputs.subnetResourceIds
output appServiceSubnetResourceId string = vnetDeployment.outputs.subnetResourceIds[0]
output privateEndpointSubnetResourceId string = vnetDeployment.outputs.subnetResourceIds[1]
