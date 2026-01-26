#!/usr/bin/env python3
"""
Fix parameter mismatches in Nextflow workflows.

The bug: Function calls use NF param names instead of matching the Python function signature.
This script aligns the NF params and function calls to match the Python function definition.
"""

import os
import re
import json
from pathlib import Path

SUBWORKFLOWS_DIR = Path('subworkflows')

def extract_function_info(content):
    """Extract Python function name and parameters from workflow."""
    # Find the main function definition (not auto_convert, not prefix)
    # Handle type hints like: def func(param1: str, param2: int) -> dict:
    func_pattern = r"def\s+(\w+)\(([^)]*)\)\s*(?:->[^:]+)?:\s*\n\s*['\"]"
    match = re.search(func_pattern, content)
    if not match:
        # Try without docstring
        func_pattern = r"def\s+(\w+)\(([^)]*)\)\s*(?:->[^:]+)?:\s*\n"
        matches = re.findall(func_pattern, content)
        # Filter out auto_convert and prefix
        for name, params in matches:
            if name not in ('auto_convert', 'prefix'):
                # Parse params, handling type hints
                param_list = []
                for p in params.split(','):
                    p = p.strip()
                    if not p:
                        continue
                    # Remove type hints (e.g., "param: str" -> "param")
                    p = p.split(':')[0].strip()
                    # Remove default values (e.g., "param=None" -> "param")
                    p = p.split('=')[0].strip()
                    if p:
                        param_list.append(p)
                return name, param_list
        return None, []

    func_name = match.group(1)
    params_str = match.group(2)
    # Parse params, handling type hints
    param_list = []
    for p in params_str.split(','):
        p = p.strip()
        if not p:
            continue
        # Remove type hints
        p = p.split(':')[0].strip()
        # Remove default values
        p = p.split('=')[0].strip()
        if p:
            param_list.append(p)
    return func_name, param_list


def extract_nf_params(content):
    """Extract Nextflow params from workflow."""
    params = re.findall(r"params\.(\w+)\s*=\s*null", content)
    return [p for p in params if p != 'outdir']


def extract_function_call_params(content, func_name):
    """Extract parameters used in the function call."""
    # Pattern: result = func_name(\n        param1=...,\n        param2=...,\n    )
    call_pattern = rf"result\s*=\s*{func_name}\(\s*\n([\s\S]*?)\s*\)"
    match = re.search(call_pattern, content)
    if not match:
        return []

    call_body = match.group(1)
    # Extract param names from param=auto_convert(...) pattern
    params = re.findall(r"(\w+)=auto_convert", call_body)
    return params


def fix_workflow(workflow_path):
    """Fix a single workflow file."""
    main_nf = workflow_path / 'main.nf'
    if not main_nf.exists():
        return None, "No main.nf found"

    with open(main_nf) as f:
        content = f.read()

    # Extract info
    func_name, func_params = extract_function_info(content)
    if not func_name:
        return None, "Could not find function definition"

    nf_params = extract_nf_params(content)
    call_params = extract_function_call_params(content, func_name)

    # Check if already aligned
    if set(func_params) == set(call_params) and set(func_params) == set(nf_params):
        return None, "Already aligned"

    # The fix: align NF params and function call to match function definition
    # Strategy: Update NF params to match function params, and fix the function call

    original_content = content

    # 1. Update params declarations
    for old_param in nf_params:
        if old_param not in func_params:
            # Remove this param declaration
            content = re.sub(rf"params\.{old_param}\s*=\s*null\n", "", content)

    for new_param in func_params:
        if new_param not in nf_params:
            # Add this param declaration after outdir
            content = re.sub(
                r"(params\.outdir\s*=\s*'[^']*'\n)",
                rf"\1params.{new_param} = null\n",
                content
            )

    # 2. Update PARAM exports
    # Remove old exports
    for old_param in nf_params:
        if old_param not in func_params:
            export_pattern = rf'export PARAM_{old_param.upper()}="[^"]*"\n\s*'
            content = re.sub(export_pattern, "", content)

    # Add new exports
    for new_param in func_params:
        if new_param not in nf_params:
            # Find where to insert (after last export)
            export_pattern = r'(export PARAM_\w+="[^"]*"\n)'
            matches = list(re.finditer(export_pattern, content))
            if matches:
                last_match = matches[-1]
                insert_pos = last_match.end()
                new_export = f'    export PARAM_{new_param.upper()}="${{params.{new_param}?.toString()?.replace(\'"\', \'\\\\"\') ?: \'null\'}}"\n'
                content = content[:insert_pos] + new_export + content[insert_pos:]

    # 3. Fix the function call to use correct param names
    # Build new function call
    call_lines = []
    for param in func_params:
        call_lines.append(f'        {param}=auto_convert(os.environ.get("PARAM_{param.upper()}", "")),')

    new_call = f"result = {func_name}(\n" + "\n".join(call_lines) + "\n    )"

    # Replace old function call
    old_call_pattern = rf"result\s*=\s*{func_name}\(\s*\n[\s\S]*?\s*\)"
    content = re.sub(old_call_pattern, new_call, content)

    # Check if content changed
    if content == original_content:
        return None, "No changes needed"

    # Write fixed content
    with open(main_nf, 'w') as f:
        f.write(content)

    return {
        'func_name': func_name,
        'func_params': func_params,
        'old_nf_params': nf_params,
        'old_call_params': call_params
    }, "Fixed"


def main():
    fixed = []
    errors = []
    skipped = []

    for domain in sorted(os.listdir(SUBWORKFLOWS_DIR)):
        domain_path = SUBWORKFLOWS_DIR / domain
        if not domain_path.is_dir():
            continue

        for wf in sorted(os.listdir(domain_path)):
            wf_path = domain_path / wf
            if not wf_path.is_dir():
                continue

            wf_key = f"{domain}/{wf}"
            result, msg = fix_workflow(wf_path)

            if result:
                fixed.append({'workflow': wf_key, **result})
                print(f"✓ Fixed: {wf_key}")
            elif msg == "Already aligned":
                skipped.append(wf_key)
            else:
                errors.append({'workflow': wf_key, 'error': msg})

    print(f"\n{'='*60}")
    print(f"Fixed: {len(fixed)}")
    print(f"Skipped (already ok): {len(skipped)}")
    print(f"Errors: {len(errors)}")

    if errors:
        print("\nErrors:")
        for e in errors[:10]:
            print(f"  - {e['workflow']}: {e['error']}")

    # Save report
    report = {
        'fixed': fixed,
        'skipped': skipped,
        'errors': errors
    }
    with open('test_data/fix_report.json', 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\nReport saved to test_data/fix_report.json")


if __name__ == '__main__':
    main()
