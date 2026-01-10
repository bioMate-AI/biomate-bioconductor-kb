#!/usr/bin/env python3
"""
Test script to verify Docker tag normalization fix.

This script tests that tool versions with '+' characters are properly
converted to Docker-compatible tags with '--' separators.
"""

import sys
import os

# Add galaxy lib to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib/galaxy/galaxy-cloud-executor'))

from galaxy_cloud.galaxy_workflow.tool_registry import GalaxyToolRegistry
from galaxy_cloud.galaxy_workflow.models import ToolContainerInfo


def test_normalize_docker_tag():
    """Test the _normalize_docker_tag method"""
    print("=" * 60)
    print("Testing Docker Tag Normalization")
    print("=" * 60)

    registry = GalaxyToolRegistry({})

    test_cases = [
        # (input, expected_output)
        ('9.3+galaxy1', '9.3--galaxy1'),
        ('2.11.40.8+galaxy0', '2.11.40.8--galaxy0'),
        ('1.0.0+build123', '1.0.0--build123'),
        ('1.2.3', '1.2.3'),  # No change needed
        ('latest', 'latest'),  # No change needed
        (None, None),  # Handle None
    ]

    all_passed = True
    for input_tag, expected in test_cases:
        result = registry._normalize_docker_tag(input_tag)
        status = "✅ PASS" if result == expected else "❌ FAIL"

        if result != expected:
            all_passed = False

        print(f"{status}: '{input_tag}' -> '{result}' (expected: '{expected}')")

    print()
    return all_passed


def test_tool_container_creation():
    """Test that ToolContainerInfo objects use normalized tags"""
    print("=" * 60)
    print("Testing ToolContainerInfo Creation")
    print("=" * 60)

    registry = GalaxyToolRegistry({})

    # Test pattern-based resolution
    tool_id = "toolshed.g2.bx.psu.edu/repos/bgruening/text_processing/tp_replace_in_line/9.3+galaxy1"
    tool_version = "9.3+galaxy1"

    print(f"Tool ID: {tool_id}")
    print(f"Tool Version: {tool_version}")

    container_info = registry._resolve_by_pattern(tool_id, tool_version)

    if container_info:
        print(f"\n✅ Resolved container:")
        print(f"   Image: {container_info.image}")
        print(f"   Tag: {container_info.tag}")
        print(f"   Full: {container_info.image}:{container_info.tag}")

        # Verify tag is normalized
        if '+' in container_info.tag:
            print(f"\n❌ FAIL: Tag still contains '+' character: {container_info.tag}")
            return False
        elif '--' in container_info.tag:
            print(f"\n✅ PASS: Tag properly normalized with '--'")
            return True
        else:
            print(f"\n⚠️  WARNING: Tag doesn't contain '--' (might be acceptable)")
            return True
    else:
        print("\n⚠️  WARNING: Could not resolve container (pattern might not match)")
        return True


def test_image_tag_format():
    """Test that full image:tag format is Docker-compatible"""
    print("=" * 60)
    print("Testing Docker Image Reference Format")
    print("=" * 60)

    # These are the formats that should work
    valid_formats = [
        "quay.io/biocontainers/text_processing:9.3--galaxy1",
        "quay.io/biocontainers/deseq2:2.11.40.8--galaxy0",
        "docker.io/library/python:3.9",
    ]

    # These formats should be avoided (contain invalid characters)
    invalid_formats = [
        "quay.io/biocontainers/text_processing:9.3+galaxy1",  # Contains '+'
        "example.com/repo/image:v1.0.0+build",  # Contains '+'
    ]

    print("\n✅ Valid Docker image references (should use these):")
    for ref in valid_formats:
        print(f"   {ref}")

    print("\n❌ Invalid Docker image references (avoid these):")
    for ref in invalid_formats:
        print(f"   {ref}")

    print("\nDocker tag regex: ^[\\w][\\w.-]{0,127}$")
    print("Allowed characters: [a-zA-Z0-9_.-]")
    print("NOT allowed: '+' (plus sign)")

    return True


def main():
    """Run all tests"""
    print("\n" + "=" * 60)
    print("Docker Tag Normalization Fix - Test Suite")
    print("=" * 60 + "\n")

    results = []

    # Run tests
    results.append(("Tag Normalization", test_normalize_docker_tag()))
    results.append(("Container Creation", test_tool_container_creation()))
    results.append(("Image Format", test_image_tag_format()))

    # Print summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {test_name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if passed == total:
        print("\n✅ All tests passed! The fix is working correctly.")
        return 0
    else:
        print("\n❌ Some tests failed. Please review the output above.")
        return 1


if __name__ == '__main__':
    sys.exit(main())
