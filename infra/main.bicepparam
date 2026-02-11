// =============================================================================
// eShop Production Parameter File
//
// Usage:
//   az deployment group create \
//     -g rg-eshop-prod \
//     -f infra/main.bicep \
//     -p infra/main.bicepparam
// =============================================================================

using 'main.bicep'

param environmentName = 'prod'

param appName = 'eshop'

param imageTag = 'latest'

param useOpenAI = false

// PostgreSQL admin password — override with a secret at deploy time:
//   az deployment group create ... -p postgresAdminPassword='<value>'
// Or source from a Key Vault using --parameters syntax.
param postgresAdminPassword = '' // MUST be overridden at deployment time
