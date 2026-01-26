#!/usr/bin/env python3
"""
Create complete nf-core structure for passed workflows.
Adds meta.yml and tests directory to each workflow.
"""

import json
import os
import re
from pathlib import Path

NFCORE_DIR = Path('/home/yzhang/biomate/backend/biomni_workflows/nextflow_nfcore')
SUBWORKFLOWS_DIR = NFCORE_DIR / 'subworkflows'
TEST_VALUES_FILE = NFCORE_DIR / 'test_data' / 'test_values.json'
PASSED_FILE = NFCORE_DIR / 'test_results' / 'passed_workflows.txt'


def load_test_values():
    with open(TEST_VALUES_FILE) as f:
        return json.load(f)


def load_passed_workflows():
    with open(PASSED_FILE) as f:
        return [line.strip() for line in f if line.strip()]


def extract_workflow_info(main_nf_path):
    """Extract info from main.nf file."""
    with open(main_nf_path) as f:
        content = f.read()

    # Extract params
    params = re.findall(r"params\.(\w+)\s*=\s*null", content)
    params = [p for p in params if p != 'outdir']

    # Extract function name and docstring
    func_match = re.search(r"def\s+(\w+)\([^)]*\):\s*\n\s*'''([^']*'''|[^']*)", content)
    if func_match:
        func_name = func_match.group(1)
        docstring = func_match.group(2).replace("'''", "").strip()
    else:
        func_name = main_nf_path.parent.name
        docstring = ""

    # Extract description from comment
    desc_match = re.search(r"/\*\s*\*\s*(\w+/\w+)\s*\*\s*\n\s*\*\s*([^\n]*)", content)
    description = desc_match.group(2).strip() if desc_match else docstring.split('\n')[0] if docstring else ""

    return {
        'params': params,
        'func_name': func_name,
        'description': description,
        'docstring': docstring
    }


def create_meta_yml(wf_path, domain, wf_name, info):
    """Create meta.yml for a workflow."""
    params_yaml = ""
    for p in info['params']:
        params_yaml += f"""  - name: {p}
    type: string
    description: Parameter {p}
"""

    meta_content = f"""name: "{wf_name}"
description: "{info['description'] or f'{wf_name} function'}"
keywords:
  - {domain}
  - biomni
tools:
  - biomni:
      description: "Biomni bioinformatics tool library"
      homepage: "https://github.com/biomate/biomni"
      documentation: "https://github.com/biomate/biomni"
      licence: ["MIT"]

input:
  - meta:
      type: map
      description: |
        Groovy Map containing sample information
        e.g. [ id:'test' ]
{params_yaml}
output:
  - results:
      type: tuple
      description: JSON results file
      pattern: "*_results.json"
  - output:
      type: tuple
      description: Human-readable output
      pattern: "*_output.txt"
  - versions:
      type: file
      description: File containing software versions
      pattern: "versions.yml"

authors:
  - "@biomni"
maintainers:
  - "@biomni"
"""
    meta_path = wf_path / 'meta.yml'
    with open(meta_path, 'w') as f:
        f.write(meta_content)
    return meta_path


def get_test_value(param_name, test_values):
    """Get test value for a parameter."""
    if param_name in test_values['by_name']:
        return test_values['by_name'][param_name]
    # Partial match
    for key, val in test_values['by_name'].items():
        if key in param_name or param_name in key:
            return val
    return "test_value"


def create_tests_dir(wf_path, domain, wf_name, info, test_values):
    """Create tests directory with nf-test files."""
    tests_dir = wf_path / 'tests'
    tests_dir.mkdir(exist_ok=True)

    # Create nextflow.config for tests
    config_content = """/*
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
"""
    with open(tests_dir / 'nextflow.config', 'w') as f:
        f.write(config_content)

    # Create test.yml
    params_yaml = ""
    for p in info['params']:
        val = get_test_value(p, test_values)
        if isinstance(val, (list, dict)):
            val_str = json.dumps(val)
        elif isinstance(val, bool):
            val_str = str(val).lower()
        else:
            val_str = f'"{val}"' if isinstance(val, str) else str(val)
        params_yaml += f"      {p}: {val_str}\n"

    test_yml_content = f"""- name: "{wf_name} test"
  command: nextflow run ../main.nf -profile docker
  params:
{params_yaml}  tags:
    - {domain}
    - {wf_name}
"""
    with open(tests_dir / 'test.yml', 'w') as f:
        f.write(test_yml_content)

    # Create main.nf.test (nf-test format)
    process_name = wf_name.upper().replace('-', '_')
    nf_test_content = f'''nextflow_process {{

    name "Test Process {process_name}"
    script "../main.nf"
    process "{process_name}"

    test("Should run {wf_name} successfully") {{

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
'''
    with open(tests_dir / 'main.nf.test', 'w') as f:
        f.write(nf_test_content)

    return tests_dir


def main():
    test_values = load_test_values()
    passed_workflows = load_passed_workflows()

    print(f"Creating nf-core structure for {len(passed_workflows)} workflows...")

    created = []
    errors = []

    for wf_key in passed_workflows:
        domain, wf_name = wf_key.split('/')
        wf_path = SUBWORKFLOWS_DIR / domain / wf_name
        main_nf = wf_path / 'main.nf'

        if not main_nf.exists():
            errors.append(f"{wf_key}: main.nf not found")
            continue

        try:
            info = extract_workflow_info(main_nf)
            create_meta_yml(wf_path, domain, wf_name, info)
            create_tests_dir(wf_path, domain, wf_name, info, test_values)
            created.append(wf_key)
            print(f"  ✓ {wf_key}")
        except Exception as e:
            errors.append(f"{wf_key}: {e}")
            print(f"  ✗ {wf_key}: {e}")

    print(f"\n{'='*60}")
    print(f"Created: {len(created)}")
    print(f"Errors: {len(errors)}")

    if errors:
        print("\nErrors:")
        for e in errors[:10]:
            print(f"  - {e}")


if __name__ == '__main__':
    main()
