#!/usr/bin/env python3
"""
Quick test script for Galaxy workflow conversion.

Tests GalaxyToUnifiedConverter and UnifiedToGalaxyConverter
with sample workflows.

Usage:
    python test_galaxy_conversion_quick.py
"""

import sys
import json
from pathlib import Path

# Add backend to path
backend_path = Path(__file__).parent.parent.parent / "backend"
sys.path.insert(0, str(backend_path / "lib"))

from galaxy.ai.workflow_converters import (
    GalaxyToUnifiedConverter,
    UnifiedToGalaxyConverter
)


def test_galaxy_workflow(workflow_path: Path):
    """Test conversion of a single Galaxy workflow."""
    print(f"\n{'='*60}")
    print(f"Testing: {workflow_path.name}")
    print('='*60)

    # 1. Load Galaxy workflow
    print("\n1. Loading Galaxy workflow...")
    with open(workflow_path) as f:
        galaxy_workflow = json.load(f)
    print(f"   ✓ Loaded {len(galaxy_workflow.get('steps', {}))} steps")

    # 2. Convert to BUWF
    print("\n2. Converting Galaxy → BUWF...")
    try:
        converter = GalaxyToUnifiedConverter()
        unified_workflow = converter.convert(galaxy_workflow)
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
        print(f"      - Tools: {[s.tool_name for s in hl_step.detailed_steps]}")
        print(f"      - Category: {hl_step.category.value}")
        print(f"      - Inputs: {len(hl_step.inputs)}")
        print(f"      - Outputs: {len(hl_step.outputs)}")

    # 5. Convert back to Galaxy
    print("\n5. Converting BUWF → Galaxy...")
    try:
        galaxy_converter = UnifiedToGalaxyConverter()
        galaxy_output = galaxy_converter.convert(unified_workflow)
        print(f"   ✓ Converted successfully")
        print(f"   - Output steps: {len(galaxy_output.get('steps', {}))}")
    except Exception as e:
        print(f"   ✗ Conversion failed: {e}")
        import traceback
        traceback.print_exc()
        return False

    # 6. Compare step counts (should be same)
    print("\n6. Comparing round-trip...")
    orig_steps = len(galaxy_workflow.get('steps', {}))
    output_steps = len(galaxy_output.get('steps', {}))

    # Count tool steps (exclude input steps)
    orig_tool_steps = sum(
        1 for s in galaxy_workflow.get('steps', {}).values()
        if s.get('type') in ('tool', 'subworkflow')
    )
    output_tool_steps = sum(
        1 for s in galaxy_output.get('steps', {}).values()
        if s.get('type') in ('tool', 'subworkflow')
    )

    if orig_tool_steps == output_tool_steps:
        print(f"   ✓ Step count preserved: {orig_tool_steps} tool steps")
    else:
        print(f"   ⚠ Step count mismatch:")
        print(f"      Original: {orig_tool_steps} tool steps")
        print(f"      Output: {output_tool_steps} tool steps")

    # 7. Export to JSON
    print("\n7. Exporting BUWF to JSON...")
    json_output = unified_workflow.to_json(indent=2)
    print(f"   ✓ JSON length: {len(json_output)} characters")

    # 8. Save Galaxy output
    output_path = workflow_path.parent / f"{workflow_path.stem}_converted.ga"
    with open(output_path, 'w') as f:
        json.dump(galaxy_output, f, indent=2)
    print(f"\n8. Saved converted Galaxy workflow to: {output_path}")

    print(f"\n{'='*60}")
    print("✅ Test passed!")
    print('='*60)

    return True


def main():
    """Test Galaxy conversion with sample workflows."""

    # Find sample workflows
    workflows_dir = Path(__file__).parent.parent.parent / "backend" / "galaxy_workflows_reformatted"

    if not workflows_dir.exists():
        print(f"Error: Workflow directory not found: {workflows_dir}")
        return 1

    # Get first workflow as test
    workflow_files = list(workflows_dir.glob("*.ga"))

    if not workflow_files:
        print(f"Error: No .ga files found in {workflows_dir}")
        return 1

    print(f"Found {len(workflow_files)} Galaxy workflows")
    print(f"Testing first workflow...")

    # Test first workflow
    success = test_galaxy_workflow(workflow_files[0])

    if success:
        print("\n🎉 Galaxy conversion test successful!")
        return 0
    else:
        print("\n❌ Galaxy conversion test failed!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
