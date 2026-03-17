// ========== Azure Container Registry ========== //
// Deploys ACR for storing Docker images for MCP servers, Data Broker, and Dashboard.

@description('Name of the Container Registry.')
param acrName string

@description('Location for the Container Registry.')
param solutionLocation string

@description('SKU for the Container Registry.')
@allowed(['Basic', 'Standard', 'Premium'])
param sku string = 'Basic'

@description('Enable admin user for the Container Registry.')
param adminUserEnabled bool = true

@description('Managed Identity principal ID to assign AcrPull role.')
param pullPrincipalId string = ''

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: solutionLocation
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: 'Enabled'
    policies: {
      retentionPolicy: {
        status: 'disabled'
      }
    }
  }
}

// AcrPull role for Managed Identity (so Container Apps can pull images)
@description('Built-in AcrPull role')
resource acrPullRole 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: resourceGroup()
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(pullPrincipalId)) {
  name: guid(containerRegistry.id, pullPrincipalId, acrPullRole.id)
  scope: containerRegistry
  properties: {
    principalId: pullPrincipalId
    roleDefinitionId: acrPullRole.id
    principalType: 'ServicePrincipal'
  }
}

output acrName string = containerRegistry.name
output acrLoginServer string = containerRegistry.properties.loginServer
output acrId string = containerRegistry.id
