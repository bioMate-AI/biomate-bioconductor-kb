#!/usr/bin/env python3
"""
Regenerate workflow_params.json by extracting parameters from main.nf files.
"""

import os
import re
import json
from pathlib import Path

SUBWORKFLOWS_DIR = Path('subworkflows')
OUTPUT_FILE = Path('test_data/workflow_params.json')


def extract_params_from_main_nf(main_nf_path):
    """Extract parameter declarations from main.nf file."""
    content = main_nf_path.read_text()

    # Find params declarations
    params = {}

    # Pattern: params.name = value
    param_pattern = r"params\.(\w+)\s*=\s*([^\n]+)"

    for match in re.finditer(param_pattern, content):
        name = match.group(1)
        value_str = match.group(2).strip()

        # Skip outdir
        if name == 'outdir':
            params[name] = {"type": "string", "default": "./results"}
            continue

        # Parse default value
        if value_str == 'null':
            default = None
            param_type = "unknown"
        elif value_str.startswith("'") and value_str.endswith("'"):
            default = value_str[1:-1]
            param_type = "string"
        elif value_str in ('true', 'false'):
            default = value_str == 'true'
            param_type = "boolean"
        else:
            try:
                if '.' in value_str:
                    default = float(value_str)
                    param_type = "float"
                else:
                    default = int(value_str)
                    param_type = "integer"
            except ValueError:
                default = value_str
                param_type = "string"

        params[name] = {
            "type": param_type,
            "default": default
        }

    # Extract description from comment header
    desc_match = re.search(r"/\*\s*\*\s*\w+/\w+\s*\*\s*\n\s*\*\s*([^\n]*)", content)
    description = desc_match.group(1).strip() if desc_match else ""

    return {
        "description": description or "nf-core style module generated from tested Galaxy wrapper",
        "params": params
    }


def main():
    all_workflows = {}

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

            try:
                wf_info = extract_params_from_main_nf(main_nf)
                all_workflows[wf_key] = wf_info
            except Exception as e:
                print(f"Error processing {wf_key}: {e}")

    output = {
        "_generated": "Auto-generated from main.nf files",
        "workflows": all_workflows
    }

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"Generated {OUTPUT_FILE} with {len(all_workflows)} workflows")


if __name__ == '__main__':
    main()
