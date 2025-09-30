import { portal } from 'types.bicep'

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
  '#{ DEPLOYMENT_LOCATION }#' // This is a special value that will be replaced with the deployment location
])
@description('Azure region for all resources (must match an allowed list to avoid drift).')
param location string
@minLength(3)
@maxLength(23)
@description('Extra entropy appended to base name to ensure global uniqueness (e.g. dev, qa, prod, u123).')
param suffix string
@description('The API Management gateway configuration.')
param gateway portal

// Derived short identifiers (respecting provider length limits) used to build consistent child resource names.
var shortName = substring(name, 0, min(10, length(name)))
var shortSuffix = substring(suffix, 0, min(24, length(suffix)))
var resourceName = '${shortName}-${shortSuffix}'

targetScope = 'subscription'

// Root resource group for all environment-scoped resources.
resource resourceGroup 'Microsoft.Resources/resourceGroups@2020-06-01' = {
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

module aks 'modules/aks.bicep' = {
  name: '${deployment().name}--kubernetesCluster'
  scope: resourceGroup
  params: {
    name: 'aks-${resourceName}'
    location: resourceGroup.location
    kubernetesVersion: '1.28.6' // As of June 2024, the latest supported version in most regions
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
