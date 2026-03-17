// ========== Virtual Network (Minimal — AI Foundry + AI Search) ========== //
// Stripped-down VNet for testing network isolation with just AI services.
//
// SUBNET LAYOUT (10.0.0.0/16):
//   10.0.2.0/24  → Private Endpoints (AI Services, AI Search, Key Vault, Storage)
//   10.0.5.0/26  → AzureBastionSubnet (secure entry point)
//   10.0.6.0/24  → Jump box VM (your workstation inside the VNet)
//
// NOTE: No Container Apps or Databricks subnets — those come later
// when you expand to the full infra-isolated/ deployment.

@description('Name of the Virtual Network.')
param vnetName string

@description('Location for the VNet.')
param solutionLocation string

@description('Address space for the VNet.')
param addressPrefix string = '10.0.0.0/16'

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: solutionLocation
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        // Private Endpoints land here — each service gets a private IP in this subnet.
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.0.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        // Azure Bastion MUST live in a subnet named exactly "AzureBastionSubnet".
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.5.0/26'
        }
      }
      {
        // Jump box VM — you RDP/SSH here through Bastion to test services.
        name: 'snet-jumpbox'
        properties: {
          addressPrefix: '10.0.6.0/24'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output peSubnetId string = vnet.properties.subnets[0].id
output bastionSubnetId string = vnet.properties.subnets[1].id
output jumpboxSubnetId string = vnet.properties.subnets[2].id
