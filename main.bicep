// azure-alert entry point.
// Deploy with: az deployment sub create -l <region> -f main.bicep -p <params>
//   - core + pull modules go into one central resource group (resourceGroupName)
//   - push modules (alert rules) are deployed into every subscription in pushSubscriptionIds
targetScope = 'subscription'

@description('Region of the central resource group and Logic Apps.')
param location string

@description('Central resource group for core and pull modules.')
param resourceGroupName string = 'rg-azure-alert'

@description('Resource name prefix.')
param prefix string = 'aa'

param tags object = {
  solution: 'azure-alert'
}

@description('Which modules to deploy.')
param modules object = {
  serviceHealth: true
  flash: true
  resourceHealth: true
  metric: true
  quota: true
  scheduledEvents: true
  activityFailure: true
  aks: true
}

@secure()
@description('Feishu webhook per category. Keys: full category (e.g. Flash.HostFailure), category prefix (e.g. ServiceHealth) or default. Entries with an empty value are ignored, so a template with every category can be left partly blank.')
param webhooks object = {}

@secure()
@description('Default Feishu webhook (merged into webhooks as "default"; convenient for the portal wizard).')
param defaultWebhook string = ''

@description('Reader assignment for the alerting identity: subscription (each id in readerSubscriptionIds), resourceGroup (central RG only, which core always assigns; for testing) or none (assign at management group yourself, see scripts/grant-reader-mg.sh).')
@allowed([
  'subscription'
  'resourceGroup'
  'none'
])
param readerScope string = 'subscription'

param readerSubscriptionIds array = [
  subscription().subscriptionId
]

@description('ARG request scope for pull modules: {} = everything the identity can read, or { "managementGroups": [...] } / { "subscriptions": [...] }.')
param argScope object = {}

@description('Subscriptions the pull modules leave out (e.g. when Reader is granted on a management group).')
param excludedSubscriptionIds array = []

@description('First run of each pull module only records fingerprints without sending.')
param bootstrapSilent bool = true

@description('Deployment time (UTC). Pull modules treat HTTP 403 as "Reader role not effective yet" only within permissionGraceMinutes after this time; later a 403 fails the run (self-monitoring alert). Leave the default.')
param deploymentTime string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

param fastLookback string = '2h'
param slowLookback string = '24h'

@description('Start pull Logic Apps enabled.')
param pullEnabled bool = true

@description('Subscriptions that get the push alert rules (M3/M4/M7).')
param pushSubscriptionIds array = [
  subscription().subscriptionId
]

@description('Resource group (created in each push subscription) that holds the alert rules.')
param pushResourceGroupName string = resourceGroupName

@description('Limit push rules to the push resource group instead of the whole subscription (testing).')
param pushScopeToResourceGroup bool = false

@description('M4: regions for the multi-resource VM metric rules.')
param metricRegions array = [
  location
]

@description('Write standard events to a Log Analytics custom table (AzureAlertEvents_CL).')
param sinkEnabled bool = false

@description('Existing workspace in the central resource group for the sink; empty = create one.')
param sinkWorkspaceResourceId string = ''

@description('M4: VM CPU threshold in percent.')
param cpuThreshold int = 80
@description('M4: data disk bandwidth consumed threshold in percent.')
param dataDiskBandwidthThreshold int = 100

@description('Feishu rate limiting (code 11232 / HTTP 429): attempts per message before it is recorded as failed; the wait grows with each attempt (8 attempts take about 10 minutes).')
@minValue(1)
@maxValue(15)
param feishuMaxAttempts int = 8

var anyPush = (modules.?resourceHealth ?? false) || (modules.?metric ?? false) || (modules.?activityFailure ?? false)

var alertCategoryMap = union(
  {
    '${prefix}-m3-resource-health': 'ResourceHealth'
    '${prefix}-m7-activity-failure': 'ActivityFailure'
  },
  toObject(metricRegions, r => '${prefix}-m4-vm-cpu-${r}', r => 'Metric.VmCpu'),
  toObject(metricRegions, r => '${prefix}-m4-vm-datadisk-bw-${r}', r => 'Metric.DataDiskBandwidth')
)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module core 'modules/core/main.bicep' = {
  name: '${prefix}-core'
  scope: rg
  params: {
    prefix: prefix
    location: location
    tags: tags
    // Drop blank entries (the portal wizard pre-fills every module with ""), so those categories fall back to default.
    webhooks: union(toObject(filter(items(webhooks), w => !empty(w.value)), w => w.key, w => w.value), empty(defaultWebhook) ? {} : { default: defaultWebhook })
    alertCategoryMap: alertCategoryMap
    sinkEnabled: sinkEnabled
    sinkWorkspaceResourceId: sinkWorkspaceResourceId
    feishuMaxAttempts: feishuMaxAttempts
  }
}

// union(x, []) removes duplicate subscription ids (a duplicate would fail the deployment with "defined multiple times").
module readerSub 'modules/shared/reader-subscription.bicep' = [for sub in (readerScope == 'subscription' ? union(readerSubscriptionIds, []) : []): {
  name: '${prefix}-reader-${uniqueString(sub)}'
  scope: subscription(sub)
  params: {
    principalId: core.outputs.identityPrincipalId
  }
}]

module m1 'modules/m1-service-health/main.bicep' = if (modules.?serviceHealth ?? false) {
  name: '${prefix}-m1'
  scope: rg
  params: {
    prefix: prefix
    location: location
    tags: tags
    identityId: core.outputs.identityId
    routerName: core.outputs.routerName
    actionGroupId: core.outputs.actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    deployedAt: deploymentTime
    fastLookback: fastLookback
    slowLookback: slowLookback
    enabled: pullEnabled
  }
}

module m2 'modules/m2-flash/main.bicep' = if (modules.?flash ?? false) {
  name: '${prefix}-m2'
  scope: rg
  params: {
    prefix: prefix
    location: location
    tags: tags
    identityId: core.outputs.identityId
    routerName: core.outputs.routerName
    actionGroupId: core.outputs.actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    deployedAt: deploymentTime
    fastLookback: fastLookback
    slowLookback: slowLookback
    enabled: pullEnabled
  }
}

module m5 'modules/m5-quota/main.bicep' = if (modules.?quota ?? false) {
  name: '${prefix}-m5'
  scope: rg
  params: {
    prefix: prefix
    location: location
    tags: tags
    identityId: core.outputs.identityId
    routerName: core.outputs.routerName
    actionGroupId: core.outputs.actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    deployedAt: deploymentTime
    enabled: pullEnabled
  }
}

module m6 'modules/m6-scheduled-events/main.bicep' = if (modules.?scheduledEvents ?? false) {
  name: '${prefix}-m6'
  scope: rg
  params: {
    prefix: prefix
    location: location
    tags: tags
    identityId: core.outputs.identityId
    routerName: core.outputs.routerName
    actionGroupId: core.outputs.actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    deployedAt: deploymentTime
    enabled: pullEnabled
  }
}

module m8 'modules/m8-aks/main.bicep' = if (modules.?aks ?? false) {
  name: '${prefix}-m8'
  scope: rg
  params: {
    prefix: prefix
    location: location
    tags: tags
    identityId: core.outputs.identityId
    routerName: core.outputs.routerName
    actionGroupId: core.outputs.actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    deployedAt: deploymentTime
    enabled: pullEnabled
  }
}

module pushRg 'modules/shared/resource-group.bicep' = [for sub in (anyPush ? union(pushSubscriptionIds, []) : []): {
  name: '${prefix}-push-rg-${uniqueString(sub)}'
  scope: subscription(sub)
  params: {
    name: pushResourceGroupName
    location: location
    tags: tags
  }
}]

module push 'modules/push/main.bicep' = [for (sub, i) in (anyPush ? union(pushSubscriptionIds, []) : []): {
  name: '${prefix}-push-${uniqueString(sub)}'
  scope: resourceGroup(sub, pushResourceGroupName)
  dependsOn: [
    pushRg[i]
  ]
  params: {
    prefix: prefix
    tags: tags
    actionGroupId: core.outputs.actionGroupId
    scopeId: pushScopeToResourceGroup ? '/subscriptions/${sub}/resourceGroups/${pushResourceGroupName}' : ''
    enableResourceHealth: modules.?resourceHealth ?? false
    enableMetric: modules.?metric ?? false
    enableActivityFailure: modules.?activityFailure ?? false
    metricRegions: metricRegions
    cpuThreshold: cpuThreshold
    dataDiskBandwidthThreshold: dataDiskBandwidthThreshold
  }
}]

output resourceGroupName string = rg.name
output identityPrincipalId string = core.outputs.identityPrincipalId
output routerName string = core.outputs.routerName
output sinkWorkspaceId string = core.outputs.sinkWorkspaceId
output actionGroupId string = core.outputs.actionGroupId
