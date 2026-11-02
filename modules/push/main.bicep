// Push modules deployed into one subscription: alert rules that send to the shared Action Group (Router -> Normalizer -> Feishu).
//   M3 Resource Health (activity log alert, all resource types)
//   M4 Metric examples (multi-resource metric alerts per region: VM CPU, data disk bandwidth)
//   M7 Activity failures (activity log alert on failed write operations)
targetScope = 'resourceGroup'

param prefix string
param tags object = {}
param actionGroupId string

@description('Scope watched by the rules. Empty = the whole subscription; set to a resource group id to limit (used for testing).')
param scopeId string = ''

param enableResourceHealth bool = true
param enableMetric bool = true
param enableActivityFailure bool = true

@description('M3: activity log levels to alert on. Critical = platform-initiated unavailability.')
param resourceHealthLevels array = [
  'Critical'
]

@description('M3: event statuses to alert on. Updated (progress updates of an ongoing event) is left out.')
param resourceHealthEventStatuses array = [
  'Active'
  'In Progress'
  'Resolved'
]

@description('M4: regions to create the multi-resource VM metric rules in (one rule per region).')
param metricRegions array = []
@description('M4: VM Percentage CPU threshold (average over 5 minutes). The platform metric may never reach 100 on some sizes (measured 83.3% max on D2s_v5).')
param cpuThreshold int = 80
@description('M4: VM Data Disk Bandwidth Consumed Percentage threshold (average over 5 minutes, per LUN).')
param dataDiskBandwidthThreshold int = 100

@description('M7: activity log levels to alert on (Administrative category, all resource types and operations). Add Warning to also get policy audit and similar events.')
param activityFailureLevels array = [
  'Error'
  'Critical'
]

@description('M7: optional operation filter; empty = every operation.')
param activityFailureOperations array = []

var activityLevelItems = [for l in activityFailureLevels: {
  field: 'level'
  equals: l
}]
var activityOperationItems = [for op in activityFailureOperations: {
  field: 'operationName'
  equals: op
}]

var watchScope = empty(scopeId) ? subscription().id : scopeId
var actions = {
  actionGroups: [
    {
      actionGroupId: actionGroupId
    }
  ]
}

resource resourceHealth 'Microsoft.Insights/activityLogAlerts@2020-10-01' = if (enableResourceHealth) {
  name: '${prefix}-m3-resource-health'
  location: 'Global'
  tags: tags
  properties: {
    enabled: true
    description: 'azure-alert M3: Resource Health events of level Critical (not Updated) for all resource types.'
    scopes: [
      watchScope
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          anyOf: [for l in resourceHealthLevels: {
            field: 'level'
            equals: l
          }]
        }
        {
          anyOf: [for st in resourceHealthEventStatuses: {
            field: 'status'
            equals: st
          }]
        }
      ]
    }
    actions: actions
  }
}

resource activityFailure 'Microsoft.Insights/activityLogAlerts@2020-10-01' = if (enableActivityFailure) {
  name: '${prefix}-m7-activity-failure'
  location: 'Global'
  tags: tags
  properties: {
    enabled: true
    description: 'azure-alert M7: Administrative activity log events of level Error / Critical (all resource types and operations).'
    scopes: [
      watchScope
    ]
    condition: {
      allOf: concat([
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          anyOf: activityLevelItems
        }
      ], empty(activityFailureOperations) ? [] : [
        {
          anyOf: activityOperationItems
        }
      ])
    }
    actions: actions
  }
}

resource cpu 'Microsoft.Insights/metricAlerts@2018-03-01' = [for region in (enableMetric ? metricRegions : []): {
  name: '${prefix}-m4-vm-cpu-${region}'
  location: 'global'
  tags: tags
  properties: {
    description: 'azure-alert M4: VM Percentage CPU >= ${cpuThreshold}% (average over 5 minutes).'
    severity: 1
    enabled: true
    scopes: [
      watchScope
    ]
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: region
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'cpu'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Percentage CPU'
          operator: 'GreaterThanOrEqual'
          threshold: cpuThreshold
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
  }
}]

resource dataDisk 'Microsoft.Insights/metricAlerts@2018-03-01' = [for region in (enableMetric ? metricRegions : []): {
  name: '${prefix}-m4-vm-datadisk-bw-${region}'
  location: 'global'
  tags: tags
  properties: {
    description: 'azure-alert M4: VM Data Disk Bandwidth Consumed Percentage >= ${dataDiskBandwidthThreshold}% (average over 5 minutes, per LUN).'
    severity: 2
    enabled: true
    scopes: [
      watchScope
    ]
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: region
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'datadiskbw'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Data Disk Bandwidth Consumed Percentage'
          operator: 'GreaterThanOrEqual'
          threshold: dataDiskBandwidthThreshold
          timeAggregation: 'Average'
          dimensions: [
            {
              name: 'LUN'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
  }
}]
