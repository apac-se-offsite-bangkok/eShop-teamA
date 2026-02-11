// =============================================================================
// eShop Production Infrastructure — Main Orchestration
//
// Provisions all Azure resources for the eShop application, mapping from the
// local Aspire AppHost topology (src/eShop.AppHost/Program.cs) to Azure
// managed services.
//
// Architecture (from README.md):
//   PostgreSQL (pgvector) → Azure Database for PostgreSQL Flexible Server
//   Redis                 → Azure Cache for Redis
//   RabbitMQ              → Azure Service Bus
//   .NET services (10)    → Azure Container Apps
//   YARP mobile-bff       → Azure Container App (external ingress)
//   Container images      → Azure Container Registry
//
// Usage:
//   az deployment group create \
//     -g rg-eshop-prod \
//     -f infra/main.bicep \
//     -p infra/main.bicepparam
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// Parameters
// =============================================================================

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('The environment name')
@allowed(['prod', 'staging', 'dev'])
param environmentName string

@description('The base name for the application')
param appName string = 'eshop'

@description('PostgreSQL administrator password')
@secure()
param postgresAdminPassword string

@description('Enable Azure OpenAI (mirrors useOpenAI flag in AppHost Program.cs)')
param useOpenAI bool = false

@description('Container image tag to deploy')
param imageTag string = 'latest'

// =============================================================================
// Variables
// =============================================================================

var tags = {
  application: appName
  environment: environmentName
  managedBy: 'bicep'
}

// =============================================================================
// Module: Shared Infrastructure
// (Container Apps Environment, Log Analytics, Key Vault, Managed Identity)
// =============================================================================

module shared 'modules/shared.bicep' = {
  name: 'shared-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    appName: appName
    tags: tags
  }
}

// =============================================================================
// Module: PostgreSQL Flexible Server
// (4 databases: catalogdb, identitydb, orderingdb, webhooksdb + pgvector)
// =============================================================================

module postgres 'modules/postgres.bicep' = {
  name: 'postgres-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    appName: appName
    tags: tags
    administratorPassword: postgresAdminPassword
    keyVaultName: shared.outputs.keyVaultName
    databaseNames: ['catalogdb', 'identitydb', 'orderingdb', 'webhooksdb']
  }
}

// =============================================================================
// Module: Azure Cache for Redis
// (Basket.API session/cache store — replaces local Redis container)
// =============================================================================

module redis 'modules/redis.bicep' = {
  name: 'redis-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    appName: appName
    tags: tags
    keyVaultName: shared.outputs.keyVaultName
  }
}

// =============================================================================
// Module: Azure Service Bus
// (Replaces RabbitMQ "eventbus" — topic: eshop_event_bus)
// =============================================================================

module serviceBus 'modules/service-bus.bicep' = {
  name: 'servicebus-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    appName: appName
    tags: tags
    keyVaultName: shared.outputs.keyVaultName
    managedIdentityPrincipalId: shared.outputs.managedIdentityPrincipalId
  }
}

// =============================================================================
// Module: Azure Container Registry
// =============================================================================

module acr 'modules/acr.bicep' = {
  name: 'acr-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    appName: appName
    tags: tags
    managedIdentityPrincipalId: shared.outputs.managedIdentityPrincipalId
  }
}

// =============================================================================
// Module: Azure OpenAI (optional)
// =============================================================================

module openai 'modules/openai.bicep' = if (useOpenAI) {
  name: 'openai-${environmentName}'
  params: {
    location: location
    environmentName: environmentName
    appName: appName
    tags: tags
    keyVaultName: shared.outputs.keyVaultName
    managedIdentityPrincipalId: shared.outputs.managedIdentityPrincipalId
  }
}

// =============================================================================
// Container Apps — one per eShop service
//
// Service wiring derived from src/eShop.AppHost/Program.cs:
//   identity-api     → identityDb, external ingress, callback URLs for all apps
//   catalog-api      → catalogDb, eventbus, (optional OpenAI)
//   basket-api       → redis, eventbus, Identity__Url (gRPC: http2 transport)
//   ordering-api     → orderingDb, eventbus, Identity__Url
//   order-processor  → orderingDb, eventbus (worker — no ingress)
//   payment-processor→ eventbus (worker — no ingress)
//   webhooks-api     → webhooksDb, eventbus, Identity__Url
//   webhooksclient   → webhooks-api, IdentityUrl, CallBackUrl
//   webapp           → basket-api, catalog-api, ordering-api, eventbus, IdentityUrl
//   mobile-bff       → catalog-api, ordering-api, identity-api (YARP, external)
// =============================================================================

// --- Common environment variables (mirrors AddForwardedHeaders in AppHost) ---

var commonEnv = [
  { name: 'ASPNETCORE_FORWARDEDHEADERS_ENABLED', value: 'true' }
  { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
]

// Pre-compute service URLs using Container Apps predictable FQDN pattern
// This avoids circular dependencies between modules (e.g., identity-api ↔ webapp)
var caeDomain = shared.outputs.containerAppEnvironmentDefaultDomain
var identityApiUrl = 'https://ca-identity-api.${caeDomain}'
var catalogApiUrl = 'https://ca-catalog-api.${caeDomain}'
var orderingApiUrl = 'https://ca-ordering-api.${caeDomain}'
var basketApiUrl = 'https://ca-basket-api.${caeDomain}'
var webhooksApiUrl = 'https://ca-webhooks-api.${caeDomain}'
var webhooksClientUrl = 'https://ca-webhooksclient.${caeDomain}'
var webappUrl = 'https://ca-webapp.${caeDomain}'

// --- Common secrets used by multiple services ---

var postgresSecrets = [
  { name: 'postgres-catalogdb-conn', keyVaultUrl: '${shared.outputs.keyVaultUri}secrets/postgres-catalogdb-connection-string', identity: shared.outputs.managedIdentityId }
  { name: 'postgres-identitydb-conn', keyVaultUrl: '${shared.outputs.keyVaultUri}secrets/postgres-identitydb-connection-string', identity: shared.outputs.managedIdentityId }
  { name: 'postgres-orderingdb-conn', keyVaultUrl: '${shared.outputs.keyVaultUri}secrets/postgres-orderingdb-connection-string', identity: shared.outputs.managedIdentityId }
  { name: 'postgres-webhooksdb-conn', keyVaultUrl: '${shared.outputs.keyVaultUri}secrets/postgres-webhooksdb-connection-string', identity: shared.outputs.managedIdentityId }
]

var serviceBusSecret = [
  { name: 'servicebus-conn', keyVaultUrl: '${shared.outputs.keyVaultUri}secrets/servicebus-connection-string', identity: shared.outputs.managedIdentityId }
]

var redisSecret = [
  { name: 'redis-conn', keyVaultUrl: '${shared.outputs.keyVaultUri}secrets/redis-connection-string', identity: shared.outputs.managedIdentityId }
]

// ===== 1. Identity API =====
// AppHost: .WithReference(identityDb), .WithExternalHttpEndpoints()
// Receives callback URLs for all client apps

module identityApi 'modules/container-app.bicep' = {
  name: 'ca-identity-api-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'identity-api'
    containerImage: '${acr.outputs.loginServer}/identity-api:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: true
    hasIngress: true
    cpu: '0.5'
    memory: '1Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    secrets: postgresSecrets
    env: union(commonEnv, [
      { name: 'ConnectionStrings__identitydb', secretRef: 'postgres-identitydb-conn' }
      { name: 'BasketApiClient', value: basketApiUrl }
      { name: 'OrderingApiClient', value: orderingApiUrl }
      { name: 'WebhooksApiClient', value: webhooksApiUrl }
      { name: 'WebhooksWebClient', value: webhooksClientUrl }
      { name: 'WebAppClient', value: webappUrl }
    ])
  }
}

// ===== 2. Catalog API =====
// AppHost: .WithReference(catalogDb), .WithReference(rabbitMq)

module catalogApi 'modules/container-app.bicep' = {
  name: 'ca-catalog-api-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'catalog-api'
    containerImage: '${acr.outputs.loginServer}/catalog-api:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: false
    hasIngress: true
    cpu: '0.5'
    memory: '1Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    secrets: union(postgresSecrets, serviceBusSecret)
    env: union(commonEnv, [
      { name: 'ConnectionStrings__catalogdb', secretRef: 'postgres-catalogdb-conn' }
      { name: 'ConnectionStrings__eventbus', secretRef: 'servicebus-conn' }
    ])
  }
}

// ===== 3. Basket API =====
// AppHost: .WithReference(redis), .WithReference(rabbitMq), gRPC service
// Uses http2 transport for gRPC

module basketApi 'modules/container-app.bicep' = {
  name: 'ca-basket-api-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'basket-api'
    containerImage: '${acr.outputs.loginServer}/basket-api:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: false
    hasIngress: true
    transport: 'http2' // gRPC requires http2
    cpu: '0.5'
    memory: '1Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    secrets: union(redisSecret, serviceBusSecret)
    env: union(commonEnv, [
      { name: 'ConnectionStrings__redis', secretRef: 'redis-conn' }
      { name: 'ConnectionStrings__eventbus', secretRef: 'servicebus-conn' }
      { name: 'Identity__Url', value: identityApiUrl }
    ])
  }
}

// ===== 4. Ordering API =====
// AppHost: .WithReference(orderDb), .WithReference(rabbitMq), .WithEnvironment("Identity__Url")

module orderingApi 'modules/container-app.bicep' = {
  name: 'ca-ordering-api-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'ordering-api'
    containerImage: '${acr.outputs.loginServer}/ordering-api:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: false
    hasIngress: true
    cpu: '0.5'
    memory: '1Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    secrets: union(postgresSecrets, serviceBusSecret)
    env: union(commonEnv, [
      { name: 'ConnectionStrings__orderingdb', secretRef: 'postgres-orderingdb-conn' }
      { name: 'ConnectionStrings__eventbus', secretRef: 'servicebus-conn' }
      { name: 'Identity__Url', value: identityApiUrl }
    ])
  }
}

// ===== 5. Order Processor =====
// AppHost: .WithReference(rabbitMq), .WithReference(orderDb) — background worker, no ingress

module orderProcessor 'modules/container-app.bicep' = {
  name: 'ca-order-processor-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'order-processor'
    containerImage: '${acr.outputs.loginServer}/order-processor:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: false
    hasIngress: false // background worker
    cpu: '0.5'
    memory: '1Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    secrets: union(postgresSecrets, serviceBusSecret)
    env: union(commonEnv, [
      { name: 'ConnectionStrings__orderingdb', secretRef: 'postgres-orderingdb-conn' }
      { name: 'ConnectionStrings__eventbus', secretRef: 'servicebus-conn' }
    ])
  }
}

// ===== 6. Payment Processor =====
// AppHost: .WithReference(rabbitMq) — background worker, no ingress, no DB

module paymentProcessor 'modules/container-app.bicep' = {
  name: 'ca-payment-processor-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'payment-processor'
    containerImage: '${acr.outputs.loginServer}/payment-processor:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: false
    hasIngress: false // background worker
    cpu: '0.25'
    memory: '0.5Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    secrets: serviceBusSecret
    env: union(commonEnv, [
      { name: 'ConnectionStrings__eventbus', secretRef: 'servicebus-conn' }
    ])
  }
}

// ===== 7. Webhooks API =====
// AppHost: .WithReference(webhooksDb), .WithReference(rabbitMq), .WithEnvironment("Identity__Url")

module webhooksApi 'modules/container-app.bicep' = {
  name: 'ca-webhooks-api-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'webhooks-api'
    containerImage: '${acr.outputs.loginServer}/webhooks-api:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: false
    hasIngress: true
    cpu: '0.25'
    memory: '0.5Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    secrets: union(postgresSecrets, serviceBusSecret)
    env: union(commonEnv, [
      { name: 'ConnectionStrings__webhooksdb', secretRef: 'postgres-webhooksdb-conn' }
      { name: 'ConnectionStrings__eventbus', secretRef: 'servicebus-conn' }
      { name: 'Identity__Url', value: identityApiUrl }
    ])
  }
}

// ===== 8. Webhooks Client =====
// AppHost: .WithReference(webHooksApi), .WithEnvironment("IdentityUrl"), .WithEnvironment("CallBackUrl")

module webhooksClient 'modules/container-app.bicep' = {
  name: 'ca-webhooksclient-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'webhooksclient'
    containerImage: '${acr.outputs.loginServer}/webhooksclient:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: false
    hasIngress: true
    cpu: '0.25'
    memory: '0.5Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    env: union(commonEnv, [
      { name: 'IdentityUrl', value: identityApiUrl }
    ])
  }
}

// ===== 9. WebApp (Blazor Server) =====
// AppHost: .WithReference(basketApi, catalogApi, orderingApi, rabbitMq), .WithEnvironment("IdentityUrl")
// Primary user-facing app — external ingress

module webapp 'modules/container-app.bicep' = {
  name: 'ca-webapp-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'webapp'
    containerImage: '${acr.outputs.loginServer}/webapp:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: true // public-facing storefront
    hasIngress: true
    cpu: '1.0'
    memory: '2Gi'
    maxReplicas: 5
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    secrets: union(serviceBusSecret, redisSecret)
    env: union(commonEnv, [
      { name: 'IdentityUrl', value: identityApiUrl }
      { name: 'ConnectionStrings__eventbus', secretRef: 'servicebus-conn' }
      { name: 'services__basket-api__http__0', value: basketApiUrl }
      { name: 'services__basket-api__http2__0', value: basketApiUrl }
      { name: 'services__catalog-api__http__0', value: catalogApiUrl }
      { name: 'services__ordering-api__http__0', value: orderingApiUrl }
    ])
  }
}

// ===== 10. Mobile BFF (YARP reverse proxy) =====
// AppHost: .AddYarp("mobile-bff"), .WithExternalHttpEndpoints()
// Routes to catalog-api, ordering-api, identity-api

module mobileBff 'modules/container-app.bicep' = {
  name: 'ca-mobile-bff-${environmentName}'
  params: {
    location: location
    tags: tags
    containerAppName: 'mobile-bff'
    containerImage: '${acr.outputs.loginServer}/mobile-bff:${imageTag}'
    environmentId: shared.outputs.containerAppEnvironmentId
    isExternalIngress: true // mobile clients connect externally
    hasIngress: true
    cpu: '0.5'
    memory: '1Gi'
    managedIdentityId: shared.outputs.managedIdentityId
    registryLoginServer: acr.outputs.loginServer
    env: union(commonEnv, [
      { name: 'services__catalog-api__http__0', value: catalogApiUrl }
      { name: 'services__ordering-api__http__0', value: orderingApiUrl }
      { name: 'services__identity-api__http__0', value: identityApiUrl }
    ])
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The WebApp URL — public storefront entry point')
output webAppUrl string = webapp.outputs.url

@description('The Identity API URL')
output identityApiUrl string = identityApiUrl

@description('The Mobile BFF URL — mobile client entry point')
output mobileBffUrl string = mobileBff.outputs.url

@description('The Container Apps Environment default domain')
output containerAppsDomain string = shared.outputs.containerAppEnvironmentDefaultDomain

@description('The ACR login server for pushing images')
output acrLoginServer string = acr.outputs.loginServer

@description('The Key Vault URI for secret management')
output keyVaultUri string = shared.outputs.keyVaultUri

@description('The PostgreSQL server FQDN')
output postgresServerFqdn string = postgres.outputs.fqdn

@description('The Service Bus FQDN')
output serviceBusFqdn string = serviceBus.outputs.fqdn
