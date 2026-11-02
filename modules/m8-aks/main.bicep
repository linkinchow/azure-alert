// M8 AKS platform events from ARG containerserviceeventresources (auto-upgrade scheduled events and version EOL notifications).
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
param enabled bool = true

@description('Event kinds to alert on: OutOfSupport (weekly reminder), EOLSoon (2 weeks / 1 week before EOL), UpgradeScheduled (pre-notice), UpgradeNotSucceeded (failed / canceled), UpgradeSkipped (skipped, e.g. cluster stopped), Routine (started / succeeded).')
param kinds array = [
  'OutOfSupport'
  'EOLSoon'
  'UpgradeScheduled'
  'UpgradeNotSucceeded'
]

var query = replace(loadTextContent('query.kql'), '__KINDS__', join(map(kinds, k => '\'${k}\''), ', '))

module pull '../shared/pull-module.bicep' = {
  name: '${prefix}-m8-aks'
  params: {
    name: '${prefix}-m8-aks'
    location: location
    tags: tags
    moduleName: 'm8-aks'
    query: query
    identityId: identityId
    routerName: routerName
    actionGroupId: actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    intervalMinutes: 5
    fastLookback: '2h'
    slowLookback: '24h'
    // weekly OutOfSupport fingerprints must outlive a week
    retentionHours: 200
    enabled: enabled
  }
}

output workflowName string = pull.outputs.workflowName
