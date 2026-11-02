// M5 Quota (Compute): ARG quotaresources usage per subscription/region/quota, alert when usage reaches a threshold band.
// Fingerprint = subscription + region + quota + band: a higher band alerts at once; staying in a band re-alerts after retentionHours (daily reminder).
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

@description('Usage bands in percent, ascending. The highest band is reported as Critical, the others as Warning.')
param bands array = [
  80
  90
  95
]

@description('Hours after which an unchanged band is reported again.')
param reminderHours int = 24

var sorted = sort(bands, (a, b) => a > b)
var bandCase = join(map(sorted, b => 'pct >= ${b}, ${b}'), ', ')
var query = replace(replace(loadTextContent('query.kql'), '__BAND_CASE__', bandCase), '__CRITICAL_BAND__', string(sorted[0]))

module pull '../shared/pull-module.bicep' = {
  name: '${prefix}-m5-quota'
  params: {
    name: '${prefix}-m5-quota'
    location: location
    tags: tags
    moduleName: 'm5-quota'
    query: query
    identityId: identityId
    routerName: routerName
    actionGroupId: actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    intervalMinutes: 15
    retentionHours: reminderHours
    enabled: enabled
  }
}

output workflowName string = pull.outputs.workflowName
