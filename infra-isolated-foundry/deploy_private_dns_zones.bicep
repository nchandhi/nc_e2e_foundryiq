// ========== Private DNS Zones (Minimal — AI Foundry + AI Search) ========== //
// DNS zones needed for this baby-steps deployment:
//   1. AI Services (cognitiveservices) — base Cognitive Services endpoint
//   2. OpenAI (openai) — for *.openai.azure.com endpoints (embeddings, chat)
//   3. AI Foundry (services.ai) — for *.services.ai.azure.com project endpoints
//   4. AI Search
//   5. Key Vault
//   6. Storage Account (blob) — required by AI Foundry
//
// NOTE: AI Services needs ALL THREE zones (#1, #2, #3) linked to the same PE.
// Without them, the VM resolves hostnames to public IPs → gets 403 blocked.

@description('Resource ID of the VNet to link DNS zones to.')
param vnetId string

#disable-next-line no-hardcoded-env-urls
var zones = [
  'privatelink.cognitiveservices.azure.com'   // [0] AI Services base
  #disable-next-line no-hardcoded-env-urls
  'privatelink.openai.azure.com'              // [1] OpenAI endpoints (embeddings, chat)
  #disable-next-line no-hardcoded-env-urls
  'privatelink.services.ai.azure.com'         // [2] AI Foundry project endpoint
  'privatelink.search.windows.net'            // [3] AI Search
  'privatelink.vaultcore.azure.net'           // [4] Key Vault
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'         // [5] Storage Account (blob)
]

resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in zones: {
  name: zone
  location: 'global'
}]

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in zones: {
  parent: dnsZone[i]
  name: '${replace(zone, '.', '-')}-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}]

// AI Services needs all 3 zones: cognitiveservices + openai + services.ai
output cognitiveServicesZoneId string = dnsZone[0].id
output openaiZoneId string = dnsZone[1].id
output aiFoundryZoneId string = dnsZone[2].id
output searchZoneId string = dnsZone[3].id
output keyVaultZoneId string = dnsZone[4].id
output storageBlobZoneId string = dnsZone[5].id
