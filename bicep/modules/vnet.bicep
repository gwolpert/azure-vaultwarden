// ========================================
// Virtual Network Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('CIDR for the entire virtual network')
param vnetAddressPrefix string = '10.101.0.0/24'

@description('CIDR for the App Service delegated subnet')
param appServiceSubnetAddressPrefix string = '10.101.0.0/26'

@description('CIDR for the PostgreSQL Flexible Server delegated subnet')
param postgresqlSubnetAddressPrefix string = '10.101.0.64/26'

@description('CIDR for the subnet hosting private endpoints (Key Vault, Storage Account, etc.). Must be inside vnetAddressPrefix and not overlap with the other subnets.')
param privateEndpointsSubnetAddressPrefix string = '10.101.0.128/26'

@description('TCP port used by PostgreSQL Flexible Server')
param postgresqlPort int = 5432

@description('Resource tags applied to the VNet and its NSGs.')
param tags object = {}

// Build the full VNet name using naming convention
var vnetName = '${baseName}-vnet'
var appServiceNsgName = '${baseName}-app-snet-nsg'
var postgresqlNsgName = '${baseName}-psql-snet-nsg'

// Network Security Group for the App Service subnet
//   Inbound: only HTTPS (443) from the internet (+ AzureLoadBalancer health probes); deny-all otherwise.
//   Outbound: PostgreSQL (5432) is restricted to the database subnet only — any other traffic destined
//   for the database subnet is denied. Outbound traffic to the rest of the internet/Azure (Key Vault,
//   MCR, Azure metadata, DNS, etc.) is intentionally left to the platform default rules so the
//   container can pull images and the app can reach its dependencies.
module appServiceNsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: '${deployment().name}-app-snet-nsg'
  params: {
    name: appServiceNsgName
    location: location
    tags: tags
    securityRules: [
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: appServiceSubnetAddressPrefix
          destinationPortRange: '443'
          description: 'Allow inbound HTTPS from the internet to the App Service subnet'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 200
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Allow Azure infrastructure health probes'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny everything else inbound'
        }
      }
      {
        name: 'Allow-Postgres-Outbound'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Outbound'
          protocol: 'Tcp'
          sourceAddressPrefix: appServiceSubnetAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: postgresqlSubnetAddressPrefix
          destinationPortRange: string(postgresqlPort)
          description: 'Allow App Service to reach PostgreSQL on its TCP port'
        }
      }
      {
        name: 'Allow-Storage-Outbound'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Outbound'
          protocol: 'Tcp'
          sourceAddressPrefix: appServiceSubnetAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointsSubnetAddressPrefix
          destinationPortRange: '445'
          description: 'Allow App Service to mount the data Azure Files share over SMB via the Storage Account private endpoint in the private-endpoints subnet.'
        }
      }
      {
        name: 'Deny-Postgres-Subnet-Outbound'
        properties: {
          priority: 200
          access: 'Deny'
          direction: 'Outbound'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: postgresqlSubnetAddressPrefix
          destinationPortRange: '*'
          description: 'Defense-in-depth: deny any non-PostgreSQL traffic destined for the PostgreSQL subnet (the Allow rule above is the only path)'
        }
      }
    ]
  }
}

// Network Security Group for the PostgreSQL subnet
//   Inbound: only PostgreSQL (5432) from the App Service subnet
module postgresqlNsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: '${deployment().name}-psql-snet-nsg'
  params: {
    name: postgresqlNsgName
    location: location
    tags: tags
    securityRules: [
      {
        name: 'Allow-Postgres-From-AppService'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: appServiceSubnetAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: postgresqlSubnetAddressPrefix
          destinationPortRange: string(postgresqlPort)
          description: 'Allow PostgreSQL traffic from the App Service subnet only'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny everything else inbound'
        }
      }
    ]
  }
}

// Deploy Virtual Network with subnets for App Service and PostgreSQL
module vnetDeployment 'br/public:avm/res/network/virtual-network:0.8.0' = {
  name: '${deployment().name}-vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        name: 'app-service-snet'
        addressPrefix: appServiceSubnetAddressPrefix
        delegation: 'Microsoft.Web/serverFarms'
        networkSecurityGroupResourceId: appServiceNsg.outputs.resourceId
        // Key Vault and Storage Account are reached over private endpoints
        // deployed into the dedicated private-endpoints-snet, so this subnet
        // no longer needs Microsoft.KeyVault / Microsoft.Storage service
        // endpoints. Resolution happens via the private DNS zones linked to
        // this VNet.
      }
      {
        name: 'postgresql-snet'
        addressPrefix: postgresqlSubnetAddressPrefix
        delegation: 'Microsoft.DBforPostgreSQL/flexibleServers'
        networkSecurityGroupResourceId: postgresqlNsg.outputs.resourceId
      }
      {
        name: 'private-endpoints-snet'
        addressPrefix: privateEndpointsSubnetAddressPrefix
        // Disable network policies so private endpoint NICs can be created
        // in this subnet (Azure currently requires this for PEs).
        privateEndpointNetworkPolicies: 'Disabled'
      }
    ]
  }
}

output name string = vnetDeployment.outputs.name
output resourceId string = vnetDeployment.outputs.resourceId
output subnetResourceIds array = vnetDeployment.outputs.subnetResourceIds
// Resolve subnet resource IDs deterministically by name rather than by their position
// in the AVM module's `subnetResourceIds` array. Reordering or adding subnets above
// must not silently rewire downstream modules to the wrong subnet.
output appServiceSubnetResourceId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'app-service-snet')
output postgresqlSubnetResourceId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'postgresql-snet')
output privateEndpointsSubnetResourceId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'private-endpoints-snet')
output appServiceNsgResourceId string = appServiceNsg.outputs.resourceId
output postgresqlNsgResourceId string = postgresqlNsg.outputs.resourceId
