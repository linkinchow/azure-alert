"""Remove deployed azure-alert modules (redeploying with a module turned off does not delete it).

  python scripts/remove-module.py --module m5                       # list what would be deleted (nothing is changed)
  python scripts/remove-module.py --module m5 --module m7 --apply   # delete
  python scripts/remove-module.py --prefix aa --resource-group rg-azure-alert --module m4

Finds the module's resources with Azure Resource Graph across every subscription the signed-in account can read:
name starts with "<prefix>-m<N>-", type is a Logic App, metric alert or activity log alert, and the resource group is the
central resource group or the push resource group (M3 / M4 / M7 rules live in the push resource group of every push
subscription). Without --apply it only lists them.

After deleting, set the module to false in the parameters (or leave it unticked in the portal) for later deployments,
otherwise the next deployment creates it again. Deleting a pull module (M1 / M2 / M5 / M6 / M8) also deletes its
de-duplication history; if it is added back later, "bootstrapSilent" keeps the first 30 minutes quiet.
"""
import argparse
import json
import subprocess
import sys

MODULES = {
    'm1': 'M1 service health', 'm2': 'M2 Project Flash', 'm3': 'M3 resource health', 'm4': 'M4 metrics',
    'm5': 'M5 compute quota', 'm6': 'M6 scheduled events', 'm7': 'M7 activity failures', 'm8': 'M8 AKS',
}
TYPES = ['microsoft.logic/workflows', 'microsoft.insights/metricalerts', 'microsoft.insights/activitylogalerts']

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('--module', action='append', required=True, choices=sorted(MODULES), help='module to remove (repeatable)')
ap.add_argument('--prefix', default='aa', help='resource name prefix used at deployment (default aa)')
ap.add_argument('--resource-group', default='rg-azure-alert', help='central resource group (default rg-azure-alert)')
ap.add_argument('--push-resource-group', help='resource group of the M3 / M4 / M7 rules in each push subscription (default: same as --resource-group)')
ap.add_argument('--apply', action='store_true', help='delete the listed resources')
args = ap.parse_args()
groups = {args.resource_group.lower(), (args.push_resource_group or args.resource_group).lower()}
sys.stdout.reconfigure(encoding='utf-8')


def az(cmd):
    r = subprocess.run(['az', *cmd], capture_output=True, text=True, shell=sys.platform == 'win32')
    if r.returncode != 0:
        sys.exit(r.stderr.strip())
    return r.stdout


def find(module):
    q = ("resources"
         f" | where type in~ ({', '.join(repr(t) for t in TYPES)})"
         f" | where name startswith '{args.prefix}-{module}-'"
         f" | where resourceGroup in~ ({', '.join(repr(g) for g in sorted(groups))})"
         " | project id, name, type, resourceGroup, subscriptionId | order by subscriptionId asc, name asc")
    rows, skip = [], None
    while True:
        cmd = ['graph', 'query', '-q', q, '--first', '1000', '-o', 'json']
        if skip:
            cmd += ['--skip-token', skip]
        out = json.loads(az(cmd))
        rows += out['data']
        skip = out.get('skip_token')
        if not skip:
            return rows


found = []
for m in args.module:
    rows = find(m)
    print(f'== {MODULES[m]} ({args.prefix}-{m}-*): {len(rows)} resource(s)')
    for r in rows:
        print(f"   {r['type'].split('/')[-1]:<18} {r['name']:<45} rg={r['resourceGroup']}  subscription={r['subscriptionId']}")
    found += rows

if not found:
    print('Nothing to delete. Check --prefix / --resource-group, and that the signed-in account can read the subscriptions.')
    sys.exit(0)
if not args.apply:
    print(f'(list only - nothing was deleted; add --apply to delete these {len(found)} resource(s))')
    sys.exit(0)

failed = 0
for r in found:
    res = subprocess.run(['az', 'resource', 'delete', '--ids', r['id']], capture_output=True, text=True, shell=sys.platform == 'win32')
    if res.returncode == 0:
        print('   deleted', r['name'])
    else:
        failed += 1
        print('   FAILED ', r['name'], '-', (res.stderr.strip().splitlines() or [''])[-1][:200])
print(f'{len(found) - failed} deleted, {failed} failed.',
      'Set these modules to false (or untick them) in later deployments, otherwise they are created again.')
sys.exit(1 if failed else 0)
