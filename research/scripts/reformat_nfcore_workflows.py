#!/usr/bin/env python3
"""
Reformat nf-core converted workflows to proper Galaxy format.

Adds proper structure while keeping custom tool IDs (not ToolShed format).
"""

import json
import os
from pathlib import Path
from datetime import datetime

WORKFLOWS_DIR = "/home/yzhang/biomate/backend/galaxy_workflows"
OUTPUT_DIR = "/home/yzhang/biomate/backend/galaxy_workflows_reformatted"
REPORT_DIR = "/home/yzhang/biomate/research"


def reformat_workflow(workflow_data: dict, filename: str) -> dict:
    """Reformat a single workflow to proper Galaxy format."""

    # Create new workflow with proper structure
    reformatted = {
        "a_galaxy_workflow": "true",
        "annotation": workflow_data.get('annotation', ''),
        "creator": [
            {
                "class": "Organization",
                "name": "nf-core",
                "url": "https://nf-co.re"
            },
            {
                "class": "Organization",
                "name": "BioMate",
                "url": "https://biomate.ai"
            }
        ],
        "format-version": "0.1",
        "license": "MIT",
        "name": workflow_data.get('name', filename.replace('.ga', '')),
        "release": "1.0",
        "report": {
            "markdown": "\n# Workflow Execution Report\n\n## Workflow Inputs\n```galaxy\ninvocation_inputs()\n```\n\n## Workflow Outputs\n```galaxy\ninvocation_outputs()\n```\n\n## Workflow\n```galaxy\nworkflow_display()\n```\n"
        },
        "steps": {},
        "tags": ["nf-core", "converted"],
        "uuid": None,
        "version": 1
    }

    # Get the old outputs mapping (non-standard format)
    old_outputs = workflow_data.get('outputs', {})

    # Track which step outputs should be workflow outputs
    step_outputs_map = {}
    for output_name, output_info in old_outputs.items():
        step_id = str(output_info.get('id', ''))
        output_port = output_info.get('output_name', '')
        description = output_info.get('description', output_name)

        if step_id not in step_outputs_map:
            step_outputs_map[step_id] = []
        step_outputs_map[step_id].append({
            'label': output_name,
            'output_name': output_port,
            'description': description
        })

    # Process each step
    old_steps = workflow_data.get('steps', {})

    for step_id, step in old_steps.items():
        step_type = step.get('type', '')

        new_step = {
            "annotation": step.get('annotation', ''),
            "content_id": None,
            "errors": None,
            "id": int(step_id),
            "input_connections": step.get('input_connections', {}),
            "inputs": [],
            "name": step.get('name', ''),
            "outputs": [],
            "position": step.get('position', {"left": 0, "top": 0}),
            "tool_id": None,
            "tool_state": "{}",
            "tool_version": None,
            "type": step_type,
            "uuid": None,
            "when": None,
            "workflow_outputs": []
        }

        # Handle input steps
        if step_type in ['data_input', 'data_collection_input', 'parameter_input']:
            old_inputs = step.get('inputs', [])

            # Create proper label from inputs
            if old_inputs:
                input_info = old_inputs[0]
                input_name = input_info.get('name', f'Input {step_id}')
                input_desc = input_info.get('description', '')

                new_step['label'] = input_name
                new_step['inputs'] = [{
                    "description": input_desc or input_name,
                    "name": input_name
                }]
            else:
                new_step['label'] = step.get('name', f'Input {step_id}')
                new_step['inputs'] = [{
                    "description": step.get('annotation', ''),
                    "name": new_step['label']
                }]

            # Set tool_state based on type
            if step_type == 'data_input':
                new_step['tool_state'] = '{"optional": false, "tag": null}'
            elif step_type == 'data_collection_input':
                new_step['tool_state'] = '{"optional": false, "tag": "", "collection_type": "list"}'
            elif step_type == 'parameter_input':
                new_step['tool_state'] = '{"parameter_type": "text", "optional": true}'

        # Handle tool steps
        elif step_type == 'tool':
            tool_id = step.get('tool_id', '')
            tool_version = step.get('tool_version', '')

            new_step['content_id'] = tool_id
            new_step['tool_id'] = tool_id
            new_step['tool_version'] = tool_version
            new_step['label'] = step.get('name', tool_id)

            # Add workflow_outputs if this step has outputs
            if step_id in step_outputs_map:
                for output in step_outputs_map[step_id]:
                    new_step['workflow_outputs'].append({
                        "label": output['label'],
                        "output_name": output['output_name'],
                        "uuid": None
                    })

        reformatted['steps'][step_id] = new_step

    return reformatted


def main():
    print("=" * 60)
    print("Reformatting nf-core Workflows")
    print("=" * 60)
    print()

    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Process all workflows
    ga_files = list(Path(WORKFLOWS_DIR).glob("*.ga"))
    print(f"Found {len(ga_files)} workflows to reformat")
    print()

    success = 0
    failed = 0
    results = []

    for ga_file in ga_files:
        try:
            with open(ga_file, 'r') as f:
                workflow = json.load(f)

            # Reformat
            reformatted = reformat_workflow(workflow, ga_file.name)

            # Save
            output_path = os.path.join(OUTPUT_DIR, ga_file.name)
            with open(output_path, 'w') as f:
                json.dump(reformatted, f, indent=2)

            # Track results
            num_steps = len(reformatted['steps'])
            num_outputs = sum(
                len(s.get('workflow_outputs', []))
                for s in reformatted['steps'].values()
            )

            results.append({
                'name': reformatted['name'],
                'file': ga_file.name,
                'steps': num_steps,
                'outputs': num_outputs,
                'status': 'success'
            })

            success += 1

        except Exception as e:
            print(f"Error reformatting {ga_file.name}: {e}")
            results.append({
                'name': ga_file.stem,
                'file': ga_file.name,
                'steps': 0,
                'outputs': 0,
                'status': f'failed: {e}'
            })
            failed += 1

    print(f"Reformatted: {success}")
    print(f"Failed: {failed}")
    print(f"\nOutput directory: {OUTPUT_DIR}")

    # Generate report
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    report_path = f"{REPORT_DIR}/{timestamp}_NFCORE_REFORMAT_REPORT.md"

    with open(report_path, 'w') as f:
        f.write("# nf-core Workflow Reformatting Report\n\n")
        f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"**Total:** {len(ga_files)}\n")
        f.write(f"**Success:** {success}\n")
        f.write(f"**Failed:** {failed}\n\n")

        f.write("## Changes Made\n\n")
        f.write("1. Added `license: MIT`\n")
        f.write("2. Added `creator` with nf-core and BioMate attribution\n")
        f.write("3. Added `label` fields to all input steps\n")
        f.write("4. Converted top-level `outputs` to `workflow_outputs` in steps\n")
        f.write("5. Added `release` version\n")
        f.write("6. Added `report` template\n")
        f.write("7. Added `tags` for organization\n\n")

        f.write("## Tool ID Format\n\n")
        f.write("Tool IDs are kept as-is (not ToolShed format) because these are custom tools:\n")
        f.write("- `nfcore_*` - nf-core specific tools\n")
        f.write("- `umitools_*` - UMI-tools\n")
        f.write("- `Filter1`, etc. - Galaxy built-ins\n")
        f.write("- ToolShed format for tools that exist there\n\n")

        f.write("## Reformatted Workflows\n\n")
        f.write("| Workflow | Steps | Outputs | Status |\n")
        f.write("|----------|-------|---------|--------|\n")

        for r in sorted(results, key=lambda x: x['name']):
            status = "✓" if r['status'] == 'success' else "✗"
            f.write(f"| {r['name']} | {r['steps']} | {r['outputs']} | {status} |\n")

    print(f"\nReport saved to: {report_path}")


if __name__ == "__main__":
    main()
