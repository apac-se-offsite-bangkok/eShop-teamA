@description('Azure Container Registry for eShop service container images')

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

@description('The ACR SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param skuName string = 'Standard'

@description('Managed identity principal ID for AcrPull role')
param managedIdentityPrincipalId string

// =============================================================================
// Variables
// =============================================================================

// ACR names must be alphanumeric
var acrName = 'acr${appName}${environmentName}'
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// =============================================================================
// Resources
// =============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    adminUserEnabled: false
    policies: {
      retentionPolicy: {
        days: environmentName == 'prod' ? 30 : 7
        status: 'enabled'
      }
    }
  }
}

// AcrPull RBAC so Container Apps can pull images via managed identity
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentityPrincipalId, acrPullRoleId)
  scope: containerRegistry
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The ACR resource ID')
output id string = containerRegistry.id

@description('The ACR login server (e.g., acreshopprod.azurecr.io)')
output loginServer string = containerRegistry.properties.loginServer

@description('The ACR name')
output name string = containerRegistry.name
