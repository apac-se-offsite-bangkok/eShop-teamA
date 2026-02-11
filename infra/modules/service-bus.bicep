@description('Azure Service Bus — replaces RabbitMQ "eventbus" for production integration events')

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

@description('The Service Bus SKU')
@allowed(['Standard', 'Premium'])
param skuName string = 'Standard'

@description('Key Vault name for storing connection strings')
param keyVaultName string

@description('Managed identity principal ID for RBAC')
param managedIdentityPrincipalId string

// =============================================================================
// Variables
// =============================================================================

var serviceBusName = 'sb-${appName}-${environmentName}'
// Topic matches the RabbitMQ exchange name used in EventBusRabbitMQ/RabbitMQEventBus.cs
var topicName = 'eshop_event_bus'

// Azure Service Bus Data Sender / Receiver role definition IDs
var sbDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var sbDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

// Every service that publishes or subscribes to integration events
var subscribers = [
  'catalog-api'
  'basket-api'
  'ordering-api'
  'order-processor'
  'payment-processor'
  'webhooks-api'
  'webapp'
]

// =============================================================================
// Resources
// =============================================================================

resource serviceBus 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: serviceBusName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: {
    minimumTlsVersion: '1.2'
    disableLocalAuth: environmentName == 'prod'
  }
}

resource eventBusTopic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = {
  parent: serviceBus
  name: topicName
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'P14D'
    enablePartitioning: skuName == 'Standard'
  }
}

// Per-service subscriptions with dead-lettering
resource subscriptions 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = [
  for subscriber in subscribers: {
    parent: eventBusTopic
    name: subscriber
    properties: {
      deadLetteringOnMessageExpiration: true
      maxDeliveryCount: 10
      lockDuration: 'PT1M'
      defaultMessageTimeToLive: 'P14D'
    }
  }
]

// RBAC: managed identity can send messages
resource senderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, managedIdentityPrincipalId, sbDataSenderRoleId)
  scope: serviceBus
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataSenderRoleId)
    principalType: 'ServicePrincipal'
  }
}

// RBAC: managed identity can receive messages
resource receiverRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, managedIdentityPrincipalId, sbDataReceiverRoleId)
  scope: serviceBus
  properties: {
    principalId: managedIdentityPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sbDataReceiverRoleId)
    principalType: 'ServicePrincipal'
  }
}

// Store connection string in Key Vault for fallback scenarios
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

resource sbConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
  parent: keyVault
  name: 'servicebus-connection-string'
  properties: {
    value: listKeys('${serviceBus.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBus.apiVersion).primaryConnectionString
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The Service Bus namespace resource ID')
output id string = serviceBus.id

@description('The Service Bus namespace FQDN')
output fqdn string = '${serviceBusName}.servicebus.windows.net'

@description('The Service Bus namespace name')
output name string = serviceBus.name

@description('The event bus topic name')
output topicName string = eventBusTopic.name
