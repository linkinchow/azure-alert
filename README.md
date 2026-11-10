# azure-alert

一键部署、模块化的 Azure 全方位告警方案：把 Service Health、Project Flash、Resource Health、Metric、Quota、AKS 等平台事件统一转换成标准事件，通过 Logic App 推送到飞书。每个模块会发出哪些告警、各有哪些小类，以及对应的官方文档，见 [docs/alert-catalog.md](docs/alert-catalog.md)。

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Flinkinchow%2Fazure-alert%2Fmain%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Flinkinchow%2Fazure-alert%2Fmain%2Fui%2FcreateUiDefinition.json)

部署前请先看下面的[部署](#部署)说明。

## 模块（v1）

| 模块 | 数据源 | 方式 | 默认 |
|---|---|---|---|
| Core | — | 用户分配 MI、Router Logic App（Normalizer + 飞书卡片）、Action Group | 必选 |
| M1 Service Health | ARG `servicehealthresources` | Pull，每分钟 | ✅ |
| M2 Project Flash（VM / VMSS） | ARG `healthresourcechanges` | Pull，每分钟（VM、VMSS 各一个 Logic App） | ✅ |
| M3 Resource Health（全资源类型） | Activity Log | 每个订阅一条 activity log alert | ✅ |
| M4 Metric（VM CPU、数据盘带宽） | 平台指标 | 每个订阅 × 区域一条多资源 metric alert | ✅ |
| M5 Quota（Compute） | ARG `quotaresources` | Pull，每 15 分钟 | ✅ |
| M7 Activity 失败 | Activity Log | 每个订阅一条 activity log alert | ✅ |
| M8 AKS 平台事件 | ARG `containerserviceeventresources` | Pull，每 5 分钟 | ✅ |
| 自监控 | Logic App `RunsFailed` 指标 | 每个 workflow 一条 metric alert，分类为 `SelfMonitor` | 随 core / 模块部署 |
| 数据落地（可选） | — | Log Analytics 自定义表 `AzureAlertEvents_CL`（DCR + Logs Ingestion API） | `sinkEnabled=false` |

部署时可以只选部分模块：门户向导里在"告警模块"一步勾选；命令行用 `modules` 参数，见[命令行部署](#命令行部署)。以后要加模块或升级，见[添加、升级或删除模块](#添加升级或删除模块)。

## 目录

```
main.bicep                    入口（subscription 作用域）
modules/core/                 MI、Router Logic App、Action Group
modules/shared/               通用 ARG 轮询 Logic App、角色分配、资源组
modules/m1-service-health/    query.kql + main.bicep
modules/m2-flash/             query-vm.kql / query-vmss.kql + rules.json（annotation 分类表）+ main.bicep
modules/m5-quota/  modules/m8-aks/
modules/push/                 M3 / M4 / M7 告警规则（部署到每个推送订阅）
scripts/                      查询渲染、测试辅助、MG 授权脚本
test/                         测试参数（webhook 放在 *.local.json，不提交）
```

## 部署

1. 建飞书群自定义机器人，复制 webhook 地址（不需要配置安全设置）。
   - Logic App 出口 IP 不固定，不适合用 IP 白名单。
2. 准备参数文件。webhook 是 secure 参数，请放在不提交到 git 的 `*.local.json` 文件里：

   ```json
   {
     "parameters": {
       "webhooks": { "value": {
         "default": "https://open.feishu.cn/open-apis/bot/v2/hook/xxx",
         "ServiceHealth": "https://open.feishu.cn/open-apis/bot/v2/hook/yyy",
         "Flash.HostFailure": "https://open.feishu.cn/open-apis/bot/v2/hook/zzz"
       } }
     }
   }
   ```

   发到多个飞书群的写法见下面的[多个飞书群（按分类路由）](#多个飞书群按分类路由)。

3. 部署：见下面的[命令行部署](#命令行部署)，或者用[一键部署](#一键部署deploy-to-azure)。

   常用参数（完整列表见 `main.bicep` 开头的 `param`）：

   | 参数 | 说明 |
   |---|---|
   | `readerScope` | `subscription`（默认，对 `readerSubscriptionIds` 中的订阅授予 Reader）或 `none`。选 `none` 时，部署后执行 `scripts/grant-reader-mg.sh <mg> <identityPrincipalId>` 在管理组上授权，新订阅会自动纳入 |
   | `pushSubscriptionIds` | 需要部署 M3 / M4 / M7 告警规则的订阅列表 |
   | `metricRegions` | M4 多资源 metric 规则的区域列表 |
   | `bootstrapSilent` | 默认 `true`：全新部署后，每个 Pull 模块从第一次成功运行起 30 分钟内只记录指纹、不发送（每次回看 24 小时），避免把历史事件一次性推进群。重新部署、更新模板不会再次静默 |
   | `feishuMaxAttempts` | 默认 `8`：飞书限流时每条消息最多发送几次（见下文"飞书限流"） |

### 命令行部署

先拿到最新代码（`git clone https://github.com/linkinchow/azure-alert.git`，已有的话 `git pull`），在仓库根目录执行。需要 Azure CLI，Bicep 会自动安装；也可以把 `main.bicep` 换成编译好的 `azuredeploy.json`，效果一样。

**1. 准备参数文件**，例如 `deploy.local.json`（文件名以 `.local.json` 结尾不会被提交到 git）：

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "value": "eastus2" },
    "resourceGroupName": { "value": "rg-azure-alert" },
    "prefix": { "value": "aa" },
    "modules": { "value": {
      "serviceHealth": true,
      "flash": true,
      "resourceHealth": true,
      "metric": false,
      "quota": true,
      "scheduledEvents": true,
      "activityFailure": false,
      "aks": true
    } },
    "defaultWebhook": { "value": "https://open.feishu.cn/open-apis/bot/v2/hook/<默认群>" },
    "webhooks": { "value": {} },
    "readerSubscriptionIds": { "value": ["<要告警的订阅 ID>", "<订阅 ID 2>"] },
    "argScope": { "value": { "subscriptions": ["<要告警的订阅 ID>", "<订阅 ID 2>"] } },
    "pushSubscriptionIds": { "value": ["<要告警的订阅 ID>", "<订阅 ID 2>"] },
    "metricRegions": { "value": ["eastus2"] }
  }
}
```

**2. 部署**（在要放中心资源组的订阅下执行）：

```bash
az account set --subscription <中心订阅 ID>
az deployment sub create -l eastus2 -n azure-alert -f main.bicep -p @deploy.local.json
```

**选择模块**（参数 `modules`）：值为 `true` 的模块才部署，没写或写 `false` 的不部署。

| 键 | 模块 |
|---|---|
| `serviceHealth` | M1 服务健康 |
| `flash` | M2 Project Flash（VM / VMSS 平台事件） |
| `resourceHealth` | M3 资源健康 |
| `metric` | M4 指标 |
| `quota` | M5 计算配额 |
| `scheduledEvents` | M6 计划事件（需要先满足先决条件，见 `modules/m6-scheduled-events/README.md`） |
| `activityFailure` | M7 资源操作失败 |
| `aks` | M8 AKS |

上面的例子不部署 M4 和 M7。不传 `modules` 时全部部署。

**其他说明：**

- 订阅相关的三个参数：
  - `readerSubscriptionIds`：给告警系统的托管身份授予 Reader 的订阅；
  - `argScope`：Pull 模块（M1 / M2 / M5 / M6 / M8）查询的订阅，通常和上面相同；
  - `pushSubscriptionIds`：建 M3 / M4 / M7 告警规则的订阅。
  - 都不传时，默认只用当前订阅。
- 只临时改某个参数时，可以在参数文件后面再加 `-p`，后出现的为准。例如 bash 下：`-p @deploy.local.json -p modules='{"serviceHealth":true,"flash":true}'`。PowerShell 的引号规则不同，建议直接改参数文件。
- 多个飞书群的写法见[多个飞书群（按分类路由）](#多个飞书群按分类路由)，填在 `webhooks` 里。
- 重新部署（改参数、升级到新版本）可以重复执行同一条命令，已有资源会就地更新。**把某个模块改成 `false` 不会删除之前已经建好的资源**，需要的话手动删除（资源名以 `<前缀>-m<编号>` 开头）。

### 多个飞书群（按分类路由）

每条告警都有一个分类（category），例如 `Flash.HostFailure`。Router 按下面的顺序决定发到哪个群：

1. 完整分类名，例如 `Flash.HostFailure`；
2. 分类前缀（第一个点之前的部分），例如 `Flash`；
3. `default`（部署向导里的"默认飞书 webhook"）。

值为空字符串的项会被忽略，等同于没写。

**部署向导**的"按分类路由"已经预填了每个模块的前缀，值都是空的。在想单独建群的模块后面填上 webhook，其余留空，就会发到默认群。

| 键 | 对应模块 | 可单独指定的完整分类 |
|---|---|---|
| `ServiceHealth` | M1 服务健康 | `.ServiceIssue` `.PlannedMaintenance` `.HealthAdvisory` `.SecurityAdvisory` `.Billing` |
| `Flash` | M2 VM / VMSS 平台事件 | `.HostFailure` `.DegradedHardware` `.LiveMigration` `.PlannedFreeze` `.PlannedMaintenance` `.VMCrash` `.StorageOffline` `.ProvisioningTimeout` `.SpotEviction` |
| `ResourceHealth` | M3 资源健康 | （没有小类） |
| `Metric` | M4 指标 | `.VmCpu` `.DataDiskBandwidth` `.Other` |
| `Quota` | M5 计算配额 | `.Compute` |
| `ScheduledEvent` | M6 计划事件 | `.Reboot` `.Redeploy` `.Freeze` `.Preempt` `.Terminate` |
| `ActivityFailure` | M7 资源操作失败 | `.Capacity` `.Quota` `.Policy` `.Other` |
| `AKS` | M8 AKS | `.Upgrade` `.VersionEOL` |
| `SelfMonitor` | 告警系统自检 | （没有小类） |
| `LogAlert` | 客户自建的日志告警 | （没有小类） |

每个分类的中文名和含义见 [docs/alert-catalog.md](docs/alert-catalog.md) 第 11 节。

**示例**：服务健康、VM 平台事件、操作失败各一个群；主机故障和 Spot 抢占再单独各一个群；其余（资源健康、指标、配额、计划事件、AKS、自检）发到默认群。

```json
{
  "ServiceHealth": "https://open.feishu.cn/open-apis/bot/v2/hook/<服务健康群>",
  "Flash": "https://open.feishu.cn/open-apis/bot/v2/hook/<VM 平台事件群>",
  "Flash.HostFailure": "https://open.feishu.cn/open-apis/bot/v2/hook/<主机故障群>",
  "Flash.SpotEviction": "https://open.feishu.cn/open-apis/bot/v2/hook/<Spot 群>",
  "ResourceHealth": "",
  "Metric": "",
  "Quota": "",
  "ScheduledEvent": "",
  "ActivityFailure": "https://open.feishu.cn/open-apis/bot/v2/hook/<操作失败群>",
  "AKS": "",
  "SelfMonitor": ""
}
```

结果：

| 告警 | 发到 |
|---|---|
| 主机故障 | 主机故障群（完整分类优先） |
| Spot 抢占 | Spot 群 |
| 硬件降级、热迁移等其他 Flash 小类 | VM 平台事件群 |
| 服务问题、健康公告等 | 服务健康群 |
| 所有操作失败 | 操作失败群 |
| 资源健康、指标、配额、计划事件、AKS、自检 | 默认群 |

注意：

- 分类名区分大小写；键和值都用英文双引号，最后一项后面不要加逗号。
- 多个分类发到同一个群，填同一个地址即可。
- 飞书自定义机器人每个机器人每分钟最多 100 条。告警量大的分类（例如 `ActivityFailure`、`Flash.SpotEviction`）建议单独用一个群，避免挤占其他告警的额度。
- 用命令行部署时，把同样的对象作为参数 `webhooks` 的值，`default` 也可以直接写在里面（见上面第 2 步）。

### 一键部署（Deploy to Azure）

- `azuredeploy.json`：由 `az bicep build -f main.bicep --outfile azuredeploy.json` 生成的 ARM 模板，修改 Bicep 后需要重新生成。
- `ui/createUiDefinition.json`：门户部署向导，包含模块勾选、飞书 webhook、范围与权限三步。
- 按钮：

  [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Flinkinchow%2Fazure-alert%2Fmain%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Flinkinchow%2Fazure-alert%2Fmain%2Fui%2FcreateUiDefinition.json)

- 按钮链接格式：`https://portal.azure.com/#create/Microsoft.Template/uri/<azuredeploy.json 的 URL 编码>/createUIDefinitionUri/<createUiDefinition.json 的 URL 编码>`。fork 本仓库后，把链接里的 `linkinchow/azure-alert/main` 换成自己的仓库和分支。
- 验证情况（2026-11-02）：
  - 已验证：按向导输出构造参数，对 `azuredeploy.json` 执行 `az deployment sub validate` 和 `what-if` 均通过，计划创建的资源与勾选的模块一致。
  - 未验证：向导本身在门户中的显示和交互。发布前可以在门户的 [Create UI Definition Sandbox](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/SandboxBlade) 粘贴 `ui/createUiDefinition.json` 预览；发布后再用真实按钮完整走一遍。

### 添加、升级或删除模块

部署完成后，想加模块（例如第一次只选了 M1–M7，后来要加 M8），或者升级到新版本，**都是再部署一次**：

> **规则：使用和第一次相同的订阅、资源组名称和前缀，勾选所有需要的模块（已经部署的 + 新加的）。**

为什么这样是安全的：

- 部署是增量的：已有资源就地更新，不会重建，也不会重复创建。
- Pull 模块的去重记录保存在它自己的运行历史里，重新部署不会丢，不会把旧事件再推一遍。"首次运行静默"只对新加的模块生效。
- 新模块有时需要新版本的 Router 配合；勾选全部模块重新部署，会把已有模块和 Router 一起升级到最新版本。

**方式一：门户（Deploy to Azure）**

1. 再点一次本页顶部的 Deploy to Azure 按钮。
2. 订阅、区域、**资源组名称、前缀**都填得和第一次一样。
3. "告警模块"里勾选所有需要的模块。
4. **重新填写默认飞书 webhook 和"按分类路由"**：这两项是加密参数，门户不会记住。"按分类路由"如果保留预填的空模板，原来分到各个群的告警会全部改发到默认群。
5. 其他参数（订阅范围、M4 区域和阈值等）也按第一次的填写。

**方式二：命令行（推荐配置较多的情况）**

- 第一次部署时用的参数文件保存好，以后只改 `modules` 里的开关，再执行同样的部署命令。
- 参数文件丢了，可以从上一次的部署记录导出（加密参数 `defaultWebhook`、`webhooks` 需要重新填写）：

  ```bash
  python scripts/export-params.py                              # 列出这个订阅里的 azure-alert 部署记录
  python scripts/export-params.py <部署名称> > deploy.local.json  # 导出参数
  ```

  导出后补填 webhook，把新模块设为 `true`，再按[命令行部署](#命令行部署)执行。

**注意：**

- **资源组名称或前缀和第一次不同，会再部署出一整套告警系统**，同一事件会收到两张卡片。
- 只勾选新模块也能部署成功（没勾的模块保持原样），但已有模块不会升级；建议始终勾选全部需要的模块。
- **取消勾选不会删除已部署的模块**，要用删除脚本，见下面。

**删除模块**：重新部署时取消勾选不会删除模块（订阅级部署只支持增量模式），要用删除脚本：

```bash
# 先列出要删除的资源（不做任何改动）
python scripts/remove-module.py --prefix aa --resource-group rg-azure-alert --module m5

# 确认无误后删除；可以一次删多个模块
python scripts/remove-module.py --prefix aa --resource-group rg-azure-alert --module m5 --module m7 --apply
```

- 脚本用 Resource Graph 在当前账号能看到的所有订阅里查找：名称以 `<前缀>-m<编号>-` 开头、类型是 Logic App / 指标告警 / 活动日志告警、并且在中心资源组或推送资源组里的资源。M3 / M4 / M7 在每个推送订阅里的规则会一起找到。
- 推送资源组如果和中心资源组名称不同，加 `--push-resource-group <名称>`。
- 删除 Pull 模块（M1 / M2 / M5 / M6 / M8）会同时删掉它的去重记录；以后再加回来时，"首次运行静默"会让前 30 分钟只记录不推送，不会把历史事件推进群。
- 刚删完马上再运行列出命令，可能还会看到已删除的资源，这是 Resource Graph 的索引延迟（通常一分钟内），不影响。

各模块对应的资源（供手动核对）：

| 模块 | 资源 |
|---|---|
| M1 | Logic App `<前缀>-m1-service-health`，指标告警 `<前缀>-m1-service-health-runs-failed` |
| M2 | Logic App `<前缀>-m2-flash-vm`、`<前缀>-m2-flash-vmss`，以及各自的 `-runs-failed` 指标告警 |
| M3 | 活动日志告警 `<前缀>-m3-resource-health`（每个推送订阅一条） |
| M4 | 指标告警 `<前缀>-m4-vm-cpu-<区域>`、`<前缀>-m4-vm-datadisk-bw-<区域>`（每个推送订阅、每个区域各一对） |
| M5 | Logic App `<前缀>-m5-quota`，指标告警 `<前缀>-m5-quota-runs-failed` |
| M6 | Logic App `<前缀>-m6-scheduled-events`，指标告警 `<前缀>-m6-scheduled-events-runs-failed` |
| M7 | 活动日志告警 `<前缀>-m7-activity-failure`（每个推送订阅一条） |
| M8 | Logic App `<前缀>-m8-aks`，指标告警 `<前缀>-m8-aks-runs-failed` |

删除后再部署时，把对应模块设为 `false`（门户里不勾），就不会再建出来。

## 关键实现说明

- **去重**：Pull 模块按"回看窗口 + 事件指纹"去重。
  - 每分钟查最近 2h，每小时查最近 24h，用于覆盖 ARG 的迟到事件。
  - 已通知的指纹保存在 Logic App **自己的运行历史**里（`State_out` 动作的输出），下一次运行通过 ARM 读取上一次成功运行的结果。
  - 不需要额外的 Storage 资源和授权。（Storage 关闭公网访问时，Consumption Logic App 仍可通过"受信任的 Azure 服务"例外访问，但要额外授予 Blob 数据角色，所以没有采用。）
- **ARG 限制**（实现时踩到的）：
  - 不支持 `let`、`datatable`。
  - `title`、`limit`、`kind` 是保留字。
  - `resources` 和 `computeresources` 不能出现在同一查询里，`healthresources` 和 `computeresources` 也不能。
  - 所以 Flash 的 VM 和 VMSS 分成两个查询；VMSS 事件拿不到订阅名。
- **刚部署完的权限延迟**：部署时给托管身份授予的 Reader 要几分钟才生效，生效前 ARG 可能返回 403，也可能返回**空结果**。
  - 部署后 60 分钟内（`permissionGraceMinutes`），查询 ARG 返回 403 时这次运行标为"已取消"，不触发自检告警，下一次运行自动重试。
  - 超过 60 分钟后返回 403，或者读不到自己的运行历史（去重状态），按失败处理并告警。这样授权被收回时能及时发现，不会悄悄停止工作。
  - 返回空结果的情况由 `bootstrapSilent` 的 30 分钟静默期覆盖：静默期内每次都回看 24 小时、只记录指纹，权限完全生效后补齐的历史事件不会被当成新事件推送。
- **飞书限流**：自定义机器人每个机器人每分钟 100 条、每秒 5 条，超出时返回错误码 11232。
  - Router 收到 11232 或 HTTP 429 时，等待后重新发送同一条消息。等待时间随次数增加：15～30 秒、30～45 秒……；默认最多 8 次，约 10 分钟。
  - 其他错误（例如 9499 消息格式错误）不重试，直接记为失败。
  - 最终仍未发出的消息会记为失败，Router 这次运行标为失败，触发"告警系统自检"告警。
  - 限流是按机器人计算的。告警量大的分类（例如 M7 操作失败、Spot 抢占）建议单独配一个 webhook，避免占用其他分类的额度。
- **卡片正文不截断**：飞书单条消息的请求体上限是 20 KB，正文超过 4000 字时拆成多张连续卡片（"（1/N）""（续 2/N）"）。
- **Flash 分类**：由 `modules/m2-flash/rules.json` 在部署时生成 KQL `case()` 表达式。
  - annotation 名按去掉 `LiveMigration(Not)Eligible` 后缀后的名字精确匹配。
  - 名字缺失时，按真实数据验证过的 summary 关键词兜底。

## 测试

```bash
python scripts/render_query.py m2-flash query-vm.kql 3d > q.kql   # 生成与部署时完全一致的查询，可直接在 ARG 中运行
python scripts/send_events.py events.json                          # 把示例事件推给 Router
python scripts/la_runs.py runs aa-m2-flash-vm 5                    # 查看运行记录和失败的动作
python scripts/la_runs.py sent 3                                    # 查看 Router 最近发出的卡片和飞书的返回
```

```bash
az bicep build -f main.bicep --outfile out.json && python scripts/ci_check.py out.json   # 与 GitHub Actions 相同的检查
```

- `scripts/ci_check.py`：JSON 能否解析、`azuredeploy.json` 是否已按最新 Bicep 重新生成、各模块查询的占位符是否都已替换、部署向导的输出是否都对应模板参数。GitHub Actions（`.github/workflows/validate.yml`）在每次推送时运行它。
- `test/mock-feishu.bicep`：模拟飞书 webhook 的 Logic App，按 URL 参数 `mode` 返回成功、限流（`always` / `half`）或格式错误（`bad`），用来测试限流重试，不会往真实飞书群发消息。

测试参数：复制 `test/test.parameters.example.json` 为 `test/test.parameters.local.json` 并填入自己的订阅和资源组；webhook 放在 `test/webhooks.local.json`。所有 `*.local.json` 都在 .gitignore 中，不会提交。测试脚本通过环境变量 `AA_SUB`、`AA_RG`、`AA_ROUTER` 指定目标。
