"""Export the parameters of an earlier azure-alert deployment into a parameter file, for adding / upgrading modules.

  python scripts/export-params.py                        # list azure-alert deployments in the current subscription
  python scripts/export-params.py <deployment name> > deploy.local.json

Run it in the subscription the deployment was made in (az account set --subscription ...).
The deployment record keeps every parameter except the secure ones: defaultWebhook and webhooks come out as
placeholders and must be filled in again. deploymentTime is left out so the next deployment uses the current time.
Then edit "modules" (set the new module to true) and deploy with the same command as the first time:

  az deployment sub create -l <location> -n azure-alert -f main.bicep -p @deploy.local.json
"""
import json
import subprocess
import sys

SECURE_PLACEHOLDERS = {
    'defaultWebhook': 'https://open.feishu.cn/open-apis/bot/v2/hook/<fill in the default webhook again>',
    'webhooks': {},
}
SKIP = {'deploymentTime'}


def az(*args):
    out = subprocess.run(['az', *args, '-o', 'json'], capture_output=True, text=True, shell=sys.platform == 'win32')
    if out.returncode != 0:
        sys.exit(out.stderr.strip())
    return json.loads(out.stdout or 'null')


def is_azure_alert(d):
    params = (d.get('properties') or {}).get('parameters') or {}
    return 'modules' in params and 'prefix' in params and 'resourceGroupName' in params


if len(sys.argv) < 2:
    rows = [d for d in az('deployment', 'sub', 'list') if is_azure_alert(d)]
    rows.sort(key=lambda d: d['properties']['timestamp'], reverse=True)
    print('azure-alert deployments in this subscription (newest first):', file=sys.stderr)
    for d in rows:
        p = d['properties']['parameters']
        on = [k for k, v in (p['modules'].get('value') or {}).items() if v]
        print(f"  {d['name']:<40} {d['properties']['timestamp'][:19]}  {d['properties']['provisioningState']:<10} "
              f"prefix={p['prefix']['value']}  rg={p['resourceGroupName']['value']}  modules={','.join(on)}", file=sys.stderr)
    sys.exit(0)

d = az('deployment', 'sub', 'show', '-n', sys.argv[1])
if not is_azure_alert(d):
    sys.exit(f'{sys.argv[1]} is not an azure-alert deployment')
out = {}
for name, p in d['properties']['parameters'].items():
    if name in SKIP:
        continue
    if p.get('type', '').lower().startswith('secure'):
        out[name] = {'value': SECURE_PLACEHOLDERS.get(name, '<secure value: fill in again>')}
    else:
        out[name] = {'value': p.get('value')}
sys.stdout.reconfigure(encoding='utf-8')
print('Fill in again: defaultWebhook, and webhooks if you route categories to several Feishu groups '
      '(the deployment record does not keep secure values). Then set the modules you want to true.', file=sys.stderr)
print(json.dumps({'$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#',
                  'contentVersion': '1.0.0.0', 'parameters': out}, ensure_ascii=False, indent=2))
