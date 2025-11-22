#!/usr/bin/env python3
"""
Test script for Nextflow workflow conversion.

Tests NextflowToUnifiedConverter and UnifiedToNextflowConverter
with nf-core subworkflows.

Usage:
    python test_nextflow_conversion.py
"""

import sys
import json
from pathlib import Path

# Add backend to path
backend_path = Path(__file__).parent.parent.parent / "backend"
sys.path.insert(0, str(backend_path / "lib"))

from galaxy.ai.workflow_converters import (
    NextflowToUnifiedConverter,
    UnifiedToNextflowConverter,
    parse_nextflow_file
)


def test_nextflow_workflow(workflow_path: Path):
    """Test conversion of a single Nextflow workflow."""
    print(f"\n{'='*60}")
    print(f"Testing: {workflow_path.name}")
    print('='*60)

    # 1. Parse Nextflow workflow
    print("\n1. Parsing Nextflow workflow...")
    try:
        nf_workflow = parse_nextflow_file(workflow_path)
        print(f"   ✓ Parsed successfully")
        print(f"   - Workflow name: {nf_workflow.name}")
        print(f"   - Description: {nf_workflow.description}")
        print(f"   - Includes: {len(nf_workflow.includes)} modules")
        print(f"   - Inputs: {len(nf_workflow.inputs)} channels")
        print(f"   - Outputs: {len(nf_workflow.outputs)} channels")
        print(f"   - Process calls: {len(nf_workflow.process_calls)}")
    except Exception as e:
        print(f"   ✗ Parsing failed: {e}")
        import traceback
        traceback.print_exc()
        return False

    # 2. Convert to BUWF
    print("\n2. Converting Nextflow → BUWF...")
    try:
        converter = NextflowToUnifiedConverter()
        unified_workflow = converter.convert(nf_workflow)
        print(f"   ✓ Converted successfully")
        print(f"   - Workflow name: {unified_workflow.name}")
        print(f"   - High-level steps: {len(unified_workflow.high_level_steps)}")
        print(f"   - Detailed steps: {len(unified_workflow.get_all_detailed_steps())}")
        print(f"   - Source format: {unified_workflow.source_format.value}")
        print(f"   - Execution engine: {unified_workflow.execution_engine.value}")
    except Exception as e:
        print(f"   ✗ Conversion failed: {e}")
        import traceback
        traceback.print_exc()
        return False

    # 3. Validate BUWF
    print("\n3. Validating BUWF...")
    is_valid, errors = unified_workflow.validate()
    if is_valid:
        print("   ✓ Workflow is valid")
    else:
        print(f"   ✗ Validation errors:")
        for error in errors:
            print(f"      - {error}")
        return False

    # 4. Print high-level steps
    print("\n4. High-Level Steps:")
    for idx, hl_step in enumerate(unified_workflow.high_level_steps, 1):
        print(f"   {idx}. {hl_step.name}")
        print(f"      - Category: {hl_step.category.value}")
        print(f"      - Icon: {hl_step.icon}")
        print(f"      - Tools: {[s.tool_name for s in hl_step.detailed_steps]}")
        print(f"      - Inputs: {[i.name for i in hl_step.inputs]}")

    # 5. Convert back to Nextflow
    print("\n5. Converting BUWF → Nextflow...")
    try:
        nf_converter = UnifiedToNextflowConverter()
        nf_output = nf_converter.convert(unified_workflow)
        print(f"   ✓ Converted successfully")
        print(f"   - Files generated: {len(nf_output)}")
        for filename in nf_output.keys():
            print(f"      - {filename}")
    except Exception as e:
        print(f"   ✗ Conversion failed: {e}")
        import traceback
        traceback.print_exc()
        return False

    # 6. Display main.nf content
    print("\n6. Generated main.nf (first 30 lines):")
    if "main.nf" in nf_output:
        lines = nf_output["main.nf"].split('\n')[:30]
        for i, line in enumerate(lines, 1):
            print(f"   {i:3d} | {line}")
        if len(nf_output["main.nf"].split('\n')) > 30:
            print(f"   ... ({len(nf_output['main.nf'].split(chr(10))) - 30} more lines)")

    # 7. Save generated files
    output_dir = workflow_path.parent / f"{workflow_path.stem}_generated"
    output_dir.mkdir(exist_ok=True)

    print(f"\n7. Saving generated Nextflow files to: {output_dir}")
    for filename, content in nf_output.items():
        output_path = output_dir / filename
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(content)
        print(f"   ✓ Saved {filename}")

    # 8. Export BUWF to JSON
    print("\n8. Exporting BUWF to JSON...")
    json_output = unified_workflow.to_json(indent=2)
    json_path = output_dir / "workflow.buwf.json"
    json_path.write_text(json_output)
    print(f"   ✓ Saved to {json_path}")
    print(f"   - JSON length: {len(json_output)} characters")

    print(f"\n{'='*60}")
    print("✅ Test passed!")
    print('='*60)

    return True


def main():
    """Test Nextflow conversion with nf-core subworkflows."""

    # Find nf-core subworkflows
    nf_core_dir = Path(__file__).parent.parent.parent / "backend" / "nf-core-workflows"

    if not nf_core_dir.exists():
        print(f"Error: nf-core directory not found: {nf_core_dir}")
        return 1

    # Find subworkflow files
    subworkflow_files = list(nf_core_dir.glob("**/subworkflows/**/*.nf"))

    # Filter for main.nf files (actual subworkflows)
    subworkflow_files = [f for f in subworkflow_files if f.name == "main.nf"]

    if not subworkflow_files:
        print(f"Error: No subworkflow main.nf files found in {nf_core_dir}")
        return 1

    print(f"Found {len(subworkflow_files)} Nextflow subworkflows")
    print(f"Testing first subworkflow...")

    # Test first subworkflow
    success = test_nextflow_workflow(subworkflow_files[0])

    if success:
        print("\n🎉 Nextflow conversion test successful!")
        print(f"\nTo test all {len(subworkflow_files)} subworkflows, run:")
        print(f"    python research/scripts/test_all_nextflow_conversions.py")
        return 0
    else:
        print("\n❌ Nextflow conversion test failed!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
