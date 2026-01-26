#!/usr/bin/env python3
"""
Fix Nextflow workflows by regenerating params, exports, and function calls
based on the actual Python function signature in the file.

This fixes the mismatch where Galaxy XML had wrong parameter names.
"""

import os
import re
from pathlib import Path

SUBWORKFLOWS_DIR = Path('subworkflows')


def extract_function_signature(content):
    """Extract function name and parameters from Python function definition."""
    # Find the main function definition (not auto_convert, prefix, main)
    func_pattern = r"def\s+(\w+)\(([^)]*)\)\s*(?:->[^:]+)?:"
    for match in re.finditer(func_pattern, content):
        name = match.group(1)
        params_str = match.group(2)

        if name in ('auto_convert', 'prefix', 'main'):
            continue

        # Parse parameters
        params = []
        for p in params_str.split(','):
            p = p.strip()
            if not p or p.startswith('*'):  # Skip *args, **kwargs
                continue
            # Remove type hints and defaults
            p = p.split(':')[0].split('=')[0].strip()
            if p:
                params.append(p)

        return name, params

    return None, None


def fix_workflow(wf_path, dry_run=False):
    """Fix a single workflow by regenerating params from function signature."""
    main_nf = wf_path / 'main.nf'
    if not main_nf.exists():
        return None, "No main.nf"

    content = main_nf.read_text()

    # Extract function info
    func_name, func_params = extract_function_signature(content)

    if not func_name:
        return None, "No function found"

    if not func_params:
        return None, "No parameters (or only *args/**kwargs)"

    # Check if already correct by seeing if function call matches
    call_pattern = rf"result\s*=\s*{func_name}\(\s*\n((?:.*\n)*?)\s*\)"
    call_match = re.search(call_pattern, content)

    if call_match:
        call_body = call_match.group(1)
        call_args = re.findall(r"(\w+)=auto_convert", call_body)

        # Check if already aligned
        if call_args == func_params:
            return False, "Already correct"

    # Generate new params section
    new_params_lines = ["params.outdir = './results'"]
    for p in func_params:
        new_params_lines.append(f"params.{p} = null")
    new_params_section = "\n".join(new_params_lines)

    # Generate new exports section
    new_exports = []
    for p in func_params:
        new_exports.append(
            f'export PARAM_{p.upper()}="${{params.{p}?.toString()?.replace(' +
            "'\"'" + ', ' + "'" + '\\\\"' + "'" + ') ?: ' + "'null'" + '}"'
        )
    new_exports_section = "    " + "\n    ".join(new_exports)

    # Generate new function call
    new_call_args = []
    for p in func_params:
        new_call_args.append(f'        {p}=auto_convert(os.environ.get("PARAM_{p.upper()}", "")),')
    new_call_section = f"    result = {func_name}(\n" + "\n".join(new_call_args) + "\n    )"

    # Apply fixes to content
    new_content = content

    # 1. Fix params section
    params_pattern = r"(// Parameters\n)(params\.outdir = '[^']*'\n)((?:params\.\w+ = (?:null|'[^']*'|\d+|true|false)\n)*)"
    def replace_params(m):
        return "// Parameters\n" + new_params_section + "\n"
    new_content = re.sub(params_pattern, replace_params, new_content)

    # 2. Fix exports section - match from comment to python3 heredoc
    exports_pattern = r"(# Export parameters as environment variables\n)((?:.*export PARAM_\w+.*\n)*)"
    def replace_exports(m):
        return "    # Export parameters as environment variables\n" + new_exports_section + "\n\n"
    new_content = re.sub(exports_pattern, replace_exports, new_content)

    # 3. Fix function call
    old_call_pattern = rf"(    result = {func_name}\(\s*\n)((?:.*\n)*?)(\s*\))"
    def replace_call(m):
        return new_call_section
    new_content = re.sub(old_call_pattern, replace_call, new_content)

    # Validate
    if new_content == content:
        return False, "No changes made"

    # Check that we still have the essential parts
    if f"result = {func_name}(" not in new_content:
        return None, "Fix broke the function call"

    if not dry_run:
        main_nf.write_text(new_content)

    return True, f"Fixed params: {func_params}"


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true', help='Show what would be fixed')
    parser.add_argument('--workflow', type=str, help='Fix specific workflow (domain/name)')
    parser.add_argument('--analyze', action='store_true', help='Only analyze, do not fix')
    args = parser.parse_args()

    if args.analyze:
        print("Analyzing all workflows...")
        issues = analyze_all()
        print(f"\n{'='*60}")
        print("ANALYSIS SUMMARY")
        print(f"{'='*60}")
        print(f"\nMissing params: {len(issues['missing_params'])}")
        print(f"Extra params: {len(issues['extra_params'])}")
        print(f"Case mismatches: {len(issues['case_mismatch'])}")
        print(f"No function found: {len(issues['no_function'])}")
        print(f"No function call found: {len(issues['no_call'])}")
        return

    if args.workflow:
        # Fix single workflow
        parts = args.workflow.split('/')
        if len(parts) != 2:
            print(f"Invalid workflow format: {args.workflow}")
            return
        wf_path = SUBWORKFLOWS_DIR / parts[0] / parts[1]
        result, msg = fix_workflow(wf_path, dry_run=args.dry_run)
        print(f"{args.workflow}: {msg}")
        return

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
            result, msg = fix_workflow(wf_path, dry_run=args.dry_run)

            if result is None:
                errors.append(f"{wf_key}: {msg}")
            elif result:
                fixed.append(f"{wf_key}: {msg}")
                print(f"{'[DRY RUN] ' if args.dry_run else ''}✓ {wf_key}")
            else:
                skipped.append(f"{wf_key}: {msg}")

    print(f"\n{'='*60}")
    print(f"{'[DRY RUN] ' if args.dry_run else ''}Fixed: {len(fixed)}")
    print(f"Skipped: {len(skipped)}")
    print(f"Errors: {len(errors)}")

    if errors:
        print("\nErrors:")
        for e in errors[:20]:
            print(f"  - {e}")


if __name__ == '__main__':
    main()
