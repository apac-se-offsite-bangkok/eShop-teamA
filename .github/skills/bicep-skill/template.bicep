// =============================================================================
// eShop Bicep Module Template
//
// Copy this file as a starting point when creating new Bicep modules.
// Follow the section order: Parameters → Variables → Resources → Outputs.
// See SKILL.md for full conventions and naming rules.
// =============================================================================

@description('Brief description: what this module provisions and why')

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

// Add module-specific parameters below.
// Guidelines:
//   - Use @description() on every parameter
//   - Use @allowed() for enum-like values
//   - Use @secure() for secrets — never set defaults on secure params
//   - Use @minValue()/@maxValue() for numeric bounds
//   - Provide sensible defaults where possible
//   - Group related params together with a comment

// --- Example: SKU configuration ---
// @description('The SKU name for the resource')
// @allowed(['Basic', 'Standard', 'Premium'])
// param skuName string = 'Standard'

// --- Example: Key Vault integration ---
// @description('Key Vault name for storing connection strings and secrets')
// param keyVaultName string

// --- Example: RBAC integration ---
// @description('Managed identity principal ID for role assignments')
// param managedIdentityPrincipalId string

// =============================================================================
// Variables
// =============================================================================

// Resource name using CAF abbreviation: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations
// Common: psql, redis, sb, ca, cae, acr, kv, log, id, oai, cosmos, appi, st
var resourceName = '<abbrev>-${appName}-${environmentName}'

// =============================================================================
// Resources
// =============================================================================

// Primary resource
// Guidelines:
//   - Use the latest stable API version (2024-xx-xx or newer)
//   - Always set location, tags
//   - Set minTlsVersion = '1.2' where supported
//   - Prefer managed identity auth over keys/passwords
//   - Do NOT use dependsOn when an implicit dependency exists via property references
//   - For prod: enable zone redundancy, geo-redundant backups, soft delete

/*
resource exampleResource 'Microsoft.XXX/yyy@2024-xx-xx' = {
  name: resourceName
  location: location
  tags: tags
  properties: {
    // Resource-specific properties
  }
}
*/

// --- RBAC role assignment (if applicable) ---
// Use built-in role definition IDs from:
// https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
/*
var roleDefinitionId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(exampleResource.id, managedIdentityPrincipalId, roleDefinitionId)
  scope: exampleResource
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalType: 'ServicePrincipal'
  }
}
*/

// --- Key Vault secret storage (if applicable) ---
// Store connection strings, keys, or endpoints in Key Vault — never output secrets directly
/*
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource connectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
  parent: keyVault
  name: '<resource>-connection-string'
  properties: {
    value: '<constructed-connection-string>'
  }
}
*/

// --- Diagnostic settings (recommended for production) ---
// Send logs and metrics to Log Analytics
/*
@description('Log Analytics workspace resource ID for diagnostics')
param logAnalyticsWorkspaceId string

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${resourceName}-diagnostics'
  scope: exampleResource
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
*/

// =============================================================================
// Outputs
// =============================================================================

// Always output at minimum: id, name
// Output FQDNs, endpoints, URLs as needed by consuming modules
// NEVER output secrets — use Key Vault references instead

/*
@description('The resource ID')
output id string = exampleResource.id

@description('The resource name')
output name string = exampleResource.name
*/

// --- Example: FQDN / endpoint output ---
// @description('The resource FQDN')
// output fqdn string = exampleResource.properties.fullyQualifiedDomainName
