// M6 VM Scheduled Events from ARG maintenanceresources (no agent inside the VM).
// Prerequisites per subscription and per VM / VMSS: see README.md in this folder.
// Rows carry no timestamp and stay in ARG for a long time, so the whole table is read every run and fingerprints
// (EventId + status) are kept for 30 days.
targetScope = 'resourceGroup'

param prefix string
param location string = resourceGroup().location
param tags object = {}
param identityId string
param routerName string
param actionGroupId string = ''
param argScope object = {}
param excludedSubscriptionIds array = []
param bootstrapSilent bool = true
param deployedAt string = utcNow('yyyy-MM-ddTHH:mm:ssZ')
param enabled bool = true

@description('Event statuses to alert on. Scheduled = advance notice (only when the event is not auto-approved), Started / Completed / Canceled = progress.')
param statuses array = [
  'Scheduled'
  'Started'
  'Completed'
  'Canceled'
]

@description('Also alert on user-initiated events (e.g. az vm restart / redeploy).')
param includeUserInitiated bool = false

var sources = includeUserInitiated ? [
  'Platform'
  'User'
] : [
  'Platform'
]
var query = replace(replace(loadTextContent('query.kql'), '__STATUSES__', join(map(statuses, s => '\'${s}\''), ', ')), '__SOURCES__', join(map(sources, s => '\'${s}\''), ', '))

module pull '../shared/pull-module.bicep' = {
  name: '${prefix}-m6-scheduled-events'
  params: {
    name: '${prefix}-m6-scheduled-events'
    location: location
    tags: tags
    moduleName: 'm6-scheduled-events'
    query: query
    identityId: identityId
    routerName: routerName
    actionGroupId: actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    deployedAt: deployedAt
    intervalMinutes: 1
    retentionHours: 720
    enabled: enabled
  }
}

output workflowName string = pull.outputs.workflowName
