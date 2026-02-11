@description('Azure Cache for Redis — caching/session store for Basket.API')

// =============================================================================
// Parameters
// =============================================================================

@description('The Azure region for all resources')
param location string

@description('The environment name')
@allowed(['prod', 'staging', 'dev'])
param environmentName string

@description('The base name for the application')
param appName string = 'eshop'

@description('Tags to apply to all resources')
param tags object

@description('The Redis SKU name')
@allowed(['Basic', 'Standard', 'Premium'])
param skuName string = 'Standard'

@description('The Redis cache capacity (C-family: 0-6, P-family: 1-5)')
param capacity int = 1

@description('Key Vault name for storing access keys')
param keyVaultName string

// =============================================================================
// Variables
// =============================================================================

var redisName = 'redis-${appName}-${environmentName}'
var skuFamily = skuName == 'Premium' ? 'P' : 'C'

// =============================================================================
// Resources
// =============================================================================

resource redisCache 'Microsoft.Cache/redis@2024-03-01' = {
  name: redisName
  location: location
  tags: tags
  properties: {
    sku: {
      name: skuName
      family: skuFamily
      capacity: capacity
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
  }
}

// Store connection string in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource redisConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
  parent: keyVault
  name: 'redis-connection-string'
  properties: {
    value: '${redisCache.properties.hostName}:${redisCache.properties.sslPort},password=${redisCache.listKeys().primaryKey},ssl=True,abortConnect=False'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The Redis cache resource ID')
output id string = redisCache.id

@description('The Redis cache hostname')
output hostName string = redisCache.properties.hostName

@description('The Redis cache name')
output name string = redisCache.name
