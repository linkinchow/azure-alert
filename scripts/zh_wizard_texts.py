"""Regenerate section 6 (deployment wizard texts) of docs/zh-text-list.md from ui/createUiDefinition.json.

  python scripts/zh_wizard_texts.py
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
src = (ROOT / 'ui' / 'createUiDefinition.json').read_text(encoding='utf-8')
lines = src.split('\n')
rows, seen = [], set()
KINDS = {'label': 'label', 'toolTip': 'tooltip', 'description': '说明', 'validationMessage': '校验提示', 'password': 'label',
         'confirmPassword': 'label', 'text': '说明框'}


def lineno(text):
    needle = json.dumps(text, ensure_ascii=False)[1:-1]
    return next((i for i, line in enumerate(lines, 1) if needle in line), 10 ** 6)


def add(kind, text):
    if not isinstance(text, str) or not re.search(r'[一-鿿]', text) or (kind, text) in seen:
        return
    seen.add((kind, text))
    rows.append((lineno(text), kind, text.replace('|', '\\|').replace('\n', ' ')))


def walk(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == 'allowedValues' and isinstance(v, list):
                for a in v:
                    if isinstance(a, dict):
                        add('选项', a.get('label'))
                        add('选项说明', a.get('description'))
                continue
            if k in KINDS and isinstance(v, str):
                add(KINDS[k], v)
            walk(v)
    elif isinstance(node, list):
        for x in node:
            walk(x)


P = json.loads(src)['parameters']
walk(P['config'])
walk(P['basics'])
for step in P['steps']:
    add('步骤', step['label'])
    walk(step['elements'])
rows.sort()

doc = ROOT / 'docs' / 'zh-text-list.md'
s = doc.read_text(encoding='utf-8')
start = s.index('## 6. 部署向导 ui/createUiDefinition.json')
end = s.index('\n---\n', start)
section = ('## 6. 部署向导 ui/createUiDefinition.json\n\n'
           '由 `scripts/zh_wizard_texts.py` 从向导文件生成。"告警模块"是多选下拉框（默认全选），"首次运行静默""写入 Log Analytics"是"是 / 否"单选，以便在审阅页显示；'
           '"按分类路由"预填了各模块的分类前缀（值为空，留空的发到默认 webhook）。\n\n'
           '| 行 | 类型 | 文字 |\n|---|---|---|\n' + '\n'.join(f'| {n} | {k} | {t} |' for n, k, t in rows) + '\n')
doc.write_text(s[:start] + section + s[end:], encoding='utf-8', newline='\n')
print(len(rows), 'rows')
