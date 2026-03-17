// ========== Cosmos DB (Network Isolated) ========== //
// NETWORK ISOLATION CHANGES:
//   1. publicNetworkAccess → Disabled
//   2. New output: cosmosAccountId (needed for private endpoint in main.bicep)

param solutionLocation string
param accountName string
param tags object = {}

@description('Managed Identity principal ID for data-plane RBAC.')
param managedIdentityPrincipalId string = ''

@description('Deploying user principal ID for data-plane RBAC.')
param deployerPrincipalId string = ''

@allowed(['GlobalDocumentDB', 'MongoDB', 'Parse'])
param kind string = 'GlobalDocumentDB'

var databaseName = 'db_conversation_history'
var collectionName = 'conversations'

var reportsDatabaseName = 'db_well_health'
var reportsContainerName = 'well_health_reports'

var containers = [
  {
    name: collectionName
    id: collectionName
    partitionKey: '/userId'
  }
]

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' = {
  name: accountName
  kind: kind
  location: solutionLocation
  tags: tags
  properties: {
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [
      {
        locationName: solutionLocation
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    disableLocalAuth: true
    apiProperties: (kind == 'MongoDB') ? { serverVersion: '4.0' } : {}
    capabilities: [{ name: 'EnableServerless' }]
    // NETWORK ISOLATION CHANGE: No public access. Data plane only via private endpoint.
    publicNetworkAccess: 'Disabled'
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-05-15' = {
  parent: cosmos
  name: databaseName
  properties: {
    resource: { id: databaseName }
  }

  resource list 'containers' = [for container in containers: {
    name: container.name
    properties: {
      resource: {
        id: container.id
        partitionKey: { paths: [container.partitionKey] }
      }
      options: {}
    }
  }]
}

// Well Health Reports database + container
resource reportsDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-05-15' = {
  parent: cosmos
  name: reportsDatabaseName
  properties: {
    resource: { id: reportsDatabaseName }
  }

  resource reportsContainer 'containers' = {
    name: reportsContainerName
    properties: {
      resource: {
        id: reportsContainerName
        partitionKey: { paths: ['/facility_id'] }
      }
      options: {}
    }
  }
}

// Cosmos DB Built-in Data Contributor role ID: 00000000-0000-0000-0000-000000000002
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

// Data-plane RBAC for Managed Identity
resource miCosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-08-15' = if (!empty(managedIdentityPrincipalId)) {
  parent: cosmos
  name: guid(cosmos.id, managedIdentityPrincipalId, cosmosDataContributorRoleId)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: managedIdentityPrincipalId
    scope: cosmos.id
  }
}

// Data-plane RBAC for deploying user
resource deployerCosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-08-15' = if (!empty(deployerPrincipalId)) {
  parent: cosmos
  name: guid(cosmos.id, deployerPrincipalId, cosmosDataContributorRoleId)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: deployerPrincipalId
    scope: cosmos.id
  }
}

output cosmosAccountName string = cosmos.name
output cosmosDatabaseName string = databaseName
output cosmosReportsDatabaseName string = reportsDatabaseName
output cosmosContainerName string = collectionName
// NETWORK ISOLATION CHANGE: New output for creating the private endpoint.
output cosmosAccountId string = cosmos.id
