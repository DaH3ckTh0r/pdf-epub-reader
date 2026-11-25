// Sync backend + AI Foundry for the PDF/EPUB reader.
// Deploy at resource-group scope:
//   az deployment group create -g <rg> -f main.bicep -p main.bicepparam

@description('Short prefix used in resource names (lowercase letters/digits, max 10).')
@minLength(3)
@maxLength(10)
param prefix string = 'lectorpdf'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Environment name, e.g. dev, prod.')
@allowed([
  'dev'
  'prod'
])
param env string = 'dev'

@description('Object ID of the user or group that gets access to Key Vault secrets (your Entra ID object ID).')
param adminObjectId string

@description('Cosmos DB mode. Serverless is cheapest for a personal/low-traffic app.')
@allowed([
  'serverless'
  'provisioned'
])
param cosmosMode string = 'serverless'

@description('Foundry model to deploy. Check availability in your region and subscription before deploying.')
param modelName string = 'gpt-4.1-mini'

@description('Model version matching modelName.')
param modelVersion string

@description('Model deployment capacity (thousands of tokens per minute). Keep low on the free tier.')
param modelCapacity int = 10

var suffix = uniqueString(resourceGroup().id)
var baseName = '${prefix}${env}'

// ---------- Storage: book files (PDF/EPUB) ----------
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('${baseName}st${suffix}', 24)
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 14
    }
  }
}

resource booksContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'books'
  properties: {
    publicAccess: 'None'
  }
}

// ---------- Cosmos DB: reading progress, notes, library index ----------
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: take('${baseName}cosmos${suffix}', 44)
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: cosmosMode == 'serverless' ? [
      {
        name: 'EnableServerless'
      }
    ] : []
    minimalTlsVersion: 'Tls12'
    disableLocalAuth: true
  }
}

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmos
  name: 'reader'
  properties: {
    resource: {
      id: 'reader'
    }
  }
}

resource cosmosSync 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDb
  name: 'sync'
  properties: {
    resource: {
      id: 'sync'
      partitionKey: {
        paths: [
          '/userId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
      }
    }
  }
}

// ---------- Key Vault: secrets and config ----------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take('${baseName}kv${suffix}', 24)
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

// Key Vault Secrets Officer for the admin principal
var kvSecretsOfficerRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')

resource kvAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, adminObjectId, kvSecretsOfficerRole)
  scope: keyVault
  properties: {
    roleDefinitionId: kvSecretsOfficerRole
    principalId: adminObjectId
    principalType: 'User'
  }
}

// ---------- Azure AI Foundry: account, project, model deployment ----------
resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: take('${baseName}ai${suffix}', 64)
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: take('${baseName}ai${suffix}', 64)
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: '${baseName}-project'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'PDF/EPUB Reader ${env}'
    description: 'AI explanations and summaries for the reader app.'
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundry
  name: modelName
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

// ---------- Outputs (no secrets) ----------
output storageAccountName string = storage.name
output booksContainerName string = booksContainer.name
output cosmosAccountName string = cosmos.name
output cosmosDatabaseName string = cosmosDb.name
output cosmosContainerName string = cosmosSync.name
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output foundryAccountName string = foundry.name
output foundryEndpoint string = foundry.properties.endpoint
output foundryProjectName string = foundryProject.name
output modelDeploymentName string = modelDeployment.name
