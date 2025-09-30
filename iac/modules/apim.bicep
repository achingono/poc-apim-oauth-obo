import { policy, backend } from '../types.bicep'

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

/*
 * Resources
*/
resource insights 'Microsoft.Insights/components@2020-02-02-preview' existing = {
  name: insightsName
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  sku: {
    capacity: capacity
    name: skuName
  }
  properties: {
    virtualNetworkType: 'External'
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Named values for OAuth configuration
resource tenantIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  name: 'tenant-id'
  parent: apim
  properties: {
    displayName: 'tenant-id'
    value: subscription().tenantId
    secret: false
  }
}

resource apiAppIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  name: 'api-app-id'
  parent: apim
  properties: {
    displayName: 'api-app-id'
    value: '11111111-1111-1111-1111-111111111111' // Placeholder - update with actual API App ID
    secret: false
  }
}

resource adminGroupIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  name: 'admin-group-id'
  parent: apim
  properties: {
    displayName: 'admin-group-id'
    value: '22222222-2222-2222-2222-222222222222' // Placeholder - update with actual Admin Group ID
    secret: false
  }
}

resource rule 'Microsoft.ApiManagement/service/policies@2024-05-01' = [
  for p in policies: {
    name: p.name
    parent: apim
    properties: {
      format: p.format
      value: p.value
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
