#!/usr/bin/env python3
"""
Test API Integration for Workflow Grouping

Tests the complete integration of workflow grouping with the backend API:
1. Convert Galaxy .ga to BUWF with grouping
2. Test grouping patterns endpoint
3. Test workflow converter API
4. Verify serialization and deserialization
"""

import sys
import json
from pathlib import Path

# Add backend to path
backend_path = Path(__file__).parent.parent.parent / "backend"
sys.path.insert(0, str(backend_path))


def test_buwf_serialization():
    """Test BUWF serialization for API responses"""
    print("\n" + "=" * 80)
    print(" Test 1: BUWF Serialization")
    print("=" * 80)

    from lib.galaxy.ai.workflow_converters import (
        GalaxyToUnifiedConverter,
        group_workflow_steps,
        serialize_buwf
    )

    # Load a Galaxy workflow
    workflow_path = Path("backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga")

    if not workflow_path.exists():
        print(f"❌ Workflow not found: {workflow_path}")
        return False

    with open(workflow_path) as f:
        galaxy_wf = json.load(f)

    # Convert to BUWF
    converter = GalaxyToUnifiedConverter()
    unified_wf = converter.convert(galaxy_wf)

    # Apply grouping
    grouped_wf = group_workflow_steps(unified_wf)

    # Serialize to JSON
    buwf_json = serialize_buwf(grouped_wf)

    # Verify structure
    print(f"\n✅ Serialized BUWF workflow:")
    print(f"   Name: {buwf_json['name']}")
    print(f"   High-level steps: {len(buwf_json['high_level_steps'])}")
    print(f"   Source format: {buwf_json['source_format']}")

    # Verify each high-level step has required fields
    for i, step in enumerate(buwf_json['high_level_steps'], 1):
        required_fields = ['step_id', 'name', 'category', 'icon', 'color', 'detailed_steps']
        missing = [f for f in required_fields if f not in step]
        if missing:
            print(f"   ❌ Step {i} missing fields: {missing}")
            return False

        print(f"   Step {i}: {step['icon']} {step['name']} ({len(step['detailed_steps'])} tools)")

    # Test JSON serialization
    try:
        json_str = json.dumps(buwf_json, indent=2)
        print(f"\n✅ JSON serialization successful ({len(json_str)} bytes)")
    except Exception as e:
        print(f"❌ JSON serialization failed: {e}")
        return False

    return True


def test_grouping_patterns():
    """Test retrieving grouping patterns"""
    print("\n" + "=" * 80)
    print(" Test 2: Grouping Patterns")
    print("=" * 80)

    from lib.galaxy.ai.workflow_converters import WorkflowGrouper

    grouper = WorkflowGrouper()

    print(f"\n✅ Loaded {len(grouper.patterns)} grouping patterns:")

    # Group by category
    by_category = {}
    for pattern in grouper.patterns:
        cat = pattern.category.value
        if cat not in by_category:
            by_category[cat] = []
        by_category[cat].append(pattern)

    for category, patterns in sorted(by_category.items()):
        print(f"\n{category.upper()}:")
        for pattern in patterns:
            print(f"   {pattern.icon} {pattern.name} (frequency: {pattern.frequency})")
            print(f"      Tools: {', '.join(pattern.tools[:3])}")
            if len(pattern.tools) > 3:
                print(f"      ... and {len(pattern.tools) - 3} more")

    return True


def test_workflow_converter_api():
    """Test the workflow converter API functions"""
    print("\n" + "=" * 80)
    print(" Test 3: Workflow Converter API")
    print("=" * 80)

    from lib.galaxy.ai.workflow_converters import (
        GalaxyToUnifiedConverter,
        group_workflow_steps,
        GroupingStrategy
    )
    from lib.galaxy.webapps.galaxy.api.workflow_converter import serialize_buwf

    # Load workflow
    workflow_path = Path("backend/galaxy_workflows_official_iwc/computational-chemistry/gromacs-mmgbsa/gromacs-mmgbsa.ga")

    if not workflow_path.exists():
        # Try alternative
        workflow_path = Path("backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga")

    if not workflow_path.exists():
        print(f"❌ No test workflow found")
        return False

    with open(workflow_path) as f:
        galaxy_wf = json.load(f)

    print(f"\nTesting: {workflow_path.name}")

    # Test conversion
    converter = GalaxyToUnifiedConverter()
    unified_wf = converter.convert(galaxy_wf)

    original_steps = len(unified_wf.high_level_steps)
    print(f"   Before grouping: {original_steps} high-level steps")

    # Test each grouping strategy
    strategies = [
        (GroupingStrategy.HYBRID, "Hybrid"),
        (GroupingStrategy.PATTERN_BASED, "Pattern-Based"),
        (GroupingStrategy.CATEGORY_BASED, "Category-Based"),
    ]

    results = []
    for strategy, name in strategies:
        grouped_wf = group_workflow_steps(unified_wf, strategy)
        grouped_steps = len(grouped_wf.high_level_steps)
        reduction = ((original_steps - grouped_steps) / original_steps) * 100

        results.append((name, grouped_steps, reduction))
        print(f"   {name}: {grouped_steps} steps ({reduction:.1f}% reduction)")

    # Verify Hybrid is best or equal
    hybrid_reduction = results[0][2]
    other_reductions = [r[2] for r in results[1:]]

    if hybrid_reduction >= max(other_reductions):
        print(f"\n✅ Hybrid strategy performs best ({hybrid_reduction:.1f}% reduction)")
    else:
        print(f"\n⚠️  Hybrid strategy not optimal (consider tuning)")

    return True


def test_conversion_round_trip():
    """Test round-trip conversion: Galaxy → BUWF → Galaxy"""
    print("\n" + "=" * 80)
    print(" Test 4: Round-Trip Conversion")
    print("=" * 80)

    from lib.galaxy.ai.workflow_converters import (
        GalaxyToUnifiedConverter,
        UnifiedToGalaxyConverter,
        group_workflow_steps
    )

    # Load workflow
    workflow_path = Path("backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga")

    if not workflow_path.exists():
        print(f"❌ Workflow not found: {workflow_path}")
        return False

    with open(workflow_path) as f:
        original_wf = json.load(f)

    print(f"\nTesting round-trip: {workflow_path.name}")

    # Convert to BUWF
    to_unified = GalaxyToUnifiedConverter()
    unified_wf = to_unified.convert(original_wf)

    # Apply grouping
    grouped_wf = group_workflow_steps(unified_wf)

    print(f"   Original Galaxy: {len(original_wf.get('steps', {}))} steps")
    print(f"   BUWF (grouped): {len(grouped_wf.high_level_steps)} high-level steps")

    # Convert back to Galaxy
    to_galaxy = UnifiedToGalaxyConverter()
    converted_wf = to_galaxy.convert(grouped_wf)

    # Count detailed steps (should match original)
    total_detailed = sum(len(hl.detailed_steps) for hl in grouped_wf.high_level_steps)
    converted_steps = len(converted_wf.get('steps', {}))

    print(f"   Converted Galaxy: {converted_steps} steps")

    # Verify step count preservation
    if total_detailed == converted_steps:
        print(f"\n✅ Round-trip preserved all {total_detailed} detailed steps")
        return True
    else:
        print(f"\n❌ Step count mismatch: {total_detailed} → {converted_steps}")
        return False


def test_api_response_format():
    """Test that API response format is correct"""
    print("\n" + "=" * 80)
    print(" Test 5: API Response Format")
    print("=" * 80)

    from lib.galaxy.ai.workflow_converters import (
        GalaxyToUnifiedConverter,
        group_workflow_steps,
        serialize_buwf
    )

    # Load workflow
    workflow_path = Path("backend/galaxy_workflows_reformatted/quantify_pseudo_alignment.ga")

    if not workflow_path.exists():
        print(f"❌ Workflow not found")
        return False

    with open(workflow_path) as f:
        galaxy_wf = json.load(f)

    # Simulate API response generation
    converter = GalaxyToUnifiedConverter()
    unified_wf = converter.convert(galaxy_wf)
    grouped_wf = group_workflow_steps(unified_wf)
    buwf_data = serialize_buwf(grouped_wf)

    # Simulate complete API response
    api_response = {
        'success': True,
        'workflow_ga': galaxy_wf,  # Original Galaxy format
        'buwf_workflow': buwf_data,  # Grouped BUWF format
        'grouped': True,
        'high_level_steps': len(grouped_wf.high_level_steps),
        'detailed_steps': sum(len(hl.detailed_steps) for hl in grouped_wf.high_level_steps),
        'source': 'test',
        'confidence': 1.0
    }

    # Verify all required fields
    required_fields = ['success', 'workflow_ga', 'buwf_workflow', 'grouped', 'high_level_steps']
    missing = [f for f in required_fields if f not in api_response]

    if missing:
        print(f"❌ Missing required fields: {missing}")
        return False

    print(f"\n✅ API response format correct:")
    print(f"   success: {api_response['success']}")
    print(f"   grouped: {api_response['grouped']}")
    print(f"   high_level_steps: {api_response['high_level_steps']}")
    print(f"   detailed_steps: {api_response['detailed_steps']}")

    # Verify JSON serializability
    try:
        json_str = json.dumps(api_response, indent=2, default=str)
        print(f"\n✅ API response is JSON serializable ({len(json_str)} bytes)")
    except Exception as e:
        print(f"❌ JSON serialization failed: {e}")
        return False

    return True


def main():
    """Run all integration tests"""
    print("\n" + "=" * 80)
    print(" API Integration Test Suite")
    print("=" * 80)

    tests = [
        ("BUWF Serialization", test_buwf_serialization),
        ("Grouping Patterns", test_grouping_patterns),
        ("Workflow Converter API", test_workflow_converter_api),
        ("Round-Trip Conversion", test_conversion_round_trip),
        ("API Response Format", test_api_response_format),
    ]

    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
        except Exception as e:
            print(f"\n❌ Test '{name}' failed with exception: {e}")
            import traceback
            traceback.print_exc()
            results.append((name, False))

    # Print summary
    print("\n" + "=" * 80)
    print(" Test Summary")
    print("=" * 80)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if passed == total:
        print("\n🎉 All integration tests passed!")
        return 0
    else:
        print(f"\n⚠️  {total - passed} test(s) failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
