// ========== Azure Databricks Workspace (Network Isolated) ========== //
// NETWORK ISOLATION CHANGES:
//   1. VNet injection — Databricks clusters run inside YOUR VNet subnets instead
//      of Microsoft-managed VNets. This means data never leaves your network.
//   2. enableNoPublicIp = true — cluster nodes don't get public IPs (Secure Cluster Connectivity).
//   3. publicNetworkAccess → Disabled — the workspace UI/API is only reachable via PE.
//   4. New params: subnetIds for host and container subnets, VNet ID.

@description('Name of the Databricks workspace.')
param workspaceName string

@description('Location for the Databricks workspace.')
param solutionLocation string

@description('Pricing tier for the Databricks workspace.')
@allowed(['standard', 'premium', 'trial'])
param pricingTier string = 'premium'

@description('Managed Resource Group Name for Databricks managed resources.')
param managedResourceGroupName string = ''

// NETWORK ISOLATION CHANGE: New parameters for VNet injection.
@description('Resource ID of the VNet for Databricks VNet injection.')
param vnetId string

@description('Name of the host (public) subnet for Databricks.')
param hostSubnetName string = 'snet-databricks-host'

@description('Name of the container (private) subnet for Databricks.')
param containerSubnetName string = 'snet-databricks-container'

var dbManagedRgName = !empty(managedResourceGroupName) ? managedResourceGroupName : 'databricks-rg-${workspaceName}'

resource databricksWorkspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: workspaceName
  location: solutionLocation
  sku: {
    name: pricingTier
  }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', dbManagedRgName)
    // NETWORK ISOLATION CHANGE: No public access to workspace UI/API.
    // Users and services reach it through the private endpoint.
    publicNetworkAccess: 'Disabled'
    requiredNsgRules: 'AllRules'   // Let Databricks manage NSG rules on the subnets.
    parameters: {
      // NETWORK ISOLATION CHANGE: No public IPs on cluster nodes (Secure Cluster Connectivity).
      // Nodes communicate with the control plane through a secure relay, not public IPs.
      enableNoPublicIp: {
        value: true
      }
      // NETWORK ISOLATION CHANGE: VNet injection — clusters run in these subnets.
      customVirtualNetworkId: {
        value: vnetId
      }
      customPublicSubnetName: {
        value: hostSubnetName
      }
      customPrivateSubnetName: {
        value: containerSubnetName
      }
    }
  }
}

output workspaceName string = databricksWorkspace.name
output workspaceId string = databricksWorkspace.id
output workspaceUrl string = 'https://${databricksWorkspace.properties.workspaceUrl}'
output managedResourceGroupId string = databricksWorkspace.properties.managedResourceGroupId
output workspaceResourceId string = databricksWorkspace.id
