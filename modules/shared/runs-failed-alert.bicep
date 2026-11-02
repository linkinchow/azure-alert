// Self-monitoring: alert when a Logic App has failed runs (multi-resource metric alerts do not support Logic Apps).
// The rule name ends with -runs-failed, which the router maps to category SelfMonitor.
targetScope = 'resourceGroup'

param workflowId string
param workflowName string
param actionGroupId string
param tags object = {}

resource alert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${workflowName}-runs-failed'
  location: 'global'
  tags: tags
  properties: {
    description: 'azure-alert self-monitoring: ${workflowName} has failed runs.'
    severity: 2
    enabled: true
    scopes: [
      workflowId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'runsfailed'
          metricNamespace: 'Microsoft.Logic/workflows'
          metricName: 'RunsFailed'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroupId
      }
    ]
  }
}
