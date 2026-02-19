// ========================================
// Private DNS Zone Module
// ========================================

targetScope = 'resourceGroup'

@description('The resource ID of the Virtual Network to link the DNS zone to')
param vnetResourceId string

// Deploy Private DNS Zone for Azure Files private endpoint
module privateDnsZoneDeployment 'br/public:avm/res/network/private-dns-zone:0.3.1' = {
  name: '${deployment().name}-private-dns-zone'
  params: {
    #disable-next-line no-hardcoded-env-urls
    name: 'privatelink.file.core.windows.net'
    location: 'global'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: vnetResourceId
        registrationEnabled: false
      }
    ]
  }
}

output resourceId string = privateDnsZoneDeployment.outputs.resourceId
output name string = privateDnsZoneDeployment.outputs.name
