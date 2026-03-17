// ========== Azure Databricks Workspace ========== //
// Deploys an Azure Databricks workspace for production analytics.
// Used by MCP Server Databricks for Spark SQL queries, Unity Catalog, Delta Lake.

@description('Name of the Databricks workspace.')
param workspaceName string

@description('Location for the Databricks workspace.')
param solutionLocation string

@description('Pricing tier for the Databricks workspace.')
@allowed(['standard', 'premium', 'trial'])
param pricingTier string = 'premium'

@description('Managed Resource Group Name for Databricks managed resources.')
param managedResourceGroupName string = ''

// Databricks requires a managed resource group for its internal resources
var dbManagedRgName = !empty(managedResourceGroupName) ? managedResourceGroupName : 'databricks-rg-${workspaceName}'

resource databricksWorkspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: workspaceName
  location: solutionLocation
  sku: {
    name: pricingTier
  }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', dbManagedRgName)
    publicNetworkAccess: 'Enabled'
    parameters: {
      enableNoPublicIp: {
        value: false
      }
    }
  }
}

output workspaceName string = databricksWorkspace.name
output workspaceId string = databricksWorkspace.id
output workspaceUrl string = 'https://${databricksWorkspace.properties.workspaceUrl}'
output managedResourceGroupId string = databricksWorkspace.properties.managedResourceGroupId
output workspaceResourceId string = databricksWorkspace.id
