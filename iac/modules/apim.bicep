import { policy, backend, namedValue } from '../types.bicep'

@description('The name of the API Management resource to be created.')
param name string

@description('The email address of the publisher of the APIM resource.')
@minLength(1)
param publisherEmail string = 'apim@contoso.com'

@description('Company name of the publisher of the APIM resource.')
@minLength(1)
param publisherName string = 'Contoso'

@description('The pricing tier of the APIM resource.')
param skuName string = 'Developer'

@description('The instance size of the APIM resource.')
param capacity int = 1

@description('Location for Azure resources.')
param location string = resourceGroup().location

@description('The name of the Application Insights resource to be used for logging.')
param insightsName string

@description('The list of backend services and their operations to deploy into API Management.')
param backends backend[] = []

@description('The list of policies to apply to the API Management service.')
param policies policy[] = []

@description('The name of the Key Vault resource for storing secrets.')
param keyVaultName string = ''

@description('The list of named values to create in API Management.')
param namedValues namedValue[] = []

@description('Custom tags to apply to the resources')
param tags object = {}

/*
 * Resources
*/
resource insights 'Microsoft.Insights/components@2020-02-02-preview' existing = {
  name: insightsName
}

// Reference to existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (keyVaultName != '') {
  name: keyVaultName
}

// Grant APIM access to Key Vault secrets
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = if (keyVaultName != '') {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: apim.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    capacity: capacity
    name: skuName
  }
  properties: {
    virtualNetworkType: 'External'
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
  tags: tags
}

// Named values for OAuth configuration
resource namedValueResources 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = [
  for nv in namedValues: {
    name: nv.name
    parent: apim
    properties: {
      displayName: nv.?displayName ?? nv.name
      value: (keyVaultName != '' && nv.?keyVaultSecretName != null) ? null : nv.?value
      keyVault: (keyVaultName != '' && nv.?keyVaultSecretName != null) ? {
        secretIdentifier: '${keyVault!.properties.vaultUri}secrets/${nv.keyVaultSecretName!}'
      } : null
      secret: nv.secret
    }
    dependsOn: (keyVaultName != '' && nv.?keyVaultSecretName != null) ? [keyVaultAccessPolicy] : []
  }
]

resource rule 'Microsoft.ApiManagement/service/policies@2024-05-01' = [
  for p in policies: {
    name: p.name
    parent: apim
    properties: {
      format: p.format
      value: p.?value ?? '<policies></policies>'
    }
  }
]

module backendModule 'apim/backend.bicep' = [
  for api in backends: {
    name: '${deployment().name}--${api.name}'
    params: {
      apimName: apim.name
      api: api
    }
  }
]

resource logger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: insightsName
  properties: {
    loggerType: 'applicationInsights'
    resourceId: insights.id
    credentials: {
      instrumentationKey: insights.properties.InstrumentationKey
    }
  }
}

resource diagnostics 'Microsoft.ApiManagement/service/diagnostics@2024-05-01' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: logger.id
    alwaysLog: 'allErrors'
    sampling: {
      percentage: 100
      samplingType: 'fixed'
    }
  }
}

output gatewayUrl string = apim.properties.gatewayUrl
output portalUrl string = apim.properties.portalUrl
output name string = apim.name
output principalId string = apim.identity.principalId
output keyVaultIntegrationEnabled bool = keyVaultName != ''
