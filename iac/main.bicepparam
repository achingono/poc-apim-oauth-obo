using 'main.bicep'

param name = readEnvironmentVariable('DEPLOYMENT_NAME', 'airloge')
param suffix = readEnvironmentVariable('DEPLOYMENT_SUFFIX', 'dev')
param location = readEnvironmentVariable('DEPLOYMENT_LOCATION', 'eastus')
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
