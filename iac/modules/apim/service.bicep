import { service } from '../../types.bicep'

@description('The name of the API Management resource to be created.')
param apimName string

@description('The list of backend services and their operations to deploy into API Management.')
param endpoint service

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource apiResource 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  name: endpoint.name
  parent: apim
  properties: {
    displayName: endpoint.displayName
    subscriptionRequired: endpoint.subscriptionRequired
    path: endpoint.path
    protocols: endpoint.protocols
    isCurrent: endpoint.isCurrent
  }
}

resource apiPolicies 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = [
  for (policy, i) in endpoint.policies: {
    name: policy.name
    parent: apiResource
    properties: {
      value: policy.?value ?? '<policies></policies>'
      format: policy.format
    }
  }
]

module operations 'operation.bicep' = [
  for (operation, i) in endpoint.operations: {
    name: '${deployment().name}--${operation.name}'
    params: {
      apimName: apim.name
      endpointName: apiResource.name
      request: operation
    }
  }
]
