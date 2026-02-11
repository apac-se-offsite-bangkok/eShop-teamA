@description('Shared infrastructure: Container Apps Environment, Log Analytics, Key Vault, User-Assigned Managed Identity')

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

// =============================================================================
// Variables
// =============================================================================

var logAnalyticsName = 'log-${appName}-${environmentName}'
var containerAppEnvName = 'cae-${appName}-${environmentName}'
var keyVaultName = 'kv-${appName}-${environmentName}'
var managedIdentityName = 'id-${appName}-${environmentName}'

// =============================================================================
// Resources
// =============================================================================

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: environmentName == 'prod' ? 90 : 30
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: environmentName == 'prod'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Key Vault Secrets Officer role for the managed identity
resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: keyVault
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
    )
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The Container Apps Environment resource ID')
output containerAppEnvironmentId string = containerAppEnvironment.id

@description('The Container Apps Environment default domain')
output containerAppEnvironmentDefaultDomain string = containerAppEnvironment.properties.defaultDomain

@description('The Key Vault resource ID')
output keyVaultId string = keyVault.id

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The Key Vault name')
output keyVaultName string = keyVault.name

@description('The managed identity resource ID')
output managedIdentityId string = managedIdentity.id

@description('The managed identity client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('The managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.id
