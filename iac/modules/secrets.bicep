import { namedValue } from '../types.bicep'

@description('The name of the Key Vault to store secrets in.')
param keyVaultName string

@description('Named values to store as secrets in Key Vault.')
param namedValues namedValue[]

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Store secrets in Key Vault for namedValues that have keyVaultSecretName defined
resource secrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [
  for nv in filter(namedValues, nv => nv.?keyVaultSecretName != null): {
    name: nv.keyVaultSecretName!
    parent: keyVault
    properties: {
      value: nv.?value ?? '00000000-0000-0000-0000-000000000000'
      contentType: 'Named value for ${nv.name}'
    }
  }
]

output secretUris object = toObject(filter(namedValues, nv => nv.?keyVaultSecretName != null), nv => nv.name, nv => '${keyVault.properties.vaultUri}secrets/${nv.keyVaultSecretName!}')
