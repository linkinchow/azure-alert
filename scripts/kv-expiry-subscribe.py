"""M9 Key Vault expiry: connect Key Vaults to the Router (one Event Grid subscription per vault).

  python scripts/kv-expiry-subscribe.py                                   # list Key Vaults and whether they are connected (no changes)
  python scripts/kv-expiry-subscribe.py --apply                           # connect every vault that is not connected yet
  python scripts/kv-expiry-subscribe.py --vault kv-a --vault kv-b --apply # only these vaults (name or resource ID)
  python scripts/kv-expiry-subscribe.py --remove --apply                  # remove the subscriptions created by this solution

Common options: --prefix (default aa) and --resource-group (default rg-azure-alert) locate the Router <prefix>-router;
--router-subscription if the Router is not in the current subscription; --subscriptions limits which subscriptions are
scanned (default: every subscription the signed-in account can read).

What --apply does for each vault: creates the Event Grid subscription <prefix>-kv-expiry directly on the vault, sending
certificate / secret / key NearExpiry and Expired events to the Router's callback URL. Event Grid creates the vault's
system topic in the vault's resource group, or reuses the existing one (a vault can only have one). Nothing on the vault
itself changes. Needs Event Grid write access on the vault's resource group (EventGrid Contributor or Contributor).
Run it again from time to time to connect Key Vaults created later.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile

EVENT_TYPES = ['Microsoft.KeyVault.CertificateNearExpiry', 'Microsoft.KeyVault.CertificateExpired',
               'Microsoft.KeyVault.SecretNearExpiry', 'Microsoft.KeyVault.SecretExpired',
               'Microsoft.KeyVault.KeyNearExpiry', 'Microsoft.KeyVault.KeyExpired']

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('--prefix', default='aa')
ap.add_argument('--resource-group', default='rg-azure-alert', help='central resource group that holds <prefix>-router')
ap.add_argument('--router-subscription', help='subscription of the Router (default: current az subscription)')
ap.add_argument('--subscriptions', nargs='*', help='subscriptions to scan (default: all readable)')
ap.add_argument('--vault', action='append', help='only these vaults (name or resource ID; repeatable)')
ap.add_argument('--remove', action='store_true', help='remove the subscriptions instead of creating them')
ap.add_argument('--apply', action='store_true', help='make the changes (default: list only)')
args = ap.parse_args()
NAME = f'{args.prefix}-kv-expiry'
sys.stdout.reconfigure(encoding='utf-8')


def az(cmd, check=True):
    r = subprocess.run(['az', *cmd], capture_output=True, text=True, shell=sys.platform == 'win32')
    if check and r.returncode != 0:
        sys.exit(r.stderr.strip())
    return r


def vaults():
    q = "resources | where type =~ 'microsoft.keyvault/vaults' | project id, name, resourceGroup, subscriptionId | order by subscriptionId asc, name asc"
    rows, skip = [], None
    while True:
        cmd = ['graph', 'query', '-q', q, '--first', '1000', '-o', 'json']
        if args.subscriptions:
            cmd += ['--subscriptions', *args.subscriptions]
        if skip:
            cmd += ['--skip-token', skip]
        out = json.loads(az(cmd).stdout)
        rows += out['data']
        skip = out.get('skip_token')
        if not skip:
            break
    if args.vault:
        want = {v.lower() for v in args.vault}
        rows = [r for r in rows if r['name'].lower() in want or r['id'].lower() in want]
    return rows


def connected(vault_id):
    r = az(['eventgrid', 'event-subscription', 'show', '--source-resource-id', vault_id, '-n', NAME, '-o', 'json'], check=False)
    return r.returncode == 0


def router_url():
    sub = args.router_subscription or json.loads(az(['account', 'show', '-o', 'json']).stdout)['id']
    rid = f'/subscriptions/{sub}/resourceGroups/{args.resource_group}/providers/Microsoft.Logic/workflows/{args.prefix}-router'
    r = az(['rest', '--method', 'post', '--url', f'https://management.azure.com{rid}/triggers/manual/listCallbackUrl?api-version=2019-05-01',
            '--query', 'value', '-o', 'tsv'], check=False)
    if r.returncode != 0:
        sys.exit(f'Cannot get the callback URL of {rid}. Check --prefix / --resource-group / --router-subscription.\n{r.stderr.strip()[-300:]}')
    return r.stdout.strip()


rows = vaults()
print(f'{len(rows)} Key Vault(s); subscription name on each vault: {NAME}')
todo = []
for r in rows:
    on = connected(r['id'])
    print(f"   {'connected    ' if on else 'not connected'}  {r['name']:<26} rg={r['resourceGroup']}  subscription={r['subscriptionId']}")
    if on == args.remove:
        todo.append(r)
action = 'remove' if args.remove else 'connect'
done = 'removed' if args.remove else 'connected'
if not todo:
    print(f'Nothing to {action}.')
    sys.exit(0)
if not args.apply:
    print(f'(list only - nothing was changed; add --apply to {action} {len(todo)} Key Vault(s))')
    sys.exit(0)

url = None if args.remove else router_url()
failed = 0
for r in todo:
    if args.remove:
        cmd = ['eventgrid', 'event-subscription', 'delete', '--source-resource-id', r['id'], '-n', NAME]
    else:
        # The callback URL contains '&': pass it in a body file, never on the command line (cmd.exe would split it).
        body = {'properties': {'destination': {'endpointType': 'WebHook', 'properties': {'endpointUrl': url}},
                               'filter': {'includedEventTypes': EVENT_TYPES}, 'eventDeliverySchema': 'EventGridSchema',
                               'retryPolicy': {'maxDeliveryAttempts': 30, 'eventTimeToLiveInMinutes': 1440}}}
        fd, path = tempfile.mkstemp(suffix='.json')
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            json.dump(body, f)
        cmd = ['rest', '--method', 'put', '--body', f'@{path}', '-o', 'none', '--url',
               f"https://management.azure.com{r['id']}/providers/Microsoft.EventGrid/eventSubscriptions/{NAME}?api-version=2025-02-15"]
    res = az(cmd, check=False)
    if not args.remove:
        os.remove(path)
    if res.returncode == 0:
        print(f"   {done} {r['name']}")
    else:
        failed += 1
        print(f"   FAILED {r['name']} - {(res.stderr.strip().splitlines() or [''])[-1][:200]}")
print(f'{len(todo) - failed} {done}, {failed} failed.')
sys.exit(1 if failed else 0)
