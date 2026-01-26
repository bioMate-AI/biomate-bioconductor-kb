#!/usr/bin/env python3
"""
Fix parameter case mismatches in Nextflow workflows.
Only fixes the function call to match the function signature.
Does not modify param declarations or exports.
"""

import os
import re
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


def fix_workflow(wf_path):
    """Fix function call parameter case to match function signature."""
    main_nf = wf_path / 'main.nf'
    if not main_nf.exists():
        return None, "No main.nf"

    with open(main_nf) as f:
        content = f.read()

    # Find the main function (not auto_convert)
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

    # Create case-insensitive mapping from function params
    # func_params are the source of truth
    param_map = {p.lower(): p for p in func_params}
    func_param_set = set(func_params)

    # Find the function call and fix parameter names
    # Look for the call ending with "    )" on its own line
    call_pattern = rf"(result\s*=\s*{func_name}\(\s*\n)((?:.*\n)*?)(    \))"
    call_match = re.search(call_pattern, content)

    if not call_match:
        return None, "No function call found"

    call_body = call_match.group(2)

    # Find all parameters in the call
    call_params = re.findall(r"(\w+)=auto_convert", call_body)

    # Check if any need fixing - only fix if:
    # 1. The call param differs from func param only in case
    # 2. The lowercase matches a func param
    needs_fix = False
    fixable_params = []
    for cp in call_params:
        cp_lower = cp.lower()
        if cp_lower in param_map:
            correct_name = param_map[cp_lower]
            if cp != correct_name:
                # This is a case-only mismatch - fixable
                fixable_params.append((cp, correct_name))
                needs_fix = True

    if not needs_fix:
        return False, "No case mismatch"

    # Fix the call body
    new_call_body = call_body
    for old_name, new_name in fixable_params:
        # Replace the parameter name in the call
        new_call_body = re.sub(
            rf"\b{old_name}=auto_convert",
            f"{new_name}=auto_convert",
            new_call_body
        )

    # Reconstruct the full call
    new_content = content[:call_match.start()] + \
                  call_match.group(1) + new_call_body + call_match.group(3) + \
                  content[call_match.end():]

    # Verify the fix
    if new_content.count(f'result = {func_name}(') != 1:
        return None, "Fix validation failed"

    # Write back
    with open(main_nf, 'w') as f:
        f.write(new_content)

    return True, f"Fixed: {call_params} -> {func_params}"


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

            result, msg = fix_workflow(wf_path)
            if result is None:
                errors.append(f"{wf_key}: {msg}")
            elif result:
                fixed.append(f"{wf_key}: {msg}")
                print(f"✓ {wf_key}")
            else:
                skipped.append(wf_key)

    print(f"\n{'='*60}")
    print(f"Fixed: {len(fixed)}")
    print(f"Skipped (no case mismatch): {len(skipped)}")
    print(f"Errors: {len(errors)}")

    if fixed:
        print("\nFixed workflows:")
        for f in fixed[:20]:
            print(f"  - {f}")

    if errors:
        print("\nErrors:")
        for e in errors[:10]:
            print(f"  - {e}")


if __name__ == '__main__':
    main()
