#!/usr/bin/env python3
"""
Batch test workflows and add tests/ directories for passing ones.
Uses test values from test_values.json.
"""

import json
import os
import subprocess
from pathlib import Path

SUBWORKFLOWS_DIR = Path('subworkflows')
TEST_VALUES_FILE = Path('test_data/test_values.json')

def load_test_values():
    with open(TEST_VALUES_FILE) as f:
        return json.load(f).get('by_name', {})

def get_workflow_params(wf_path):
    """Extract params from main.nf."""
    main_nf = wf_path / 'main.nf'
    import re
    content = main_nf.read_text()
    params = []
    for match in re.finditer(r"params\.(\w+)\s*=", content):
        p = match.group(1)
        if p != 'outdir':
            params.append(p)
    return params

def build_nextflow_cmd(wf_path, test_values):
    """Build nextflow command with params."""
    params = get_workflow_params(wf_path)
    main_nf = wf_path / 'main.nf'

    cmd = ['nextflow', 'run', str(main_nf), '-profile', 'docker']

    for p in params:
        if p in test_values:
            v = test_values[p]
            if isinstance(v, (list, dict)):
                cmd.extend([f'--{p}', json.dumps(v)])
            elif isinstance(v, bool):
                cmd.extend([f'--{p}', str(v).lower()])
            else:
                cmd.extend([f'--{p}', str(v)])

    return cmd

def test_workflow(wf_path, test_values, timeout=120):
    """Test a workflow, return True if passes."""
    cmd = build_nextflow_cmd(wf_path, test_values)

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        # Check for success marker in output
        return '✔' in result.stdout or '✔' in result.stderr
    except subprocess.TimeoutExpired:
        return False
    except Exception as e:
        print(f"  Error: {e}")
        return False

def create_tests_dir(wf_path, wf_name, test_values):
    """Create tests/ directory with nf-core structure."""
    tests_dir = wf_path / 'tests'
    tests_dir.mkdir(exist_ok=True)

    domain = wf_name.split('/')[0]
    func_name = wf_name.split('/')[-1]
    process_name = func_name.upper()
    params = get_workflow_params(wf_path)

    # main.nf.test
    (tests_dir / 'main.nf.test').write_text(f'''nextflow_process {{

    name "Test Process {process_name}"
    script "../main.nf"
    process "{process_name}"

    test("Should run {func_name} successfully") {{

        when {{
            process {{
                """
                input[0] = [ [ id:'test' ] ]
                """
            }}
        }}

        then {{
            assert process.success
            assert process.out.results
        }}

    }}

}}
''')

    # nextflow.config
    (tests_dir / 'nextflow.config').write_text('''/*
 * Test configuration
 */
params {
    outdir = './results'
}

docker {
    enabled = true
    runOptions = '-u $(id -u):$(id -g)'
}

process {
    container = 'biomate/biomni-tools:latest'
}
''')

    # test.yml
    yaml_lines = [f'- name: "{func_name} test"']
    yaml_lines.append('  command: nextflow run ../main.nf -profile docker')
    yaml_lines.append('  params:')

    for p in params:
        if p in test_values:
            v = test_values[p]
            if isinstance(v, (list, dict)):
                yaml_lines.append(f'      {p}: {json.dumps(v)}')
            elif isinstance(v, str):
                yaml_lines.append(f'      {p}: "{v}"')
            else:
                yaml_lines.append(f'      {p}: {v}')

    yaml_lines.append('  tags:')
    yaml_lines.append(f'    - {domain}')
    yaml_lines.append(f'    - {func_name}')
    yaml_lines.append('')

    (tests_dir / 'test.yml').write_text('\n'.join(yaml_lines))

def main():
    test_values = load_test_values()

    # Get workflows without tests/
    workflows_to_test = []
    for domain in sorted(os.listdir(SUBWORKFLOWS_DIR)):
        domain_path = SUBWORKFLOWS_DIR / domain
        if not domain_path.is_dir():
            continue
        for wf in sorted(os.listdir(domain_path)):
            wf_path = domain_path / wf
            if wf_path.is_dir() and not (wf_path / 'tests').exists():
                workflows_to_test.append((f"{domain}/{wf}", wf_path))

    print(f"Testing {len(workflows_to_test)} workflows without tests/ directory")
    print("=" * 60)

    passed = []
    failed = []

    for wf_name, wf_path in workflows_to_test:
        print(f"Testing: {wf_name}", end=" ... ", flush=True)

        if test_workflow(wf_path, test_values):
            passed.append(wf_name)
            print("PASS - creating tests/")
            create_tests_dir(wf_path, wf_name, test_values)
        else:
            failed.append(wf_name)
            print("FAIL")

    print("\n" + "=" * 60)
    print(f"PASSED: {len(passed)}")
    print(f"FAILED: {len(failed)}")

    if passed:
        print(f"\nAdded tests/ to {len(passed)} workflows:")
        for wf in passed:
            print(f"  - {wf}")

if __name__ == '__main__':
    main()
