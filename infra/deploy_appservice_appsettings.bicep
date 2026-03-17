// ========== App Service - App Settings ========== //
param name string

@secure()
param appSettings object = {}

resource webApp 'Microsoft.Web/sites@2022-03-01' existing = {
  name: name
}

resource webAppSettings 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'appsettings'
  parent: webApp
  properties: appSettings
}
