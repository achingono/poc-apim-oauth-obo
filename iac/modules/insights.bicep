// -----------------------------------------------------------------------------
// Module: Observability (Log Analytics + Application Insights)
// Purpose: Deploys a Log Analytics workspace and an App Insights component
//          linked to that workspace for centralized logging + metrics.
// Retention: 30 days configurable in workspace properties.
// -----------------------------------------------------------------------------
@description('Logical base name for Application Insights (trimmed to 24 chars).')
@minLength(3)
@maxLength(50)
param name string

@description('Log Analytics workspace name (stores logs / traces / metrics).')
@minLength(4)
@maxLength(63)
param workspaceName string

@description('Azure region for both workspace and App Insights (should be colocated).')
param location string = resourceGroup().location

resource workspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: workspaceName
  location: location
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  })
}

resource insights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: substring(name, 0, min(24, length(name)))
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
  }
}

output name string = insights.name
output workspaceName string = workspace.name
