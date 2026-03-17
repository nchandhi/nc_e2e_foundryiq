// ========== Private Endpoint (Reusable Module) ========== //
// Creates a private endpoint that connects an Azure service to your VNet.
//
// HOW IT WORKS:
//   1. Creates a network interface in your PE subnet with a private IP.
//   2. Connects that interface to the target service (e.g. Key Vault, Cosmos DB).
//   3. Registers a DNS record in the private DNS zone so the service hostname
//      resolves to the private IP instead of the public IP.
//
// This module is called once per service from main.bicep.

@description('Name of the private endpoint (e.g. pe-keyvault-ioc123).')
param name string

@description('Location for the private endpoint.')
param location string

@description('Subnet ID where the private endpoint will be placed.')
param subnetId string

@description('Resource ID of the service to connect to (e.g. Key Vault resource ID).')
param privateLinkServiceId string

@description('Group IDs for the private link connection (e.g. ["vault"], ["account"], ["Sql"]).')
param groupIds array

@description('Resource IDs of the private DNS zones for automatic DNS registration. Most services need 1 zone; AI Services needs 3 (cognitiveservices + openai + services.ai).')
param privateDnsZoneIds array

// ---------- Private Endpoint ---------- //
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: name
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
  }
}

// ---------- DNS Zone Group ---------- //
// Creates A records in ALL provided DNS zones.
resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, i) in privateDnsZoneIds: {
      name: replace(last(split(zoneId, '/')), '.', '-')
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

output privateEndpointId string = privateEndpoint.id
output networkInterfaceId string = privateEndpoint.properties.networkInterfaces[0].id
