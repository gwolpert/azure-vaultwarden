// ========================================
// Private DNS Zone Module
// ========================================
// Generic wrapper around the AVM private-dns-zone module so callers can
// provision and VNet-link any privatelink.* DNS zone (PostgreSQL, Key Vault,
// Storage Files, etc.) without duplicating module plumbing.

targetScope = 'resourceGroup'

@description('The fully qualified DNS zone name (e.g. privatelink.vaultcore.azure.net)')
param zoneName string

@description('The resource ID of the Virtual Network to link the DNS zone to')
param vnetResourceId string

// Deploy a Private DNS Zone and link it to the supplied virtual network so
// records resolved from inside the VNet point at the private endpoint IPs.
module privateDnsZoneDeployment 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  name: '${deployment().name}-private-dns-zone'
  params: {
    name: zoneName
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
