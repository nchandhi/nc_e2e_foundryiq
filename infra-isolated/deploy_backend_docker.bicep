// ========== Backend Docker Deployment ========== //
// UNCHANGED from original — legacy module.
param imageTag string
param acrName string
param applicationInsightsId string

@description('Solution Location')
param solutionLocation string

@secure()
param appSettings object = {}
param appServicePlanId string
param userassignedIdentityId string
param aiServicesName string
param enableCosmosDb bool = false

var imageName = 'DOCKER|${acrName}.azurecr.io/contoso-ioc-api:${imageTag}'
param name string

var reactAppLayoutConfig = '''{
  "appConfig": {
    "ALERTS_HEALTHREPORT_CHAT": {
      "ALERTS": 25,
      "HEALTHREPORT": 45,
      "CHAT": 30
    }
  }
}'''

module appService 'deploy_app_service.bicep' = {
  name: '${name}-app-module'
  params: {
    solutionName: name
    solutionLocation: solutionLocation
    appServicePlanId: appServicePlanId
    appImageName: imageName
    userassignedIdentityId: userassignedIdentityId
    appSettings: union(
      appSettings,
      {
        APPINSIGHTS_INSTRUMENTATIONKEY: reference(applicationInsightsId, '2015-05-01').InstrumentationKey
        REACT_APP_LAYOUT_CONFIG: reactAppLayoutConfig
      }
    )
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' existing = if (enableCosmosDb) {
  name: appSettings.AZURE_COSMOSDB_ACCOUNT
}

resource contributorRoleDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2024-05-15' existing = if (enableCosmosDb) {
  parent: cosmos
  name: '00000000-0000-0000-0000-000000000002'
}

resource cosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-05-15' = if (enableCosmosDb) {
  parent: cosmos
  name: guid(contributorRoleDefinition.id, cosmos.id)
  properties: {
    principalId: appService.outputs.identityPrincipalId
    roleDefinitionId: contributorRoleDefinition.id
    scope: cosmos.id
  }
}

resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesName
}

resource aiUser 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
}

resource assignAiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appService.name, aiServices.id, aiUser.id)
  scope: aiServices
  properties: {
    principalId: appService.outputs.identityPrincipalId
    roleDefinitionId: aiUser.id
    principalType: 'ServicePrincipal'
  }
}

output appUrl string = appService.outputs.appUrl
output appName string = name
output reactAppLayoutConfig string = reactAppLayoutConfig
output appInsightInstrumentationKey string = reference(applicationInsightsId, '2015-05-01').InstrumentationKey
output identityPrincipalId string = appService.outputs.identityPrincipalId
