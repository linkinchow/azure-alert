"""Repository checks, run by GitHub Actions and usable locally.

  az bicep build -f main.bicep --outfile /tmp/built.json
  python scripts/ci_check.py /tmp/built.json

1. Every tracked *.json file parses.
2. azuredeploy.json matches a fresh build of main.bicep (ignoring metadata._generator), i.e. it was regenerated after the last Bicep change.
3. Every module query renders without leftover __PLACEHOLDER__ tokens.
4. Every output of ui/createUiDefinition.json is a parameter of azuredeploy.json.
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
from render_query import render  # noqa: E402

errors = []


def load(path):
    return json.loads(pathlib.Path(path).read_text(encoding='utf-8'))


def strip_generator(node):
    if isinstance(node, dict):
        return {k: strip_generator(v) for k, v in node.items() if k != '_generator'}
    if isinstance(node, list):
        return [strip_generator(v) for v in node]
    return node


# 1. JSON files parse.
files = subprocess.check_output(['git', 'ls-files', '*.json'], cwd=ROOT, text=True).split()
for f in files:
    try:
        load(ROOT / f)
    except Exception as e:  # noqa: BLE001
        errors.append(f'{f}: invalid JSON ({e})')

# 2. azuredeploy.json is up to date.
if len(sys.argv) > 1:
    if strip_generator(load(sys.argv[1])) != strip_generator(load(ROOT / 'azuredeploy.json')):
        errors.append('azuredeploy.json is out of date: run  az bicep build -f main.bicep --outfile azuredeploy.json')
else:
    print('skip: no freshly built template given, azuredeploy.json not compared')

# 3. Queries render completely.
queries = [('m1-service-health', 'query.kql'), ('m2-flash', 'query-vm.kql'), ('m2-flash', 'query-vmss.kql'), ('m5-quota', 'query.kql'),
           ('m6-scheduled-events', 'query.kql'), ('m8-aks', 'query.kql')]
for module, query in queries:
    left = sorted(set(re.findall(r'__[A-Z_]+__', render(module, query, '2h'))))
    if left:
        errors.append(f'modules/{module}/{query}: placeholders not replaced by render_query.py: {left}')

# 4. Wizard outputs map to template parameters.
template_params = load(ROOT / 'azuredeploy.json')['parameters']
for name in load(ROOT / 'ui' / 'createUiDefinition.json')['parameters']['outputs']:
    if name not in template_params:
        errors.append(f'ui/createUiDefinition.json: output "{name}" is not a parameter of azuredeploy.json')

for e in errors:
    print('ERROR', e)
print(f'{len(files)} JSON files, {len(queries)} queries checked, {len(errors)} error(s)')
sys.exit(1 if errors else 0)
