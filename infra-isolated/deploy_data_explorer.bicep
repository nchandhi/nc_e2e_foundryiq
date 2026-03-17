// ========== Azure Data Explorer / Kusto (Network Isolated) ========== //
// NETWORK ISOLATION CHANGE:
//   publicNetworkAccess → Disabled (data queries only via private endpoint)

@description('Name of the ADX cluster.')
param clusterName string

@description('Location for the ADX cluster.')
param solutionLocation string

@description('Name of the database within the ADX cluster.')
param databaseName string = 'TelemetryDB'

@description('SKU for the ADX cluster.')
@allowed([
  'Standard_E2d_v4'
  'Standard_E2ads_v5'
  'Standard_E4ads_v5'
  'Standard_E8ads_v5'
])
param skuName string = 'Standard_E2d_v4'

@description('SKU tier for the ADX cluster.')
@allowed(['Basic', 'Standard'])
param skuTier string = 'Standard'

@description('Number of instances (nodes) in the cluster.')
param capacity int = 2

@description('Data retention period in days.')
param softDeletePeriodInDays int = 365

@description('Hot cache period in days.')
param hotCachePeriodInDays int = 31

@description('Managed Identity principal ID to assign Admin role.')
param managedIdentityPrincipalId string = ''

@description('Deploying user principal ID for Database Admin role.')
param deployerPrincipalId string = ''

resource adxCluster 'Microsoft.Kusto/clusters@2023-08-15' = {
  name: clusterName
  location: solutionLocation
  sku: {
    name: skuName
    tier: skuTier
    capacity: capacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enableStreamingIngest: true
    enableAutoStop: true
    enablePurge: false
    // NETWORK ISOLATION CHANGE: No public access. KQL queries go through private endpoint.
    publicNetworkAccess: 'Disabled'
  }
}

resource adxDatabase 'Microsoft.Kusto/clusters/databases@2023-08-15' = {
  parent: adxCluster
  name: databaseName
  location: solutionLocation
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: 'P${softDeletePeriodInDays}D'
    hotCachePeriod: 'P${hotCachePeriodInDays}D'
  }
}

// Database Admin role for Managed Identity
resource miAdminRole 'Microsoft.Kusto/clusters/databases/principalAssignments@2023-08-15' = if (!empty(managedIdentityPrincipalId)) {
  parent: adxDatabase
  name: guid(adxDatabase.id, managedIdentityPrincipalId, 'Admin')
  properties: {
    principalId: managedIdentityPrincipalId
    role: 'Admin'
    tenantId: subscription().tenantId
    principalType: 'App'
  }
}

output clusterName string = adxCluster.name
output clusterUri string = adxCluster.properties.uri
output databaseName string = adxDatabase.name
output clusterId string = adxCluster.id
