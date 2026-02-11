@description('Reusable Azure Container App module — one instance per eShop service')

// =============================================================================
// Parameters
// =============================================================================

@description('The Azure region for the Container App')
param location string

@description('Tags to apply to the resource')
param tags object

@description('The service name (e.g., catalog-api, webapp, order-processor)')
param containerAppName string

@description('The container image (e.g., acreshopprod.azurecr.io/catalog-api:v1.0)')
param containerImage string

@description('The Container Apps Environment resource ID')
param environmentId string

@description('The target port the container listens on')
param targetPort int = 8080

@description('Whether the app should have external (internet-facing) ingress')
param isExternalIngress bool = false

@description('Whether the app needs HTTP ingress (false for background workers like order-processor)')
param hasIngress bool = true

@description('Environment variables array')
param env array = []

@description('Secret definitions array')
param secrets array = []

@description('Minimum number of replicas')
param minReplicas int = 1

@description('Maximum number of replicas')
param maxReplicas int = 3

@description('CPU cores (e.g., 0.25, 0.5, 1.0)')
param cpu string = '0.5'

@description('Memory (e.g., 0.5Gi, 1Gi, 2Gi)')
param memory string = '1Gi'

@description('User-assigned managed identity resource ID')
param managedIdentityId string

@description('Container registry login server for image pull')
param registryLoginServer string

@description('Liveness probe path — maps to MapDefaultEndpoints() /health')
param healthProbePath string = '/health'

@description('Readiness probe path — maps to MapDefaultEndpoints() /alive')
param readinessProbePath string = '/alive'

@description('Transport protocol: http2 for gRPC services (basket-api), auto for others')
@allowed(['auto', 'http', 'http2'])
param transport string = 'auto'

// =============================================================================
// Variables
// =============================================================================

var caName = 'ca-${containerAppName}'

// =============================================================================
// Resources
// =============================================================================

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: caName
  location: location
  tags: union(tags, { service: containerAppName })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: hasIngress
        ? {
            external: isExternalIngress
            targetPort: targetPort
            transport: transport
            allowInsecure: false
          }
        : null
      registries: [
        {
          server: registryLoginServer
          identity: managedIdentityId
        }
      ]
      secrets: secrets
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: containerImage
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: env
          probes: hasIngress
            ? [
                {
                  type: 'Liveness'
                  httpGet: {
                    path: healthProbePath
                    port: targetPort
                  }
                  initialDelaySeconds: 15
                  periodSeconds: 30
                  failureThreshold: 3
                }
                {
                  type: 'Readiness'
                  httpGet: {
                    path: readinessProbePath
                    port: targetPort
                  }
                  initialDelaySeconds: 5
                  periodSeconds: 10
                  failureThreshold: 3
                }
              ]
            : []
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The Container App resource ID')
output id string = containerApp.id

@description('The Container App name')
output name string = containerApp.name

@description('The Container App FQDN (empty if no ingress)')
output fqdn string = hasIngress ? containerApp.properties.configuration.ingress.fqdn : ''

@description('The Container App internal URL (empty if no ingress)')
output url string = hasIngress ? 'https://${containerApp.properties.configuration.ingress.fqdn}' : ''
