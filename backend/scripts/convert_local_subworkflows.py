#!/usr/bin/env python3
"""
Convert local nf-core subworkflows to Galaxy .ga format.
Local subworkflows are workflow-specific (not shared across nf-core).
"""

import os
import json
from pathlib import Path
from convert_nfcore_to_galaxy import (
    parse_nextflow_subworkflow,
    map_tools_to_galaxy,
    generate_galaxy_workflow_with_llm
)


def find_local_subworkflows(workflows_dir: Path) -> list:
    """Find all local subworkflows in nf-core workflow directories."""
    local_subworkflows = []

    # Find all workflow directories
    for workflow_dir in workflows_dir.iterdir():
        if not workflow_dir.is_dir():
            continue

        # Look for subworkflows/local directory
        local_dir = workflow_dir / "subworkflows" / "local"
        if not local_dir.exists():
            continue

        # Find all main.nf files in local subworkflows
        for subworkflow_dir in local_dir.iterdir():
            if not subworkflow_dir.is_dir():
                continue

            main_nf = subworkflow_dir / "main.nf"
            if main_nf.exists():
                local_subworkflows.append({
                    'path': subworkflow_dir,
                    'workflow': workflow_dir.name,
                    'name': subworkflow_dir.name
                })

    return local_subworkflows


def convert_local_subworkflow(
    subworkflow_info: dict,
    db_path: str,
    api_key: str,
    output_dir: Path
) -> bool:
    """Convert a single local subworkflow to Galaxy .ga format."""

    subworkflow_path = subworkflow_info['path']
    workflow_name = subworkflow_info['workflow']
    subworkflow_name = subworkflow_info['name']

    main_nf = subworkflow_path / "main.nf"

    print(f"\n{'='*80}")
    print(f"Converting: {workflow_name}/{subworkflow_name}")
    print('='*80)

    # Step 1: Parse Nextflow code
    print("  📝 Parsing Nextflow structure...")
    parsed = parse_nextflow_subworkflow(main_nf)
    print(f"     - Workflow: {parsed['workflow_name']}")
    print(f"     - Tools: {', '.join(parsed['tool_calls']) if parsed['tool_calls'] else 'None'}")

    # Step 2: Map to Galaxy tools
    print("  🔍 Mapping to Galaxy tools...")
    tool_mapping = map_tools_to_galaxy(parsed['tool_calls'], db_path)
    print(f"     - Mapped: {len(tool_mapping)}/{len(parsed['tool_calls'])} tools")

    # Step 3: Generate Galaxy workflow with LLM
    print("  🤖 Generating Galaxy workflow with LLM...")
    galaxy_workflow = generate_galaxy_workflow_with_llm(parsed, tool_mapping, api_key)

    if not galaxy_workflow:
        return False

    # Step 4: Save .ga file with workflow prefix
    output_file = output_dir / f"{workflow_name}_{subworkflow_name}.ga"
    with open(output_file, 'w') as f:
        json.dump(galaxy_workflow, f, indent=2)

    print(f"  ✅ Saved: {output_file}")
    return True


def main():
    import argparse

    parser = argparse.ArgumentParser(description='Convert local nf-core subworkflows to Galaxy .ga format')
    parser.add_argument('--workflows', default='/opt/biomate/backend/nf-core-workflows',
                       help='Path to nf-core workflows directory')
    parser.add_argument('--db', default='/opt/biomate/backend/database/galaxy_ai_tools.db',
                       help='Path to Galaxy tools database')
    parser.add_argument('--output', default='/opt/biomate/backend/galaxy_workflows/local',
                       help='Output directory for .ga files')
    parser.add_argument('--limit', type=int, help='Limit number of subworkflows to convert')

    args = parser.parse_args()

    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        print("❌ Error: ANTHROPIC_API_KEY not set")
        return 1

    # Create output directory
    output_dir = Path(args.output)
    output_dir.mkdir(exist_ok=True, parents=True)

    print("=" * 80)
    print("nf-core Local Subworkflows → Galaxy Converter")
    print("=" * 80)
    print(f"Source: {args.workflows}")
    print(f"Database: {args.db}")
    print(f"Output: {output_dir}")
    print()

    # Find all local subworkflows
    workflows_path = Path(args.workflows)
    local_subworkflows = find_local_subworkflows(workflows_path)

    if args.limit:
        local_subworkflows = local_subworkflows[:args.limit]

    print(f"Found {len(local_subworkflows)} local subworkflows to convert")
    print()

    # Convert each subworkflow
    success_count = 0
    fail_count = 0

    for subworkflow_info in local_subworkflows:
        if convert_local_subworkflow(subworkflow_info, args.db, api_key, output_dir):
            success_count += 1
        else:
            fail_count += 1

    print()
    print("=" * 80)
    print("✅ Conversion Complete")
    print("=" * 80)
    print(f"   Successful: {success_count}")
    print(f"   Failed: {fail_count}")
    print(f"   Output: {output_dir}")

    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
