---
name: bicep-skill
description: Generate and modify Azure Bicep infrastructure-as-code for provisioning the eShop production environment. Use when the user asks to create, update, or review Bicep templates, Azure resource definitions, IaC, infrastructure provisioning, or deployment scripts.
---

# Azure Bicep Skill — eShop Production Infrastructure

## When to Use

Use this skill when asked to:
- Create or modify Bicep templates for Azure resources
- Provision infrastructure for eShop services
- Add new Azure resources (databases, caches, messaging, compute)
- Review or troubleshoot Bicep deployments
- Generate parameter files for different environments

## eShop Azure Resource Mapping

The eShop AppHost (`src/eShop.AppHost/Program.cs`) defines the local dev topology. The production Azure equivalents are:

| Local Resource | Azure Resource | Bicep Module |
|---|---|---|
| PostgreSQL (ankane/pgvector) | Azure Database for PostgreSQL Flexible Server + pgvector extension | `modules/postgres.bicep` |
| Redis | Azure Cache for Redis | `modules/redis.bicep` |
| RabbitMQ | Azure Service Bus (premium for production) | `modules/service-bus.bicep` |
| .NET services (8 projects) | Azure Container Apps | `modules/container-app.bicep` |
| YARP mobile-bff | Azure Container Apps (with ingress) | `modules/container-app.bicep` |
| Container registry | Azure Container Registry | `modules/acr.bicep` |
| Shared infra | Container Apps Environment, Log Analytics, Key Vault, Managed Identity | `modules/shared.bicep` |
| OpenAI (optional) | Azure OpenAI Cognitive Services | `modules/openai.bicep` |

### Database Mapping

| Aspire DB Name | PostgreSQL Database | Used By |
|---|---|---|
| `catalogdb` | `catalogdb` | Catalog.API |
| `identitydb` | `identitydb` | Identity.API |
| `orderingdb` | `orderingdb` | Ordering.API, OrderProcessor |
| `webhooksdb` | `webhooksdb` | Webhooks.API |

## Bicep Conventions

### Module Template

When creating a new Bicep module, start from the annotated template at `.github/skills/bicep-skill/template.bicep`. It enforces the section order, naming, security, and output conventions described below. Copy it to `infra/modules/<new-module>.bicep` and fill in the resource-specific sections.

### File Structure
```
infra/
├── main.bicep              # Orchestration — deploys all modules
├── main.bicepparam         # Production parameter values
├── abbreviations.json      # Azure resource abbreviation table
└── modules/
    ├── shared.bicep         # Container Apps Environment, Log Analytics, Key Vault, Managed Identity
    ├── postgres.bicep       # PostgreSQL Flexible Server + databases
    ├── redis.bicep          # Azure Cache for Redis
    ├── service-bus.bicep    # Azure Service Bus namespace + queues/topics
    ├── acr.bicep            # Azure Container Registry
    ├── container-app.bicep  # Reusable module for each Container App
    └── openai.bicep         # Azure OpenAI (optional)
```

### Naming Rules
- Use `camelCase` for all Bicep identifiers (parameters, variables, resources, outputs)
- Resource names: `{abbrev}-{appName}-{environment}` (e.g., `psql-eshop-prod`, `redis-eshop-prod`)
- Use abbreviations from Microsoft's Cloud Adoption Framework: `psql`, `redis`, `sb`, `ca`, `cae`, `acr`, `kv`, `log`, `id`
- Tag all resources with `environment`, `application`, and `managedBy`

### Parameter Conventions
```bicep
// Always define these shared parameters in every module
@description('The Azure region for all resources')
param location string

@description('The environment name (e.g., prod, staging)')
@allowed(['prod', 'staging', 'dev'])
param environmentName string

@description('The base name for the application')
param appName string = 'eshop'
```

### Module Pattern
Every module must follow this structure:
```bicep
// modules/example.bicep
@description('Brief description of this module')

// === Parameters ===
param location string
param environmentName string
param appName string
param tags object

// === Variables ===
var resourceName = '${abbrev}-${appName}-${environmentName}'

// === Resources ===
resource myResource '...' = {
  name: resourceName
  location: location
  tags: tags
  properties: { ... }
}

// === Outputs ===
@description('The resource ID')
output id string = myResource.id

@description('The resource name')
output name string = myResource.name
```

### Security Rules
- **Never** hardcode secrets — use Key Vault references or `@secure()` parameters
- Use **managed identities** (system-assigned on Container Apps) — no connection string passwords where avoidable
- PostgreSQL: use Entra ID authentication with managed identity; fall back to admin password stored in Key Vault only if required
- Redis: use access keys stored in Key Vault, or managed identity with Redis RBAC
- Service Bus: use managed identity with `Azure Service Bus Data Sender/Receiver` roles
- Set `minTlsVersion` to `'1.2'` on all resources that support it
- Enable diagnostic settings for production resources

### Container App Conventions
Each eShop service maps to one Container App. The reusable `container-app.bicep` module accepts:
```bicep
param containerAppName string        // e.g., 'catalog-api'
param containerImage string          // e.g., 'eshopacr.azurecr.io/catalog-api:latest'
param environmentId string           // Container Apps Environment resource ID
param targetPort int                 // e.g., 8080
param isExternalIngress bool         // true for webapp, identity-api, mobile-bff
param env array                      // Environment variables array
param secrets array                  // Secret definitions
param minReplicas int = 1
param maxReplicas int = 3
param cpu string = '0.5'
param memory string = '1Gi'
```

Services with external ingress: `webapp`, `identity-api`, `mobile-bff`
Services with internal-only ingress: `catalog-api`, `ordering-api`, `basket-api`, `webhooks-api`, `webhooksclient`
Services with no ingress (workers): `order-processor`, `payment-processor`

### Environment Variable Mapping
Map Aspire connection references to Azure equivalents:
```bicep
// Example for ordering-api
var orderingApiEnv = [
  { name: 'ConnectionStrings__orderingdb', secretRef: 'postgres-connection-string' }
  { name: 'ConnectionStrings__eventbus', secretRef: 'servicebus-connection-string' }
  { name: 'Identity__Url', value: 'https://${identityApiFqdn}' }
  { name: 'ASPNETCORE_FORWARDEDHEADERS_ENABLED', value: 'true' }
]
```

### Deployment
```bash
# Validate
az deployment sub validate \
  --location eastus \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam

# Deploy
az deployment sub create \
  --location eastus \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam

# What-if (dry run)
az deployment sub what-if \
  --location eastus \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

### Do NOT
- Use ARM JSON templates — always Bicep
- Inline large resource definitions in `main.bicep` — use modules
- Use `dependsOn` when an implicit dependency (via property reference) exists
- Create separate Bicep files per environment — use parameters instead
- Use API versions older than 2024-01-01 unless the resource type requires it