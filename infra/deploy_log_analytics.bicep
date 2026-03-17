// ========== Log Analytics Workspace ========== //
// Deploys a dedicated Log Analytics Workspace.
// Used by Application Insights, Container Apps Environment, and diagnostics.

@description('Name of the Log Analytics Workspace.')
param workspaceName string

@description('Location for the workspace.')
param solutionLocation string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: solutionLocation
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output customerId string = logAnalyticsWorkspace.properties.customerId
#disable-next-line outputs-should-not-contain-secrets
output sharedKey string = logAnalyticsWorkspace.listKeys().primarySharedKey
