// M9 Key Vault expiry: an Event Grid event subscription on one Key Vault that sends near-expiry / expired events of
// certificates, secrets and keys to the Router. Deployed into the Key Vault's resource group.
// The subscription is created directly on the vault (extension resource): Event Grid creates the vault's system topic
// in the vault's resource group, or reuses the existing one (a vault can have only one system topic).
targetScope = 'resourceGroup'

param vaultName string
param prefix string

@description('Resource ID of the Router Logic App; its callback URL is the webhook endpoint.')
param routerId string

@description('Key Vault event types sent to the Router.')
param eventTypes array = [
  'Microsoft.KeyVault.CertificateNearExpiry'
  'Microsoft.KeyVault.CertificateExpired'
  'Microsoft.KeyVault.SecretNearExpiry'
  'Microsoft.KeyVault.SecretExpired'
  'Microsoft.KeyVault.KeyNearExpiry'
  'Microsoft.KeyVault.KeyExpired'
]

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: vaultName
}

resource expiry 'Microsoft.EventGrid/eventSubscriptions@2025-02-15' = {
  name: '${prefix}-kv-expiry'
  scope: vault
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: listCallbackUrl('${routerId}/triggers/manual', '2019-05-01').value
      }
    }
    filter: {
      includedEventTypes: eventTypes
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

output subscriptionId string = expiry.id
