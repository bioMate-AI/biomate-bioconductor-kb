#!/usr/bin/env python3
"""
Test script for GalaxyWorkflowGenerator
"""

import sys
import os
import json
import logging

# Enable logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Add Galaxy lib to path
sys.path.insert(1, os.path.join(os.path.dirname(__file__), "lib"))

from galaxy.ai.galaxy_workflow_generator import GalaxyWorkflowGenerator

def test_workflow_generation():
    """Test complete workflow generation with tool validation and datasets."""

    print("=" * 70)
    print("Testing Galaxy Workflow Generator")
    print("=" * 70)

    # Test case
    user_intent = "Identify metabolites from human serum LC-MS data using peak detection and compound identification"

    print(f"\nUser Intent: {user_intent}")
    print("\n" + "=" * 70)

    # Initialize generator
    print("\n[1/4] Initializing GalaxyWorkflowGenerator...")
    generator = GalaxyWorkflowGenerator()
    print("  ✓ Generator initialized")

    # Generate workflow
    print("\n[2/4] Generating workflow...")
    result = generator.generate_workflow(
        user_intent=user_intent,
        max_tools_search=30
    )

    if result['success']:
        print("  ✓ Workflow generated successfully!")

        # Save workflow
        print("\n[3/4] Saving workflow...")
        output_file = 'test_generated_workflow.ga'
        generator.save_workflow(result, output_file)
        print(f"  ✓ Workflow saved to {output_file}")

        # Save detailed results
        print("\n[4/4] Saving detailed results...")
        with open('test_workflow_generation_results.json', 'w') as f:
            json.dump({
                'user_intent': result['user_intent'],
                'workflow_structure': result['workflow_structure'],
                'dataset_assignments': result['dataset_assignments'],
                'tool_count': len(result['tool_selections'])
            }, f, indent=2)
        print("  ✓ Detailed results saved to test_workflow_generation_results.json")

        # Print summary
        print("\n" + "=" * 70)
        print("WORKFLOW SUMMARY")
        print("=" * 70)
        print(f"\nWorkflow Name: {result['workflow_structure']['workflow_name']}")
        print(f"Tools Retrieved: {len(result['tool_selections'])}")
        print(f"Steps: {len(result['workflow_structure']['steps'])}")
        print(f"\nReasoning: {result['workflow_structure']['reasoning']}")

        print("\n" + "-" * 70)
        print("WORKFLOW STEPS")
        print("-" * 70)

        for step in result['workflow_structure']['steps']:
            print(f"\nStep {step['step']}: {step['tool_name']}")
            print(f"  Tool ID: {step['tool_id']}")
            print(f"  Purpose: {step['purpose']}")

            # Show datasets if assigned
            for step_data in result['dataset_assignments']['workflow_steps']:
                if step_data['step'] == step['step']:
                    if step_data.get('dataset_needed'):
                        if step_data.get('selected_datasets'):
                            print(f"  Datasets ({len(step_data['selected_datasets'])}):")
                            for ds in step_data['selected_datasets']:
                                print(f"    - {ds['name']}")
                                print(f"      Reason: {ds['reason'][:100]}...")
                        else:
                            print(f"  Datasets: Required but none available")
                    else:
                        print(f"  Datasets: Not needed")
                    print(f"  Reasoning: {step_data.get('reasoning', 'N/A')[:100]}...")

        # Check for validation errors
        if 'validation_errors' in result['workflow_structure']:
            print("\n" + "=" * 70)
            print("⚠️  VALIDATION WARNINGS")
            print("=" * 70)
            for error in result['workflow_structure']['validation_errors']:
                print(f"  Step {error['step']}: {error['message']}")

        # Check for missing tools
        if result['workflow_structure'].get('missing_tools'):
            print("\n" + "=" * 70)
            print("⚠️  MISSING TOOLS")
            print("=" * 70)
            for tool in result['workflow_structure']['missing_tools']:
                print(f"  - {tool}")

        print("\n" + "=" * 70)
        print("✓ TEST PASSED - Workflow generated successfully!")
        print("=" * 70)

        return True

    else:
        print(f"\n✗ Workflow generation failed!")
        print(f"  Error: {result.get('error')}")
        print(f"  Message: {result.get('message')}")

        print("\n" + "=" * 70)
        print("✗ TEST FAILED")
        print("=" * 70)

        return False


if __name__ == '__main__':
    try:
        success = test_workflow_generation()
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\n✗ Test crashed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
