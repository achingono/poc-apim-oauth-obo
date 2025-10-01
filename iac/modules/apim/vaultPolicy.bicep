import { source } from '../../types.bicep'

param vault source
param principalId string

// Reference to existing Key Vault in current resource group
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: vault.name
}

// Grant APIM access to Key Vault secrets
resource keyVaultAccessPolicyLocal 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}
