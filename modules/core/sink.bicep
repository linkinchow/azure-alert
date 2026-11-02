// Optional data sink: standard events -> Log Analytics custom table AzureAlertEvents_CL via the Logs Ingestion API.
// Creates a workspace unless workspaceResourceId points to an existing one (which must be in this resource group).
targetScope = 'resourceGroup'

param prefix string
param location string = resourceGroup().location
param tags object = {}
param identityPrincipalId string

@description('Existing workspace in this resource group; empty = create one.')
param workspaceResourceId string = ''
param retentionInDays int = 90

var tableName = 'AzureAlertEvents_CL'
var streamName = 'Custom-AzureAlertEvents'
var columns = [
  { name: 'TimeGenerated', type: 'datetime' }
  { name: 'EventId', type: 'string' }
  { name: 'Module', type: 'string' }
  { name: 'Channel', type: 'string' }
  { name: 'Category', type: 'string' }
  { name: 'Severity', type: 'string' }
  { name: 'Status', type: 'string' }
  { name: 'Initiator', type: 'string' }
  { name: 'Title', type: 'string' }
  { name: 'Summary', type: 'string' }
  { name: 'EventTime', type: 'datetime' }
  { name: 'DetectedTime', type: 'datetime' }
  { name: 'ResourceId', type: 'string' }
  { name: 'SubscriptionId', type: 'string' }
  { name: 'Event', type: 'dynamic' }
]

resource newWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (empty(workspaceResourceId)) {
  name: '${prefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: empty(workspaceResourceId) ? '${prefix}-law' : last(split(workspaceResourceId, '/'))
}

resource table 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: tableName
  properties: {
    schema: {
      name: tableName
      columns: columns
    }
    retentionInDays: retentionInDays
  }
  dependsOn: [
    newWorkspace
  ]
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${prefix}-dcr-events'
  location: location
  tags: tags
  kind: 'Direct'
  properties: {
    streamDeclarations: {
      '${streamName}': {
        columns: columns
      }
    }
    destinations: {
      logAnalytics: [
        {
          name: 'law'
          workspaceResourceId: workspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          streamName
        ]
        destinations: [
          'law'
        ]
        transformKql: 'source'
        outputStream: 'Custom-${tableName}'
      }
    ]
  }
  dependsOn: [
    table
  ]
}

// Monitoring Metrics Publisher on the DCR for the Router identity.
resource publisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dcr.id, identityPrincipalId, '3913510d-42f4-4e42-8a64-420c390055eb')
  scope: dcr
  properties: {
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
  }
}

output ingestionUrl string = '${dcr.properties.endpoints.logsIngestion}/dataCollectionRules/${dcr.properties.immutableId}/streams/${streamName}?api-version=2023-01-01'
output workspaceId string = workspace.id
