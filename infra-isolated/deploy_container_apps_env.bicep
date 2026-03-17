// ========== Container Apps Environment (Network Isolated) ========== //
// NETWORK ISOLATION CHANGES:
//   1. VNet integration — the environment runs inside your VNet subnet.
//   2. internal = true — Container Apps get private IPs only, no public URLs.
//      To expose the web app publicly, you'd add an Application Gateway or Azure Front Door.
//   3. New param: subnetId for the Container Apps subnet.

@description('Name of the Container Apps Environment.')
param envName string

@description('Location for the Container Apps Environment.')
param solutionLocation string

@description('Log Analytics Workspace customer ID (workspace ID).')
param logAnalyticsCustomerId string = ''

@description('Log Analytics Workspace shared key.')
@secure()
param logAnalyticsSharedKey string = ''

// NETWORK ISOLATION CHANGE: Subnet ID for VNet integration.
@description('Subnet ID for the Container Apps Environment (needs /23 minimum, delegated to Microsoft.App/environments).')
param subnetId string

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
    // NETWORK ISOLATION CHANGE: Inject into VNet with internal-only access.
    vnetConfiguration: {
      infrastructureSubnetId: subnetId
      internal: true   // No public ingress — apps only accessible from inside the VNet.
    }
    zoneRedundant: false
  }
}

output envId string = containerAppsEnv.id
output envName string = containerAppsEnv.name
output defaultDomain string = containerAppsEnv.properties.defaultDomain
