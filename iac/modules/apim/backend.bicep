import { backend } from '../../types.bicep'

@description('The name of the API Management resource to be created.')
param apimName string

@description('The list of backend services and their operations to deploy into API Management.')
param api backend

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource backendResource 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  name: api.name
  parent: apim
  properties: {
    url: api.url
    protocol: api.protocol
  }
}

module serviceModule 'service.bicep' = [
  for s in api.services: {
    name: '${deployment().name}--${s.name}'
    params: {
      apimName: apim.name
      endpoint: s
    }
  }
]
