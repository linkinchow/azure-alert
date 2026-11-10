# M9 Key Vault 到期提醒

Key Vault 里的**证书、机密（Secret）、密钥（Key）**快要过期和已经过期时，在飞书群里各提醒一次。

| 分类 | 中文名 | 什么时候 | 级别 |
|---|---|---|---|
| `KeyVault.CertificateNearExpiry` | 证书即将过期 | 到期前 30 天 | 警告 |
| `KeyVault.CertificateExpired` | 证书已过期 | 到期时 | 严重 |
| `KeyVault.SecretNearExpiry` | 机密即将过期 | 到期前 30 天 | 警告 |
| `KeyVault.SecretExpired` | 机密已过期 | 到期时 | 严重 |
| `KeyVault.KeyNearExpiry` | 密钥即将过期 | 到期前 30 天（见"常见问题"） | 警告 |
| `KeyVault.KeyExpired` | 密钥已过期 | 到期时 | 严重 |

卡片示例：

```
警告｜证书即将过期｜kv-prod/api-tls：证书将于 2026-11-30 过期（剩 20 天）
对象类型：证书   对象名：api-tls   版本：…
过期时间（北京时间）：2026-11-30 15:48:06   剩余天数：20
Key Vault kv-prod 中的证书 api-tls（版本 …）将于 2026-11-30 15:48:06（北京时间）过期，请及时更新或轮换。
```

路由键前缀是 `KeyVault`，要单独发到一个群，在"按分类路由"里填 `"KeyVault": "<webhook>"`，或按上表的完整分类分别填。

## 工作原理

Key Vault 会通过 Azure Event Grid 发出到期事件。在每个 Key Vault 上建一个事件订阅，把事件推给告警系统的 Router（一个 Logic App），Router 转成中文卡片发到飞书。

- 不需要读取证书、机密、密钥的权限，也不改动 Key Vault 本身。
- **关闭了公网访问的 Key Vault 也能用**（已实测）。
- 每个 Key Vault 需要单独接入。Event Grid 会在 Key Vault **所在的资源组**里自动创建这个 Key Vault 的"系统主题"（一个 Key Vault 只能有一个；已经有的会直接复用）。
- 只有设置了过期时间的对象才会提醒。

## 接入方式

> **先升级 Router**：2026-11 之前部署的告警系统，Router 还不认识 Key Vault 事件。直接接入的话，事件推过去时 Router 会运行失败（会触发"告警系统自检"告警），卡片发不出来。
> 请先用最新模板**重新部署一次**告警系统，见 README 的[添加、升级或删除模块](../README.md#添加升级或删除模块)：门户再点一次 Deploy to Azure，或者命令行用 `scripts/export-params.py` 导出上次的参数后重新部署。这次部署里可以顺便勾选 M9 接入 Key Vault，也可以不勾，之后用脚本接入。
> 下面的脚本会自动检查：Router 是旧版时只提示升级，不会接入。门户和 CLI 方式没有这个检查，请自己确认已经升级。

| 情况 | 方式 |
|---|---|
| 部署时已有的 Key Vault | 部署向导勾选 **M9 Key Vault 到期提醒**，在"Key Vault（M9）"一步选择要接入的 Key Vault；命令行部署用参数 `keyVaultIds`（见下文） |
| 以后新建的 Key Vault | 用下面的脚本、门户或 CLI 接入 |

**需要的权限**：对 Key Vault 所在资源组有 Event Grid 写权限（EventGrid Contributor 或 Contributor）。

所有方式建出的事件订阅名称都是 `<前缀>-kv-expiry`（前缀默认 `aa`），便于识别和删除。

### 方式一：脚本（推荐，可批量）

在仓库根目录执行（需要 Python 3 和已登录的 Azure CLI）：

```bash
# 列出 Key Vault 和接入状态（不做任何改动）
python scripts/kv-expiry-subscribe.py --prefix aa --resource-group rg-azure-alert

# 接入所有还没接入的 Key Vault
python scripts/kv-expiry-subscribe.py --prefix aa --resource-group rg-azure-alert --apply

# 只接入指定的 Key Vault（名称或资源 ID，可以写多个）
python scripts/kv-expiry-subscribe.py --prefix aa --resource-group rg-azure-alert --vault kv-prod --vault kv-test --apply
```

- `--prefix`、`--resource-group`：部署告警系统时用的前缀和中心资源组，脚本用它们找到 Router。Router 不在当前订阅时，加 `--router-subscription <订阅 ID>`。
- `--subscriptions <订阅 ID> ...`：只扫描这些订阅，默认扫描当前账号能看到的所有订阅。
- 可以定期运行（比如每月一次），把新建的 Key Vault 接进来；已经接入的会跳过。
- 脚本会先检查 Router 是否支持 Key Vault 事件：是旧版时，列出模式下给出警告，`--apply` 会直接退出、不做任何改动。

### 方式二：Azure 门户

1. 先取得 Router 的回调地址：门户打开 Logic App `<前缀>-router` → 左侧"Logic App 设计器" → 点触发器"When a HTTP request is received" → 复制 **HTTP URL**。**这个地址带签名，相当于密码，不要外传。**
2. 打开要接入的 Key Vault → 左侧"**事件**（Events）" → "**+ 事件订阅**"：
   - 名称：`<前缀>-kv-expiry`；
   - 事件架构：**Event Grid 架构**（Event Grid Schema），不要选云事件架构；
   - 系统主题名称：没有系统主题时门户会让你填一个名字，随意；已有时不需要填；
   - 筛选到事件类型：只勾 **Certificate Near Expiry、Certificate Expired、Secret Near Expiry、Secret Expired、Key Near Expiry、Key Expired** 这 6 项；
   - 终结点类型：**Web Hook**，终结点填第 1 步复制的 URL；
   - 创建。

### 方式三：Azure CLI

```bash
# Router 的回调地址（带签名，不要外传）
ROUTER_URL=$(az rest --method post --query value -o tsv \
  --url "https://management.azure.com/subscriptions/<告警订阅 ID>/resourceGroups/rg-azure-alert/providers/Microsoft.Logic/workflows/aa-router/triggers/manual/listCallbackUrl?api-version=2019-05-01")

# 在 Key Vault 上建事件订阅
az eventgrid event-subscription create \
  --source-resource-id "/subscriptions/<订阅 ID>/resourceGroups/<资源组>/providers/Microsoft.KeyVault/vaults/<Key Vault 名>" \
  --name aa-kv-expiry \
  --endpoint-type webhook --endpoint "$ROUTER_URL" \
  --event-delivery-schema eventgridschema \
  --included-event-types Microsoft.KeyVault.CertificateNearExpiry Microsoft.KeyVault.CertificateExpired \
      Microsoft.KeyVault.SecretNearExpiry Microsoft.KeyVault.SecretExpired \
      Microsoft.KeyVault.KeyNearExpiry Microsoft.KeyVault.KeyExpired
```

在 Windows 的 cmd 里，回调地址中的 `&` 会被当成命令分隔符，请用 bash（Git Bash、Cloud Shell）或 PowerShell 执行，或者直接用方式一的脚本。

### 部署时接入（命令行）

在参数文件里加上：

```json
"modules": { "value": { "...": true, "keyVaultExpiry": true } },
"keyVaultIds": { "value": [
  "/subscriptions/<订阅 ID>/resourceGroups/<资源组>/providers/Microsoft.KeyVault/vaults/<Key Vault 名>"
] }
```

## 验证

在已接入的 Key Vault 里建一个 20 天后过期的测试机密，约 10 分钟后群里应该收到"机密即将过期"卡片：

```bash
az keyvault secret set --vault-name <Key Vault 名> -n alert-test --value test --expires $(date -u -d '+20 days' +%Y-%m-%dT%H:%M:%SZ)
```

（Key Vault 关闭了公网访问时，这条命令会被防火墙拒绝；可以在门户里建，或者用能访问它的机器执行。测完删除这个机密。）

## 取消接入

```bash
# 列出已接入的 Key Vault，再删除事件订阅
python scripts/kv-expiry-subscribe.py --prefix aa --resource-group rg-azure-alert --remove
python scripts/kv-expiry-subscribe.py --prefix aa --resource-group rg-azure-alert --remove --apply
```

也可以在门户的 Key Vault →"事件"→"事件订阅"里删除 `<前缀>-kv-expiry`。系统主题如果是 Event Grid 自动创建的，删除最后一个订阅时会自动删除；是客户自己建的则保留。

以后重新部署告警系统时，把 `keyVaultExpiry` 设为 `false`（门户里不勾 M9），否则会按 `keyVaultIds` 再建出来。

## 常见问题

- **"即将过期"只提醒一次**：Key Vault 只在到期前 30 天发一次事件，到期时再发一次"已过期"。对象接入或创建时已经在 30 天以内的，约 10 分钟后补发一次（实测证书、机密、密钥都是如此）。
- **密钥的"即将过期"**：官方文档说这个事件的时间可以通过密钥轮换策略配置。实测（2026-11）：20 天后过期的密钥，无论有没有轮换策略，接入后约 10 分钟都收到了"即将过期"事件。
- **没有设置过期时间的对象**不会有提醒。
- **更新了证书 / 机密 / 密钥**（新版本）后，按新版本的过期时间重新计算。
- **Event Grid 是"至少一次"投递**，极少数情况下同一提醒可能收到两次。
- **新建的 Key Vault 不会自动接入**，需要重新运行脚本或手动接入。
