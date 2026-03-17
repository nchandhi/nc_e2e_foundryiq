// ========== Azure Bastion ========== //
// Provides secure RDP/SSH access to VMs inside the VNet WITHOUT exposing them to the internet.
//
// HOW IT WORKS:
//   1. You go to the Azure Portal → find your jump VM → click "Connect via Bastion".
//   2. Bastion opens an RDP/SSH session IN YOUR BROWSER (or native client).
//   3. The session goes: Your browser → Bastion (public IP) → VM (private IP).
//   4. The VM never gets a public IP. It's only reachable through Bastion.
//
// WHY NOT JUST A PUBLIC IP ON THE VM?
//   A public IP on the VM would be a security hole — anyone could try to brute-force SSH.
//   Bastion sits in front, handles TLS, integrates with Azure AD, and logs all sessions.

@description('Name of the Bastion host.')
param bastionName string

@description('Location for the Bastion host.')
param solutionLocation string

@description('Subnet ID for the AzureBastionSubnet (must be named exactly that).')
param bastionSubnetId string

// ---------- Public IP for Bastion ---------- //
// Bastion is the ONE resource that needs a public IP (it's the front door to your network).
// Standard SKU + Static allocation are required by Bastion.
resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-${bastionName}'
  location: solutionLocation
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ---------- Bastion Host ---------- //
resource bastionHost 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: bastionName
  location: solutionLocation
  sku: {
    name: 'Basic'        // Basic SKU is sufficient. Standard adds tunneling, IP-based connect, etc.
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ip-config'
        properties: {
          publicIPAddress: {
            id: bastionPip.id
          }
          subnet: {
            id: bastionSubnetId
          }
        }
      }
    ]
  }
}

output bastionId string = bastionHost.id
output bastionName string = bastionHost.name
