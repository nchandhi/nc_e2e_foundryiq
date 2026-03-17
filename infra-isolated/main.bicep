// ========== main.bicep (Network Isolated) ========== //
// Contoso IOC Health Check - Main Infrastructure Deployment WITH NETWORK ISOLATION
//
// WHAT'S DIFFERENT FROM THE ORIGINAL:
//   1. NEW: Virtual Network (VNet) with subnets for each workload.
//   2. NEW: Private DNS Zones so service names resolve to private IPs.
//   3. NEW: Private Endpoints connecting each service to the VNet.
//   4. CHANGED: All services have publicNetworkAccess = Disabled.
//   5. CHANGED: Container Apps Environment is VNet-integrated and internal-only.
//   6. CHANGED: Databricks uses VNet injection (clusters run in your network).
//   7. CHANGED: Container Registry requires Premium SKU for private endpoints.
//   8. NEW: Azure Bastion + jump box VM for secure access into the VNet.
//
// DEPLOYMENT NOTE:
//   Because all services block public access, post-deployment data-plane operations
//   (e.g. running Python scripts to load data) must happen from INSIDE the VNet.
//   Azure Bastion + a jump box VM are included for this purpose.
//
// ARCHITECTURE (same services as original, but all traffic stays private):
//
//   ┌─────────────────── VNet (10.0.0.0/16) ───────────────────┐
//   │                                                           │
//   │  ┌── snet-container-apps (10.0.0.0/23) ──┐               │
//   │  │  Container Apps Env (internal only)    │               │
//   │  │  ├─ Data Broker                        │               │
//   │  │  ├─ MCP Server ADX                     │               │
//   │  │  ├─ MCP Server Databricks              │               │
//   │  │  ├─ MCP Server Cosmos                  │               │
//   │  │  └─ Web App (Chat UI)                  │               │
//   │  └────────────────────────────────────────┘               │
//   │                                                           │
//   │  ┌── snet-private-endpoints (10.0.2.0/24) ─┐             │
//   │  │  PE → AI Services        (10.0.2.x)     │             │
//   │  │  PE → AI Search          (10.0.2.x)     │             │
//   │  │  PE → Key Vault          (10.0.2.x)     │             │
//   │  │  PE → Container Registry (10.0.2.x)     │             │
//   │  │  PE → Cosmos DB          (10.0.2.x)     │             │
//   │  │  PE → SQL Database       (10.0.2.x)     │             │
//   │  │  PE → Storage Account    (10.0.2.x)     │             │
//   │  │  PE → Data Explorer      (10.0.2.x)     │             │
//   │  │  PE → Databricks         (10.0.2.x)     │             │
//   │  └──────────────────────────────────────────┘             │
//   │                                                           │
//   │  ┌── snet-databricks-* (10.0.3-4.0/24) ──┐              │
//   │  │  Databricks host + container nodes      │              │
//   │  └─────────────────────────────────────────┘              │
//   │                                                           │//   ┌── AzureBastionSubnet (10.0.5.0/26) ───┐              │
//   │  Bastion Host (public IP → portal SSH)  │              │
//   └─────────────────────────────────────────┘              │
//                                                           │
//   ┌── snet-jumpbox (10.0.6.0/24) ────────┐              │
//   │  Jump VM (Ubuntu + Python + Azure CLI)  │              │
//   └─────────────────────────────────────────┘              │
//                                                           │//   └───────────────────────────────────────────────────────────┘

targetScope = 'resourceGroup'

var abbrs = loadJsonContent('./abbreviations.json')

// ========== Parameters ========== //
@minLength(3)
@maxLength(20)
@description('A unique environment name prefix for all resources (3-20 chars):')
param environmentName string

@minLength(1)
@description('Secondary location for databases (e.g., eastus2):')
param secondaryLocation string = 'eastus2'

@description('Location for AI Search service.')
param searchServiceLocation string = resourceGroup().location

@minLength(1)
@description('GPT model deployment type:')
@allowed(['Standard', 'GlobalStandard'])
param deploymentType string = 'GlobalStandard'

@description('Name of the GPT model to deploy:')
param gptModelName string = 'gpt-4o-mini'

@description('Version of the GPT model to deploy:')
param gptModelVersion string = '2024-07-18'

param azureOpenAIApiVersion string = '2025-01-01-preview'
param azureAiAgentApiVersion string = '2025-05-01'

@minValue(10)
@description('Capacity of the GPT deployment:')
param gptDeploymentCapacity int = 150

@minLength(1)
@description('Name of the Text Embedding model to deploy:')
@allowed(['text-embedding-3-small'])
param embeddingModel string = 'text-embedding-3-small'

@minValue(10)
@description('Capacity of the Embedding Model deployment')
param embeddingDeploymentCapacity int = 80

param imageTag string = 'latest'

@description('Deploy the application components (Container Apps, Cosmos DB, Data Broker, MCP servers, Web App). Set to true after first infra pass.')
param deployApp bool = false

@description('Set to true to deploy Azure SQL Server for structured IOC data.')
param deploySqlDb bool = true

@description('Deploy Azure Data Explorer cluster for telemetry time-series data.')
param deployAdx bool = true

@description('Deploy Azure Databricks workspace for production analytics.')
param deployDatabricks bool = true

@description('SSH public key for the jump box VM. If empty, password auth is used instead.')
@secure()
param jumpboxSshPublicKey string = ''

@description('Password for the jump box VM (only used if no SSH key is provided).')
@secure()
param jumpboxPassword string = ''

param AZURE_LOCATION string = ''
var solutionLocation = empty(AZURE_LOCATION) ? resourceGroup().location : AZURE_LOCATION
var uniqueId = toLower(uniqueString(subscription().id, environmentName, solutionLocation))
var solutionPrefix = 'ioc${padLeft(take(uniqueId, 12), 12, '0')}'

@allowed([
  'australiaeast'
  'eastus'
  'eastus2'
  'francecentral'
  'japaneast'
  'swedencentral'
  'uksouth'
  'westus'
  'westus3'
])
@metadata({
  azd: {
    type: 'location'
    usageName: [
      'OpenAI.GlobalStandard.gpt-4o-mini,150'
      'OpenAI.GlobalStandard.text-embedding-3-small,80'
    ]
  }
})
@description('Location for AI Foundry deployment.')
param aiDeploymentsLocation string

// Get the current deployer's information
var deployerInfo = deployer()
var deployingUserPrincipalId = deployerInfo.objectId

@description('The principal type of the deploying user.')
@allowed(['User', 'ServicePrincipal'])
param deployingUserPrincipalType string = 'User'

// =====================================================================
// NETWORK ISOLATION: VNet + Private DNS Zones
// These are deployed FIRST because everything else depends on them.
// =====================================================================

module vnetModule 'deploy_vnet.bicep' = {
  name: 'deploy_vnet'
  params: {
    vnetName: '${abbrs.networking.virtualNetwork}${solutionPrefix}'
    solutionLocation: solutionLocation
  }
}

module dnsZonesModule 'deploy_private_dns_zones.bicep' = {
  name: 'deploy_private_dns_zones'
  params: {
    vnetId: vnetModule.outputs.vnetId
    solutionLocation: solutionLocation
  }
}

// ========== Managed Identity ========== //
module managedIdentityModule 'deploy_managed_identity.bicep' = {
  name: 'deploy_managed_identity'
  params: {
    miName: '${abbrs.security.managedIdentity}${solutionPrefix}'
    solutionName: solutionPrefix
    solutionLocation: solutionLocation
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Log Analytics Workspace ========== //
module logAnalyticsModule 'deploy_log_analytics.bicep' = {
  name: 'deploy_log_analytics'
  params: {
    workspaceName: '${abbrs.managementGovernance.logAnalyticsWorkspace}${solutionPrefix}'
    solutionLocation: solutionLocation
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== AI Foundry and Related Resources ========== //
module aifoundry 'deploy_ai_foundry.bicep' = {
  name: 'deploy_ai_foundry'
  params: {
    solutionName: solutionPrefix
    solutionLocation: aiDeploymentsLocation
    deploymentType: deploymentType
    gptModelName: gptModelName
    gptModelVersion: gptModelVersion
    gptDeploymentCapacity: gptDeploymentCapacity
    embeddingModel: embeddingModel
    embeddingDeploymentCapacity: embeddingDeploymentCapacity
    managedIdentityObjectId: managedIdentityModule.outputs.managedIdentityOutput.objectId
    existingLogAnalyticsWorkspaceId: logAnalyticsModule.outputs.workspaceId
    deployingUserPrincipalId: deployingUserPrincipalId
    deployingUserPrincipalType: deployingUserPrincipalType
    searchServiceLocation: searchServiceLocation
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Key Vault ========== //
module keyVaultModule 'deploy_key_vault.bicep' = {
  name: 'deploy_key_vault'
  params: {
    vaultName: '${abbrs.security.keyVault}${solutionPrefix}'
    solutionLocation: solutionLocation
    managedIdentityPrincipalId: managedIdentityModule.outputs.managedIdentityOutput.objectId
    deployerPrincipalId: deployingUserPrincipalId
    deployerPrincipalType: deployingUserPrincipalType
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Container Registry ========== //
module containerRegistryModule 'deploy_container_registry.bicep' = {
  name: 'deploy_container_registry'
  params: {
    acrName: '${abbrs.containers.containerRegistry}${replace(solutionPrefix, '-', '')}'
    solutionLocation: solutionLocation
    pullPrincipalId: managedIdentityModule.outputs.managedIdentityOutput.objectId
    // NETWORK ISOLATION: Premium SKU is enforced inside the module.
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Cosmos DB ========== //
module cosmosDBModule 'deploy_cosmos_db.bicep' = {
  name: 'deploy_cosmos_db'
  params: {
    accountName: '${abbrs.databases.cosmosDBDatabase}${solutionPrefix}'
    solutionLocation: secondaryLocation
    managedIdentityPrincipalId: managedIdentityModule.outputs.managedIdentityBackendAppOutput.objectId
    deployerPrincipalId: deployingUserPrincipalId
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== SQL Database ========== //
module sqlDBModule 'deploy_sql_db.bicep' = if (deploySqlDb) {
  name: 'deploy_sql_db'
  params: {
    serverName: '${abbrs.databases.sqlDatabaseServer}${solutionPrefix}'
    sqlDBName: '${abbrs.databases.sqlDatabase}${solutionPrefix}'
    solutionLocation: secondaryLocation
    managedIdentityName: managedIdentityModule.outputs.managedIdentityOutput.name
    deployerPrincipalId: deployingUserPrincipalId
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Azure Data Explorer ========== //
module adxModule 'deploy_data_explorer.bicep' = if (deployAdx) {
  name: 'deploy_data_explorer'
  params: {
    clusterName: '${abbrs.analytics.dataExplorerCluster}${replace(solutionPrefix, '-', '')}'
    solutionLocation: solutionLocation
    databaseName: 'TelemetryDB'
    managedIdentityPrincipalId: managedIdentityModule.outputs.managedIdentityBackendAppOutput.objectId
    deployerPrincipalId: deployingUserPrincipalId
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Azure Databricks ========== //
// NETWORK ISOLATION: Databricks now uses VNet injection — clusters run in your subnets.
module databricksModule 'deploy_databricks.bicep' = if (deployDatabricks) {
  name: 'deploy_databricks'
  params: {
    workspaceName: '${abbrs.analytics.databricksWorkspace}${solutionPrefix}'
    solutionLocation: solutionLocation
    vnetId: vnetModule.outputs.vnetId
    hostSubnetName: 'snet-databricks-host'
    containerSubnetName: 'snet-databricks-container'
  }
  scope: resourceGroup(resourceGroup().name)
}

// =====================================================================
// NETWORK ISOLATION: Private Endpoints
// These connect each service to the VNet via the private endpoint subnet.
// After these are created, the services are only reachable via private IPs.
// =====================================================================

// --- AI Services Private Endpoint ---
module peAiServices 'deploy_private_endpoint.bicep' = {
  name: 'pe-ai-services'
  params: {
    name: 'pe-aiservices-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: aifoundry.outputs.aiFoundryResourceId
    groupIds: ['account']
    privateDnsZoneId: dnsZonesModule.outputs.cognitiveServicesZoneId
  }
}

// --- AI Search Private Endpoint ---
module peAiSearch 'deploy_private_endpoint.bicep' = {
  name: 'pe-ai-search'
  params: {
    name: 'pe-aisearch-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: aifoundry.outputs.aiSearchId
    groupIds: ['searchService']
    privateDnsZoneId: dnsZonesModule.outputs.searchZoneId
  }
}

// --- Storage Account Private Endpoint (blob) ---
module peStorage 'deploy_private_endpoint.bicep' = {
  name: 'pe-storage'
  params: {
    name: 'pe-storage-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: aifoundry.outputs.storageAccountId
    groupIds: ['blob']
    privateDnsZoneId: dnsZonesModule.outputs.storageBlobZoneId
  }
}

// --- Key Vault Private Endpoint ---
module peKeyVault 'deploy_private_endpoint.bicep' = {
  name: 'pe-key-vault'
  params: {
    name: 'pe-keyvault-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: keyVaultModule.outputs.vaultId
    groupIds: ['vault']
    privateDnsZoneId: dnsZonesModule.outputs.keyVaultZoneId
  }
}

// --- Container Registry Private Endpoint ---
module peContainerRegistry 'deploy_private_endpoint.bicep' = {
  name: 'pe-container-registry'
  params: {
    name: 'pe-acr-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: containerRegistryModule.outputs.acrId
    groupIds: ['registry']
    privateDnsZoneId: dnsZonesModule.outputs.containerRegistryZoneId
  }
}

// --- Cosmos DB Private Endpoint ---
module peCosmosDb 'deploy_private_endpoint.bicep' = {
  name: 'pe-cosmos-db'
  params: {
    name: 'pe-cosmos-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: cosmosDBModule.outputs.cosmosAccountId
    groupIds: ['Sql']
    privateDnsZoneId: dnsZonesModule.outputs.cosmosDbZoneId
  }
}

// --- SQL Database Private Endpoint (conditional) ---
module peSqlDb 'deploy_private_endpoint.bicep' = if (deploySqlDb) {
  name: 'pe-sql-db'
  params: {
    name: 'pe-sql-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: sqlDBModule!.outputs.sqlServerId
    groupIds: ['sqlServer']
    privateDnsZoneId: dnsZonesModule.outputs.sqlDatabaseZoneId
  }
}

// --- Data Explorer Private Endpoint (conditional) ---
module peAdx 'deploy_private_endpoint.bicep' = if (deployAdx) {
  name: 'pe-adx'
  params: {
    name: 'pe-adx-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: adxModule!.outputs.clusterId
    groupIds: ['cluster']
    privateDnsZoneId: dnsZonesModule.outputs.dataExplorerZoneId
  }
}

// --- Databricks Private Endpoint (conditional) ---
// This PE gives private access to the Databricks workspace UI and REST API.
module peDatabricks 'deploy_private_endpoint.bicep' = if (deployDatabricks) {
  name: 'pe-databricks'
  params: {
    name: 'pe-databricks-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: databricksModule!.outputs.workspaceResourceId
    groupIds: ['databricks_ui_api']
    privateDnsZoneId: dnsZonesModule.outputs.databricksZoneId
  }
}

// =====================================================================
// Container Apps (deployed into the VNet-integrated environment)
// =====================================================================

// ========== Container Apps Environment ========== //
// NETWORK ISOLATION: Now VNet-integrated and internal-only.
module containerAppsEnvModule 'deploy_container_apps_env.bicep' = if (deployApp) {
  name: 'deploy_container_apps_env'
  params: {
    envName: '${abbrs.containers.containerAppsEnv}${solutionPrefix}'
    solutionLocation: solutionLocation
    logAnalyticsCustomerId: logAnalyticsModule.outputs.customerId
    logAnalyticsSharedKey: logAnalyticsModule.outputs.sharedKey
    subnetId: vnetModule.outputs.caeSubnetId
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Container App: Data Broker ========== //
module dataBrokerApp 'deploy_container_app.bicep' = if (deployApp) {
  name: 'deploy_data_broker'
  params: {
    appName: 'ca-data-broker-${solutionPrefix}'
    solutionLocation: solutionLocation
    containerAppsEnvId: containerAppsEnvModule!.outputs.envId
    registryServer: containerRegistryModule.outputs.acrLoginServer
    containerImage: '${containerRegistryModule.outputs.acrLoginServer}/contoso-ioc-data-broker:${imageTag}'
    userAssignedIdentityId: managedIdentityModule.outputs.managedIdentityBackendAppOutput.id
    targetPort: 8000
    externalIngress: false
    cpuCores: '1.0'
    memorySize: '2Gi'
    minReplicas: 1
    maxReplicas: 5
    envVars: [
      { name: 'COSMOS_ENDPOINT', value: 'https://${cosmosDBModule.outputs.cosmosAccountName}.documents.azure.com:443/' }
      { name: 'COSMOS_DATABASE', value: cosmosDBModule.outputs.cosmosDatabaseName }
      { name: 'ADX_CLUSTER_URI', value: deployAdx ? adxModule!.outputs.clusterUri : '' }
      { name: 'ADX_DATABASE', value: deployAdx ? adxModule!.outputs.databaseName : '' }
      { name: 'DATABRICKS_WORKSPACE_URL', value: deployDatabricks ? databricksModule!.outputs.workspaceUrl : '' }
      { name: 'KEY_VAULT_URI', value: keyVaultModule.outputs.vaultUri }
      { name: 'SQLDB_SERVER', value: deploySqlDb ? sqlDBModule!.outputs.sqlServerName : '' }
      { name: 'SQLDB_DATABASE', value: deploySqlDb ? sqlDBModule!.outputs.sqlDbName : '' }
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aifoundry.outputs.applicationInsightsConnectionString }
      { name: 'AZURE_CLIENT_ID', value: managedIdentityModule.outputs.managedIdentityBackendAppOutput.clientId }
    ]
    tags: { component: 'data-broker' }
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Container App: MCP Server ADX ========== //
module mcpServerAdxApp 'deploy_container_app.bicep' = if (deployApp) {
  name: 'deploy_mcp_server_adx'
  params: {
    appName: 'ca-mcp-adx-${solutionPrefix}'
    solutionLocation: solutionLocation
    containerAppsEnvId: containerAppsEnvModule!.outputs.envId
    registryServer: containerRegistryModule.outputs.acrLoginServer
    containerImage: '${containerRegistryModule.outputs.acrLoginServer}/contoso-ioc-mcp-adx:${imageTag}'
    userAssignedIdentityId: managedIdentityModule.outputs.managedIdentityBackendAppOutput.id
    targetPort: 8001
    externalIngress: true
    cpuCores: '0.5'
    memorySize: '1Gi'
    envVars: [
      { name: 'ADX_CLUSTER_URI', value: deployAdx ? adxModule!.outputs.clusterUri : '' }
      { name: 'ADX_DATABASE', value: deployAdx ? adxModule!.outputs.databaseName : '' }
      { name: 'KEY_VAULT_URI', value: keyVaultModule.outputs.vaultUri }
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aifoundry.outputs.applicationInsightsConnectionString }
      { name: 'AZURE_CLIENT_ID', value: managedIdentityModule.outputs.managedIdentityBackendAppOutput.clientId }
    ]
    tags: { component: 'mcp-server-adx' }
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Container App: MCP Server Databricks ========== //
module mcpServerDatabricksApp 'deploy_container_app.bicep' = if (deployApp) {
  name: 'deploy_mcp_server_databricks'
  params: {
    appName: 'ca-mcp-dbx-${solutionPrefix}'
    solutionLocation: solutionLocation
    containerAppsEnvId: containerAppsEnvModule!.outputs.envId
    registryServer: containerRegistryModule.outputs.acrLoginServer
    containerImage: '${containerRegistryModule.outputs.acrLoginServer}/contoso-ioc-mcp-databricks:${imageTag}'
    userAssignedIdentityId: managedIdentityModule.outputs.managedIdentityBackendAppOutput.id
    targetPort: 8002
    externalIngress: true
    cpuCores: '0.5'
    memorySize: '1Gi'
    envVars: [
      { name: 'DATABRICKS_WORKSPACE_URL', value: deployDatabricks ? databricksModule!.outputs.workspaceUrl : '' }
      { name: 'KEY_VAULT_URI', value: keyVaultModule.outputs.vaultUri }
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aifoundry.outputs.applicationInsightsConnectionString }
      { name: 'AZURE_CLIENT_ID', value: managedIdentityModule.outputs.managedIdentityBackendAppOutput.clientId }
    ]
    tags: { component: 'mcp-server-databricks' }
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Container App: MCP Server Cosmos ========== //
module mcpServerCosmosApp 'deploy_container_app.bicep' = if (deployApp) {
  name: 'deploy_mcp_server_cosmos'
  params: {
    appName: 'ca-mcp-cosmos-${solutionPrefix}'
    solutionLocation: solutionLocation
    containerAppsEnvId: containerAppsEnvModule!.outputs.envId
    registryServer: containerRegistryModule.outputs.acrLoginServer
    containerImage: '${containerRegistryModule.outputs.acrLoginServer}/contoso-ioc-mcp-cosmos:${imageTag}'
    userAssignedIdentityId: managedIdentityModule.outputs.managedIdentityBackendAppOutput.id
    targetPort: 8003
    externalIngress: true
    cpuCores: '0.5'
    memorySize: '1Gi'
    envVars: [
      { name: 'COSMOS_ENDPOINT', value: 'https://${cosmosDBModule.outputs.cosmosAccountName}.documents.azure.com:443/' }
      { name: 'COSMOS_DATABASE', value: cosmosDBModule.outputs.cosmosReportsDatabaseName }
      { name: 'KEY_VAULT_URI', value: keyVaultModule.outputs.vaultUri }
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aifoundry.outputs.applicationInsightsConnectionString }
      { name: 'AZURE_CLIENT_ID', value: managedIdentityModule.outputs.managedIdentityBackendAppOutput.clientId }
    ]
    tags: { component: 'mcp-server-cosmos' }
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Container App: Web App (Chat Interface) ========== //
// NOTE: With internal CAE, the web app URL is only reachable from inside the VNet.
// To expose it publicly, add an Application Gateway or Azure Front Door in front.
module webApp 'deploy_container_app.bicep' = if (deployApp) {
  name: 'deploy_web_app'
  params: {
    appName: 'ca-webapp-${solutionPrefix}'
    solutionLocation: solutionLocation
    containerAppsEnvId: containerAppsEnvModule!.outputs.envId
    registryServer: containerRegistryModule.outputs.acrLoginServer
    containerImage: '${containerRegistryModule.outputs.acrLoginServer}/contoso-ioc-webapp:${imageTag}'
    userAssignedIdentityId: managedIdentityModule.outputs.managedIdentityBackendAppOutput.id
    targetPort: 4200
    externalIngress: true
    cpuCores: '0.5'
    memorySize: '1Gi'
    minReplicas: 1
    envVars: [
      { name: 'DATA_BROKER_URL', value: deployApp ? 'https://${dataBrokerApp!.outputs.fqdn}' : '' }
      { name: 'AZURE_AI_AGENT_ENDPOINT', value: aifoundry.outputs.projectEndpoint }
      { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aifoundry.outputs.applicationInsightsConnectionString }
    ]
    tags: { component: 'web-app' }
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== App Service Plan (legacy — kept for backward compat) ========== //
module hostingplan 'deploy_app_service_plan.bicep' = if (false) {
  name: 'deploy_app_service_plan'
  params: {
    solutionLocation: solutionLocation
    HostingPlanName: '${abbrs.compute.appServicePlan}${solutionPrefix}'
  }
}

// =====================================================================
// BASTION + JUMP BOX
// This is how you get INTO the VNet to run scripts, access services, etc.
// Bastion = secure gateway (public IP, in the portal).
// Jump VM = your workstation inside the network (private IP only).
// =====================================================================

module bastionModule 'deploy_bastion.bicep' = {
  name: 'deploy_bastion'
  params: {
    bastionName: 'bas-${solutionPrefix}'
    solutionLocation: solutionLocation
    bastionSubnetId: vnetModule.outputs.bastionSubnetId
  }
}

module jumpboxModule 'deploy_jumpbox.bicep' = {
  name: 'deploy_jumpbox'
  params: {
    vmName: 'vm-jump-${solutionPrefix}'
    solutionLocation: solutionLocation
    subnetId: vnetModule.outputs.jumpboxSubnetId
    adminSshPublicKey: jumpboxSshPublicKey
    adminPassword: jumpboxPassword
    // Give the VM your Managed Identity so it can authenticate to Azure services
    // (Key Vault, ACR, Cosmos, etc.) without storing any credentials.
    userAssignedIdentityId: managedIdentityModule.outputs.managedIdentityOutput.id
  }
}

// ========== Outputs ========== //

// Infrastructure identifiers
output SOLUTION_NAME string = solutionPrefix
output RESOURCE_GROUP_NAME string = resourceGroup().name
output RESOURCE_GROUP_LOCATION string = solutionLocation
output ENVIRONMENT_NAME string = environmentName
output AZURE_SECONDARY_LOCATION string = secondaryLocation

// Networking
output VNET_NAME string = vnetModule.outputs.vnetName
output BASTION_NAME string = bastionModule.outputs.bastionName
output JUMPBOX_VM_NAME string = jumpboxModule.outputs.vmName
output JUMPBOX_PRIVATE_IP string = jumpboxModule.outputs.privateIp

// AI Services (AZURE_AI_PROJECT_ENDPOINT also serves as conn string and agent endpoint)
output AZURE_AI_AGENT_API_VERSION string = azureAiAgentApiVersion
output AZURE_AI_PROJECT_NAME string = aifoundry.outputs.aiProjectName
output AZURE_AI_PROJECT_ENDPOINT string = aifoundry.outputs.projectEndpoint
output AZURE_AI_AGENT_MODEL_DEPLOYMENT_NAME string = gptModelName
output AI_SERVICE_NAME string = aifoundry.outputs.aiServicesName

// OpenAI
output AZURE_OPENAI_DEPLOYMENT_MODEL string = gptModelName
output AZURE_OPENAI_DEPLOYMENT_MODEL_CAPACITY int = gptDeploymentCapacity
output AZURE_OPENAI_ENDPOINT string = aifoundry.outputs.aiServicesTarget
output AZURE_OPENAI_MODEL_DEPLOYMENT_TYPE string = deploymentType
output AZURE_OPENAI_EMBEDDING_MODEL string = embeddingModel
output AZURE_OPENAI_API_VERSION string = azureOpenAIApiVersion

// Cosmos DB
output AZURE_COSMOSDB_ACCOUNT string = cosmosDBModule.outputs.cosmosAccountName
output AZURE_COSMOSDB_CONVERSATIONS_CONTAINER string = 'conversations'
output AZURE_COSMOSDB_DATABASE string = 'db_conversation_history'
output AZURE_COSMOSDB_ENABLE_FEEDBACK string = 'True'

// SQL Database
output SQLDB_DATABASE string = deploySqlDb ? sqlDBModule!.outputs.sqlDbName : ''
output SQLDB_SERVER string = deploySqlDb ? sqlDBModule!.outputs.sqlServerName : ''
output SQLDB_USER_MID string = deploySqlDb ? managedIdentityModule.outputs.managedIdentityBackendAppOutput.clientId : ''

// Azure Data Explorer
output ADX_CLUSTER_NAME string = deployAdx ? adxModule!.outputs.clusterName : ''
output ADX_CLUSTER_URI string = deployAdx ? adxModule!.outputs.clusterUri : ''
output ADX_DATABASE string = deployAdx ? adxModule!.outputs.databaseName : ''

// Azure Databricks
output DATABRICKS_WORKSPACE_NAME string = deployDatabricks ? databricksModule!.outputs.workspaceName : ''
output DATABRICKS_WORKSPACE_URL string = deployDatabricks ? databricksModule!.outputs.workspaceUrl : ''

// AI Search
output AZURE_AI_SEARCH_ENDPOINT string = aifoundry.outputs.aiSearchTarget
output AZURE_AI_SEARCH_INDEX string = 'health_reports_index'
output AZURE_AI_SEARCH_NAME string = aifoundry.outputs.aiSearchName
output AZURE_AI_SEARCH_CONNECTION_NAME string = aifoundry.outputs.aiSearchConnectionName
output AZURE_AI_SEARCH_CONNECTION_ID string = aifoundry.outputs.aiSearchConnectionId

// Key Vault
output KEY_VAULT_NAME string = keyVaultModule.outputs.vaultName
output KEY_VAULT_URI string = keyVaultModule.outputs.vaultUri

// Container Registry
output ACR_NAME string = containerRegistryModule.outputs.acrName
output ACR_LOGIN_SERVER string = containerRegistryModule.outputs.acrLoginServer

// Identity
output API_UID string = managedIdentityModule.outputs.managedIdentityBackendAppOutput.clientId
output MANAGED_IDENTITY_CLIENT_ID string = managedIdentityModule.outputs.managedIdentityOutput.clientId
output API_PID string = managedIdentityModule.outputs.managedIdentityBackendAppOutput.objectId
output MID_DISPLAY_NAME string = managedIdentityModule.outputs.managedIdentityBackendAppOutput.name

// App / Container Apps
output APPLICATIONINSIGHTS_CONNECTION_STRING string = aifoundry.outputs.applicationInsightsConnectionString
output AI_FOUNDRY_RESOURCE_ID string = aifoundry.outputs.aiFoundryResourceId
output AZURE_ENV_IMAGETAG string = imageTag

// Container Apps URLs (populated when deployApp = true)
// NOTE: With network isolation, these URLs are INTERNAL-ONLY (not publicly accessible).
output DATA_BROKER_URL string = deployApp ? dataBrokerApp!.outputs.appUrl : ''
output MCP_ADX_URL string = deployApp ? mcpServerAdxApp!.outputs.appUrl : ''
output MCP_DATABRICKS_URL string = deployApp ? mcpServerDatabricksApp!.outputs.appUrl : ''
output MCP_COSMOS_URL string = deployApp ? mcpServerCosmosApp!.outputs.appUrl : ''
output WEB_APP_URL string = deployApp ? webApp!.outputs.appUrl : ''

// Feature flags
output USE_AI_PROJECT_CLIENT string = 'True'
output USE_CHAT_HISTORY_ENABLED string = 'True'
output DISPLAY_CHART_DEFAULT string = 'False'
output AZURE_ENV_DEPLOY_APP bool = deployApp
output DEPLOY_SQL_DB bool = deploySqlDb
output DEPLOY_ADX bool = deployAdx
output DEPLOY_DATABRICKS bool = deployDatabricks
