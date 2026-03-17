// ========== Container App (Reusable Module) ========== //
// UNCHANGED from original — Container Apps inherit network isolation from
// their Container Apps Environment (which is VNet-integrated and internal-only).
// No changes needed at the individual app level.

@description('Name of the Container App.')
param appName string

@description('Location for the Container App.')
param solutionLocation string

@description('Container Apps Environment ID.')
param containerAppsEnvId string

@description('Container image (e.g. myacr.azurecr.io/app:latest).')
param containerImage string = ''

@description('Container registry login server (e.g. myacr.azurecr.io).')
param registryServer string = ''

@description('User-assigned Managed Identity resource ID for registry pull and app identity.')
param userAssignedIdentityId string = ''

@description('CPU cores for the container (e.g. "0.5").')
param cpuCores string = '0.5'

@description('Memory in Gi for the container (e.g. "1Gi").')
param memorySize string = '1Gi'

@description('Minimum number of replicas.')
param minReplicas int = 0

@description('Maximum number of replicas.')
param maxReplicas int = 3

@description('Target port the container listens on.')
param targetPort int = 8000

@description('Whether this app should have an external ingress (public URL).')
param externalIngress bool = false

@description('Environment variables as key-value pairs.')
param envVars array = []

@description('Tags for the resource.')
param tags object = {}

// Determine whether we have a real image or use a placeholder
var hasImage = !empty(containerImage)
var image = hasImage ? containerImage : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: solutionLocation
  tags: tags
  identity: !empty(userAssignedIdentityId) ? {
    type: 'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: externalIngress
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: !empty(registryServer) ? [
        {
          server: registryServer
          identity: !empty(userAssignedIdentityId) ? userAssignedIdentityId : 'system'
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: appName
          image: image
          resources: {
            cpu: json(cpuCores)
            memory: memorySize
          }
          env: envVars
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output appId string = containerApp.id
output appName string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output appUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output systemIdentityPrincipalId string = containerApp.identity.principalId
