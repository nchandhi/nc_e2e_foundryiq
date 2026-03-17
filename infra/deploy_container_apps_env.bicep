// ========== Container Apps Environment ========== //
// Deploys the Azure Container Apps managed environment with Log Analytics integration.
// All MCP servers, Data Broker, and Dashboard Container Apps live in this environment.

@description('Name of the Container Apps Environment.')
param envName string

@description('Location for the Container Apps Environment.')
param solutionLocation string

@description('Log Analytics Workspace customer ID (workspace ID).')
param logAnalyticsCustomerId string = ''

@description('Log Analytics Workspace shared key.')
@secure()
param logAnalyticsSharedKey string = ''

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: solutionLocation
  properties: {
    appLogsConfiguration: {
      destination: !empty(logAnalyticsCustomerId) ? 'log-analytics' : null
      logAnalyticsConfiguration: !empty(logAnalyticsCustomerId) ? {
        customerId: logAnalyticsCustomerId
        #disable-next-line use-secure-parameter-default
        sharedKey: logAnalyticsSharedKey
      } : null
    }
    zoneRedundant: false
  }
}

output envId string = containerAppsEnv.id
output envName string = containerAppsEnv.name
output defaultDomain string = containerAppsEnv.properties.defaultDomain
