# M6 VM Scheduled Events

把 VM / VMSS 的 Scheduled Events（平台维护、用户重启/重新部署、Spot 驱逐、VMSS 实例终止）从 Azure Resource Graph 拉取，推送到飞书。VM 内部不需要部署 agent，也不需要轮询 IMDS。

官方文档：
- Scheduled Events 写入 ARG：<https://learn.microsoft.com/en-us/azure/virtual-machines/scheduled-events-resource-graph>
- Scheduled Events 推送到 Event Grid：<https://learn.microsoft.com/en-us/azure/virtual-machines/scheduled-events-event-grid>
- Scheduled Events 概念（事件类型和状态）：<https://learn.microsoft.com/en-us/azure/virtual-machines/linux/scheduled-events>

## 先决条件（不满足时这个模块不会产生任何告警）

可以用脚本批量检查和开启（默认只检查、不改任何东西）：

```bash
# 检查：feature flag、provider 注册、每个订阅里 VM / VMSS 的开启情况，并列出没开启的资源
scripts/enable-scheduled-events.sh --subscriptions "<订阅 ID> <订阅 ID>"

# 开启：注册缺少的 feature flag / provider，并给没开启的 VM 开启发布
scripts/enable-scheduled-events.sh --subscriptions "<订阅 ID>" --apply

# 同时处理 VMSS（只处理 Flexible，以及升级策略为 Manual 的 Uniform；Automatic / Rolling 的会跳过并列出）
scripts/enable-scheduled-events.sh --subscriptions "<订阅 ID>" --include-vmss --apply
```

- 不指定 `--subscriptions` 时检查当前账号能看到的所有订阅；`--resource-group` 可以只看一个资源组。
- feature flag 第一次注册后要等状态变成 Registered（可能要几分钟到几十分钟），再运行一次脚本。
- 脚本不会修改"用户发起的重启 / 重新部署自动批准"设置。
- 升级策略为 Automatic / Rolling 的 Uniform VMSS 改模型可能会触发实例更新，脚本不处理，请在维护窗口手动开启。

下面是脚本做的事情，也可以手动执行：

1. **每个订阅**注册两个 feature flag（一次性操作，注册后需要等 State 变成 Registered）：

   ```bash
   az feature register --namespace Microsoft.Compute --name SendScheduledEventsPolicy
   az feature register --namespace Microsoft.Maintenance --name ScheduledEventsActivity
   az feature show --namespace Microsoft.Compute --name SendScheduledEventsPolicy --query properties.state
   az provider register --namespace Microsoft.Compute
   az provider register --namespace Microsoft.Maintenance
   ```

2. **每台 VM / 每个 VMSS**打开"发布到 Event Grid 和 Resource Graph"（Compute API 2025-04-01 及以上）：

   ```bash
   az rest --method patch \
     --url "https://management.azure.com/<VM 或 VMSS 资源 ID>?api-version=2025-04-01" \
     --body '{"properties":{"scheduledEventsPolicy":{"scheduledEventsAdditionalPublishingTargets":{"eventGridAndResourceGraph":{"enable":true,"scheduledEventsApiVersion":"2020-07-01"}}}}}'
   ```

   可选：`scheduledEventsPolicy.userInitiatedReboot.automaticallyApprove` / `userInitiatedRedeploy.automaticallyApprove`。
   - 设为 `true`：用户发起的重启或重新部署直接执行，ARG 里只能看到 Started → Completed。
   - 不设或设为 `false`：会先出现 Scheduled 状态，等待批准或超时后才执行。

3. 告警系统的 MI 对这些订阅有 Reader 权限（和其它 Pull 模块相同）。

## 告警内容

| 分类 | 中文名 | 说明 |
|---|---|---|
| `ScheduledEvent.Reboot` | 计划事件·重启 | 平台维护重启，或用户发起的重启 |
| `ScheduledEvent.Redeploy` | 计划事件·重新部署 | 迁移到其它主机，本地临时盘数据会丢失 |
| `ScheduledEvent.Freeze` | 计划事件·冻结 | 内存保留的短暂暂停（通常几秒） |
| `ScheduledEvent.Preempt` | 计划事件·抢占（Spot 驱逐） | Spot VM 被回收 |
| `ScheduledEvent.Terminate` | 计划事件·终止 | VMSS 实例被删除（需要开启 Terminate Notification） |

- 每个事件的每个状态（Scheduled / Started / Completed / Canceled）各推送一次。
- 级别：
  - 平台发起的 Reboot / Redeploy / Preempt / Terminate，在 Scheduled 和 Started 阶段为"警告"；
  - 其余情况为"提示"；
  - Completed 和 Canceled 以"已恢复"（绿色）显示。
