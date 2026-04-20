// ========================================
// Virtual Network Module
// ========================================

targetScope = 'resourceGroup'

@description('The base name for resources (without suffixes)')
param baseName string

@description('The Azure region where resources will be deployed')
param location string

@description('CIDR for the entire virtual network')
param vnetAddressPrefix string = '10.0.0.0/26'

@description('CIDR for the App Service delegated subnet')
param appServiceSubnetAddressPrefix string = '10.0.0.0/27'

@description('CIDR for the PostgreSQL Flexible Server delegated subnet')
param postgresqlSubnetAddressPrefix string = '10.0.0.32/28'

@description('TCP port used by PostgreSQL Flexible Server')
param postgresqlPort int = 5432

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
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '445'
          description: 'Allow App Service to mount the attachments Azure Files share over SMB via the Microsoft.Storage service endpoint.'
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
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        name: 'app-service-snet'
        addressPrefix: appServiceSubnetAddressPrefix
        delegation: 'Microsoft.Web/serverFarms'
        networkSecurityGroupResourceId: appServiceNsg.outputs.resourceId
        // Microsoft.KeyVault service endpoint so the VNet subnet can be added
        // to the Key Vault firewall as a virtualNetworkRule. This is required
        // for App Service Key Vault references to resolve at runtime when the
        // vault's networkAcls.defaultAction is 'Deny' — the "AzureServices"
        // bypass does NOT cover App Service Key Vault references.
        // Microsoft.Storage service endpoint so the same subnet can be added
        // to the Storage Account firewall as a virtualNetworkRule. This is
        // required for the App Service container to mount the attachments
        // Azure Files share when the storage account denies public traffic.
        serviceEndpoints: [
          'Microsoft.KeyVault'
          'Microsoft.Storage'
        ]
      }
      {
        name: 'postgresql-snet'
        addressPrefix: postgresqlSubnetAddressPrefix
        delegation: 'Microsoft.DBforPostgreSQL/flexibleServers'
        networkSecurityGroupResourceId: postgresqlNsg.outputs.resourceId
      }
    ]
  }
}

output name string = vnetDeployment.outputs.name
output resourceId string = vnetDeployment.outputs.resourceId
output subnetResourceIds array = vnetDeployment.outputs.subnetResourceIds
output appServiceSubnetResourceId string = vnetDeployment.outputs.subnetResourceIds[0]
output postgresqlSubnetResourceId string = vnetDeployment.outputs.subnetResourceIds[1]
output appServiceNsgResourceId string = appServiceNsg.outputs.resourceId
output postgresqlNsgResourceId string = postgresqlNsg.outputs.resourceId
