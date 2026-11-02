// Core: managed identity, Router Logic App (Normalizer + Feishu card rendering) and the shared Action Group.
targetScope = 'resourceGroup'

@description('Resource name prefix.')
param prefix string

param location string = resourceGroup().location

param tags object = {}

@secure()
@description('Feishu webhook per category, e.g. { "default": "https://open.feishu.cn/...", "Flash.HostFailure": "...", "ServiceHealth": "..." }. Lookup order: full category, category prefix before the dot, default.')
param webhooks object

@description('Alert rule name -> category, plus "svc:<monitoringService>" fallbacks, used by the Normalizer for Action Group payloads.')
param alertCategoryMap object = {}

@description('Write every standard event to the Log Analytics custom table AzureAlertEvents_CL.')
param sinkEnabled bool = false

@description('Existing Log Analytics workspace (must be in this resource group); empty = create one when the sink is enabled.')
param sinkWorkspaceResourceId string = ''

@description('M3: Resource Health event titles that are not sent .')
param resourceHealthExcludedTitles array = [
  'Low priority machine preempted'
  'Degraded'
  'Unhealthy'
]

@description('Category -> display name shown in the card header; merged over the built-in Chinese names.')
param categoryNames object = {}

var defaultCategoryNames = {
  'Flash.HostFailure': '主机故障'
  'Flash.DegradedHardware': '硬件降级'
  'Flash.LiveMigration': '热迁移'
  'Flash.PlannedFreeze': '计划内冻结'
  'Flash.PlannedMaintenance': '计划内维护（VM）'
  'Flash.VMCrash': '虚拟机崩溃'
  'Flash.StorageOffline': '存储断连'
  'Flash.ProvisioningTimeout': '预配超时'
  'Flash.SpotEviction': '抢占（Spot 驱逐）'
  'ServiceHealth.ServiceIssue': '服务问题'
  'ServiceHealth.PlannedMaintenance': '计划内维护（服务）'
  'ServiceHealth.HealthAdvisory': '健康公告'
  'ServiceHealth.SecurityAdvisory': '安全公告'
  'ServiceHealth.Billing': '账单通知'
  ResourceHealth: '资源健康'
  'Metric.VmCpu': 'CPU 使用率'
  'Metric.DataDiskBandwidth': '数据盘带宽'
  'Metric.Other': '指标告警'
  'Quota.Compute': '计算配额'
  'ActivityFailure.Capacity': '操作失败·容量不足'
  'ActivityFailure.Quota': '操作失败·配额不足'
  'ActivityFailure.Policy': '操作失败·策略拒绝（Azure Policy）'
  'ActivityFailure.Other': '操作失败'
  'ScheduledEvent.Reboot': '计划事件·重启'
  'ScheduledEvent.Redeploy': '计划事件·重新部署'
  'ScheduledEvent.Freeze': '计划事件·冻结'
  'ScheduledEvent.Preempt': '计划事件·抢占（Spot 驱逐）'
  'ScheduledEvent.Terminate': '计划事件·终止'
  'AKS.Upgrade': 'AKS 升级'
  'AKS.VersionEOL': 'AKS 版本到期'
  SelfMonitor: '告警系统自检'
  LogAlert: '日志告警'
  'Alert.Other': '其他告警'
}

var defaultAlertCategoryMap = {
  'svc:Platform': 'Metric.Other'
  'svc:Resource Health': 'ResourceHealth'
  'svc:Activity Log - Administrative': 'ActivityFailure'
  // Service Health alerts pushed to the Action Group are dropped by the Router: M1 (ARG) is the only Service Health source.
  'svc:ServiceHealth': 'ServiceHealth.Push'
  'svc:Log Alerts V2': 'LogAlert'
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-mi'
  location: location
  tags: tags
}

// Reader on this resource group: pull workflows read their own run history (dedup state).
resource rgReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identity.id, 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  }
}

module sink 'sink.bicep' = if (sinkEnabled) {
  name: '${prefix}-sink'
  params: {
    prefix: prefix
    location: location
    tags: tags
    identityPrincipalId: identity.properties.principalId
    workspaceResourceId: sinkWorkspaceResourceId
  }
}

resource router 'Microsoft.Logic/workflows@2019-05-01' = {
  name: '${prefix}-router'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: loadJsonContent('router-workflow.json')
    parameters: {
      webhooks: {
        value: webhooks
      }
      resourceHealthExcludedTitles: {
        value: resourceHealthExcludedTitles
      }
      categoryNames: {
        value: union(defaultCategoryNames, categoryNames)
      }
      alertCategoryMap: {
        value: union(defaultAlertCategoryMap, alertCategoryMap)
      }
      miId: {
        value: identity.id
      }
      sinkEnabled: {
        value: sinkEnabled
      }
      sinkUrl: {
        value: sinkEnabled ? sink!.outputs.ingestionUrl : ''
      }
    }
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${prefix}-ag'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: take(replace('${prefix}ag', '-', ''), 12)
    enabled: true
    logicAppReceivers: [
      {
        name: 'router'
        resourceId: router.id
        callbackUrl: listCallbackUrl('${router.id}/triggers/manual', '2019-05-01').value
        useCommonAlertSchema: true
      }
    ]
  }
}

// Self-monitoring for the router (pull workflows get their own alert in pull-module.bicep).
module routerMonitor '../shared/runs-failed-alert.bicep' = {
  name: '${prefix}-router-monitor'
  params: {
    workflowId: router.id
    workflowName: router.name
    actionGroupId: actionGroup.id
    tags: tags
  }
}

output identityId string = identity.id
output identityPrincipalId string = identity.properties.principalId
output routerName string = router.name
output actionGroupId string = actionGroup.id
output sinkWorkspaceId string = sinkEnabled ? sink!.outputs.workspaceId : ''
