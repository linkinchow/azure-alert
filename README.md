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

部署时用 `modules` 参数开关模块，例如 `{"serviceHealth": true, "flash": true}` 表示只部署这两个。

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

   路由规则：先按完整 category（如 `Flash.HostFailure`）找，找不到再按前缀（如 `ServiceHealth`）找，最后用 `default`。要做到"一类一群"，就为每个 category 配一个 webhook。

3. 部署：

   ```bash
   az deployment sub create -l eastus2 -f main.bicep -p location=eastus2 resourceGroupName=rg-azure-alert -p @webhooks.local.json
   ```

   常用参数：

   | 参数 | 说明 |
   |---|---|
   | `readerScope` | `subscription`（默认，对 `readerSubscriptionIds` 中的订阅授予 Reader）或 `none`。选 `none` 时，部署后执行 `scripts/grant-reader-mg.sh <mg> <identityPrincipalId>` 在管理组上授权，新订阅会自动纳入 |
   | `pushSubscriptionIds` | 需要部署 M3 / M4 / M7 告警规则的订阅列表 |
   | `metricRegions` | M4 多资源 metric 规则的区域列表 |
   | `bootstrapSilent` | 默认 `true`：首次运行只记录指纹不发送，避免把历史事件一次性推进群 |

### 一键部署（Deploy to Azure）

- `azuredeploy.json`：由 `az bicep build -f main.bicep --outfile azuredeploy.json` 生成的 ARM 模板，修改 Bicep 后需要重新生成。
- `ui/createUiDefinition.json`：门户部署向导，包含模块勾选、飞书 webhook、范围与权限三步。
- 按钮：

  [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Flinkinchow%2Fazure-alert%2Fmain%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Flinkinchow%2Fazure-alert%2Fmain%2Fui%2FcreateUiDefinition.json)

- 按钮链接格式：`https://portal.azure.com/#create/Microsoft.Template/uri/<azuredeploy.json 的 URL 编码>/createUIDefinitionUri/<createUiDefinition.json 的 URL 编码>`。fork 本仓库后，把链接里的 `linkinchow/azure-alert/main` 换成自己的仓库和分支。
- 验证情况（2026-11-02）：
  - 已验证：按向导输出构造参数，对 `azuredeploy.json` 执行 `az deployment sub validate` 和 `what-if` 均通过，计划创建的资源与勾选的模块一致。
  - 未验证：向导本身在门户中的显示和交互。发布前可以在门户的 [Create UI Definition Sandbox](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/SandboxBlade) 粘贴 `ui/createUiDefinition.json` 预览；发布后再用真实按钮完整走一遍。

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

测试参数：复制 `test/test.parameters.example.json` 为 `test/test.parameters.local.json` 并填入自己的订阅和资源组；webhook 放在 `test/webhooks.local.json`。所有 `*.local.json` 都在 .gitignore 中，不会提交。测试脚本通过环境变量 `AA_SUB`、`AA_RG`、`AA_ROUTER` 指定目标。
