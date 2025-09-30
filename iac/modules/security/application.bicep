// resources/appregistration.bicep
// Module to create an Azure AD App Registration and assign App Configuration Data Owner role

param name string
param publicFqdn string

extension microsoftGraphV1

resource application 'Microsoft.Graph/applications@v1.0' = {
  displayName: name
  uniqueName: uniqueString(subscription().id, name)
  signInAudience: 'AzureADMyOrg'
  web: {
    redirectUris: [
      'https://${publicFqdn}/admin/signin-oidc'
    ]
    implicitGrantSettings: {
      enableIdTokenIssuance: true
    }
    redirectUriSettings: [
      {
        uri: 'https://${publicFqdn}/admin/signin-oidc'
      }
    ]
  }
  requiredResourceAccess: [
    {
      resourceAppId: '35ffadb3-7fc1-497e-b61b-381d28e744cc' // Azure App Configuration
      resourceAccess: [
        {
          id: '08eeff12-9b4a-4273-b3d9-ff8a13c32645'
          type: 'Scope'
        }
        {
          id: '77967a14-4f88-4960-84da-e8f71f761ac2'
          type: 'Scope'
        }
        {
          id: '8d17f7f7-030c-4b57-8129-cfb5a16433cd'
          type: 'Scope'
        }
        {
          id: '5970d132-a862-421f-9352-8ed18f833d78'
          type: 'Scope'
        }
        {
          id: 'ea601552-5fd3-4792-9dfc-e85be5a6827c'
          type: 'Scope'
        }
        {
          id: '28bb462a-d940-4cbe-afeb-281756df9af8'
          type: 'Scope'
        }
      ]
    }
    {
      resourceAppId: '00000003-0000-0000-c000-000000000000' // Microsoft Graph
      resourceAccess: [
        {
          id: 'e1fe6dd8-ba31-4d61-89e7-88639da4683d' // User.Read
          type: 'Scope'
        }
      ]
    }
  ]
}

resource principal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: application.appId
}

output appId string = application.appId
output objectId string = principal.id
