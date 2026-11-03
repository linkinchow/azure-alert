// Generic ARG pull Logic App: recurrence -> state from the last successful run -> ARG query (paged) -> drop known fingerprints -> Router -> State_out.
targetScope = 'resourceGroup'

param name string
param location string = resourceGroup().location
param tags object = {}

@description('Module label written into the state output.')
param moduleName string

@description('Rendered ARG query. Must project eventId (string) and event (standard event object). __LOOKBACK__ is replaced at run time.')
param query string

param identityId string
param routerName string

@description('Action group for the self-monitoring alert; empty = no alert.')
param actionGroupId string = ''

param intervalMinutes int = 1
param fastLookback string = '2h'
param slowLookback string = '24h'
param slowEveryMinutes int = 60
param retentionHours int = 26

@description('Subscriptions to leave out (useful when the identity reads a whole management group).')
param excludedSubscriptionIds array = []

@description('ARG request scope merged into the request body, e.g. {} (all subscriptions the identity can read), { "managementGroups": ["mg-id"] } or { "subscriptions": ["..."] }.')
param argScope object = {}

@description('Deployment time (UTC); see permissionGraceMinutes.')
param deployedAt string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

@description('With bootstrapSilent, every run in the first N minutes after the first successful run only records fingerprints (24h look-back) and sends nothing. Covers Resource Graph returning empty results while the Reader role is still propagating.')
param bootstrapMinutes int = 30

@description('Minutes after deployment during which HTTP 403 (Reader role not effective yet) cancels the run instead of failing it.')
param permissionGraceMinutes int = 60

@description('When true, the first run only records fingerprints without sending, to avoid flooding the groups with history on first deployment.')
param bootstrapSilent bool = true

param enabled bool = true

// insert the exclusion right after the table name (first line) of the query
var firstLineEnd = indexOf(query, '\n')
var exclusion = '| where subscriptionId !in~ (${join(map(excludedSubscriptionIds, s => '\'${s}\''), ', ')})\n'
var finalQuery = empty(excludedSubscriptionIds) ? query : '${substring(query, 0, firstLineEnd + 1)}${exclusion}${substring(query, firstLineEnd + 1)}'

resource router 'Microsoft.Logic/workflows@2019-05-01' existing = {
  name: routerName
}

// ARM endpoint of the current cloud (no trailing slash) and the token audience (with it).
var armAudience = environment().resourceManager
var armEndpoint = replace(replace('${armAudience}#', '/#', ''), '#', '')

var baseDefinition = loadJsonContent('pull-workflow.json')
var definition = union(baseDefinition, {
  triggers: {
    Recurrence: {
      type: 'Recurrence'
      recurrence: {
        frequency: 'Minute'
        interval: intervalMinutes
      }
      runtimeConfiguration: {
        concurrency: {
          runs: 1
          maximumWaitingRuns: 1
        }
      }
    }
  }
})

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    state: enabled ? 'Enabled' : 'Disabled'
    definition: definition
    parameters: {
      moduleName: {
        value: moduleName
      }
      query: {
        value: finalQuery
      }
      fastLookback: {
        value: fastLookback
      }
      slowLookback: {
        value: slowLookback
      }
      slowEveryMinutes: {
        value: slowEveryMinutes
      }
      intervalMinutes: {
        value: intervalMinutes
      }
      retentionHours: {
        value: retentionHours
      }
      argScope: {
        value: argScope
      }
      routerUrl: {
        value: listCallbackUrl('${router.id}/triggers/manual', '2019-05-01').value
      }
      miId: {
        value: identityId
      }
      bootstrapSilent: {
        value: bootstrapSilent
      }
      armEndpoint: {
        value: armEndpoint
      }
      armAudience: {
        value: armAudience
      }
      deployedAt: {
        value: deployedAt
      }
      permissionGraceMinutes: {
        value: permissionGraceMinutes
      }
      bootstrapMinutes: {
        value: bootstrapMinutes
      }
    }
  }
}

module monitor 'runs-failed-alert.bicep' = if (!empty(actionGroupId)) {
  name: '${name}-monitor'
  params: {
    workflowId: workflow.id
    workflowName: workflow.name
    actionGroupId: actionGroupId
    tags: tags
  }
}

output workflowName string = workflow.name
