#!/usr/bin/env python3
"""
Systematically fix function call arguments in Nextflow workflows.

The issue: Galaxy XML param names don't match Python function signatures.
- Galaxy XML: Kd, dH (mixed case)
- Python function: kd, dh (lowercase)

This script:
1. Extracts the Python function signature from each main.nf
2. Extracts the current function call arguments
3. Creates a case-insensitive mapping to fix the call
4. Updates the file with correct parameter names
"""

import os
import re
from pathlib import Path

SUBWORKFLOWS_DIR = Path('subworkflows')


def extract_function_info(content):
    """Extract function name, signature params, and call params from main.nf."""

    # Find the main function definition (not auto_convert)
    # Pattern: def func_name(param1, param2, ...):
    func_pattern = r"def\s+(\w+)\(([^)]*)\)\s*(?:->[^:]+)?:"
    func_matches = re.findall(func_pattern, content)

    func_name = None
    func_params = []

    for name, params_str in func_matches:
        if name not in ('auto_convert', 'prefix', 'main'):
            func_name = name
            # Parse parameters
            for p in params_str.split(','):
                p = p.strip()
                if not p:
                    continue
                # Remove type hints and defaults
                p = p.split(':')[0].split('=')[0].strip()
                if p:
                    func_params.append(p)
            break

    if not func_name:
        return None, None, None, "No function found"

    # Find the function call
    # Pattern: result = func_name(\n    param1=auto_convert(...),\n    param2=...,\n    )
    call_pattern = rf"result\s*=\s*{func_name}\(\s*\n((?:.*\n)*?)\s*\)"
    call_match = re.search(call_pattern, content)

    if not call_match:
        return func_name, func_params, None, "No function call found"

    call_body = call_match.group(1)

    # Extract parameter names from the call
    # Pattern: param_name=auto_convert(os.environ.get("PARAM_XXX", ""))
    call_param_pattern = r"(\w+)=auto_convert\(os\.environ\.get\(\"PARAM_(\w+)\""
    call_matches = re.findall(call_param_pattern, call_body)

    call_params = [(m[0], m[1]) for m in call_matches]  # (arg_name, env_var_suffix)

    return func_name, func_params, call_params, None


def fix_workflow(wf_path):
    """Fix function call in a single workflow."""
    main_nf = wf_path / 'main.nf'
    if not main_nf.exists():
        return None, "No main.nf"

    content = main_nf.read_text()

    func_name, func_params, call_params, error = extract_function_info(content)

    if error:
        return None, error

    if not call_params:
        return None, "Could not parse function call"

    # Create case-insensitive mapping from function params
    # func_params are the source of truth
    param_map = {p.lower(): p for p in func_params}

    # Check which call params need fixing
    fixes_needed = []
    for call_arg, env_suffix in call_params:
        call_lower = call_arg.lower()
        if call_lower in param_map:
            correct_name = param_map[call_lower]
            if call_arg != correct_name:
                fixes_needed.append((call_arg, correct_name, env_suffix))

    if not fixes_needed:
        return False, "No fixes needed"

    # Apply fixes
    new_content = content
    for old_name, new_name, env_suffix in fixes_needed:
        # Replace: old_name=auto_convert(os.environ.get("PARAM_XXX"
        # With:    new_name=auto_convert(os.environ.get("PARAM_XXX"
        old_pattern = rf"\b{old_name}=auto_convert\(os\.environ\.get\(\"PARAM_{env_suffix}\""
        new_value = f"{new_name}=auto_convert(os.environ.get(\"PARAM_{env_suffix}\""
        new_content = re.sub(old_pattern, new_value, new_content)

    # Verify the fix didn't break anything
    if new_content.count(f'result = {func_name}(') != 1:
        return None, "Fix validation failed"

    # Write back
    main_nf.write_text(new_content)

    return True, f"Fixed: {[(f[0], f[1]) for f in fixes_needed]}"


def analyze_all():
    """Analyze all workflows and report issues."""
    issues = {
        'case_mismatch': [],
        'missing_params': [],
        'extra_params': [],
        'no_function': [],
        'no_call': [],
    }

    for domain in sorted(os.listdir(SUBWORKFLOWS_DIR)):
        domain_path = SUBWORKFLOWS_DIR / domain
        if not domain_path.is_dir():
            continue

        for wf in sorted(os.listdir(domain_path)):
            wf_path = domain_path / wf
            if not wf_path.is_dir():
                continue

            main_nf = wf_path / 'main.nf'
            if not main_nf.exists():
                continue

            wf_key = f"{domain}/{wf}"
            content = main_nf.read_text()

            func_name, func_params, call_params, error = extract_function_info(content)

            if error == "No function found":
                issues['no_function'].append(wf_key)
                continue
            if error == "No function call found":
                issues['no_call'].append(wf_key)
                continue

            if not call_params:
                issues['no_call'].append(wf_key)
                continue

            # Compare parameters
            func_param_set = set(func_params)
            call_arg_set = set(cp[0] for cp in call_params)

            # Case mismatches
            func_lower_map = {p.lower(): p for p in func_params}
            for call_arg, _ in call_params:
                call_lower = call_arg.lower()
                if call_lower in func_lower_map and call_arg != func_lower_map[call_lower]:
                    issues['case_mismatch'].append({
                        'workflow': wf_key,
                        'call_arg': call_arg,
                        'func_param': func_lower_map[call_lower]
                    })

            # Missing params (in function but not in call)
            call_lower_set = set(cp[0].lower() for cp in call_params)
            for fp in func_params:
                if fp.lower() not in call_lower_set:
                    issues['missing_params'].append({
                        'workflow': wf_key,
                        'param': fp,
                        'func_params': func_params,
                        'call_args': [cp[0] for cp in call_params]
                    })

            # Extra params (in call but not in function)
            func_lower_set = set(fp.lower() for fp in func_params)
            for call_arg, _ in call_params:
                if call_arg.lower() not in func_lower_set:
                    issues['extra_params'].append({
                        'workflow': wf_key,
                        'param': call_arg,
                        'func_params': func_params,
                        'call_args': [cp[0] for cp in call_params]
                    })

    return issues


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--analyze', action='store_true', help='Analyze and report issues')
    parser.add_argument('--fix', action='store_true', help='Fix case mismatches')
    args = parser.parse_args()

    if args.analyze or not args.fix:
        print("Analyzing all workflows...")
        issues = analyze_all()

        print(f"\n{'='*60}")
        print("ANALYSIS SUMMARY")
        print(f"{'='*60}")

        print(f"\nCase mismatches: {len(issues['case_mismatch'])}")
        if issues['case_mismatch']:
            for item in issues['case_mismatch'][:10]:
                print(f"  - {item['workflow']}: {item['call_arg']} -> {item['func_param']}")
            if len(issues['case_mismatch']) > 10:
                print(f"  ... and {len(issues['case_mismatch']) - 10} more")

        print(f"\nMissing params (in function but not in call): {len(issues['missing_params'])}")
        if issues['missing_params']:
            seen = set()
            for item in issues['missing_params'][:10]:
                if item['workflow'] not in seen:
                    seen.add(item['workflow'])
                    print(f"  - {item['workflow']}: missing {item['param']}")
                    print(f"      func: {item['func_params']}")
                    print(f"      call: {item['call_args']}")

        print(f"\nExtra params (in call but not in function): {len(issues['extra_params'])}")
        if issues['extra_params']:
            seen = set()
            for item in issues['extra_params'][:10]:
                if item['workflow'] not in seen:
                    seen.add(item['workflow'])
                    print(f"  - {item['workflow']}: extra {item['param']}")
                    print(f"      func: {item['func_params']}")
                    print(f"      call: {item['call_args']}")

        print(f"\nNo function found: {len(issues['no_function'])}")
        print(f"No function call found: {len(issues['no_call'])}")

    if args.fix:
        print("\nFixing case mismatches...")
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

                if result is None:
                    errors.append(f"{wf_key}: {msg}")
                elif result:
                    fixed.append(f"{wf_key}: {msg}")
                    print(f"✓ {wf_key}")
                else:
                    skipped.append(wf_key)

        print(f"\n{'='*60}")
        print(f"Fixed: {len(fixed)}")
        print(f"Skipped (no fix needed): {len(skipped)}")
        print(f"Errors: {len(errors)}")

        if fixed:
            print("\nFixed workflows:")
            for f in fixed[:20]:
                print(f"  - {f}")


if __name__ == '__main__':
    main()
