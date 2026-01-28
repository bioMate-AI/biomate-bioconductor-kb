#!/usr/bin/env python3
"""
Add complete nf-core test structure to workflows that pass tests but don't have tests/ directory.
Creates: tests/main.nf.test, tests/nextflow.config, tests/test.yml
"""

import json
import os
from pathlib import Path
import re

SUBWORKFLOWS_DIR = Path('subworkflows')
TEST_VALUES_FILE = Path('test_data/test_values.json')

# Workflows that pass but don't have tests/ directory
MISSING_TESTS = [
    "biochemistry/one_site_model",
    "bioengineering/exp_decay",
    "bioengineering/higuchi",
    "bioengineering/zero_order",
    "cancer_biology/norm_chr",
    "database/blast_sequence",
    "genetics/elbo_loss",
    "genetics/forward",
    "immunology/logistic_growth",
    "immunology/simulate_cell_population",
    "literature/advanced_web_search_claude",
    "literature/extract_url_content",
    "literature/fetch_supplementary_info_from_doi",
    "microbiology/glv_equations",
    "molecular_biology/find_orfs_in_frame",
    "molecular_biology/find_restriction_sites",
    "molecular_biology/get_coding_sequences",
    "molecular_biology/get_refseq_id",
    "molecular_biology/reverse_complement",
    "pharmacology/ADMET_pred",
    "pharmacology/apply_vcog_grade",
    "pharmacology/bi_exp_model",
    "physiology/analyze_endolysosomal_calcium_dynamics",
    "physiology/mono_exp_model",
    "physiology/pk_ode_system",
    "synthetic_biology/gene_circuit_odes",
    "synthetic_biology/gompertz_model",
    "synthetic_biology/hamming_distance",
    "systems_biology/dimerization_odes",
    "systems_biology/mass_action_kinetics",
    "systems_biology/model_protein_dimerization_network",
    "systems_biology/ode_system",
    "systems_biology/ras_ode_system",
]


def get_process_name(wf_name):
    """Convert workflow name to process name (e.g., michaelis_menten -> MICHAELIS_MENTEN)."""
    return wf_name.split('/')[-1].upper()


def get_params_from_main_nf(wf_path):
    """Extract parameter names from main.nf."""
    main_nf = wf_path / 'main.nf'
    if not main_nf.exists():
        return []

    content = main_nf.read_text()

    # Find params section - pattern: params.X =
    params = []
    for match in re.finditer(r"params\.(\w+)\s*=", content):
        param = match.group(1)
        if param != 'outdir':  # Skip outdir
            params.append(param)

    return params


def load_test_values():
    """Load test values from JSON file."""
    if TEST_VALUES_FILE.exists():
        with open(TEST_VALUES_FILE) as f:
            data = json.load(f)
            # Values are under by_name key
            return data.get('by_name', {})
    return {}


def format_yaml_value(value):
    """Format a Python value for YAML."""
    if value is None:
        return "null"
    elif isinstance(value, bool):
        return "true" if value else "false"
    elif isinstance(value, str):
        # Quote strings that need it
        if any(c in value for c in ['"', ':', '#', '[', ']', '{', '}', '\n']):
            return f'"{value}"'
        return value
    elif isinstance(value, (list, dict)):
        return json.dumps(value)
    else:
        return str(value)


def create_test_files(wf_path, wf_name, test_values):
    """Create test files for a workflow."""
    tests_dir = wf_path / 'tests'
    tests_dir.mkdir(exist_ok=True)

    domain = wf_name.split('/')[0]
    func_name = wf_name.split('/')[-1]
    process_name = get_process_name(wf_name)

    # Get parameters from main.nf
    params = get_params_from_main_nf(wf_path)

    # 1. Create main.nf.test (nf-test format)
    test_content = f'''nextflow_process {{

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
'''
    (tests_dir / 'main.nf.test').write_text(test_content)

    # 2. Create nextflow.config
    config_content = '''/*
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
'''
    (tests_dir / 'nextflow.config').write_text(config_content)

    # 3. Create test.yml with actual test values
    yaml_lines = [f'- name: "{func_name} test"']
    yaml_lines.append('  command: nextflow run ../main.nf -profile docker')
    yaml_lines.append('  params:')

    for param in params:
        if param in test_values:
            value = format_yaml_value(test_values[param])
            yaml_lines.append(f'      {param}: {value}')

    yaml_lines.append('  tags:')
    yaml_lines.append(f'    - {domain}')
    yaml_lines.append(f'    - {func_name}')
    yaml_lines.append('')

    (tests_dir / 'test.yml').write_text('\n'.join(yaml_lines))

    return True


def main():
    test_values = load_test_values()
    created = []
    errors = []

    for wf_name in MISSING_TESTS:
        wf_path = SUBWORKFLOWS_DIR / wf_name

        if not wf_path.exists():
            errors.append(f"{wf_name}: directory not found")
            continue

        if (wf_path / 'tests').exists():
            print(f"  Skipping {wf_name} (tests/ already exists)")
            continue

        try:
            create_test_files(wf_path, wf_name, test_values)
            created.append(wf_name)
            print(f"✓ Created tests/ for {wf_name}")
        except Exception as e:
            errors.append(f"{wf_name}: {e}")
            print(f"✗ Error creating tests/ for {wf_name}: {e}")

    print(f"\n{'='*60}")
    print(f"Created tests/ structure: {len(created)}")
    print(f"Errors: {len(errors)}")

    if errors:
        print("\nErrors:")
        for e in errors:
            print(f"  - {e}")


if __name__ == '__main__':
    main()
