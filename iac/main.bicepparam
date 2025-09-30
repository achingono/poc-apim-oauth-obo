using 'main.bicep'

param name = readEnvironmentVariable('DEPLOYMENT_NAME', 'apim-oauth')
param suffix = readEnvironmentVariable('DEPLOYMENT_SUFFIX', 'poc')
param location = readEnvironmentVariable('DEPLOYMENT_LOCATION', 'eastus')
param namedValues = [
  {
    name: 'tenant-id'
    displayName: 'tenant-id'
    value: '<tenant-id>' // Auto-populated with subscription().tenantId during deployment
    secret: false
    keyVaultSecretName: 'tenant-id'
  }
  {
    name: 'api-app-id'
    displayName: 'API Application ID'
    value: readEnvironmentVariable('API_APP_ID', '11111111-1111-1111-1111-111111111111') // Update after app registration
    secret: true
    keyVaultSecretName: 'api-app-id'
  }
  {
    name: 'admin-group-id'
    displayName: 'Admin Group ID'
    value: readEnvironmentVariable('ADMIN_GROUP_ID', '22222222-2222-2222-2222-222222222222') // Update after group creation
    secret: true
    keyVaultSecretName: 'admin-group-id'
  }
  {
    name: 'client-app-id'
    displayName: 'Client Application ID'
    value: readEnvironmentVariable('CLIENT_APP_ID', '33333333-3333-3333-3333-333333333333') // Update after app registration
    secret: true
    keyVaultSecretName: 'client-app-id'
  }
]
param gateway = {
  name: 'apim-oauthpoc'
  skuName: 'Developer'
  capacity: 1
  publisherEmail: 'admin@example.com'
  publisherName: 'OAuth OBO POC'
  backends: [
    {
      name: 'httpbin'
      description: 'HTTPBin service for testing OAuth OBO flows'
      url: 'https://httpbin.org'
      protocol: 'http'
      services: [
        {
          name: 'httpbin-api'
          displayName: 'HTTPBin Test API'
          subscriptionRequired: false
          path: '/httpbin'
          protocols: ['https']
          isCurrent: true
          policies: [
            {
              name: 'oauth-policy'
              format: 'rawxml'
              value: loadTextContent('./policies/oauth-policy.xml')
            }
          ]
          operations: [
            {
              name: 'get-httpbin'
              displayName: 'Get HTTPBin Response'
              method: 'GET'
              urlTemplate: '/test'
              description: 'Test endpoint that returns request details including injected headers'
              responses: [
                {
                  statusCode: 200
                  description: 'Success response with request details'
                  headers: []
                  representations: [
                    {
                      contentType: 'application/json'
                    }
                  ]
                }
              ]
              policies: []
            }
          ]
        }
      ]
    }
  ]
  policies: [
    {
      name: 'global-policy'
      format: 'rawxml'
      value: loadTextContent('./policies/global-policy.xml')
    }
  ]
}
param registry = readEnvironmentVariable('REGISTRY_NAME', '') == '' ? null : {
  name: readEnvironmentVariable('REGISTRY_NAME', '')
  resourceGroup: readEnvironmentVariable('REGISTRY_RESOURCE_GROUP', '')
  subscriptionId: readEnvironmentVariable('REGISTRY_SUBSCRIPTION_ID', '')
}
param vault = readEnvironmentVariable('VAULT_NAME', '') == '' ? null : {
  name: readEnvironmentVariable('VAULT_NAME', '')
  resourceGroup: readEnvironmentVariable('VAULT_RESOURCE_GROUP', '')
  subscriptionId: readEnvironmentVariable('VAULT_SUBSCRIPTION_ID', '')
}
