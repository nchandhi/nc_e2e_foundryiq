// ========== main.bicep ========== //
// Contoso IOC Health Check - Main Infrastructure Deployment
//
// Architecture (Three Foundational Components: Common Auth + MCP Servers + Data Broker):
//
// CLIENT LAYER:
//   - AI Agents (GPT-4.1) via Azure AI Foundry
//   - Angular Dashboard (Well Health UI / Operator Interface)
//   - Future Clients (Mobile Apps, External APIs, Power BI)
//
// MCP PROTOCOL LAYER (Model Context Protocol) — All deployed as Container Apps:
//   - MCP Server ADX (FastMCP + FastAPI, Azure Data Explorer Connector, KQL)
//   - MCP Server Databricks (FastMCP + FastAPI, Databricks SQL Connector, Delta Lake)
//   - MCP Server Cosmos (FastMCP + FastAPI, Data Broker client, CRUD)
//   - Common Auth Package (EntraID CredentialStrategy, HybridJwtTokenProvider RS256)
//
// DATA BROKER SERVICE LAYER (Centralized REST API) — Container App:
//   - Reports Router, Telemetry Router, Analytics Router
//   - Cache Manager (asyncio.Lock, LRU, pattern-based invalidation)
//   - Data Platform Clients (Cosmos SDK, KQL Client, SQL Connector)
//
// DATA SOURCES LAYER:
//   - Azure Cosmos DB (Well Health Reports — NoSQL, partition by well_reference)
//   - Azure Data Explorer (Telemetry Time Series — KQL, materialized views)
//   - Azure Databricks (Production Analytics — Delta Lake, Unity Catalog, Spark SQL)
//   - Azure SQL Database (kept for structured IOC data / future use)
//
// AZURE INFRASTRUCTURE:
//   - Container Apps + Container Apps Environment
//   - Container Registry (ACR)
//   - Key Vault (secrets management)
//   - Application Insights + Log Analytics (monitoring & metrics)
//   - Entra ID (OAuth 2.1 authentication)
//   - Azure AI Foundry (AI Services + Project, GPT & Embedding deployments)
//   - Azure AI Search (document indexing for policies and procedures)
//   - Managed Identity (service-to-service auth)

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

@description('Deploy the application components (Container Apps, Cosmos DB, Data Broker, MCP servers, Dashboard). Set to true after first infra pass.')
param deployApp bool = false

@description('Set to true to deploy Azure SQL Server for structured IOC data.')
param deploySqlDb bool = true

@description('Deploy Azure Data Explorer cluster for telemetry time-series data.')
param deployAdx bool = true

@description('Deploy Azure Databricks workspace for production analytics.')
param deployDatabricks bool = true

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
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Cosmos DB (Well Health Reports + Chat History) ========== //
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

// ========== SQL Database (Structured IOC Data — kept for future use) ========== //
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

// ========== Azure Data Explorer (Telemetry Time Series) ========== //
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

// ========== Azure Databricks (Production Analytics) ========== //
module databricksModule 'deploy_databricks.bicep' = if (deployDatabricks) {
  name: 'deploy_databricks'
  params: {
    workspaceName: '${abbrs.analytics.databricksWorkspace}${solutionPrefix}'
    solutionLocation: solutionLocation
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Databricks RBAC: Backend MI -> Contributor ========== //
// Note: The backend MI Contributor role on Databricks workspace is assigned
// via 05_create_agent.py or CLI after deployment, since the workspace resource ID
// is a runtime value that cannot be used in role assignment GUID computation.

// ========== Container Apps Environment ========== //
module containerAppsEnvModule 'deploy_container_apps_env.bicep' = if (deployApp) {
  name: 'deploy_container_apps_env'
  params: {
    envName: '${abbrs.containers.containerAppsEnv}${solutionPrefix}'
    solutionLocation: solutionLocation
    logAnalyticsCustomerId: logAnalyticsModule.outputs.customerId
    logAnalyticsSharedKey: logAnalyticsModule.outputs.sharedKey
  }
  scope: resourceGroup(resourceGroup().name)
}

// ========== Container App: Data Broker Service (Centralized REST API) ========== //
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

// ========== Container App: Dashboard (Angular Well Health UI) ========== //
module dashboardApp 'deploy_container_app.bicep' = if (deployApp) {
  name: 'deploy_dashboard'
  params: {
    appName: 'ca-dashboard-${solutionPrefix}'
    solutionLocation: solutionLocation
    containerAppsEnvId: containerAppsEnvModule!.outputs.envId
    registryServer: containerRegistryModule.outputs.acrLoginServer
    containerImage: '${containerRegistryModule.outputs.acrLoginServer}/contoso-ioc-dashboard:${imageTag}'
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
    tags: { component: 'dashboard' }
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

// ========== Outputs ========== //

// Infrastructure identifiers
output SOLUTION_NAME string = solutionPrefix
output RESOURCE_GROUP_NAME string = resourceGroup().name
output RESOURCE_GROUP_LOCATION string = solutionLocation
output ENVIRONMENT_NAME string = environmentName
output AZURE_SECONDARY_LOCATION string = secondaryLocation

// AI Services
output AZURE_AI_PROJECT_CONN_STRING string = aifoundry.outputs.projectEndpoint
output AZURE_AI_AGENT_API_VERSION string = azureAiAgentApiVersion
output AZURE_AI_PROJECT_NAME string = aifoundry.outputs.aiProjectName
output AZURE_AI_PROJECT_ENDPOINT string = aifoundry.outputs.projectEndpoint
output AZURE_AI_AGENT_ENDPOINT string = aifoundry.outputs.projectEndpoint
output AZURE_AI_AGENT_MODEL_DEPLOYMENT_NAME string = gptModelName
output AI_SERVICE_NAME string = aifoundry.outputs.aiServicesName

// OpenAI
output AZURE_OPENAI_DEPLOYMENT_MODEL string = gptModelName
output AZURE_OPENAI_DEPLOYMENT_MODEL_CAPACITY int = gptDeploymentCapacity
output AZURE_OPENAI_ENDPOINT string = aifoundry.outputs.aiServicesTarget
output AZURE_OPENAI_MODEL_DEPLOYMENT_TYPE string = deploymentType
output AZURE_OPENAI_EMBEDDING_MODEL string = embeddingModel
output AZURE_OPENAI_API_VERSION string = azureOpenAIApiVersion
output AZURE_OPENAI_RESOURCE string = aifoundry.outputs.aiServicesName

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
output SEARCH_DATA_FOLDER string = 'data/default/documents'

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
output DATA_BROKER_URL string = deployApp ? dataBrokerApp!.outputs.appUrl : ''
output MCP_ADX_URL string = deployApp ? mcpServerAdxApp!.outputs.appUrl : ''
output MCP_DATABRICKS_URL string = deployApp ? mcpServerDatabricksApp!.outputs.appUrl : ''
output MCP_COSMOS_URL string = deployApp ? mcpServerCosmosApp!.outputs.appUrl : ''
output DASHBOARD_URL string = deployApp ? dashboardApp!.outputs.appUrl : ''

// Feature flags
output USE_AI_PROJECT_CLIENT string = 'True'
output USE_CHAT_HISTORY_ENABLED string = 'True'
output DISPLAY_CHART_DEFAULT string = 'False'
output AZURE_ENV_DEPLOY_APP bool = deployApp
output DEPLOY_SQL_DB bool = deploySqlDb
output DEPLOY_ADX bool = deployAdx
output DEPLOY_DATABRICKS bool = deployDatabricks

// Agent names (populated after agent creation script)
output AGENT_NAME_CHAT string = ''
output AGENT_NAME_TITLE string = ''
