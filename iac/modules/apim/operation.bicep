import { operation } from '../../types.bicep'

@description('The name of the API Management resource to be created.')
param apimName string
@description('The name of the API (endpoint) to which the operation belongs.')
param endpointName string
@description('The list of backend services and their operations to deploy into API Management.')
param request operation

resource apim 'Microsoft.ApiManagement/service@2020-12-01' existing = {
  name: apimName
}

resource apiResource 'Microsoft.ApiManagement/service/apis@2021-12-01-preview' existing = {
  name: endpointName
  parent: apim
}

resource operationResource 'Microsoft.ApiManagement/service/apis/operations@2021-12-01-preview' = {
  name: request.name
  parent: apiResource
  properties: {
    displayName: request.displayName
    method: request.method
    urlTemplate: request.urlTemplate
    requestBody: request.requestBody
    response: request.response
  }
}

resource operationPolicies 'Microsoft.ApiManagement/service/apis/operations/policies@2021-12-01-preview' = [
  for (policy, i) in request.?policies ?? []: {
    name: policy.name
    parent: operationResource
    properties: {
      value: length(policy.value) > 0 ? policy.value : '<policies></policies>'
      format: length(policy.value) > 0 ? policy.format : 'xml'
    }
  }
]
