param userAssignedIdentityName string
param aksOidcIssuer string
param serviceAccountName string = 'oauth-obo-sa'
param serviceAccountNamespace string = 'default'

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

resource federatedIdentityCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: '${serviceAccountNamespace}-${serviceAccountName}'
  parent: userAssignedIdentity
  properties: {
    issuer: aksOidcIssuer
    subject: 'system:serviceaccount:${serviceAccountNamespace}:${serviceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

output name string = federatedIdentityCredential.name
output clientId string = userAssignedIdentity.properties.clientId
