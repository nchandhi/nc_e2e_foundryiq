// ========== Azure Key Vault ========== //
// Deploys Key Vault for secrets management.
// Stores connection strings, API keys, and OAuth client credentials
// used by MCP servers and Data Broker service.

@description('Name of the Key Vault.')
param vaultName string

@description('Location for the Key Vault.')
param solutionLocation string

@description('Managed Identity principal ID to grant Key Vault Secrets User role.')
param managedIdentityPrincipalId string = ''

@description('Deploying user principal ID for Key Vault Administrator role.')
param deployerPrincipalId string = ''

@description('Principal type of the deploying user.')
@allowed(['User', 'ServicePrincipal'])
param deployerPrincipalType string = 'User'

@description('Enable soft delete for the Key Vault.')
param enableSoftDelete bool = true

@description('Soft delete retention in days.')
param softDeleteRetentionInDays int = 7

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: solutionLocation
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    publicNetworkAccess: 'Enabled'
  }
}

// Key Vault Secrets User role for Managed Identity
// This allows MCP servers and Data Broker to read secrets at runtime
@description('Built-in Key Vault Secrets User role')
resource kvSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: resourceGroup()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource miSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(managedIdentityPrincipalId)) {
  name: guid(keyVault.id, managedIdentityPrincipalId, kvSecretsUserRole.id)
  scope: keyVault
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: kvSecretsUserRole.id
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Administrator role for deploying user
@description('Built-in Key Vault Administrator role')
resource kvAdminRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: resourceGroup()
  name: '00482a5a-887f-4fb3-b363-3b7fe8e74483'
}

resource deployerAdminAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(keyVault.id, deployerPrincipalId, kvAdminRole.id)
  scope: keyVault
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: kvAdminRole.id
    principalType: deployerPrincipalType
  }
}

output vaultName string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
output vaultId string = keyVault.id
