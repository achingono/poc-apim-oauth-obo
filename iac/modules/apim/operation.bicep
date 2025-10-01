import { operation } from '../../types.bicep'

@description('The name of the API Management resource to be created.')
param apimName string
@description('The name of the API (endpoint) to which the operation belongs.')
param endpointName string
@description('The list of backend services and their operations to deploy into API Management.')
param request operation

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource apiResource 'Microsoft.ApiManagement/service/apis@2024-05-01' existing = {
  name: endpointName
  parent: apim
}

resource operationResource 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  name: request.name
  parent: apiResource
  properties: {
    displayName: request.displayName
    method: request.method
    urlTemplate: request.urlTemplate
    description: request.?description
    responses: [for response in (request.?responses ?? []): {
      statusCode: response.statusCode
      description: response.?description
      headers: response.?headers ?? []
      representations: response.?representations ?? []
    }]
  }
}

resource operationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = if (length(request.?policies ?? []) > 0) {
  name: 'policy'
  parent: operationResource
  properties: {
    value: length(request.?policies ?? []) > 0 ? (request.?policies![0].?value ?? '<policies></policies>') : '<policies></policies>'
    format: length(request.?policies ?? []) > 0 ? (request.?policies![0].?format ?? 'xml') : 'xml'
  }
}
