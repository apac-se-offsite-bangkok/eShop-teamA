@description('Azure OpenAI Cognitive Services — optional, for Catalog.API embeddings and WebApp chat')

// =============================================================================
// Parameters
// =============================================================================

@description('The Azure region (check model availability per region)')
param location string

@description('The environment name')
@allowed(['prod', 'staging', 'dev'])
param environmentName string

@description('The base name for the application')
param appName string = 'eshop'

@description('Tags to apply to all resources')
param tags object

@description('The text embedding model deployment name — maps to AppHost textEmbeddingModel')
param embeddingDeploymentName string = 'text-embedding-3-small'

@description('The chat model deployment name — maps to AppHost chatModel')
param chatDeploymentName string = 'gpt-4o-mini'

@description('Key Vault name for storing endpoint')
param keyVaultName string

@description('Managed identity principal ID')
param managedIdentityPrincipalId string

// =============================================================================
// Variables
// =============================================================================

var openAiName = 'oai-${appName}-${environmentName}'
// Cognitive Services OpenAI User role
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

// =============================================================================
// Resources
// =============================================================================

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: environmentName == 'prod'
  }
}

resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: embeddingDeploymentName
  sku: {
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-small'
      version: '1'
    }
  }
}

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: chatDeploymentName
  sku: {
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
  }
  dependsOn: [embeddingDeployment] // Azure requires sequential model deployments
}

resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, managedIdentityPrincipalId, openAiUserRoleId)
  scope: openAiAccount
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource openAiEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
  parent: keyVault
  name: 'openai-endpoint'
  properties: {
    value: openAiAccount.properties.endpoint
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The OpenAI account resource ID')
output id string = openAiAccount.id

@description('The OpenAI endpoint URL')
output endpoint string = openAiAccount.properties.endpoint

@description('The embedding deployment name')
output embeddingDeploymentName string = embeddingDeployment.name

@description('The chat deployment name')
output chatDeploymentName string = chatDeployment.name
