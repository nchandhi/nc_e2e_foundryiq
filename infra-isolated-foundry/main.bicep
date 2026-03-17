// ========== main.bicep (Minimal — AI Foundry + AI Search Only) ========== //
// Baby-steps deployment for testing network isolation with just AI services.
//
// WHAT'S INCLUDED:
//   1. Virtual Network with 3 subnets (Private Endpoints, Bastion, Jumpbox)
//   2. Private DNS Zones for AI Services, AI Search, Key Vault, Storage
//   3. AI Foundry hub (AI Services + AI Search + Storage + App Insights)
//   4. Key Vault (for secrets)
//   5. Private Endpoints for all 4 services
//   6. Azure Bastion + Jump VM (your way into the network)
//
// WHAT'S NOT INCLUDED (add later by graduating to infra-isolated/):
//   - Container Apps / Container Registry
//   - Cosmos DB / SQL Database / Data Explorer / Databricks
//
// ARCHITECTURE:
//
//   ┌───────────────── VNet (10.0.0.0/16) ─────────────────┐
//   │                                                       │
//   │  ┌── snet-private-endpoints (10.0.2.0/24) ──┐        │
//   │  │  PE → AI Services       (10.0.2.x)       │        │
//   │  │  PE → AI Search         (10.0.2.x)       │        │
//   │  │  PE → Key Vault         (10.0.2.x)       │        │
//   │  │  PE → Storage Account   (10.0.2.x)       │        │
//   │  └───────────────────────────────────────────┘        │
//   │                                                       │
//   │  ┌── AzureBastionSubnet (10.0.5.0/26) ──┐            │
//   │  │  Bastion Host (only public IP)        │            │
//   │  └───────────────────────────────────────┘            │
//   │                                                       │
//   │  ┌── snet-jumpbox (10.0.6.0/24) ────────┐            │
//   │  │  Jump VM (Ubuntu + Edge + Python)     │            │
//   │  └───────────────────────────────────────┘            │
//   │                                                       │
//   └───────────────────────────────────────────────────────┘

targetScope = 'resourceGroup'

var abbrs = loadJsonContent('./abbreviations.json')

// ========== Parameters ========== //

@minLength(3)
@maxLength(20)
@description('A unique environment name prefix for all resources (3-20 chars):')
param environmentName string

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
// STEP 1: VNet + DNS Zones (deployed first — everything depends on them)
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
  }
}

// =====================================================================
// STEP 2: Managed Identity (used by AI Foundry, Key Vault, Jump VM)
// =====================================================================

module managedIdentityModule 'deploy_managed_identity.bicep' = {
  name: 'deploy_managed_identity'
  params: {
    miName: '${abbrs.security.managedIdentity}${solutionPrefix}'
    solutionName: solutionPrefix
    solutionLocation: solutionLocation
  }
}

// =====================================================================
// STEP 3: Log Analytics (feeds into App Insights inside AI Foundry)
// =====================================================================

module logAnalyticsModule 'deploy_log_analytics.bicep' = {
  name: 'deploy_log_analytics'
  params: {
    workspaceName: '${abbrs.managementGovernance.logAnalyticsWorkspace}${solutionPrefix}'
    solutionLocation: solutionLocation
  }
}

// =====================================================================
// STEP 4: AI Foundry (AI Services, AI Search, Storage, App Insights)
// This is the big one — deploys the AI hub, models, search, and storage.
// All with publicNetworkAccess = Disabled.
// =====================================================================

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
}

// =====================================================================
// STEP 5: Key Vault (for storing secrets — the scripts will use it)
// =====================================================================

module keyVaultModule 'deploy_key_vault.bicep' = {
  name: 'deploy_key_vault'
  params: {
    vaultName: '${abbrs.security.keyVault}${solutionPrefix}'
    solutionLocation: solutionLocation
    managedIdentityPrincipalId: managedIdentityModule.outputs.managedIdentityOutput.objectId
    deployerPrincipalId: deployingUserPrincipalId
    deployerPrincipalType: deployingUserPrincipalType
  }
}

// =====================================================================
// STEP 6: Private Endpoints (one per service)
// Each PE places the service on your VNet so traffic stays private.
// =====================================================================

// PE for AI Services (OpenAI models, embeddings, agent API)
module peAiServices 'deploy_private_endpoint.bicep' = {
  name: 'deploy_pe_ai_services'
  params: {
    name: 'pe-ai-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: aifoundry.outputs.aiFoundryResourceId
    groupIds: ['account']
    privateDnsZoneId: dnsZonesModule.outputs.cognitiveServicesZoneId
  }
}

// PE for AI Search (vector index, semantic search, knowledge base)
module peAiSearch 'deploy_private_endpoint.bicep' = {
  name: 'deploy_pe_ai_search'
  params: {
    name: 'pe-search-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: aifoundry.outputs.aiSearchId
    groupIds: ['searchService']
    privateDnsZoneId: dnsZonesModule.outputs.searchZoneId
  }
}

// PE for Key Vault (secrets, certs)
module peKeyVault 'deploy_private_endpoint.bicep' = {
  name: 'deploy_pe_key_vault'
  params: {
    name: 'pe-kv-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: keyVaultModule.outputs.vaultId
    groupIds: ['vault']
    privateDnsZoneId: dnsZonesModule.outputs.keyVaultZoneId
  }
}

// PE for Storage Account (used by AI Foundry for model artifacts, data)
module peStorage 'deploy_private_endpoint.bicep' = {
  name: 'deploy_pe_storage'
  params: {
    name: 'pe-blob-${solutionPrefix}'
    location: solutionLocation
    subnetId: vnetModule.outputs.peSubnetId
    privateLinkServiceId: aifoundry.outputs.storageAccountId
    groupIds: ['blob']
    privateDnsZoneId: dnsZonesModule.outputs.storageBlobZoneId
  }
}

// =====================================================================
// STEP 7: Azure Bastion + Jump VM (your way into the network)
// =====================================================================

module bastionModule 'deploy_bastion.bicep' = {
  name: 'deploy_bastion'
  params: {
    bastionName: '${abbrs.networking.bastionHost}${solutionPrefix}'
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
    userAssignedIdentityId: managedIdentityModule.outputs.managedIdentityOutput.id
  }
}

// =====================================================================
// Outputs — used by scripts (.env) and azd
// =====================================================================

// AI Services
output AI_SERVICE_NAME string = aifoundry.outputs.aiServicesName
output AZURE_AI_PROJECT_ENDPOINT string = aifoundry.outputs.projectEndpoint
output AZURE_OPENAI_ENDPOINT string = aifoundry.outputs.aiServicesTarget
output AZURE_OPENAI_API_VERSION string = '2025-01-01-preview'
output AZURE_OPENAI_CHAT_MODEL string = gptModelName
output AZURE_OPENAI_EMBEDDING_MODEL string = embeddingModel

// AI Search
output AZURE_AI_SEARCH_ENDPOINT string = aifoundry.outputs.aiSearchTarget
output AZURE_AI_SEARCH_NAME string = aifoundry.outputs.aiSearchName
output AZURE_AI_SEARCH_CONNECTION_NAME string = aifoundry.outputs.aiSearchConnectionName

// AI Project
output AZURE_AI_PROJECT_NAME string = aifoundry.outputs.aiProjectName

// Key Vault
output AZURE_KEY_VAULT_NAME string = keyVaultModule.outputs.vaultName
output AZURE_KEY_VAULT_ENDPOINT string = keyVaultModule.outputs.vaultUri

// App Insights
output APPLICATIONINSIGHTS_CONNECTION_STRING string = aifoundry.outputs.applicationInsightsConnectionString

// Managed Identity
output MANAGED_IDENTITY_CLIENT_ID string = managedIdentityModule.outputs.managedIdentityOutput.clientId
output MANAGED_IDENTITY_NAME string = managedIdentityModule.outputs.managedIdentityOutput.name

// Network / Access
output VNET_NAME string = vnetModule.outputs.vnetName
output BASTION_NAME string = bastionModule.outputs.bastionName
output JUMPBOX_VM_NAME string = jumpboxModule.outputs.vmName
output JUMPBOX_PRIVATE_IP string = jumpboxModule.outputs.privateIp
