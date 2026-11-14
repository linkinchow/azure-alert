// Alert state for the Router: repeat suppression (and the mute list) in an Azure Storage table.
// The Router reads and writes the table with the managed identity (Entra ID); shared keys are disabled.
// No public network access: Logic Apps reach the account through the "trusted Azure services" exception
// (bypass AzureServices), which works with publicNetworkAccess Disabled and a managed identity.
targetScope = 'resourceGroup'

param prefix string
param location string = resourceGroup().location
param tags object = {}
param identityPrincipalId string

var accountName = '${take(toLower(replace(replace(prefix, '-', ''), '_', '')), 9)}st${uniqueString(resourceGroup().id, prefix)}'
var tableName = 'alertstate'

resource account 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    defaultToOAuthAuthentication: true
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2024-01-01' = {
  parent: account
  name: 'default'
}

resource table 'Microsoft.Storage/storageAccounts/tableServices/tables@2024-01-01' = {
  parent: tableService
  name: tableName
}

// Storage Table Data Contributor, on this account only.
resource tableWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(account.id, identityPrincipalId, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: account
  properties: {
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  }
}

output tableUrl string = '${account.properties.primaryEndpoints.table}${tableName}'
output accountName string = account.name
