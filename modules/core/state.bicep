// Alert state for the Router: repeat suppression in an Azure Storage table.
// The Router reads and writes the table with its system-assigned managed identity (Entra ID); shared keys are disabled.
// No public network access, no "trusted Azure services" exception: a resource instance rule lets only the Router
// (Microsoft.Logic/workflows <prefix>-router) reach the account. Resource instance rules are documented for the
// resource's system-assigned identity, so the table calls use that identity, not the shared user-assigned one.
targetScope = 'resourceGroup'

param accountName string
param location string = resourceGroup().location
param tags object = {}

@description('Principal ID of the Router system-assigned managed identity.')
param routerPrincipalId string

@description('Resource ID of the Router workflow, the only resource allowed through the network rules.')
param routerId string

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
      bypass: 'None'
      ipRules: []
      virtualNetworkRules: []
      resourceAccessRules: [
        {
          tenantId: tenant().tenantId
          resourceId: routerId
        }
      ]
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
  name: guid(account.id, routerPrincipalId, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: account
  properties: {
    principalId: routerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  }
}

output tableUrl string = '${account.properties.primaryEndpoints.table}${tableName}'
