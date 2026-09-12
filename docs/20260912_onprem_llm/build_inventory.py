"""Static source audit; no application imports, network, or model calls.

Run from any directory: python3 docs/20260912_onprem_llm/build_inventory.py
Requires Node and the repository's existing TypeScript package.
Candidate expressions are not proof of runtime reachability or final rendered prompts.
"""
import ast
import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

OUT = Path(__file__).resolve().parent
ROOT = OUT.parent.parent

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()

def dump(name, data):
    (OUT / name).write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')

files = git('ls-files', 'backend/lib/galaxy/ai', 'backend/lib/galaxy/webapps/galaxy/api',
            'backend/lib/galaxy/jobs/runners', 'frontend/server', 'backend/scripts',
            'auto_update/scripts', 'connectors', 'evaluation').splitlines()
records = json.loads(subprocess.check_output(['node', str(OUT/'extract_ts_prompts.cjs')], text=True))
calls = []
errors = []
scanned = []
source_hashes = {}
call_re = re.compile(r'(?:llm(?:_client)?|client|claude|anthropic|openai|_anthropic|llm_client|self\.llm)\.(?:generate(?:_async|_structured)?|call|messages\.create|chat\.completions\.create)\s*\(|(?:llmGenerate|callGeminiFlash(?:Simple)?|call_gemini_flash(?:_vision)?|_gemini_flash|_gemini_vision|_gemini|_call_llm|generateContent|_call_local_regulatory_llm|_call_vllm_regulatory_llm)\s*\(')
for file in files:
    p = ROOT/file
    if p.suffix not in ('.py', '.ts', '.js') or re.search(r'(^|/)(tests?|__tests__)/|\.test\.|/test_|prototype', file):
        continue
    source = p.read_text(errors='replace')
    scanned.append(file)
    source_hashes[file] = hashlib.sha256(source.encode()).hexdigest()
    for i, line in enumerate(source.splitlines(), 1):
        if call_re.search(line) and not line.lstrip().startswith(('#', '//', '*')):
            calls.append({'file':file, 'line':i, 'source':line.strip(), 'classification':'static candidate; includes wrappers/definitions; verify reachability'})
    if p.suffix != '.py':
        continue
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        errors.append({'file':file, 'error':str(e)})
        continue
    for node in ast.walk(tree):
        value = None
        label = ''
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            label = ','.join(ast.unparse(t) for t in targets)
            if re.search(r'prompt|system|instructions', label, re.I):
                value = node.value
        elif isinstance(node, ast.keyword) and node.arg in ('system', 'system_prompt'):
            label, value = node.arg, node.value
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == 'append' and 'prompt' in ast.unparse(node.func.value).lower() and node.args:
            label, value = ast.unparse(node.func), node.args[0]
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and re.search(r'build.*(?:prompt|system)|.*prompt$', node.name, re.I):
            label, value = 'builder:' + node.name, node
        if value is not None:
            expression = ast.get_source_segment(source, value) or ''
            if len(expression) > 35:
                records.append({'file':file,'start':value.lineno,'end':value.end_lineno,'label':label,'language':'python','source_expression':expression,'source_file_sha256':source_hashes[file]})
records.sort(key=lambda x: (x['file'], x['start'], x['end'], x['label']))
for i, r in enumerate(records, 1):
    r['id'] = f'P{i:04d}'
    r['sha256'] = hashlib.sha256(r['source_expression'].encode()).hexdigest()
dump('prompt_registry.json', records)
dump('callsite_inventory.json', calls)

profiles = []
split_hashes = {}
for p in sorted((ROOT/'data/regulatory_training').rglob('*.jsonl')):
    n, invalid, keys, tasks, hashes = 0, 0, Counter(), Counter(), set()
    for line in p.open():
        if not line.strip(): continue
        n += 1
        try: row = json.loads(line)
        except json.JSONDecodeError: invalid += 1; continue
        if isinstance(row, dict):
            keys.update(row.keys())
            meta = row.get('meta') if isinstance(row.get('meta'), dict) else {}
            tasks[str(row.get('task', row.get('task_type', meta.get('task', meta.get('task_type','unspecified')))))] += 1
            canonical = json.dumps(row.get('messages', {k:v for k,v in row.items() if k in ('prompt','completion','response','chosen','rejected')}), sort_keys=True, ensure_ascii=False)
            if canonical not in ('{}','null'): hashes.add(hashlib.sha256(canonical.encode()).hexdigest())
    rel = str(p.relative_to(ROOT))
    profiles.append({'file':rel,'rows':n,'invalid_json':invalid,'keys':dict(keys),'tasks':dict(tasks),'distinct_content_hashes':len(hashes)})
    if p.parent.name.startswith('splits'): split_hashes[rel] = hashes
overlaps = []
for a, ah in split_hashes.items():
    for b, bh in split_hashes.items():
        if a < b and Path(a).parent == Path(b).parent:
            overlaps.append({'a':a,'b':b,'exact_content_overlap':len(ah & bh)})
dump('data_profile.json', {'files':profiles,'within_version_exact_split_overlaps':overlaps,
                         'limitation':'Content equality only. Does not detect compound/study/source/template-family or semantic leakage. Combined files and split files overlap by design; do not sum as independent examples.'})
manifest = {'commit':git('rev-parse','HEAD'),'date':'2026-09-12','scanned_file_count':len(scanned),
            'prompt_expression_count':len(records),'callsite_candidate_count':len(calls),'parse_errors':errors,
            'scope':'Tracked files in configured directories; excludes tests/prototypes. External library prompts, runtime skills and final assembled requests require runtime capture. Broad static candidates are not an active-call count.',
            'scanned_files':scanned, 'source_file_sha256':source_hashes,
            'snapshot_note':'Base commit plus local working tree; concurrent unrelated edits may exist. Expression and source-file hashes identify extracted content. This script does not modify application files.'}
dump('audit_manifest.json',manifest)
md = ['# Exact prompt source appendix', '',
      f"Base commit: `{manifest['commit']}` plus local working tree. Generated from local source on 2026-09-12. Source/expression hashes are recorded in the JSON registry.", '',
      'These are exact source expressions, including placeholders, escaping, concatenation and branches. They are NOT fabricated examples or final rendered production requests. Some entries are auxiliary fragments or unused paths. The task catalog identifies reviewed tasks. Capture runtime messages, tools, retrieval and skill versions to reconstruct actual model input.', '',
      'Search by filename, symbol, or P identifier. `prompt_registry.json` is the machine-readable equivalent.', '']
last = None
for r in records:
    if r['file'] != last:
        md += [f"## {r['file']}", '']
        last = r['file']
    md += [f"### {r['id']} — {r['label']} (lines {r['start']}–{r['end']})", '',
           f"[Open source]({ROOT/r['file']}:{r['start']}) · SHA-256 `{r['sha256']}`", '',
           '````'+r['language'],r['source_expression'],'````','']
(OUT/'PROMPT_APPENDIX.md').write_text('\n'.join(md))
print(json.dumps({k:v for k,v in manifest.items() if k not in ('scanned_files','source_file_sha256')}, indent=2))
