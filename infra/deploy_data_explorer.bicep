// ========== Azure Data Explorer (Kusto) ========== //
// Deploys ADX cluster + database for telemetry time-series data.
// Used by MCP Server ADX for KQL queries, materialized views, high-volume ingestion.

@description('Name of the ADX cluster.')
param clusterName string

@description('Location for the ADX cluster.')
param solutionLocation string

@description('Name of the database within the ADX cluster.')
param databaseName string = 'TelemetryDB'

@description('SKU for the ADX cluster. Dev/Test uses Dev(No SLA)_Standard_E2d_v4.')
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

@description('Number of instances (nodes) in the cluster. Standard tier requires minimum 2.')
param capacity int = 2

@description('Data retention period in days.')
param softDeletePeriodInDays int = 365

@description('Hot cache period in days.')
param hotCachePeriodInDays int = 31

@description('Managed Identity principal ID to assign Viewer/Admin role.')
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
    publicNetworkAccess: 'Enabled'
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

// Database Admin role for Managed Identity (for MCP Server ADX)
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

// NOTE: ADX automatically grants the deploying user Admin access on the database.
// No explicit principalAssignment is needed for the deployer.

output clusterName string = adxCluster.name
output clusterUri string = adxCluster.properties.uri
output databaseName string = adxDatabase.name
output clusterId string = adxCluster.id
