// ========== Private DNS Zones (Minimal — AI Foundry + AI Search) ========== //
// Only the 4 DNS zones needed for this baby-steps deployment:
//   1. AI Services (cognitiveservices)
//   2. AI Search
//   3. Key Vault
//   4. Storage Account (blob) — required by AI Foundry

@description('Resource ID of the VNet to link DNS zones to.')
param vnetId string

// Only the zones we need — no Cosmos, SQL, ACR, ADX, or Databricks.
#disable-next-line no-hardcoded-env-urls
var zones = [
  'privatelink.cognitiveservices.azure.com'   // AI Services
  'privatelink.search.windows.net'            // AI Search
  'privatelink.vaultcore.azure.net'           // Key Vault
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'         // Storage Account (blob)
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

output cognitiveServicesZoneId string = dnsZone[0].id
output searchZoneId string = dnsZone[1].id
output keyVaultZoneId string = dnsZone[2].id
output storageBlobZoneId string = dnsZone[3].id
