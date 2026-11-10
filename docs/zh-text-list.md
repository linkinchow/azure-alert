# 中文文字与枚举翻译清单

用于人工检查译法。范围：代码里我们自己写的固定中文文字（①），以及有限取值枚举的中英对照（②）。
Azure 的自由文本（Flash reason、Resource Health title、Service Health 标题和正文、错误信息）保持英文原文，不在本清单内。

扫描范围：`git ls-files` 中所有 `*.kql`、`*.json`、`*.bicep`（不含编译产物 `azuredeploy.json`）。含中文的文件只有以下 9 个，其余文件没有中文：
`modules/core/main.bicep`、`modules/core/router-workflow.json`、`modules/m1-service-health/query.kql`、`modules/m2-flash/query-vm.kql`、`modules/m2-flash/query-vmss.kql`、`modules/m5-quota/query.kql`、`modules/m6-scheduled-events/query.kql`、`modules/m8-aks/query.kql`、`ui/createUiDefinition.json`。

行号以当前 `dev/v1` 为准。缩写：`RW` = `modules/core/router-workflow.json`。

---

## 1. 卡片固定元素（Router，所有模块共用）

| 元素 | 文字 / 规则 | 位置 |
|---|---|---|
| 标题格式 | `级别｜分类名｜标题`（标题最多 150 字符） | RW:343 |
| 级别：status = Resolved | 已恢复 | RW:343 |
| 级别：severity = Critical | 严重 | RW:343 |
| 级别：severity = Warning | 警告 | RW:343 |
| 级别：其他（Informational） | 提示 | RW:343 |
| 标题栏颜色 | 已恢复 green；严重 red；警告 orange；提示 blue | RW:340 |
| 分类名找不到时 | 显示英文分类 key 本身 | RW:343 |
| 字段行格式 | `**字段名**：值`（值为空的行不显示） | RW:509 |
| 摘要为空时 | （无详细说明） | RW:361 |
| 摘要长度 | 不截断。正文超过 4000 字时拆成多张卡片：第 1 张标题后加"（1/N）"，后续卡片标题加"（续 i/N）"，只含正文和页脚（飞书单条消息请求体上限 20 KB） | RW:Summary_parts / More_parts |
| 按钮 | 在 Azure 门户中查看 | RW:372 |
| 页脚 | `Azure 告警 · 来源 {模块} · {通道}`（如 `Azure 告警 · 来源 M2-Flash · ARG`） | RW:383 |

## 2. 字段名

### 2.1 Router 基础字段（每张卡都有，排在模块字段前面）

| 字段名 | 值 | 位置 |
|---|---|---|
| 时间（北京时间） | eventTime 转 China Standard Time，`yyyy-MM-dd HH:mm:ss` | RW:293 |
| 资源 | 资源名；标题里已含资源名时不显示 | RW:297 |
| 订阅 | 订阅名（没有时为订阅 ID）；M1 多订阅时为 `N 个：a、b、…`（最多列 10 个） | RW:301-302 |
| 资源组 | 资源组名 | RW:305 |
| 区域 | 区域；M1 多区域时为 `a、b、…`，超过 8 个追加 `等 N 个区域` | RW:309-310 |

### 2.2 Push 模块字段（M3 / M4 / M7，经 Router 的 Normalizer）

| 字段名 | 出现在 | 值 | 位置 |
|---|---|---|---|
| 指标 | M4 | Metric_name_cn（见 4.3） | RW:188 |
| 当前值 | M4 | 指标当前值 | RW:192 |
| 触发条件 | M4 | Metric_condition（见 4.4） | RW:196 |
| 健康状态 | M3 | `之前 → 现在`，用 Health_cn 翻译（见 4.1） | RW:200-201 |
| 发起方 | M3 | cause 用 Health_cn 翻译 | RW:204-205 |
| 操作 | M7 | operationName 原文（英文） | RW:208 |
| 失败类型 | M7 | Activity_class 用 Health_cn 翻译 | RW:212-213 |
| 调用方 | M7 | caller 原文 | RW:216 |
| 告警规则 | 其他推送告警（非 M3/M4/M7） | 告警规则名 | RW:220 |

### 2.3 M1 Service Health

| 字段名 | 位置 |
|---|---|
| 状态 | m1-service-health/query.kql:41 |
| 子类型 | :42 |
| 影响服务 | :43 |
| 受影响资源（值：`N 个：a、b、…`，超过 10 个追加 ` 等`） | :44 |
| 影响开始（北京时间） | :45 |
| 缓解 / 截止（北京时间） | :46 |

### 2.4 M2 Flash（VM 与 VMSS 两个文件相同）

| 字段名 | 位置 |
|---|---|
| 平台事件（值：annotation 英文名；为空时为“（变更记录未带名称，按描述归类）”） | query-vm.kql:45 / query-vmss.kql:45 |
| 影响 | :46 |
| 发起方 | :47 |
| 热迁移 | :48 |
| 私网 IP（多个 IP 用“、”连接） | :49 |

### 2.5 M5 配额

| 字段名 | 位置 |
|---|---|
| 已用 / 上限 | m5-quota/query.kql:26 |
| 配额名称（值：配额英文 name.value） | :27 |

### 2.6 M6 计划事件

| 字段名 | 位置 |
|---|---|
| 状态 | m6-scheduled-events/query.kql:31 |
| 发起方 | :32 |
| 预计影响时长（值：`N 秒`） | :33 |
| 受影响实例 | :34 |

### 2.7 M8 AKS

| 字段名 | 位置 |
|---|---|
| 计划时间（北京时间） | m8-aks/query.kql:46 |
| 维护窗口（UTC） | :47 |
| 支持结束日期 | :48 |
| Kubernetes 版本 | :49 |

## 3. 分类名字典 categoryNames（34 个）

位置：`modules/core/main.bicep:35-68`（部署参数 `categoryNames` 可以覆盖）。

| # | 分类 key | 中文 | 行 |
|---|---|---|---|
| 1 | Flash.HostFailure | 主机故障 | 35 |
| 2 | Flash.DegradedHardware | 硬件降级 | 36 |
| 3 | Flash.LiveMigration | 热迁移 | 37 |
| 4 | Flash.PlannedFreeze | 计划内冻结 | 38 |
| 5 | Flash.PlannedMaintenance | 计划内维护（VM） | 39 |
| 6 | Flash.VMCrash | 虚拟机崩溃 | 40 |
| 7 | Flash.StorageOffline | 存储断连 | 41 |
| 8 | Flash.ProvisioningTimeout | 预配超时 | 42 |
| 9 | Flash.SpotEviction | 抢占（Spot 驱逐） | 43 |
| 10 | ServiceHealth.ServiceIssue | 服务问题 | 44 |
| 11 | ServiceHealth.PlannedMaintenance | 计划内维护（服务） | 45 |
| 12 | ServiceHealth.HealthAdvisory | 健康公告 | 46 |
| 13 | ServiceHealth.SecurityAdvisory | 安全公告 | 47 |
| 14 | ServiceHealth.Billing | 账单通知 | 48 |
| 15 | ~~ServiceHealth.Push~~ | （已删除：推送来的 Service Health 告警由 Router 丢弃） | — |
| 16 | ResourceHealth | 资源健康 | 50 |
| 17 | Metric.VmCpu | CPU 使用率 | 51 |
| 18 | Metric.DataDiskBandwidth | 数据盘带宽 | 52 |
| 19 | Metric.Other | 指标告警 | 53 |
| 20 | Quota.Compute | 计算配额 | 54 |
| 21 | ActivityFailure.Capacity | 操作失败·容量不足 | 55 |
| 22 | ActivityFailure.Quota | 操作失败·配额不足 | 56 |
| 23 | ActivityFailure.Policy | 操作失败·策略拒绝（Azure Policy） | 57 |
| 24 | ActivityFailure.Other | 操作失败 | 58 |
| 25 | ScheduledEvent.Reboot | 计划事件·重启 | 59 |
| 26 | ScheduledEvent.Redeploy | 计划事件·重新部署 | 60 |
| 27 | ScheduledEvent.Freeze | 计划事件·冻结 | 61 |
| 28 | ScheduledEvent.Preempt | 计划事件·抢占（Spot 驱逐） | 62 |
| 29 | ScheduledEvent.Terminate | 计划事件·终止 | 63 |
| 30 | AKS.Upgrade | AKS 升级 | 64 |
| 31 | AKS.VersionEOL | AKS 版本到期 | 65 |
| 32 | SelfMonitor | 告警系统自检 | 66 |
| 33 | LogAlert | 日志告警 | 67 |
| 34 | Alert.Other | 其他告警 | 68 |

## 4. 枚举翻译（英文原值 → 中文）

### 4.1 Health_cn（Router 共用字典，RW:665-674）

| 英文 | 中文 | 用于 |
|---|---|---|
| Available | 可用 | M3 健康状态 |
| Unavailable | 不可用 | M3 健康状态 |
| Degraded | 已降级 | M3 健康状态 |
| Unknown | 未知 | M3 健康状态 |
| PlatformInitiated | 平台 | M3 发起方 |
| UserInitiated | 用户 | M3 发起方 |
| Capacity | 容量不足 | M7 失败类型 |
| Quota | 配额不足 | M7 失败类型 |
| Policy | 策略拒绝（Azure Policy） | M7 失败类型 |
| Other | 其他 | M7 失败类型 |

未命中时：健康状态显示英文原值；发起方为空。

### 4.2 Operation_cn（M7 操作，RW:684）

operationName 按 `/` 拆分后取最后一段：

| 最后一段 | 中文 |
|---|---|
| write | 创建/更新 |
| delete | 删除 |
| action | 取倒数第二段查字典：start 启动、restart 重启、deallocate 释放、powerOff 关机、redeploy 重新部署、listKeys 读取密钥（不区分大小写）；其余显示英文原文 |
| 其他 | 最后一段英文原文 |

### 4.3 Metric_name_cn（M4 指标名，RW:637）

| metricName | 中文 |
|---|---|
| Percentage CPU | CPU 使用率 |
| Data Disk Bandwidth Consumed Percentage | 数据盘带宽使用率 |
| Data Disk IOPS Consumed Percentage | 数据盘 IOPS 使用率 |
| RunsFailed | 运行失败次数 |
| 其他 | 英文原名 |

### 4.4 Metric_condition（M4 触发条件，RW:655）

| 英文 | 中文 / 符号 |
|---|---|
| operator GreaterThanOrEqual | ≥ |
| operator GreaterThan | > |
| operator LessThan | < |
| operator LessThanOrEqual | ≤ |
| 其他 operator | 英文原值 |
| timeAggregation Average | 平均值 |
| timeAggregation Total | 总计 |
| timeAggregation Maximum | 最大值 |
| 其他 timeAggregation | 英文原值 |
| windowSize `PT5M` / `PT1H` | 5 分钟 / 1 小时（去掉 PT / P / T，D→天，M→分钟，H→小时） |

### 4.5 Activity_class（M7 失败归类，RW:126；按错误文本关键字判断，英文 → 分类）

| 错误文本包含 | 分类 | 中文（经 Health_cn / categoryNames） |
|---|---|---|
| AllocationFailed / OverconstrainedAllocationRequest / OverconstrainedZonalAllocationRequest / SkuNotAvailable | Capacity | 容量不足 |
| QuotaExceeded，或 OperationNotAllowed 且含 quota | Quota | 配额不足 |
| RequestDisallowedByPolicy | Policy | 策略拒绝（Azure Policy） |
| 其他 | Other | 其他 / 操作失败 |

### 4.6 M1 Service Health

| 字段 | 英文 | 中文 | 位置 |
|---|---|---|---|
| 状态 | Resolved | 已恢复 | query.kql:41 |
| 状态 | PIR（EventTags 含 PIR） | 事后复盘（PIR） | :41 |
| 状态 | Mitigated（缓解时间已过）：ServiceIssue / PlannedMaintenance | 已缓解 | :41 |
| 状态 | Mitigated（截止日期已过）：HealthAdvisory / SecurityAdvisory / Billing | 已过截止日期 | :41 |
| 状态 | 其他（Active）：ServiceIssue / PlannedMaintenance 为"进行中"，HealthAdvisory / SecurityAdvisory / Billing 为"生效中" | 进行中 / 生效中 | :41 |
| 子类型 | Retirement | 退役通知 | :42 |
| 子类型 | PriceChanges | 价格变更 | :42 |
| 子类型 | 其他 | 英文原值 | :42 |

### 4.7 M2 Flash（VM / VMSS 相同）

| 字段 | 英文 | 中文 | 位置 |
|---|---|---|---|
| 影响 | Downtime Reboot | 停机重启 | query-vm.kql:46 |
| 影响 | Downtime Freeze | 短暂冻结 | :46 |
| 影响 | Degraded | 性能降级 | :46 |
| 影响 | Informational | 无影响（仅通知） | :46 |
| 影响 | 其他 | 英文原值 | :46 |
| 发起方 | 含 Platform | 平台 | :47 |
| 发起方 | 含 VM | 虚拟机自身 | :47 |
| 发起方 | 含 Customer / User | 用户 | :47 |
| 发起方 | 其他 | 英文原值 | :47 |
| 热迁移 | Eligible | 支持（平台会尝试热迁移） | :48 |
| 热迁移 | NotEligible | 不支持（建议尽快重新部署） | :48 |
| 热迁移 | 无后缀 | 不显示 | :48 |

Flash 的分类和级别由 `modules/m2-flash/rules.json` 按 annotationName 决定，中文名来自第 3 节。rules.json 本身没有中文。

### 4.8 M6 计划事件（query.kql:12-14）

| 字段 | 英文 | 中文 |
|---|---|---|
| 事件类型 | Reboot | 重启 |
| 事件类型 | Redeploy | 重新部署 |
| 事件类型 | Freeze | 冻结 |
| 事件类型 | Preempt | 抢占（Spot 驱逐） |
| 事件类型 | Terminate | 终止 |
| 状态 | Scheduled | 已计划 |
| 状态 | Started | 已开始 |
| 状态 | Completed | 已完成 |
| 状态 | Canceled | 已取消 |
| 发起方 | Platform | 平台 |
| 发起方 | User | 用户 |

未命中时都显示英文原值。

### 4.9 M8 AKS（query.kql:20-22）

| 字段 | 英文 | 中文 |
|---|---|---|
| 升级类型 | K8sVersionUpgrade | Kubernetes 版本升级 |
| 升级类型 | NodeOSUpgrade | 节点 OS 升级 |
| 事件状态 | Scheduled | 已计划 |
| 事件状态 | Started | 已开始 |
| 事件状态 | Completed | 已结束 |
| 事件状态 | Failed | 失败 |
| 事件状态 | Canceled / Cancelled | 已取消 |
| 升级结果 | Skipped | 已跳过 |
| 升级结果 | Failed | 失败 |
| 升级结果 | Succeeded / Success | 成功 |
| EOL 描述 | KubernetesVersionOutOfSupport | 已超出支持期 |
| EOL 描述 | 其他 EOL 通知 | 即将结束支持 |

未命中时都显示英文原值。

### 4.10 M5 配额

没有枚举翻译。配额名用 Azure 的 `localizedValue`（英文），档位 80 / 90 / 95 是数字。

## 5. 拼接的中文句子模板（标题后半段 / 摘要）

`{}` 表示变量。

| 模块 | 用途 | 模板 | 位置 |
|---|---|---|---|
| M1 | 标题 | `{TrackingId} {英文标题}` | m1 query.kql |
| M2 | 标题 | `{VM 名}：{英文 reason}`；reason 为空时 `{VM 名}：{annotation 名}`，再为空时 `{VM 名}：平台事件` | query-vm.kql:37 / query-vmss.kql:37 |
| M3 | 标题 | `{资源名}：{英文 title}`（没有 title 时用 currentHealthStatus） | RW:167 |
| M3 | 摘要 | 英文 details / title 原文 | RW:146 |
| M4 | 标题 | `{VM 名} {指标中文名} {当前值}%` | RW:167 |
| M4 | 摘要 | `{指标中文名} 当前 {值}，触发条件 {条件}。` | RW:146 |
| M4 | 触发条件 | `≥ {阈值}（平均值，5 分钟）` | RW:655 |
| M5 | 标题 | `{配额英文名}（{区域}）使用率 {pct}%` | m5 query.kql:19 |
| M5 | 摘要 | `已使用 {cur} / {lim}，达到 {band}% 档位。持续高于该档位时约每天提醒一次，升到更高档位时立即提醒。` | m5 query.kql:20 |
| M6 | 标题 | `{实例名}：{事件类型} {状态}` | m6 query.kql:24 |
| M6 | 摘要 | `{英文描述}（最早开始时间 {yyyy-MM-dd HH:mm:ss} 北京时间）` | m6 query.kql:25 |
| M7 | 标题 | `{资源名}：{操作中文} 失败` | RW:167 |
| M7 | 摘要 | 英文错误信息原文（最多 1500 字符） | RW:146 |
| M8 | 标题（EOL） | `{集群名}：Kubernetes {版本} 已超出支持期` / `… 即将结束支持` | m8 query.kql:37 |
| M8 | 标题（升级） | `{集群名}：{升级类型} {状态}（{升级结果}）` | m8 query.kql:37 |
| M8 | 摘要（EOL） | `Kubernetes {版本} 的支持结束日期为 {yyyy-MM-dd}，请规划升级。` | m8 query.kql:39 |
| M8 | 摘要（有错误） | `{升级类型} {状态}（{结果}）：{英文错误}` | m8 query.kql:40 |
| M8 | 摘要（其他） | `{升级类型} {状态}。` | m8 query.kql:41 |
| ~~推送·Service Health~~ | — | （已删除：Router 丢弃这类告警，不再生成卡片） | — |
| 其他推送告警 | 标题 | `{告警规则名}：{资源名}`；没有规则名时 `Azure Monitor 告警` | RW:167 |

## 6. 部署向导 ui/createUiDefinition.json

由 `scripts/zh_wizard_texts.py` 从向导文件生成。"告警模块"是多选下拉框（默认全选），"首次运行静默""写入 Log Analytics"是"是 / 否"单选，以便在审阅页显示；"按分类路由"预填了各模块的分类前缀（值为空，留空的发到默认 webhook）。

| 行 | 类型 | 文字 |
|---|---|---|
| 9 | 说明 | **azure-alert**：把 Azure 平台事件（Service Health、Project Flash、Resource Health、Metric、Quota、AKS 等）统一推送到飞书。 |
| 11 | label | 中心资源组区域 |
| 23 | 说明框 | 已经部署过、这次是添加模块或升级？请使用和第一次相同的订阅、资源组名称和前缀，勾选所有需要的模块（已部署的不会重复创建），并重新填写飞书 webhook 和按分类路由（这两项不会被记住）。资源组名称或前缀不同会再部署出一整套。点击查看说明。 |
| 23 | 选项 | 是 |
| 30 | label | 中心资源组名称 |
| 35 | 校验提示 | 1-90 个字母、数字、-、_、.、() |
| 37 | tooltip | 告警系统自身的资源（托管身份、Router、各模块 Logic App、Action Group）都建在这个资源组里，不存在会自动创建。 |
| 42 | label | 资源名前缀 |
| 47 | 校验提示 | 2-10 个小写字母、数字或 -，以字母开头 |
| 49 | tooltip | 所有资源名的前缀，例如 aa-router、aa-m1-service-health。同一订阅里部署多套时用不同前缀区分。 |
| 55 | 步骤 | 告警模块 |
| 60 | label | 要部署的告警模块 |
| 61 | tooltip | 默认全选。M3 / M4 / M7 会在"范围与权限"一步选择的订阅里建告警规则；其余模块通过 Azure Resource Graph 轮询。 |
| 61 | 步骤 | 范围与权限 |
| 94 | 选项 | M1 服务健康 |
| 95 | 选项说明 | 服务问题、计划内维护、健康公告、安全公告、账单通知。每分钟查询一次 Azure Resource Graph。 |
| 99 | 选项 | M2 Project Flash（VM / VMSS 平台事件） |
| 100 | 选项说明 | 主机故障、硬件降级、热迁移、计划内冻结 / 维护、虚拟机崩溃、存储断连、预配超时、Spot 抢占。VM 和 VMSS 各一个 Logic App。 |
| 104 | 选项 | M3 资源健康（全资源类型） |
| 105 | 选项说明 | 所有资源类型的平台发起的不可用 / 降级（活动日志 level 为 Critical）。在每个选中的订阅里建一条活动日志告警规则。 |
| 109 | 选项 | M4 指标示例（CPU、数据盘带宽） |
| 110 | 选项说明 | 多资源指标告警示例：VM CPU 使用率、数据盘带宽使用率，阈值在"范围与权限"一步设置。每个区域一条规则。 |
| 114 | 选项 | M5 计算配额 |
| 115 | 选项说明 | 计算配额使用率达到 80% / 90% / 95% 时提醒。 |
| 119 | 选项 | M6 计划事件（需先决条件） |
| 120 | 选项说明 | VM / VMSS 维护的事前通知（重启、重新部署、冻结、抢占、终止）。订阅和 VM 需要先满足先决条件，见 modules/m6-scheduled-events/README.md。 |
| 124 | 选项 | M7 资源操作失败 |
| 125 | 选项说明 | 所有资源、所有操作中 level 为 Error / Critical 的失败（容量不足、配额不足、策略拒绝等会自动归类）。自动化调用多的环境量可能很大。 |
| 129 | 选项 | M8 AKS 升级与版本到期 |
| 130 | 选项说明 | AKS 自动升级的计划和失败、Kubernetes 版本即将到期 / 已超出支持期。 |
| 134 | 选项 | M9 Key Vault 到期提醒 |
| 135 | 选项说明 | 证书、机密、密钥到期前 30 天和过期时提醒。为下一步选中的现有 Key Vault 建 Event Grid 订阅，部署人需要对这些 Key Vault 所在资源组有 Event Grid 写权限；以后新建的 Key Vault 按文档接入。 |
| 147 | 步骤 | 飞书通知 |
| 153 | label | 默认飞书 webhook |
| 154 | label | 再次输入默认飞书 webhook（不显示） |
| 159 | 校验提示 | 请输入飞书 / Lark 自定义机器人 webhook |
| 164 | tooltip | 飞书群自定义机器人的 webhook 地址。没有在"按分类路由"里单独指定的告警都发到这里。 |
| 172 | 说明框 | 想把不同告警发到不同的飞书群，就在下面对应的分类后面填上该群的 webhook，不填的发到上面的默认 webhook。ServiceHealth = M1 服务健康，Flash = M2 VM 平台事件，ResourceHealth = M3 资源健康，Metric = M4 指标，Quota = M5 配额，ScheduledEvent = M6 计划事件，ActivityFailure = M7 操作失败，AKS = M8 AKS，KeyVault = M9 Key Vault 到期提醒，SelfMonitor = 告警系统自检。点击查看完整说明和示例。 |
| 179 | label | 按分类路由（可选） |
| 180 | tooltip | 留空的分类发到默认 webhook。要把某个小类单独发到一个群，可以再加一行，例如 "Flash.HostFailure": "https://..."；完整分类名优先于模块前缀。[完整说明和示例](https://github.com/linkinchow/azure-alert#多个飞书群按分类路由) |
| 186 | 校验提示 | 请输入 JSON 对象：键用英文双引号，最后一项后面不要加逗号 |
| 206 | label | ARG 读取权限（Reader）授予方式 |
| 207 | 选项 | 按订阅授予 |
| 215 | 选项 | 不授予（部署后用 scripts/grant-reader-mg.sh 在管理组上授予） |
| 220 | tooltip | Pull 模块（M1 / M2 / M5 / M6 / M8）需要对被监控的订阅有 Reader 权限。按订阅授予会在每个选中的订阅上授予；也可以部署后在管理组上统一授予。 |
| 225 | label | 要告警的订阅（Pull 模块读取范围，授予 Reader） |
| 234 | tooltip | 这些订阅会给告警托管身份授予 Reader，Pull 模块只读取这些订阅。 |
| 239 | label | 排除的订阅（可选） |
| 248 | tooltip | 在管理组上授权时，管理组下不想告警的订阅。 |
| 253 | label | 部署 M3 / M4 / M7 告警规则的订阅 |
| 262 | tooltip | M3 / M4 / M7 的告警规则会建在这些订阅里，监控整个订阅。 |
| 267 | label | M4 metric 规则的区域（逗号分隔，例如 eastus2,westus3） |
| 272 | 校验提示 | 区域名用逗号分隔，例如 eastus2,westus3 |
| 274 | tooltip | M4 指标规则按区域创建，多个区域用逗号分隔，例如 eastus2,westus3。 |
| 279 | label | M4 CPU 告警阈值（%，5 分钟平均） |
| 281 | tooltip | 平台 CPU 指标在部分规格上到不了 100%（实测 D2s_v5 最高 83.3%），建议 80。 |
| 285 | 校验提示 | 1-100 的整数 |
| 291 | label | M4 数据盘带宽使用率告警阈值（%，5 分钟平均） |
| 302 | label | 首次运行静默（不推送历史事件） |
| 304 | tooltip | 建议勾选：首次运行只记录当前已有的事件，不把历史事件一次性推进群。 |
| 312 | 选项 | 否 |
| 322 | label | 事件落地到 Log Analytics 自定义表 AzureAlertEvents_CL |
| 324 | tooltip | 把标准事件同时写入 Log Analytics 自定义表 AzureAlertEvents_CL，便于以后统计和分析。会新建一个工作区。 |
| 351 | 说明框 | 没有勾选 M9 Key Vault 到期提醒，这一步不需要填写，直接点"下一步"。 |
| 360 | 说明框 | 选择要接入到期提醒的现有 Key Vault（列出当前账号能看到的所有订阅里的 Key Vault）。部署时会在每个选中的 Key Vault 上建一个事件订阅（<前缀>-kv-expiry），Event Grid 会在 Key Vault 所在资源组自动创建或复用它的系统主题，不改动 Key Vault 本身。部署人需要对这些资源组有 Event Grid 写权限（EventGrid Contributor 或 Contributor），没有权限的请不要勾选。以后新建的 Key Vault 用脚本或门户接入，点击查看说明。 |
| 381 | label | 要接入的 Key Vault |
| 386 | tooltip | 列出当前账号能看到的所有订阅里的 Key Vault（最多 1000 个），每项下方显示资源组和订阅 ID。可以搜索，也可以全选。 |

---

## 7. 疑点（2026-11-02 已全部处理：第 6 条统一为“已恢复”，第 12 条改为“已结束”，其余按建议）

| # | 位置 | 问题 | 建议 |
|---|---|---|---|
| 1 | UI:66 | 写的是“VM CPU 100%、数据盘带宽 100%”，但 CPU 默认阈值已改为 80，两个阈值都可调 | 改为“M4 Metric 示例：VM CPU 使用率、数据盘带宽使用率（阈值可调）” |
| 2 | UI:84 | 写的是“容量 / 配额 / Policy”，但 M7 已改为所有操作中 level 为 Error / Critical 的失败 | 改为“M7 资源操作失败：所有操作，Error / Critical（每个订阅一条告警规则）” |
| 3 | M2:47 / M6:32 / RW:204 | 同一含义有两个字段名：Flash 和 M3 叫“触发方”，M6 叫“发起方”；值也不同，M3 是“平台触发 / 用户触发”，Flash 和 M6 是“平台 / 用户” | 统一字段名为“发起方”，值统一为“平台 / 用户” |
| 4 | M2:48 | “不支持（建议尽快 redeploy）”中英混用 | 改为“不支持（建议尽快重新部署）” |
| 5 | RW:665-667 / M2:46 / main.bicep:36 | Degraded 有三种译法：健康状态“降级”、Flash 影响“性能降级”、分类“硬件降级” | 健康状态用“已降级”（与门户一致），Flash 影响保留“性能降级”；分类“硬件降级”含义不同，可以保留 |
| 6 | RW:343 / M1:41 | Resolved 有两种译法：卡片级别“已恢复”，M1 状态“已解决” | M1 是公告类事件，用“已解决”合理；如果要统一，可以都用“已恢复” |
| 7 | M2:46 | Informational →“信息”，作为“影响”的值不通顺 | 改为“无影响（仅通知）” |
| 8 | M1:41 | 健康公告、安全公告、账单通知没有“进行”的概念，但状态也显示“进行中” | 公告类显示“生效中”，ServiceIssue / PlannedMaintenance 保留“进行中” |
| 9 | RW:684 | 操作是 action 时显示英文原文，如“vm01：start 失败”“deallocate 失败” | 给常见 action 加字典：start→启动、restart→重启、deallocate→释放、powerOff→关机、redeploy→重新部署、listKeys→读取密钥；其余保留英文 |
| 10 | main.bicep:57 / RW:673 | “Policy 拒绝”中英混用 | 改为“策略拒绝（Azure Policy）”；也可以保留“Policy”，因为它是产品名 |
| 11 | M6:12 / main.bicep:62 | Preempt：类型写“抢占（Spot 驱逐）”，分类写“Spot 驱逐”；Preempt 也适用于低优先级 VMSS | 两处可以统一为“抢占（Spot 驱逐）” |
| 12 | M8:21-22 | 事件状态“失败”和升级结果“失败”可能连着出现，如“节点 OS 升级 已完成（失败）” | 可以接受；如果介意，可以改为“已结束（失败）” |
| 13 | RW:655 | windowSize 只处理 PT 开头（分钟 / 小时），P1D 之类会显示原文 | 目前规则只用 PT5M，不影响；以后要用天级窗口时补 D→天 |
