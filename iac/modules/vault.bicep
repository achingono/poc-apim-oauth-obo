@minLength(5)
@maxLength(50)
@description('Provide a globally unique name of your Azure Container Registry')
param name string = 'kv-${uniqueString(resourceGroup().id)}'

@description('Provide a location for the registry.')
param location string = resourceGroup().location

@description('Provide a tier of your Azure Container Registry.')
param skuFamily string = 'A'

@description('Provide a size of your Azure Container Registry.')
param skuName string = 'standard'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  properties: {
    sku: {
      family: skuFamily
      name: skuName
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Enabled'
  }
}

@description('Output the name property for later use')
output name string = keyVault.name

@description('Output the vault URI for later use')
output vaultUri string = keyVault.properties.vaultUri
