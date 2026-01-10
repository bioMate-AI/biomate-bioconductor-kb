#!/usr/bin/env python3
"""
Embed Subworkflows into Galaxy Workflows

Galaxy .ga format requires subworkflows to be embedded inline, unlike Nextflow
which uses file imports. This script:

1. Reads a parent workflow that references subworkflows by file path
2. Loads the subworkflow .ga files
3. Embeds them inline using Galaxy's "type": "subworkflow" format
4. Outputs a complete, valid Galaxy workflow

Usage:
    python embed_subworkflows.py input_workflow.ga output_workflow.ga

References:
    - Galaxy subworkflow format: https://docs.galaxyproject.org/en/master/_modules/galaxy/workflow/modules.html
    - IWC examples: https://github.com/galaxyproject/iwc
"""

import json
import copy
from pathlib import Path
from typing import Any


def load_workflow(path: Path) -> dict:
    """Load a Galaxy workflow from .ga file."""
    with open(path, 'r') as f:
        return json.load(f)


def save_workflow(workflow: dict, path: Path):
    """Save a Galaxy workflow to .ga file."""
    with open(path, 'w') as f:
        json.dump(workflow, f, indent=2)


def find_subworkflow_references(workflow: dict) -> list[dict]:
    """
    Find steps that reference external subworkflows.

    Looks for steps with:
    - "type": "subworkflow_reference" (our custom marker)
    - "subworkflow_path": "path/to/subworkflow.ga"
    """
    references = []
    for step_id, step in workflow.get('steps', {}).items():
        if step.get('type') == 'subworkflow_reference':
            references.append({
                'step_id': step_id,
                'path': step.get('subworkflow_path'),
                'step': step
            })
    return references


def convert_to_embedded_subworkflow(
    parent_step: dict,
    subworkflow: dict,
    step_id: str
) -> dict:
    """
    Convert a subworkflow reference to an embedded subworkflow step.

    Galaxy embedded subworkflow format:
    {
        "type": "subworkflow",
        "id": <step_id>,
        "label": "...",
        "input_connections": {
            "<parent_input_name>": {
                "id": <source_step_id>,
                "input_subworkflow_step_id": <target_step_in_subworkflow>,
                "output_name": "..."
            }
        },
        "subworkflow": {
            "a_galaxy_workflow": "true",
            "format-version": "0.1",
            "name": "...",
            "steps": { ... }
        }
    }
    """
    embedded = {
        "type": "subworkflow",
        "id": int(step_id),
        "label": parent_step.get('label', subworkflow.get('name', f'Subworkflow {step_id}')),
        "name": subworkflow.get('name', ''),
        "annotation": subworkflow.get('annotation', ''),
        "position": parent_step.get('position', {"left": 0, "top": 0}),
        "input_connections": {},
        "subworkflow": {
            "a_galaxy_workflow": "true",
            "format-version": subworkflow.get('format-version', '0.1'),
            "name": subworkflow.get('name', ''),
            "annotation": subworkflow.get('annotation', ''),
            "steps": subworkflow.get('steps', {}),
            "tags": subworkflow.get('tags', [])
        }
    }

    # Copy input connections from parent step
    # These need to map to subworkflow input steps
    if 'input_connections' in parent_step:
        for conn_name, conn_info in parent_step['input_connections'].items():
            # Find the corresponding input step in subworkflow
            subworkflow_input_id = find_subworkflow_input_step(
                subworkflow, conn_name
            )

            if subworkflow_input_id is not None:
                embedded['input_connections'][conn_name] = {
                    'id': conn_info.get('id'),
                    'input_subworkflow_step_id': subworkflow_input_id,
                    'output_name': conn_info.get('output_name', 'output')
                }

    return embedded


def find_subworkflow_input_step(subworkflow: dict, input_name: str) -> int | None:
    """
    Find the step ID in subworkflow that corresponds to an input name.

    Looks for steps with:
    - "type": "data_input" or "parameter_input"
    - "label" matching input_name
    """
    for step_id, step in subworkflow.get('steps', {}).items():
        step_type = step.get('type', '')
        if step_type in ('data_input', 'parameter_input', 'data_collection_input'):
            if step.get('label', '').lower() == input_name.lower():
                return int(step_id)

    # If no exact match, try first input step
    for step_id, step in subworkflow.get('steps', {}).items():
        if step.get('type', '') in ('data_input', 'parameter_input'):
            return int(step_id)

    return None


def embed_all_subworkflows(
    workflow: dict,
    subworkflows_dir: Path
) -> dict:
    """
    Process a workflow and embed all referenced subworkflows.

    Args:
        workflow: Parent workflow dict
        subworkflows_dir: Base directory for subworkflow .ga files

    Returns:
        New workflow dict with all subworkflows embedded inline
    """
    result = copy.deepcopy(workflow)
    references = find_subworkflow_references(result)

    if not references:
        print("No subworkflow references found")
        return result

    print(f"Found {len(references)} subworkflow references")

    for ref in references:
        subworkflow_path = subworkflows_dir / ref['path']

        if not subworkflow_path.exists():
            print(f"  Warning: Subworkflow not found: {subworkflow_path}")
            continue

        print(f"  Embedding: {ref['path']}")
        subworkflow = load_workflow(subworkflow_path)

        # Convert to embedded format
        embedded_step = convert_to_embedded_subworkflow(
            ref['step'],
            subworkflow,
            ref['step_id']
        )

        # Replace the reference step with embedded step
        result['steps'][ref['step_id']] = embedded_step

    return result


def create_workflow_with_subworkflow(
    parent_name: str,
    parent_annotation: str,
    main_steps: list[dict],
    subworkflows: list[tuple[str, dict, dict]],  # (name, subworkflow, connections)
    tags: list[str] = None
) -> dict:
    """
    Create a new workflow that includes subworkflows.

    This is a helper for programmatically building workflows with embedded subworkflows.

    Args:
        parent_name: Name of the parent workflow
        parent_annotation: Description
        main_steps: List of non-subworkflow steps
        subworkflows: List of (name, subworkflow_dict, input_connections)
        tags: Optional tags

    Returns:
        Complete workflow dict with embedded subworkflows
    """
    workflow = {
        "a_galaxy_workflow": "true",
        "format-version": "0.1",
        "name": parent_name,
        "annotation": parent_annotation,
        "tags": tags or [],
        "steps": {}
    }

    step_id = 0

    # Add main steps
    for step in main_steps:
        workflow['steps'][str(step_id)] = {**step, 'id': step_id}
        step_id += 1

    # Add subworkflows
    for name, subwf, connections in subworkflows:
        workflow['steps'][str(step_id)] = {
            "type": "subworkflow",
            "id": step_id,
            "label": name,
            "name": subwf.get('name', name),
            "input_connections": connections,
            "subworkflow": subwf,
            "position": {"left": step_id * 300, "top": 100}
        }
        step_id += 1

    return workflow


# Example: How to create a workflow reference that will be embedded later
def create_subworkflow_reference(
    label: str,
    subworkflow_path: str,
    input_connections: dict,
    position: dict = None
) -> dict:
    """
    Create a subworkflow reference step (to be embedded later).

    This creates a placeholder that embed_all_subworkflows() will process.

    Args:
        label: Display label for the step
        subworkflow_path: Relative path to .ga file (from subworkflows/ dir)
        input_connections: Connections from parent workflow
        position: Visual position in workflow editor

    Returns:
        Step dict with type "subworkflow_reference"
    """
    return {
        "type": "subworkflow_reference",
        "label": label,
        "subworkflow_path": subworkflow_path,
        "input_connections": input_connections,
        "position": position or {"left": 0, "top": 0}
    }


def main():
    """Example usage of the embedding functionality."""
    import sys

    if len(sys.argv) < 3:
        print("Usage: python embed_subworkflows.py <input.ga> <output.ga>")
        print("\nThis script embeds subworkflow references into Galaxy workflows.")
        print("\nExample workflow with subworkflow reference:")
        example = {
            "a_galaxy_workflow": "true",
            "name": "Example Parent Workflow",
            "steps": {
                "0": {
                    "type": "data_input",
                    "label": "Input Data"
                },
                "1": {
                    "type": "subworkflow_reference",
                    "label": "Run Alignment",
                    "subworkflow_path": "genomics/align_reads.ga",
                    "input_connections": {
                        "reads": {"id": 0, "output_name": "output"}
                    }
                }
            }
        }
        print(json.dumps(example, indent=2))
        return

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    subworkflows_dir = Path("/home/yzhang/biomate/Biomni/biomni_galaxy/subworkflows")

    print(f"Loading: {input_path}")
    workflow = load_workflow(input_path)

    print(f"Processing subworkflows from: {subworkflows_dir}")
    result = embed_all_subworkflows(workflow, subworkflows_dir)

    print(f"Saving: {output_path}")
    save_workflow(result, output_path)

    print("Done!")


if __name__ == "__main__":
    main()
