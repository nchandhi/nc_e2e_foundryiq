// ========== Private DNS Zones ========== //
// Creates DNS zones that resolve service hostnames to private IP addresses.
//
// WHY: When you create a private endpoint for, say, Key Vault, Azure gives it
// a private IP (e.g. 10.0.2.5). But your code still calls "myvault.vault.azure.net".
// Private DNS zones make that hostname resolve to 10.0.2.5 instead of the public IP.
// Without this, your VNet resources would still try to reach services over the internet.
//
// Each zone is linked to the VNet so all resources inside the VNet automatically
// use these private DNS records.

@description('Resource ID of the VNet to link DNS zones to.')
param vnetId string

@description('Location of the solution (needed for ADX zone name which is region-specific).')
param solutionLocation string

// ---------- Zone Definitions ---------- //
// One zone per Azure service type. The zone names are fixed by Azure — you can't change them.
#disable-next-line no-hardcoded-env-urls  // DNS zone names are fixed by Azure — they ARE the literal strings.
var zones = [
  'privatelink.cognitiveservices.azure.com'             // AI Services (OpenAI, etc.)
  'privatelink.search.windows.net'                      // AI Search
  'privatelink.vaultcore.azure.net'                     // Key Vault
  'privatelink.azurecr.io'                              // Container Registry
  'privatelink.documents.azure.com'                     // Cosmos DB
  #disable-next-line no-hardcoded-env-urls
  'privatelink.database.windows.net'                    // SQL Database
  #disable-next-line no-hardcoded-env-urls
  'privatelink.blob.core.windows.net'                   // Storage Account (blob)
  #disable-next-line no-hardcoded-env-urls
  'privatelink.${solutionLocation}.kusto.windows.net'   // Data Explorer (region-specific!)
  'privatelink.azuredatabricks.net'                     // Databricks
]

// ---------- Create Each DNS Zone ---------- //
resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zone in zones: {
  name: zone
  location: 'global'   // Private DNS zones are always "global" — not tied to a region.
}]

// ---------- Link Each Zone to the VNet ---------- //
// This makes resources inside the VNet automatically query these zones for DNS resolution.
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, i) in zones: {
  parent: dnsZone[i]
  name: '${replace(zone, '.', '-')}-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false   // We don't auto-register VMs — only PE records go here.
  }
}]

// ---------- Outputs ---------- //
// Expose zone IDs so the private endpoint module can register DNS records in the right zone.
output cognitiveServicesZoneId string = dnsZone[0].id
output searchZoneId string = dnsZone[1].id
output keyVaultZoneId string = dnsZone[2].id
output containerRegistryZoneId string = dnsZone[3].id
output cosmosDbZoneId string = dnsZone[4].id
output sqlDatabaseZoneId string = dnsZone[5].id
output storageBlobZoneId string = dnsZone[6].id
output dataExplorerZoneId string = dnsZone[7].id
output databricksZoneId string = dnsZone[8].id
