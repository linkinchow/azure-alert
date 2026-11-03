// M1 Service Health: servicehealthresources events, one standard event per TrackingId + content fingerprint, aggregated across subscriptions.
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
param fastLookback string = '2h'
param slowLookback string = '24h'
param enabled bool = true

@description('Service Health event types to alert on.')
param eventTypes array = [
  'ServiceIssue'
  'PlannedMaintenance'
  'HealthAdvisory'
  'SecurityAdvisory'
  'Billing'
]

var query = replace(loadTextContent('query.kql'), '__EVENT_TYPES__', join(map(eventTypes, t => '\'${t}\''), ', '))

module pull '../shared/pull-module.bicep' = {
  name: '${prefix}-m1-service-health'
  params: {
    name: '${prefix}-m1-service-health'
    location: location
    tags: tags
    moduleName: 'm1-service-health'
    query: query
    identityId: identityId
    routerName: routerName
    actionGroupId: actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    deployedAt: deployedAt
    fastLookback: fastLookback
    slowLookback: slowLookback
    enabled: enabled
  }
}

output workflowName string = pull.outputs.workflowName
