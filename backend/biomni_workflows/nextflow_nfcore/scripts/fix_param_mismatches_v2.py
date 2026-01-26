#!/usr/bin/env python3
"""
Fix parameter mismatches in Nextflow workflows - Version 2.
More careful approach that doesn't corrupt files.
"""

import os
import re
import json
from pathlib import Path

SUBWORKFLOWS_DIR = Path('subworkflows')


def parse_function_params(params_str):
    """Parse function parameters, handling type hints."""
    params = []
    for p in params_str.split(','):
        p = p.strip()
        if not p:
            continue
        # Remove type hints (e.g., "param: str" -> "param")
        p = p.split(':')[0].strip()
        # Remove default values (e.g., "param=None" -> "param")
        p = p.split('=')[0].strip()
        if p:
            params.append(p)
    return params


def analyze_workflow(wf_path):
    """Analyze a workflow and return mismatch info."""
    main_nf = wf_path / 'main.nf'
    if not main_nf.exists():
        return None, "No main.nf"

    with open(main_nf) as f:
        content = f.read()

    # Extract NF params
    nf_params = re.findall(r"params\.(\w+)\s*=\s*null", content)
    nf_params = [p for p in nf_params if p != 'outdir']

    # Find the main function (not auto_convert, not prefix)
    func_pattern = r"def\s+(\w+)\(([^)]*)\)\s*(?:->[^:]+)?:"
    matches = re.findall(func_pattern, content)

    func_name = None
    func_params = []
    for name, params_str in matches:
        if name not in ('auto_convert', 'prefix'):
            func_name = name
            func_params = parse_function_params(params_str)
            break

    if not func_name:
        return None, "No function found"

    # Extract function call params
    call_pattern = rf"result\s*=\s*{func_name}\(\s*\n([\s\S]*?)\s*\)"
    call_match = re.search(call_pattern, content)
    call_params = []
    if call_match:
        call_body = call_match.group(1)
        call_params = re.findall(r"(\w+)=auto_convert", call_body)

    return {
        'content': content,
        'func_name': func_name,
        'func_params': func_params,
        'nf_params': nf_params,
        'call_params': call_params,
    }, None


def fix_workflow(wf_path, info):
    """Fix a workflow by aligning params."""
    content = info['content']
    func_name = info['func_name']
    func_params = info['func_params']
    nf_params = info['nf_params']
    call_params = info['call_params']

    # Already aligned?
    if set(func_params) == set(call_params) == set(nf_params):
        return False, "Already aligned"

    # The function signature is the source of truth
    # We need to:
    # 1. Update NF params to match function params
    # 2. Update exports to match function params
    # 3. Update function call to match function params

    new_content = content

    # Step 1: Fix params declarations
    # Remove old params and add correct ones
    params_section_pattern = r"(params\.outdir\s*=\s*'[^']*'\n)((?:params\.\w+\s*=\s*null\n)*)"

    def replace_params(match):
        outdir_line = match.group(1)
        new_params = "".join(f"params.{p} = null\n" for p in func_params)
        return outdir_line + new_params

    new_content = re.sub(params_section_pattern, replace_params, new_content)

    # Step 2: Fix export statements
    export_section_pattern = r"(# Export parameters as environment variables\n)((?:\s*export PARAM_\w+=\"[^\"]*\"\n)*)"

    def replace_exports(match):
        header = match.group(1)
        new_exports = ""
        for p in func_params:
            new_exports += f'    export PARAM_{p.upper()}="${{params.{p}?.toString()?.replace(\'"\', \'\\\\"\') ?: \'null\'}}"\n'
        return header + new_exports

    new_content = re.sub(export_section_pattern, replace_exports, new_content)

    # Step 3: Fix function call
    old_call_pattern = rf"(result\s*=\s*{func_name}\(\s*\n)([\s\S]*?)(\s*\))"

    def replace_call(match):
        prefix = match.group(1)
        suffix = match.group(3)
        new_args = ""
        for p in func_params:
            new_args += f'        {p}=auto_convert(os.environ.get("PARAM_{p.upper()}", "")),\n'
        return prefix + new_args + "    " + suffix.strip()

    new_content = re.sub(old_call_pattern, replace_call, new_content, count=1)

    # Verify the content is valid (basic check)
    if new_content.count('result = ') != 1:
        return False, "Fix would corrupt file"

    # Write back
    main_nf = wf_path / 'main.nf'
    with open(main_nf, 'w') as f:
        f.write(new_content)

    return True, "Fixed"


def main():
    fixed = []
    skipped = []
    errors = []

    for domain in sorted(os.listdir(SUBWORKFLOWS_DIR)):
        domain_path = SUBWORKFLOWS_DIR / domain
        if not domain_path.is_dir():
            continue

        for wf in sorted(os.listdir(domain_path)):
            wf_path = domain_path / wf
            if not wf_path.is_dir():
                continue

            wf_key = f"{domain}/{wf}"

            # Analyze
            info, error = analyze_workflow(wf_path)
            if error:
                errors.append({'workflow': wf_key, 'error': error})
                continue

            # Check if needs fixing
            if set(info['func_params']) == set(info['call_params']) == set(info['nf_params']):
                skipped.append(wf_key)
                continue

            # Fix
            success, msg = fix_workflow(wf_path, info)
            if success:
                fixed.append({
                    'workflow': wf_key,
                    'func_params': info['func_params'],
                    'old_nf_params': info['nf_params'],
                    'old_call_params': info['call_params']
                })
                print(f"✓ Fixed: {wf_key}")
            else:
                errors.append({'workflow': wf_key, 'error': msg})

    print(f"\n{'='*60}")
    print(f"Fixed: {len(fixed)}")
    print(f"Skipped (already ok): {len(skipped)}")
    print(f"Errors: {len(errors)}")

    if errors:
        print("\nErrors:")
        for e in errors[:20]:
            print(f"  - {e['workflow']}: {e['error']}")

    # Save report
    with open('test_data/fix_report_v2.json', 'w') as f:
        json.dump({'fixed': fixed, 'skipped': skipped, 'errors': errors}, indent=2, fp=f)
    print(f"\nReport saved to test_data/fix_report_v2.json")


if __name__ == '__main__':
    main()
