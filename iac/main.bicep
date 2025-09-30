import { portal, namedValue } from 'types.bicep'

@minLength(3)
@maxLength(21)
@description('Base logical environment name (used in naming every resource – truncated to provider constraints).')
param name string
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'westus3'
  'centralus'
  'northeurope'
  'westeurope'
  'uksouth'
  'ukwest'
  'australiaeast'
  'australiasoutheast'
  'eastasia'
  'southeastasia'
  'japaneast'
  'japanwest'
  'canadacentral'
  'canadaeast'
  'brazilsouth'
])
@description('Azure region for all resources (must match an allowed list to avoid drift).')
param location string
@minLength(3)
@maxLength(23)
@description('Extra entropy appended to base name to ensure global uniqueness (e.g. dev, qa, prod, u123).')
param suffix string
@description('The API Management gateway configuration.')
param gateway portal
@description('Named values for API Management configuration.')
param namedValues namedValue[]

// Derived short identifiers (respecting provider length limits) used to build consistent child resource names.
var shortName = substring(name, 0, min(10, length(name)))
var shortSuffix = substring(suffix, 0, min(24, length(suffix)))
var resourceName = '${shortName}-${shortSuffix}'

// Process namedValues to replace tenant-id placeholder with actual tenant ID
var processedNamedValues = [for nv in namedValues: {
  name: nv.name
  displayName: nv.?displayName ?? nv.name
  value: nv.name == 'tenant-id' ? subscription().tenantId : nv.?value
  secret: nv.secret
  keyVaultSecretName: nv.?keyVaultSecretName
}]

targetScope = 'subscription'

// Root resource group for all environment-scoped resources.
resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${resourceName}-${location}'
  location: location
}

// Observability (Log Analytics + Application Insights)
module insights 'modules/insights.bicep' = {
  name: '${deployment().name}--applicationInsights'
  scope: resourceGroup
  params: {
    name: 'appi-${resourceName}'
    workspaceName: 'log-${resourceName}'
    location: resourceGroup.location
  }
}

module apim 'modules/apim.bicep' = {
  name: '${deployment().name}--apiManagement'
  scope: resourceGroup
  params: {
    name: gateway.?name ?? 'apim-${resourceName}'
    publisherEmail: gateway.?publisherEmail
    publisherName: gateway.?publisherName
    skuName: gateway.?skuName
    capacity: gateway.?capacity
    location: resourceGroup.location
    insightsName: insights.outputs.name
    policies: gateway.?policies
    backends: gateway.backends
    keyVaultName: keyVault.outputs.name
    namedValues: processedNamedValues
    tags: {}
  }
}

module acr 'modules/acr.bicep' = {
  name: '${deployment().name}--containerRegistry'
  scope: resourceGroup
  params: {
    name: 'acr${resourceName}'
    location: resourceGroup.location
    sku: 'Basic'
    adminUserEnabled: true
  }
}

module keyVault 'modules/vault.bicep' = {
  name: '${deployment().name}--keyVault'
  scope: resourceGroup
  params: {
    name: 'kv-${resourceName}'
    location: resourceGroup.location
    skuFamily: 'A'
    skuName: 'standard'
  }
}

// Populate Key Vault with OAuth configuration secrets
module kvSecrets 'modules/secrets.bicep' = {
  name: '${deployment().name}--keyVaultSecrets'
  scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.name
    namedValues: processedNamedValues
  }
}

module aks 'modules/aks.bicep' = {
  name: '${deployment().name}--kubernetesCluster'
  scope: resourceGroup
  params: {
    name: 'aks-${resourceName}'
    location: resourceGroup.location
    kubernetesVersion: '1.30.6' // Updated to latest supported version as of September 2025
  }
}

module acrAccess 'modules/security/acr-access.bicep' = {
  name: '${deployment().name}--aksAcrAccess'
  scope: resourceGroup
  params: {
    acrName: acr.outputs.name
    principalId: aks.outputs.clusterIdentity.objectId
  }
}

module workloadIdentity './modules/security/identity.bicep' = {
  name: 'workloadIdentity'
  scope: resourceGroup
  params: {
    name: 'id-${resourceName}'
    location: location
  }
}

module federatedCredential './modules/security/credential.bicep' = {
  name: 'federatedCredential'
  scope: resourceGroup
  params: {
    userAssignedIdentityName: workloadIdentity.outputs.name
    aksOidcIssuer: aks.outputs.aksOidcIssuer
    serviceAccountName: 'oauth-obo-sa'
    serviceAccountNamespace: 'default'
  }
}

module appRegistration './modules/security/application.bicep' = {
  name: 'appRegistration'
  scope: resourceGroup
  params: {
    name: 'appreg${resourceName}'
    publicFqdn: aks.outputs.publicFqdn
  }
}
