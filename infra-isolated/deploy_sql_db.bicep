// ========== Azure SQL Database (Network Isolated) ========== //
// NETWORK ISOLATION CHANGES:
//   1. publicNetworkAccess → Disabled
//   2. Removed "AllowAllAzureIPs" firewall rule (not needed with PE)
//   3. New output: sqlServerId (needed for private endpoint)

param solutionLocation string
param managedIdentityName string
param serverName string
param sqlDBName string
param deployerPrincipalId string = ''

var location = solutionLocation

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  properties: {
    // NETWORK ISOLATION CHANGE: No public access. SQL clients connect via private endpoint.
    publicNetworkAccess: 'Disabled'
    version: '12.0'
    restrictOutboundNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
    administrators: {
      login: !empty(deployerPrincipalId) ? deployerPrincipalId : managedIdentityName
      sid: !empty(deployerPrincipalId) ? deployerPrincipalId : managedIdentity.properties.principalId
      tenantId: subscription().tenantId
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
    }
  }
}

// NETWORK ISOLATION CHANGE: Removed the "AllowAllAzureIPs" firewall rule.
// With public access disabled, firewall rules aren't needed — all access goes through PE.

resource sqlDB 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDBName
  location: location
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    autoPauseDelay: 60
    minCapacity: 1
    readScale: 'Disabled'
    zoneRedundant: false
  }
}

output sqlServerName string = '${serverName}${environment().suffixes.sqlServerHostname}'
output sqlDbName string = sqlDBName
// NETWORK ISOLATION CHANGE: New output for creating the private endpoint.
output sqlServerId string = sqlServer.id
