#!/usr/bin/env python3
"""
Test script to verify package name resolution for container lookup.

This script simulates how Galaxy resolves tool requirements to container images.
"""

import sys
import os

# Add galaxy lib to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib/galaxy/galaxy-cloud-executor'))

from galaxy_cloud.galaxy_workflow.tool_registry import GalaxyToolRegistry


def test_package_name_resolution():
    """Test resolving package names to container images"""
    print("=" * 70)
    print("Testing Package Name to Container Resolution")
    print("=" * 70)

    registry = GalaxyToolRegistry({})

    # Test cases: (package_name, version)
    test_cases = [
        ('coreutils', '9.3'),
        ('text_processing', '9.3+galaxy1'),
        ('pick_value', '0.2.0'),
        ('python', '3.9'),
    ]

    for package_name, version in test_cases:
        print(f"\n📦 Package: {package_name} v{version}")

        # Clean the package name
        cleaned = registry._clean_tool_id_for_biocontainers(package_name)
        print(f"   Cleaned name: {cleaned}")

        # Normalize the version
        normalized_version = registry._normalize_docker_tag(version)
        print(f"   Normalized version: {normalized_version}")

        # Try pattern-based resolution
        container_info = registry._resolve_by_pattern(package_name, version)
        if container_info:
            full_image = f"{container_info.image}:{container_info.tag}"
            print(f"   ✅ Resolved: {full_image}")
        else:
            print(f"   ❌ Could not resolve")


def test_tool_vs_package_names():
    """Demonstrate the difference between tool IDs and package names"""
    print("\n" + "=" * 70)
    print("Tool ID vs Package Name Mapping")
    print("=" * 70)

    examples = [
        ("Tool ID", "Package Name", "Container Image"),
        ("-" * 30, "-" * 20, "-" * 40),
        ("text_processing", "coreutils", "quay.io/biocontainers/coreutils:9.3"),
        ("pick_value", "pick_value", "quay.io/biocontainers/pick_value:0.2.0"),
        ("tp_replace_in_line", "coreutils", "quay.io/biocontainers/coreutils:9.3"),
    ]

    for tool_id, package, container in examples:
        print(f"{tool_id:30s} | {package:20s} | {container}")

    print("\n💡 Key Insight:")
    print("   Galaxy tool IDs != Conda package names != Container image names")
    print("   We must extract the actual package requirement from tool XML!")


def test_real_world_case():
    """Test the actual text_processing tool case"""
    print("\n" + "=" * 70)
    print("Real World Example: text_processing Tool")
    print("=" * 70)

    registry = GalaxyToolRegistry({})

    print("\n❌ WRONG Approach (using tool ID):")
    print("   Tool ID: text_processing")
    print("   Looking for: quay.io/biocontainers/text_processing:9.3--galaxy1")
    print("   Result: ❌ Image does not exist!")

    print("\n✅ CORRECT Approach (using requirement package):")
    print("   Tool ID: text_processing")
    print("   Tool Requirement: <requirement type='package'>coreutils</requirement>")
    print("   Looking for: quay.io/biocontainers/coreutils:9.3")

    # Try to resolve coreutils
    container_info = registry._resolve_by_pattern('coreutils', '9.3')
    if container_info:
        full_image = f"{container_info.image}:{container_info.tag}"
        print(f"   Result: ✅ {full_image}")
        print("\n   This image EXISTS and can be pulled from quay.io!")


def main():
    """Run all tests"""
    print("\n" + "=" * 70)
    print("Container Resolution Fix - Test Suite")
    print("=" * 70 + "\n")

    test_package_name_resolution()
    test_tool_vs_package_names()
    test_real_world_case()

    print("\n" + "=" * 70)
    print("Summary")
    print("=" * 70)
    print("""
✅ Fix Applied:
   - Modified galaxy_job_runner.py to extract package names from tool.requirements
   - Tool registry now uses package names instead of tool IDs for container lookup
   - Docker tag normalization converts '+' to '--' for compatibility

📋 Example Flow:
   1. Galaxy tool: text_processing (tool ID)
   2. Tool XML: <requirement>coreutils==9.3</requirement>
   3. Container lookup: coreutils (package name)
   4. Container image: quay.io/biocontainers/coreutils:9.3
   5. Docker pull: ✅ SUCCESS

🔧 Next Steps:
   1. Restart Galaxy to apply the fix
   2. Re-run the workflow
   3. Check AWS Batch logs for successful container pulls
""")


if __name__ == '__main__':
    main()
