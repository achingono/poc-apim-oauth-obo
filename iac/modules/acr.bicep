@minLength(5)
@maxLength(50)
@description('Provide a globally unique name of your Azure Container Registry')
param name string = 'acr${uniqueString(resourceGroup().id)}'

@description('Provide a location for the registry.')
param location string = resourceGroup().location

@description('Provide a tier of your Azure Container Registry.')
param sku string = 'Basic'

@description('Enable or disable the admin user for the registry.')
param adminUserEnabled bool = true

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: name
  location: location
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
  }
}

@description('Output the name property for later use')
output name string = registry.name

@description('Output the login server property for later use')
output loginServer string = registry.properties.loginServer
