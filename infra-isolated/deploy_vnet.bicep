// ========== Virtual Network ========== //
// Creates the VNet that all isolated services connect through.
//
// WHY: A VNet is the foundation of network isolation in Azure. Instead of
// services talking over the public internet, they communicate through
// private IP addresses inside this network.
//
// SUBNET LAYOUT (10.0.0.0/16):
//   10.0.0.0/23  → Container Apps (needs /23 minimum for consumption plan)
//   10.0.2.0/24  → Private Endpoints (where services get their private IPs)
//   10.0.3.0/24  → Databricks host subnet (public side of VNet injection)
//   10.0.4.0/24  → Databricks container subnet (private side of VNet injection)
//   10.0.5.0/26  → AzureBastionSubnet (name MUST be exactly this — Azure requirement)
//   10.0.6.0/24  → Jump box VM (your workstation inside the VNet)

@description('Name of the Virtual Network.')
param vnetName string

@description('Location for the VNet.')
param solutionLocation string

@description('Address space for the VNet.')
param addressPrefix string = '10.0.0.0/16'

// ---------- NSGs for Databricks ---------- //
// Databricks VNet injection requires NSGs on its subnets.
// We create empty NSGs here — Databricks automatically adds the rules it needs.

resource nsgDbxHost 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-${vnetName}-dbx-host'
  location: solutionLocation
  properties: { securityRules: [] }
}

resource nsgDbxContainer 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-${vnetName}-dbx-container'
  location: solutionLocation
  properties: { securityRules: [] }
}

// ---------- Virtual Network ---------- //
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: solutionLocation
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        // Container Apps Environment lives here.
        // Delegation tells Azure this subnet is reserved for Container Apps.
        name: 'snet-container-apps'
        properties: {
          addressPrefix: '10.0.0.0/23'
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        // Private Endpoints land here — each service gets a private IP in this subnet.
        // privateEndpointNetworkPolicies must be Disabled for PEs to work.
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.0.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        // Databricks "host" subnet — runs the driver nodes.
        // Delegation reserves it exclusively for Databricks.
        name: 'snet-databricks-host'
        properties: {
          addressPrefix: '10.0.3.0/24'
          networkSecurityGroup: { id: nsgDbxHost.id }
          delegations: [
            {
              name: 'Microsoft.Databricks.workspaces'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
        }
      }
      {
        // Databricks "container" subnet — runs the worker nodes.
        name: 'snet-databricks-container'
        properties: {
          addressPrefix: '10.0.4.0/24'
          networkSecurityGroup: { id: nsgDbxContainer.id }
          delegations: [
            {
              name: 'Microsoft.Databricks.workspaces'
              properties: {
                serviceName: 'Microsoft.Databricks/workspaces'
              }
            }
          ]
        }
      }
      {
        // Azure Bastion MUST live in a subnet named exactly "AzureBastionSubnet".
        // This is a hard Azure requirement — any other name will fail.
        // Minimum size is /26 (64 IPs). Bastion uses this to broker RDP/SSH sessions
        // to VMs without exposing them to the internet.
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.5.0/26'
        }
      }
      {
        // Jump box VM lives here. You RDP/SSH into this VM through Bastion,
        // then run scripts, access Key Vault, push to ACR, etc.
        name: 'snet-jumpbox'
        properties: {
          addressPrefix: '10.0.6.0/24'
        }
      }
    ]
  }
}

// ---------- Outputs ---------- //
output vnetId string = vnet.id
output vnetName string = vnet.name
output caeSubnetId string = vnet.properties.subnets[0].id
output peSubnetId string = vnet.properties.subnets[1].id
output dbxHostSubnetId string = vnet.properties.subnets[2].id
output dbxContainerSubnetId string = vnet.properties.subnets[3].id
output bastionSubnetId string = vnet.properties.subnets[4].id
output jumpboxSubnetId string = vnet.properties.subnets[5].id
