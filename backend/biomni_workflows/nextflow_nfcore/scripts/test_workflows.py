#!/usr/bin/env python3
"""
Test Nextflow workflows and record pass/fail status.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

SUBWORKFLOWS_DIR = Path('subworkflows')
TEST_VALUES_FILE = Path('test_data/test_values.json')
RESULTS_DIR = Path('test_results')


def load_test_values():
    """Load test values from JSON file."""
    if TEST_VALUES_FILE.exists():
        with open(TEST_VALUES_FILE) as f:
            data = json.load(f)
            return data.get('by_name', {})
    return {}


def get_workflow_params(wf_path):
    """Extract parameter names from main.nf."""
    main_nf = wf_path / 'main.nf'
    if not main_nf.exists():
        return []

    import re
    content = main_nf.read_text()
    params = []
    for match in re.finditer(r"params\.(\w+)\s*=", content):
        param = match.group(1)
        if param != 'outdir':
            params.append(param)
    return params


def test_workflow(wf_name, test_values, timeout=120):
    """Test a single workflow."""
    wf_path = SUBWORKFLOWS_DIR / wf_name
    main_nf = wf_path / 'main.nf'

    if not main_nf.exists():
        return False, "No main.nf"

    # Build command with parameters
    params = get_workflow_params(wf_path)
    cmd = ['nextflow', 'run', str(main_nf), '-profile', 'docker']

    for param in params:
        if param in test_values:
            value = test_values[param]
            if isinstance(value, (list, dict)):
                cmd.extend([f'--{param}', json.dumps(value)])
            elif isinstance(value, bool):
                cmd.extend([f'--{param}', str(value).lower()])
            else:
                cmd.extend([f'--{param}', str(value)])

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(Path.cwd())
        )
        if result.returncode == 0:
            return True, "Success"
        else:
            # Extract error from stderr
            err = result.stderr[-500:] if result.stderr else "Unknown error"
            return False, err
    except subprocess.TimeoutExpired:
        return False, "Timeout"
    except Exception as e:
        return False, str(e)


def main():
    skip_passed = '--skip-passed' in sys.argv

    test_values = load_test_values()
    RESULTS_DIR.mkdir(exist_ok=True)

    # Load existing passed workflows if skipping
    passed_file = RESULTS_DIR / 'passed_workflows.txt'
    skip_list = set()
    if skip_passed and passed_file.exists():
        with open(passed_file) as f:
            for line in f:
                if '→' in line:
                    wf = line.split('→')[1].strip()
                    if wf:
                        skip_list.add(wf)

    passed = []
    failed = []

    for domain in sorted(os.listdir(SUBWORKFLOWS_DIR)):
        domain_path = SUBWORKFLOWS_DIR / domain
        if not domain_path.is_dir():
            continue

        for wf in sorted(os.listdir(domain_path)):
            wf_path = domain_path / wf
            if not wf_path.is_dir():
                continue

            wf_name = f"{domain}/{wf}"

            if wf_name in skip_list:
                passed.append(wf_name)
                continue

            print(f"Testing: {wf_name}", end=" ... ", flush=True)
            success, msg = test_workflow(wf_name, test_values)

            if success:
                passed.append(wf_name)
                print("PASS")
            else:
                failed.append((wf_name, msg))
                print(f"FAIL: {msg[:60]}")

    # Write results
    with open(RESULTS_DIR / 'passed_workflows.txt', 'w') as f:
        for i, wf in enumerate(passed, 1):
            f.write(f"{i:>6}→{wf}\n")

    with open(RESULTS_DIR / 'failed_workflows.txt', 'w') as f:
        for wf, msg in failed:
            f.write(f"{wf}: {msg[:200]}\n")

    print(f"\n{'='*60}")
    print(f"PASSED: {len(passed)}/{len(passed)+len(failed)} ({100*len(passed)/(len(passed)+len(failed)):.1f}%)")
    print(f"FAILED: {len(failed)}")


if __name__ == '__main__':
    main()
