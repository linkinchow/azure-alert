# Azure 告警方案 v1：告警目录（Alert Catalog）

> 读者：部署和配置本方案的客户 SRE。
> 目的：说清楚**会收到哪些告警**：每个模块监控什么、数据从哪来、多久查一次、分成哪些子类（`category`）、每类包含哪些具体事件、默认严重度、哪些事件被过滤掉，以及列出这些事件取值的**微软官方文档**。
> 依据：本文只描述仓库代码**当前的实际行为**（`modules/**`，2026-11-01）。文中所有 learn.microsoft.com 链接都在 2026-11-01 打开核对过；没能核实的内容标为 **未验证**。

---

## 0. 总览

| 模块 | 监控内容 | category（飞书卡片上的中文名） | 数据源 | 频率 / 时效 | 默认 |
|---|---|---|---|---|---|
| M1 Service Health | Azure 平台级事件：服务问题、计划维护、健康公告（含退役）、安全公告、账单 | `ServiceHealth.ServiceIssue` / `.PlannedMaintenance` / `.HealthAdvisory` / `.SecurityAdvisory` / `.Billing` | ARG `servicehealthresources`（`microsoft.resourcehealth/events`） | Pull，每 1 分钟查一次，回看 2h；每小时整点附近回看 24h | 开 |
| M2 Project Flash | 单台 VM / VMSS 实例的平台事件（主机故障、硬件降级、热迁移、冻结、维护重启、崩溃、存储断连等） | `Flash.*`（9 类，其中 1 类默认关闭） | ARG `healthresourcechanges`（`microsoft.resourcehealth/resourceannotations` 的变更记录） | Pull，VM 和 VMSS 各一个 Logic App，每 1 分钟，回看同 M1 | 开 |
| M3 Resource Health | **所有资源类型**的健康状态变为 不可用 / 降级（仅平台触发） | `ResourceHealth` | 活动日志 ResourceHealth 类别 → 订阅级 activity log alert | Push，近实时 | 开 |
| M4 指标 | VM CPU 使用率、数据盘带宽使用率 | `Metric.VmCpu`、`Metric.DataDiskBandwidth` | Azure Monitor 平台指标 → 多资源 metric alert（每个区域一条规则） | Push，每 1 分钟评估，5 分钟平均 | 开（只覆盖 `metricRegions`，默认只有部署区域） |
| M5 配额 | 计算配额使用率 ≥ 80 / 90 / 95% | `Quota.Compute` | ARG `quotaresources`（`microsoft.compute/locations/usages`） | Pull，每 15 分钟 | 开 |
| M6 Scheduled Events | VM / VMSS 维护的**事前**通知（重启、重新部署、冻结、Spot 驱逐、实例终止） | `ScheduledEvent.Reboot` / `.Redeploy` / `.Freeze` / `.Preempt` / `.Terminate` | ARG `maintenanceresources`（`microsoft.maintenance/scheduledevents`） | Pull，每 1 分钟 | 默认开（需先满足先决条件，否则不会有事件） |
| M7 操作失败 | **所有资源、所有操作**的失败（活动日志 level 为 Error / Critical） | `ActivityFailure.Capacity` / `.Quota` / `.Policy` / `.Other` | 活动日志 Administrative、level ∈ Error / Critical → activity log alert | Push（实测失败后约 6 分钟到达） | 开 |
| M8 AKS | AKS 自动升级预告 / 失败 / 跳过；Kubernetes 版本到期 | `AKS.Upgrade`、`AKS.VersionEOL` | ARG `containerserviceeventresources`（`microsoft.containerservice/managedclusters/scheduledevents`） | Pull，每 5 分钟 | 开 |
| 自监控 | 告警系统自身的 Logic App 运行失败 | `SelfMonitor` | Logic App 指标 `RunsFailed` → metric alert | Push，每 5 分钟评估，15 分钟窗口 | 开（随 Core 和每个 Pull 模块一起部署） |
| 兜底 | 客户自己把其他告警规则接到本方案的 Action Group 上 | `Metric.Other`、`LogAlert`、`Alert.Other`（客户自建的 Service Health 告警接进来会被丢弃，服务健康只以 M1 为准） | Common Alert Schema | Push | 只有客户自己接入时才会出现 |

默认开关来自根目录 `main.bicep` 的 `modules` 参数（`serviceHealth / flash / resourceHealth / metric / quota / activityFailure / aks` 默认全部为 `true`）。

---

## 1. 通用机制（所有模块都适用）

| 项目 | 行为 |
|---|---|
| 卡片标题 | `<严重 / 警告 / 提示 / 已恢复>｜<category 中文名>｜<事件标题>`。颜色：严重=红，警告=橙，提示=蓝，已恢复=绿 |
| 严重度 | 统一为 `Critical`（严重）/ `Warning`（警告）/ `Informational`（提示），各模块的映射见下文 |
| 推送到哪个群 | `webhooks` 参数按以下顺序查找：① 完整 category（如 `Flash.HostFailure`）→ ② 点号前的前缀（如 `Flash`）→ ③ `default`。三者都没有配置时，Router 的这次运行标记为失败，并触发 `SelfMonitor` |
| Pull 模块去重 | 每个事件有一个指纹（`eventId`），一段时间内只推送一次。保留期：M1 / M2 为 26 小时，M5 为 24 小时，M8 为 200 小时 |
| 首次部署静默 | `bootstrapSilent=true`（默认）：每个 Pull 模块第一次运行只记录指纹、不推送，避免把历史事件一次性刷进群里。**注意：M5 在部署前就已超过阈值的配额，要等约 24 小时、指纹过期后才会第一次提醒** |
| Push 模块 | 不去重。活动日志里每产生一条符合条件的事件，就推送一张卡片；指标告警恢复时推送"已恢复"卡片 |
| 查询范围 | Pull：`argScope`（默认是托管标识能读取的所有订阅）。Push：`pushSubscriptionIds` 中每个订阅的整个订阅范围 |

---

## 2. M1 Service Health

- **监控内容**：Azure 发布的、影响到你订阅的平台级事件。
- **数据源**：ARG `servicehealthresources | where type =~ 'microsoft.resourcehealth/events'`，按 `LastUpdateTime` 在回看窗口内筛选。
- **频率**：每 1 分钟一次。回看 2 小时；每小时有一次回看 24 小时（防止漏掉事件）。
- **聚合方式**：同一个 TrackingId、同一版内容，**只发一张卡片**，并在卡片里列出所有受影响的订阅、服务和区域。
- **内容更新会再发一张**：指纹由 状态 + EventTags + 缓解时间 + Description + Summary 组成，其中任何一项变化都会产生新卡片。

### 2.1 子类

| category | 中文名 | 包含的事件（`EventType`） | 典型内容 |
|---|---|---|---|
| `ServiceHealth.ServiceIssue` | 服务问题 | `ServiceIssue` | 正在影响你的服务中断或降级（Incident） |
| `ServiceHealth.PlannedMaintenance` | 计划内维护（服务） | `PlannedMaintenance` | 平台计划维护窗口 |
| `ServiceHealth.HealthAdvisory` | 健康公告 | `HealthAdvisory` | 需要关注或采取行动的公告。**服务退役（`EventSubType=Retirement`）也属于这一类**，卡片"子类型"显示"退役通知" |
| `ServiceHealth.SecurityAdvisory` | 安全公告 | `SecurityAdvisory` | 安全相关通知 |
| `ServiceHealth.Billing` | 账单通知 | `Billing` | 账单 / 价格变更（如 `EventSubType=PriceChanges`，卡片显示"价格变更"） |

### 2.2 严重度与状态

| 条件 | 严重度 |
|---|---|
| `EventLevel = Critical` | 严重 |
| `EventLevel = Warning`，或事件类型为 `SecurityAdvisory` | 警告 |
| `Error` | 严重（2026-11-01 修正：原来映射为"提示"） |
| 其他（`Informational`） | 提示 |

| 卡片"状态"字段 | 判断条件（按顺序） | 卡片颜色 |
|---|---|---|
| 已恢复 | `Status = Resolved` | 绿色"已恢复" |
| 事后复盘（PIR） | `EventTags` 包含 `PIR`（官方标签：`Preliminary PIR`、`Final PIR`） | 按严重度 |
| 已过截止日期 | 健康公告 / 安全公告 / 账单通知，且缓解时间（对这类事件是截止日期）已过 | 按严重度 |
| 已缓解 | 服务问题 / 计划内维护，且缓解时间已过 | 按严重度 |
| 生效中 | 其他情况下的健康公告 / 安全公告 / 账单通知 | 按严重度 |
| 进行中 | 其他情况下的服务问题 / 计划内维护 | 按严重度 |

### 2.3 过滤掉的事件
- `EventType` 为 `RCA`、`EmergingIssues` 的事件不推送（不在默认的 `eventTypes` 参数中）。另外，新兴问题（Emerging issues）不绑定订阅，本来也查不到。

### 2.4 官方文档
- 事件类型说明（Incident / Maintenance / Information / Action required / Security / Billing）：<https://learn.microsoft.com/en-us/azure/service-health/service-health-notifications-properties>
- **取值枚举**（`EventTypeValues`、`EventSubTypeValues`、`EventLevelValues`、`EventStatusValues`、`eventTags` 含义）：<https://learn.microsoft.com/en-us/rest/api/resourcehealth/events/list-by-subscription-id>
- ARG 查询示例（说明退役事件属于 HealthAdvisory、`EventSubType == "Retirement"`）：<https://learn.microsoft.com/en-us/azure/service-health/resource-graph-samples>
- Service Health 概述：<https://learn.microsoft.com/en-us/azure/service-health/overview>

---

## 3. M2 Project Flash（VM 平台事件）

- **监控内容**：平台在单台 VM 或 VMSS 实例上发布的可用性注释（annotation），覆盖平台触发和 VM 自身触发的事件。
- **数据源**：ARG `healthresourcechanges`，筛选 `targetResourceType = microsoft.resourcehealth/resourceannotations`。VM 和 VMSS 实例分别由两个 Logic App 查询。
- **频率**：同 M1（每 1 分钟，回看 2 小时 / 24 小时）。
- **分类规则**（`modules/m2-flash/rules.json`）：
  - 先去掉 annotation 名称末尾的 `LiveMigrationEligible` / `LiveMigrationNotEligible`（卡片"热迁移"字段会显示"支持 / 不支持"），再与规则表**精确匹配**（不区分大小写）。
  - 如果变更记录**没有带 annotation 名称**，就用摘要里的关键词兜底分类。
  - **名称不在规则表里的事件一律丢弃。**
- **去重**：每条变更记录（资源 + 时间戳）推送一次。

### 3.1 子类

| category | 中文名 | annotation 名称（精确匹配） | 严重度 | 关键词兜底（仅在名称为空时使用） |
|---|---|---|---|---|
| `Flash.HostFailure` | 主机故障 | `VirtualMachineHostCrashed`、`VirtualMachineHostRebootedForRepair`、`VirtualMachineMigrationInitiatedForRepair`、`NetworkUnhealthy`、`UnhealthyHostState` | 严重 | `underlying`、`unexpected failure` |
| `Flash.DegradedHardware` | 硬件降级 | `VirtualMachinePossiblyDegradedDueToHardwareFailure`、`VirtualMachinePossiblyDegradedDueToHardwareFailureWithRedeployDeadline`、`PossiblyDegradedDueToHardwareFailureWithRedeployDeadline`、`VirtualMachineMigrationScheduledForDegradedHardware`、`VirtualMachineScheduledForServiceHealing`、`VirtualMachineScheduledForMigrationWithGracePeriod`、`AccelnetUnhealthy` | 警告 | `disruptions`、`Accelerated` |
| `Flash.DegradedHardware` | 硬件降级 | `AccelnetHealthy`、`VirtualMachineMigratedDueToHardwareFailure` | 提示 | — |
| `Flash.LiveMigration` | 热迁移 | `LiveMigrationFailure` | 警告 | — |
| `Flash.LiveMigration` | 热迁移 | `LiveMigrationSucceeded` | 提示 | `Live Migration operation` |
| `Flash.PlannedFreeze` | 计划内冻结 | `VirtualMachinePlannedFreezeFailed` | 警告 | — |
| `Flash.PlannedFreeze` | 计划内冻结 | `VirtualMachinePlannedFreezeStarted`、`VirtualMachinePlannedFreezeSucceeded` | 提示 | `applied` |
| `Flash.PlannedMaintenance` | 计划内维护（VM） | `VirtualMachineMigrationInitiatedForPlannedMaintenance`、`VirtualMachineRebootInitiatedForPlannedMaintenance` | 警告 | `orchestrated` |
| `Flash.VMCrash` | 虚拟机崩溃 | `VirtualMachineCrashed`（发起方为 VM 自身） | 警告 | `guest OS crash` |
| `Flash.StorageOffline` | 存储断连 | `VirtualMachineStorageOffline` | 严重 | `loss` |
| `Flash.ProvisioningTimeout` | 预配超时 | `VirtualMachineProvisioningTimedOut` | 警告 | `reimaging` |
| `Flash.SpotEviction` | 抢占（Spot 驱逐） | `VirtualMachinePreempted` | 提示 | — |

大量使用 Spot 的环境，抢占事件可能很多（每天可能有上千条）。不需要时在 `rules.json` 里把这条规则的 `enabled` 设为 false。

### 3.2 过滤掉的事件（有意不推送）
- **所有用户触发（Customer Initiated）的注释**，例如 `VirtualMachineRestarted`、`VirtualMachineAllocated`、`VirtualMachineDeallocationInitiated`、`VirtualMachineStart/StopInitiatedByControlPlane`、`VirtualMachineRebootInitiatedByControlPlane`、`VirtualMachineRedeployInitiatedByControlPlane(DueToPlannedMaintenance)`、`VirtualMachineSizeChanged`、`VirtualMachineConfigurationUpdated`、`VirtualMachineStoppedInternally`、`VirtualMachineStopInitiatedByControlPlaneTrackingId`、`VirtualMachineFailedToSecureBoot`、`VirtualMachineFailedSecureKeyRelease`。这些是用户自己的操作，不推送。
- 名称为空、摘要也不含任何兜底关键词的变更记录。

### 3.3 已知文档差异与限制
- 官方表格**第一行** `PossiblyDegradedDueToHardwareFailureWithRedeployDeadline` 缺少 `VirtualMachine` 前缀；实际数据中使用的是 `VirtualMachinePossiblyDegradedDueToHardwareFailureWithRedeployDeadline`。规则表两种写法都收录了。
- `AccelnetHealthy`、`UnhealthyHostState` 在实际数据中出现过，但**不在官方表格里**；规则表已收录。
- 实测数据中出现过 `VirtualMachineScheduledForServiceHealingLiveMigrationEligible//{NotBeforeTime}@@` 这种带后缀的名称。2026-11-01 已修正：先按 `//` 截断再匹配。修正后 VMSS 查询在 14 天内多找回 1 条事件。
- 同一个 VM 平台事件可能**同时**触发 M2（`Flash.*`）和 M3（`ResourceHealth`），收到两张卡片。

### 3.4 官方文档
- **annotation 全表**（名称、Context、Category、ImpactType）：<https://learn.microsoft.com/en-us/azure/service-health/resource-health-vm-annotation>
- Flash 与 ARG（HealthResources、14 天变更记录）：<https://learn.microsoft.com/en-us/azure/virtual-machines/flash-azure-resource-graph>
- Flash 概述：<https://learn.microsoft.com/en-us/azure/virtual-machines/flash-overview>

---

## 4. M3 Resource Health（所有资源类型）

- **监控内容**：订阅中**任何资源类型**的 Resource Health 事件。
- **数据源**：活动日志，通过订阅级 activity log alert（`<prefix>-m3-resource-health`）推送。条件：
  - `category = ResourceHealth`
  - `properties.currentHealthStatus ∈ {Unavailable, Degraded}`（参数 `resourceHealthStatuses`）
  - `properties.cause = PlatformInitiated`（参数 `resourceHealthCauses`）
- **频率**：Push，活动日志写入后触发。

### 4.1 子类与严重度

| category | 中文名 | 条件 | 严重度 |
|---|---|---|---|
| `ResourceHealth` | 资源健康 | `currentHealthStatus = Unavailable` | 严重 |
| `ResourceHealth` | 资源健康 | `currentHealthStatus = Degraded` | 警告 |

- 卡片标题：`<资源名>：<properties.title>`。正文：`properties.details`（为空时使用 title）。字段：健康状态（如"可用 → 不可用"）、发起方。
- 不发"已恢复"卡片：恢复到 `Available` 的事件被条件过滤掉；而且活动日志告警本身没有"已解决"状态。
- 每条活动日志事件推送一张卡片。按官方说明，以下情况都会写活动日志：资源状态变为或恢复自不健康、不健康持续超过 15 分钟、提交了注释。因此**同一次故障可能收到多张卡片**。

### 4.2 过滤掉的事件
- 用户触发（`UserInitiated`）的事件，例如停止或解除分配 VM。
- `Available`、`Unknown` 状态（另外，官方说明转为 `Unknown` 的状态本来就不写活动日志）。

### 4.3 如何知道某种资源会产生哪些 Resource Health 事件
1. 在 **Resource types and health checks** 页面找到你的资源类型（如 `Microsoft.Network/expressRouteCircuits`、`Microsoft.ContainerService/managedClusters`、`Microsoft.Storage/storageAccounts`）。页面列出了平台对该类型执行的健康检查（Executed Checks），事件标题就来自这些检查。该页面**只列检查项，不列出完整的事件标题清单**。
2. 虚拟机例外：VM 的具体事件可以在 M2 的 annotation 全表中逐条查到。
3. 健康状态的含义（Available / Unavailable / Degraded / Unknown）和平台事件 / 非平台事件的区别，见 Resource Health 概述。
4. 活动日志字段：`level`、`status`（Active / Resolved / InProgress / Updated）、`properties.title`、`properties.details`、`properties.currentHealthStatus`、`properties.previousHealthStatus`、`properties.type`、`properties.cause`（`PlatformInitiated` / `UserInitiated`）。

### 4.4 实际环境中观察到的事件标题（示例）

| 事件标题 | 资源类型 |
|---|---|
| Redeploying due to host failure | 虚拟机（推断） |
| Remote disk disconnected | 虚拟机（推断） |
| Degraded Hardware recovery | 虚拟机（推断） |
| Migration scheduled due to degraded hardware | 虚拟机（推断） |
| Host server crashed/reboot | 虚拟机（推断） |
| Maintenance rebooting for host update | 虚拟机（推断） |
| Live Migration | 虚拟机（推断） |
| Provisioning failure | 虚拟机（推断） |
| Degraded performance detected | — |
| At least 1 BGP session is down | ExpressRoute |
| Etcd is Running out of Storage Space | AKS |
| Unavailable | Load Balancer / SQL / Storage |
| A failover operation was triggered automatically | MySQL 灵活服务器 |
| More than 1 hour latency | Log Analytics 工作区 |

### 4.5 官方文档
- **各资源类型的健康检查**：<https://learn.microsoft.com/en-us/azure/service-health/resource-health-checks-resource-types>
- 健康状态与平台 / 非平台事件、哪些转换会写入活动日志：<https://learn.microsoft.com/en-us/azure/service-health/resource-health-overview>
- **活动日志 ResourceHealth 类别 schema**：<https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/activity-log-schema#resource-health-category>
- Resource Health 告警的条件（事件状态、资源状态、原因类型）：<https://learn.microsoft.com/en-us/azure/service-health/resource-health-alert-monitor-guide>

---

## 5. M4 指标告警（VM）

- **数据源**：Azure Monitor 平台指标。在 `metricRegions` 中的**每个区域**各建一条多资源 metric alert，范围为整个订阅，目标类型 `Microsoft.Compute/virtualMachines`。
- **频率**：每 1 分钟评估一次，窗口 5 分钟，取平均值。开启了 `autoMitigate`，指标回落后推送绿色"已恢复"卡片。

| category | 中文名 | 指标 | 默认条件 | 告警级别 → 严重度 |
|---|---|---|---|---|
| `Metric.VmCpu` | CPU 使用率 | `Percentage CPU` | 5 分钟平均 ≥ `cpuThreshold`（默认 **100**） | Sev1 → 严重 |
| `Metric.DataDiskBandwidth` | 数据盘带宽 | `Data Disk Bandwidth Consumed Percentage`（按 `LUN` 维度拆分） | 5 分钟平均 ≥ `dataDiskBandwidthThreshold`（默认 **100**） | Sev2 → 警告 |
| `Metric.Other` | 指标告警 | 客户自己接入本方案 Action Group 的其他平台指标告警 | — | Sev0/1 → 严重，Sev2 → 警告，Sev3/4 → 提示 |

**范围限制**：
- 没有列在 `metricRegions` 中的区域不会监控（默认只有部署区域）。
- 规则只针对 VM 资源类型，VMSS 不在范围内。
- 按官方说明，数据盘带宽指标只在支持高级存储的 VM 系列上提供。

**官方文档**：VM 支持的指标（名称、单位、维度、时间粒度）：<https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/microsoft-compute-virtualmachines-metrics>

---

## 6. M5 计算配额

- **数据源**：ARG `quotaresources | where type =~ 'microsoft.compute/locations/usages'`，展开 `properties.value`，只看 `limit > 0` 的项。
- **频率**：每 15 分钟一次（读取当前快照，不使用回看窗口）。
- **覆盖范围**：Compute 用量里的**每一项**。实际数据中见过：`Total Regional vCPUs`（`cores`）、`Total Regional Low-priority vCPUs`、各 VM 系列 vCPU（如 `Standard Dsv6 Family vCPUs`）、`Virtual Machine Scale Sets`、`Gallery`、`PremiumV2TotalDiskSizeInGB` 等。代码不排除磁盘或 Gallery 类项目。

| category | 中文名 | 档位（`bands`） | 严重度 |
|---|---|---|---|
| `Quota.Compute` | 计算配额 | 使用率 ≥ 80% | 警告 |
| `Quota.Compute` | 计算配额 | 使用率 ≥ 90% | 警告 |
| `Quota.Compute` | 计算配额 | 使用率 ≥ 95%（最高档） | 严重 |

**提醒规则**：
- 指纹 = 订阅 + 区域 + 配额名 + 档位。每次只报告达到的最高档位。
- 升到更高档位时立即提醒；一直停在同一档位时，约每 24 小时（`reminderHours`）提醒一次。
- 回落到较低档位时，如果该档位 24 小时内没有提醒过，会按较低档位再提醒一次。
- 降到 80% 以下时**不发恢复卡片**。

**官方文档**：
- vCPU 配额的两层结构（区域总 vCPU、VM 系列 vCPU）、`az vm list-usage`：<https://learn.microsoft.com/en-us/azure/virtual-machines/quotas>
- 配额告警与 ARG `QuotaResources` 表（注意：官方说明 NRT 用量数据目前只支持 Compute）：<https://learn.microsoft.com/en-us/azure/quotas/how-to-guide-monitoring-alerting>

---

## 7. M6 Scheduled Events

- **价值**：在维护**发生之前**收到通知（`EventStatus=Scheduled`，带最早开始时间 `NotBefore`）。Flash annotation 大多是事后通知。
- **数据源**：ARG `maintenanceresources | where type == "microsoft.maintenance/scheduledevents"`，每 1 分钟读取一次。
  - 这些记录没有时间字段，而且会在 ARG 里保留较长时间，所以每次读全表，按"事件 ID + 状态"去重，指纹保留 30 天。
- **小类**：

  | category | 中文名 | 含义 | 默认级别 |
  |---|---|---|---|
  | `ScheduledEvent.Reboot` | 计划事件·重启 | 平台维护重启，或用户发起的重启 | 平台发起且为"已计划 / 已开始"时：警告；其余：提示 |
  | `ScheduledEvent.Redeploy` | 计划事件·重新部署 | 迁移到其它主机，本地临时盘数据会丢失 | 同上 |
  | `ScheduledEvent.Freeze` | 计划事件·冻结 | 内存保留的短暂暂停（通常几秒） | 提示 |
  | `ScheduledEvent.Preempt` | 计划事件·抢占（Spot 驱逐） | Spot VM 被回收 | 平台发起且为"已计划 / 已开始"时：警告 |
  | `ScheduledEvent.Terminate` | 计划事件·终止 | VMSS 实例被删除（需要在 VMSS 上开启 Terminate Notification） | 同上 |

- **每个事件的每个状态各推送一次**：已计划 → 已开始 → 已完成（绿色"已恢复"），或者已取消。
- **事件取值**（官方）：
  - `EventType`：Freeze / Reboot / Redeploy / Preempt / Terminate
  - `EventStatus`：Scheduled / Started / Completed / Canceled
  - `EventSource`：Platform / User
- **先决条件**（不满足就不会有任何事件，具体命令见 `modules/m6-scheduled-events/README.md`）：
  1. 每个订阅注册 feature flag：`Microsoft.Compute/SendScheduledEventsPolicy`、`Microsoft.Maintenance/ScheduledEventsActivity`。
  2. 每台 VM / 每个 VMSS 设置 `scheduledEventsPolicy.scheduledEventsAdditionalPublishingTargets.eventGridAndResourceGraph.enable = true`，需要 Compute REST API **2025-04-01 或更新版本**。
  3. 可选：`scheduledEventsPolicy.userInitiatedReboot.automaticallyApprove` / `userInitiatedRedeploy.automaticallyApprove`。
     - 为 `true`：用户发起的操作直接执行，只能看到"已开始 / 已完成"。
     - 不设或为 `false`：会先出现"已计划"，等待批准或超时后才执行。
- **实测**（2026-11-01）：在一台已开启发布、关闭自动批准的 VM 上执行 `az vm restart`。约 2 分钟后收到"重启 已计划"，之后依次收到"已开始"和"已完成"。
- 官方标注 ARG 和 Event Grid 两种投递方式**目前都是预览版**。
- **官方文档**：
  - <https://learn.microsoft.com/en-us/azure/virtual-machines/scheduled-events-resource-graph>
  - <https://learn.microsoft.com/en-us/azure/virtual-machines/scheduled-events-event-grid>
  - <https://learn.microsoft.com/en-us/azure/virtual-machines/linux/scheduled-events>

## 8. M7 资源操作失败

- **数据源**：活动日志 Administrative 类别，通过 activity log alert（`<prefix>-m7-activity-failure`）推送。条件：`category = Administrative`，`level` 为 Error 或 Critical（参数 `activityFailureLevels`），**所有资源类型、所有操作**。可选参数 `activityFailureOperations` 限定操作列表，默认为空（全部）。
- **分类方式**：Router 在 `statusMessage` **全文中做子串匹配**，按以下顺序判断：

| category | 中文名 | 判定条件（按顺序） | 严重度 |
|---|---|---|---|
| `ActivityFailure.Capacity` | 操作失败·容量不足 | 包含 `AllocationFailed`（同时也会匹配到 `ZonalAllocationFailed`）、`OverconstrainedAllocationRequest`、`OverconstrainedZonalAllocationRequest`、`SkuNotAvailable` | 警告 |
| `ActivityFailure.Quota` | 操作失败·配额不足 | 包含 `QuotaExceeded`（同时也会匹配到 `ResourceQuotaExceeded`），或者同时包含 `OperationNotAllowed` 和 `quota`（不区分大小写） | 警告 |
| `ActivityFailure.Policy` | 操作失败·策略拒绝（Azure Policy） | 包含 `RequestDisallowedByPolicy` | 按活动日志 level：Critical → 严重，Error → 警告 |
| `ActivityFailure.Other` | 操作失败 | 其他所有失败 | 同上 |

- 卡片内容：标题为 `<资源>：<操作> 失败`。操作的中文：`write` → 创建/更新，`delete` → 删除，常见 action 有中文（start 启动、restart 重启、deallocate 释放、powerOff 关机、redeploy 重新部署、listKeys 读取密钥），其余 action 显示英文原名。字段包括操作、失败类型、调用方。正文为最内层的错误信息。
- **注意**：不排除限流（HTTP 429，`SubscriptionRequestsThrottled` 等）。自动化工具调用量大的环境，失败事件可能很多，部署前可以先用活动日志估算量。
- 本模块**不推送**：成功的操作，以及 level 为 Warning / Informational 的事件（除非加进 `activityFailureLevels`）。

**官方文档**：
- 活动日志 Administrative 类别（`status` 常见值包括 Failed）：<https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/activity-log-schema>
- 常见部署错误码总表（AllocationFailed、SkuNotAvailable、OperationNotAllowed、ResourceQuotaExceeded、RequestDisallowedByPolicy）：<https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/common-deployment-errors>
- 分配失败（AllocationFailed / ZonalAllocationFailed / Overconstrained*）：<https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/windows/allocation-failure>
- SKU 不可用：<https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-sku-not-available>
- 配额错误（OperationNotAllowed "exceeding quota limits"、ResourceQuotaExceeded）：<https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-resource-quota>
- Policy 拒绝：<https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-policy-requestdisallowedbypolicy>

---

## 9. M8 AKS 平台事件

- **数据源**：ARG `containerserviceeventresources | where type =~ 'microsoft.containerservice/managedclusters/scheduledevents'`，按 `lastUpdateTime` 在回看窗口内筛选。
- **频率**：每 5 分钟一次，回看 2 小时 / 24 小时。
- **分类**（参数 `kinds`，默认值前 4 项）：

| 内部类型 | category | 中文名 | 判定条件 | 严重度 | 推送频率 |
|---|---|---|---|---|---|
| OutOfSupport | `AKS.VersionEOL` | AKS 版本到期 | `eventSource=EOLNotification` 且 `description=KubernetesVersionOutOfSupport` | 警告 | 每个集群每周一次 |
| EOLSoon | `AKS.VersionEOL` | AKS 版本到期 | `eventSource=EOLNotification` 的其他事件（实际数据中有 `KubernetesVersionEOLTwoWeeks`、`KubernetesVersionEOLOneWeek`） | 警告 | 每个集群 + description + EOL 日期推送一次 |
| UpgradeScheduled | `AKS.Upgrade` | AKS 升级 | `eventStatus=Scheduled`（自动升级预告，`K8sVersionUpgrade` 或 `NodeOSUpgrade`，带计划时间和维护窗口） | 提示 | 每个事件 + 状态推送一次 |
| UpgradeNotSucceeded | `AKS.Upgrade` | AKS 升级 | `eventStatus=Completed` 且结果不是 Succeeded / Success | `Failed` → 警告；`Skipped` → 提示 | 同上 |
| Routine | `AKS.Upgrade` | AKS 升级 | 其他情况（Started、Completed+Succeeded 等） | 提示 | **默认不推送** |

- 实际数据中见过的 Skipped 原因：`power state of the cluster is Stopped, skip upgrading.`、`Autoupgrade not enabled for k8s none, os None, skip upgrading.`
- **前提条件**：只有配置了自动升级通道（cluster 或 node OS）并设置了计划维护窗口的集群，才会产生 Scheduled / Started / Completed 事件。EOL 事件不需要这个前提。
- `eventStatus=Failed` 或 `Canceled` 的事件：2026-11-01 已修正，归为 UpgradeNotSucceeded，会推送（标题显示"失败"或"已取消"）。实际数据中暂未见到这两种状态。
- AKS 自身的健康问题（如 etcd 空间不足、节点 NotReady）由 M3 `ResourceHealth` 覆盖。

**官方文档**：
- AKS Communication Manager（`containerserviceeventresources`、事件状态 Scheduled / Started / Completed / Canceled / Failed、提前一周和一天的预告）：<https://learn.microsoft.com/en-us/azure/aks/aks-communication-manager>
- 集群自动升级通道（none / patch / stable / rapid / node-image）：<https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-cluster>
- 节点 OS 自动升级通道（None / Unmanaged / SecurityPatch / NodeImage）：<https://learn.microsoft.com/en-us/azure/aks/auto-upgrade-node-os-image>
- 计划维护（`aksManagedAutoUpgradeSchedule` / `aksManagedNodeOSUpgradeSchedule`）：<https://learn.microsoft.com/en-us/azure/aks/planned-maintenance>
- 版本支持策略与 EOL 日历：<https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions>
- 平台发起的升级（2027-06-01 起，60 天宽限期后自动升级；通知渠道）：<https://learn.microsoft.com/en-us/azure/aks/platform-initiated-upgrades>
- **未验证**：
  - `EOLNotification` 和 `KubernetesVersionEOLTwoWeeks / EOLOneWeek / OutOfSupport` 这些取值在官方文档中**没有找到**，只来自实测数据。
  - ARG 支持表页面把 `microsoft.containerservice/managedclusters/scheduledevents` 列在 `maintenanceresources` 下，而 Communication Manager 页面和本方案的实测都使用 `containerserviceeventresources`。参见 <https://learn.microsoft.com/en-us/azure/governance/resource-graph/reference/supported-tables-resources>。

---

## 10. 自监控与兜底类别

| category | 中文名 | 来源 | 条件 | 严重度 |
|---|---|---|---|---|
| `SelfMonitor` | 告警系统自检 | 名称以 `-runs-failed` 结尾的 metric alert。Router 和每个 Pull Logic App（m1、m2-vm、m2-vmss、m5、m8）各有一条 | `RunsFailed` 15 分钟总计 > 0，每 5 分钟评估一次。常见原因：ARG 查询失败、飞书返回非 0 错误码（限流错误 11232 会先等待重试，默认最多 8 次，仍失败才算）、HTTP 失败、某个 category 没有可用的 webhook | Sev2 → 警告，恢复后推送"已恢复" |
| `ServiceHealth.Push` | 服务健康 | 客户自建的 Service Health 活动日志告警，接到了本方案的 Action Group | — | **不推送**：Router 直接丢弃。服务健康只以 M1（ARG 轮询）为准，避免同一事件出现一张内容更少的重复卡 |
| `LogAlert` | 日志告警 | 客户自建的日志告警（monitoringService = `Log Alerts V2`） | — | 按告警级别 |
| `Metric.Other` | 指标告警 | 客户自建的平台指标告警 | — | 按告警级别 |
| `Alert.Other` | 其他告警 | 以上都没匹配上的告警 | — | 按告警级别 |

- **注意**：如果 Router 本身无法投递卡片，它自己的 `SelfMonitor` 卡片也可能发不出去。

**官方文档**：
- Logic Apps 指标（`RunsFailed`）：<https://learn.microsoft.com/en-us/azure/azure-monitor/reference/supported-metrics/microsoft-logic-workflows-metrics>
- Common Alert Schema（Sev0–Sev4、`monitoringService`、`monitorCondition`）：<https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-common-schema>

---

## 11. 生产环境一类一群：分类清单

用法：在部署参数 `webhooks` 中配置每个 category 对应的群。key 可以写：
- **完整 category**，只路由这一类；
- **前缀**（`Flash`、`ServiceHealth`、`Metric`、`Quota`、`ActivityFailure`、`AKS`、`Alert`），路由这个前缀下的所有子类；
- `default`，兜底。

`ResourceHealth`、`SelfMonitor`、`LogAlert` 没有点号，前缀就是它自己。

| # | category | 中文名 | 模块 | 默认严重度 | 默认是否会出现 |
|---|---|---|---|---|---|
| 1 | `ServiceHealth.ServiceIssue` | 服务问题 | M1 | 按 EventLevel：严重 / 警告 / 提示 | 是 |
| 2 | `ServiceHealth.PlannedMaintenance` | 计划内维护（服务） | M1 | 按 EventLevel | 是 |
| 3 | `ServiceHealth.HealthAdvisory` | 健康公告（含退役） | M1 | 按 EventLevel | 是 |
| 4 | `ServiceHealth.SecurityAdvisory` | 安全公告 | M1 | 至少为警告 | 是 |
| 5 | `ServiceHealth.Billing` | 账单通知 | M1 | 按 EventLevel | 是 |
| 6 | `Flash.HostFailure` | 主机故障 | M2 | 严重 | 是 |
| 7 | `Flash.DegradedHardware` | 硬件降级 | M2 | 警告 / 提示 | 是 |
| 8 | `Flash.LiveMigration` | 热迁移 | M2 | 警告（失败）/ 提示（成功） | 是 |
| 9 | `Flash.PlannedFreeze` | 计划内冻结 | M2 | 警告（失败）/ 提示（开始、成功） | 是 |
| 10 | `Flash.PlannedMaintenance` | 计划内维护（VM） | M2 | 警告 | 是 |
| 11 | `Flash.VMCrash` | 虚拟机崩溃 | M2 | 警告 | 是 |
| 12 | `Flash.StorageOffline` | 存储断连 | M2 | 严重 | 是 |
| 13 | `Flash.ProvisioningTimeout` | 预配超时 | M2 | 警告 | 是 |
| 14 | `Flash.SpotEviction` | 抢占（Spot 驱逐） | M2 | 提示 | 是 |
| 15 | `ResourceHealth` | 资源健康 | M3 | 取活动日志 level（规则只放行 Critical → 严重） | 是 |
| 16 | `Metric.VmCpu` | CPU 使用率 | M4 | 严重 | 是（仅 `metricRegions` 中的区域） |
| 17 | `Metric.DataDiskBandwidth` | 数据盘带宽 | M4 | 警告 | 是（同上） |
| 18 | `Metric.Other` | 指标告警 | 兜底 | 按告警级别 | 仅客户自行接入时 |
| 19 | `Quota.Compute` | 计算配额 | M5 | 警告（80 / 90%）/ 严重（95%） | 是 |
| 20 | `ActivityFailure.Capacity` | 操作失败·容量不足 | M7 | 警告 | 是 |
| 21 | `ActivityFailure.Quota` | 操作失败·配额不足 | M7 | 警告 | 是 |
| 22 | `ActivityFailure.Policy` | 操作失败·策略拒绝（Azure Policy） | M7 | 警告 / 严重 | 是 |
| 23 | `ActivityFailure.Other` | 操作失败 | M7 | 警告 / 严重 | 是 |
| 24 | `AKS.Upgrade` | AKS 升级 | M8 | 提示 / 警告（失败） | 是 |
| 25 | `AKS.VersionEOL` | AKS 版本到期 | M8 | 警告 | 是 |
| 26 | `SelfMonitor` | 告警系统自检 | 自监控 | 警告 | 是 |
| 27 | `ServiceHealth.Push` | — | 兜底 | —（Router 丢弃，不推送） | 否 |
| 28 | `LogAlert` | 日志告警 | 兜底 | 按告警级别 | 仅客户自行接入时 |
| 29 | `Alert.Other` | 其他告警 | 兜底 | 按告警级别 | 仅客户自行接入时 |
| 30 | `ScheduledEvent.Reboot` | 计划事件·重启 | M6 | 警告 / 提示 | 仅满足先决条件的 VM |
| 31 | `ScheduledEvent.Redeploy` | 计划事件·重新部署 | M6 | 警告 / 提示 | 同上 |
| 32 | `ScheduledEvent.Freeze` | 计划事件·冻结 | M6 | 提示 | 同上 |
| 33 | `ScheduledEvent.Preempt` | 计划事件·抢占（Spot 驱逐） | M6 | 警告 / 提示 | 同上 |
| 34 | `ScheduledEvent.Terminate` | 计划事件·终止 | M6 | 警告 / 提示 | 同上（还需开启 VMSS Terminate Notification） |

> 中文名可以通过参数 `categoryNames` 覆盖（`modules/core/main.bicep` 中的 `defaultCategoryNames` 是内置默认值）。

---

## 12. 默认行为变更记录（2026-11-02）

| 模块 | 变更 |
|---|---|
| M7 操作失败 | 改为**所有资源、所有操作**：活动日志 Administrative 中 level 为 Error / Critical 的事件都推送。参数 `activityFailureLevels`（可加 Warning）、`activityFailureOperations`（可选的操作白名单，留空表示全部）。级别：容量 / 配额类为警告；其余按 level，Critical→严重，Error→警告 |
| M4 指标 | CPU 阈值默认改为 **80%**（平台 CPU 指标在部分规格上到不了 100%，实测 D2s_v5 最高只有 83.3%）；数据盘带宽阈值默认 100%（实测可以触发）。两个阈值都是部署参数，也放进了部署向导 |
| M8 AKS | "已结束（已跳过）"（多为集群停机）默认**不推送**，作为单独的类型 `UpgradeSkipped`，需要时加入 `kinds` 参数。版本到期卡片的时间改为通知时间，并显示订阅名 |
| M6 计划事件 | 默认只推送**平台发起**的事件；用户自己发起的重启 / 重新部署不推（参数 `includeUserInitiated`） |
| M2 Flash | 新增推送：`VirtualMachinePreempted`（Spot 驱逐，提示）和 `VirtualMachinePlannedFreezeStarted`（计划内冻结开始，提示） |
| 通用 | 新参数 `excludedSubscriptionIds`：Pull 模块排除指定订阅（在管理组上授权时使用）。部署向导中的订阅改为多选列表 |

**AKS 版本到期提醒频率**：
- 已超出支持期：同一集群每周最多 1 次（指纹为"集群 + 本周起始日"）。
- 即将到期（提前 2 周 / 1 周）：每条通知各 1 次。

**推送来的 Service Health 告警**（2026-11-02）：客户自建的 Service Health 活动日志告警如果接到本方案的 Action Group，Router 直接丢弃，不再发一张"以 M1 为准"的简要卡。服务健康只以 M1 为准。

**卡片正文不截断**（2026-11-02）：Azure 原文完整保留。飞书自定义机器人单条消息的请求体上限是 20 KB，所以正文超过 4000 字时自动拆成多张连续卡片（"（1/N）"、"（续 2/N）"……）。服务健康的事后复盘（PIR）正文可能有上万字，会收到多张卡片。

## 附：官方链接核验记录（2026-11-01）

| 链接 | 结果 |
|---|---|
| service-health/service-health-notifications-properties、service-health/overview、service-health/resource-graph-samples、rest/api/resourcehealth/events/list-by-subscription-id | 已验证 |
| service-health/resource-health-vm-annotation、virtual-machines/flash-overview、virtual-machines/flash-azure-resource-graph | 已验证 |
| service-health/resource-health-checks-resource-types、resource-health-overview、resource-health-alert-monitor-guide、azure-monitor/fundamentals/activity-log-schema | 已验证 |
| supported-metrics/microsoft-compute-virtualmachines-metrics、supported-metrics/microsoft-logic-workflows-metrics、alerts/alerts-common-schema | 已验证 |
| virtual-machines/quotas、quotas/how-to-guide-monitoring-alerting | 已验证 |
| troubleshooting/common-deployment-errors、error-sku-not-available、error-resource-quota、error-policy-requestdisallowedbypolicy、troubleshoot/.../allocation-failure | 已验证 |
| aks/aks-communication-manager、auto-upgrade-cluster、auto-upgrade-node-os-image、planned-maintenance、supported-kubernetes-versions、platform-initiated-upgrades | 已验证 |
| virtual-machines/scheduled-events-resource-graph、scheduled-events-event-grid、governance/resource-graph/reference/supported-tables-resources | 已验证 |
| 活动日志告警在 Common Alert Schema 中的 severity 为 Sev4 | **未验证**（官方 schema 只列出 Sev0–Sev4 的取值范围） |
| AKS `EOLNotification` 和 `KubernetesVersionEOL*` / `OutOfSupport` 取值 | **未验证**（未找到官方文档，只来自实测数据） |
