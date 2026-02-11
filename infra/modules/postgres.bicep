@description('Azure Database for PostgreSQL Flexible Server with pgvector extension and eShop databases')

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

@description('The administrator login name')
param administratorLogin string = 'eshopadmin'

@description('The administrator login password')
@secure()
param administratorPassword string

@description('The PostgreSQL SKU name')
param skuName string = 'Standard_D2ds_v5'

@description('The PostgreSQL SKU tier')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'GeneralPurpose'

@description('Storage size in GB')
param storageSizeGB int = 128

@description('PostgreSQL version')
@allowed(['14', '15', '16', '17'])
param postgresVersion string = '16'

@description('Key Vault name for storing connection strings')
param keyVaultName string

@description('The database names to create — matches Aspire AppHost AddDatabase() calls')
param databaseNames array = ['catalogdb', 'identitydb', 'orderingdb', 'webhooksdb']

// =============================================================================
// Variables
// =============================================================================

var serverName = 'psql-${appName}-${environmentName}'

// =============================================================================
// Resources
// =============================================================================

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresVersion
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: environmentName == 'prod' ? 35 : 7
      geoRedundantBackup: environmentName == 'prod' ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: environmentName == 'prod' ? 'ZoneRedundant' : 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Disabled'
    }
  }
}

// Enable pgvector extension (used by Catalog.API for semantic search with ankane/pgvector image)
resource pgvectorConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: postgresServer
  name: 'azure.extensions'
  properties: {
    value: 'vector'
    source: 'user-override'
  }
}

// Create databases matching Aspire AppHost: catalogdb, identitydb, orderingdb, webhooksdb
resource databases 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = [
  for dbName in databaseNames: {
    parent: postgresServer
    name: dbName
    properties: {
      charset: 'UTF8'
      collation: 'en_US.utf8'
    }
  }
]

// Store per-database connection strings in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource connectionStringSecrets 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = [
  for dbName in databaseNames: {
    parent: keyVault
    name: 'postgres-${dbName}-connection-string'
    properties: {
      value: 'Host=${postgresServer.properties.fullyQualifiedDomainName};Database=${dbName};Username=${administratorLogin};Password=${administratorPassword};SSL Mode=Require;Trust Server Certificate=true'
    }
  }
]

// =============================================================================
// Outputs
// =============================================================================

@description('The PostgreSQL server resource ID')
output id string = postgresServer.id

@description('The PostgreSQL server FQDN')
output fqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('The PostgreSQL server name')
output name string = postgresServer.name

@description('The administrator login name')
output adminLogin string = administratorLogin
