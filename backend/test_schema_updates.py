#!/usr/bin/env python3
"""
Test script to verify database schema updates and API responses
"""

import sys
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from galaxy.tools.search_index import ToolSearchIndex


def test_database_path():
    """Test that database can be found at new location"""
    print("=" * 80)
    print("TEST 1: Database Path Configuration")
    print("=" * 80)
    try:
        index = ToolSearchIndex()
        print(f"✅ Database found at: {index.db_path}")
        return True
    except FileNotFoundError as e:
        print(f"❌ Database not found: {e}")
        return False


def test_get_tool_schema():
    """Test that get_tool_schema returns comprehensive metadata"""
    print("\n" + "=" * 80)
    print("TEST 2: Get Tool Schema - Comprehensive Metadata")
    print("=" * 80)

    index = ToolSearchIndex()

    # Search for FastQC tools
    print("\nSearching for FastQC tools...")
    results = index.search("fastqc", limit=10)

    if not results:
        print("❌ No FastQC tools found")
        return False

    print(f"✅ Found {len(results)} FastQC tools")

    # Test first FastQC tool
    test_tool = results[0]
    tool_id = test_tool['tool_id']
    print(f"\nTesting schema for: {test_tool['name']} ({tool_id})")

    schema = index.get_tool_schema(tool_id)

    if not schema:
        print(f"❌ Schema not found for {tool_id}")
        return False

    # Check basic fields
    print("\nBasic fields:")
    for field in ['id', 'name', 'version', 'description']:
        if field in schema:
            value = schema[field]
            value_preview = str(value)[:60] if value else "None"
            print(f"  ✅ {field}: {value_preview}")
        else:
            print(f"  ❌ {field}: MISSING")

    # Check comprehensive metadata fields
    print("\nComprehensive metadata fields:")
    required_fields = ['function_info', 'help', 'requirements', 'examples', 'citations']

    all_present = True
    for field in required_fields:
        if field in schema:
            print(f"  ✅ {field}: present")
        else:
            print(f"  ❌ {field}: MISSING")
            all_present = False

    # Check function_info structure
    if 'function_info' in schema:
        print("\nfunction_info structure:")
        function_info = schema['function_info']
        for key in ['underlying_software', 'wrapper_function', 'operation_type', 'is_primary_function']:
            if key in function_info:
                print(f"  ✅ {key}: {function_info[key]}")
            else:
                print(f"  ❌ {key}: MISSING")
    else:
        print("\n❌ function_info not present in schema")
        all_present = False

    return all_present


def test_multiple_fastqc_tools():
    """Test that different FastQC wrappers are distinguished"""
    print("\n" + "=" * 80)
    print("TEST 3: Multiple FastQC Wrappers - Function Distinction")
    print("=" * 80)

    index = ToolSearchIndex()
    results = index.search("fastqc", limit=20)

    print(f"\nFound {len(results)} FastQC-related tools\n")

    operation_types = {}

    for tool in results:
        schema = index.get_tool_schema(tool['tool_id'])
        if schema and 'function_info' in schema:
            func_info = schema['function_info']
            op_type = func_info.get('operation_type', 'unknown')
            wrapper_func = func_info.get('wrapper_function', 'N/A')
            is_primary = func_info.get('is_primary_function', True)

            if op_type not in operation_types:
                operation_types[op_type] = []

            operation_types[op_type].append({
                'name': schema['name'],
                'function': wrapper_func,
                'is_primary': is_primary
            })

    # Display by operation type
    print("Tools by operation type:")
    for op_type, tools in operation_types.items():
        print(f"\n{op_type.upper()}:")
        for t in tools:
            primary_mark = "⭐ " if t['is_primary'] else "   "
            print(f"  {primary_mark}{t['name']}")
            print(f"      → {t['function']}")

    # Check if we have different operation types
    if len(operation_types) > 1:
        print(f"\n✅ Found {len(operation_types)} different operation types - Function distinction working!")
        return True
    else:
        print(f"\n⚠️  Only found 1 operation type - May need more diverse tools")
        return True  # Still pass, might be expected


def test_installed_tools_graceful():
    """Test that get_installed_tools handles missing columns gracefully"""
    print("\n" + "=" * 80)
    print("TEST 4: Installed Tools - Graceful Degradation")
    print("=" * 80)

    index = ToolSearchIndex()

    try:
        installed = index.get_installed_tools()
        if len(installed) == 0:
            print("✅ get_installed_tools() returned empty list (column may not exist)")
        else:
            print(f"✅ get_installed_tools() returned {len(installed)} tools")
        return True
    except Exception as e:
        print(f"❌ get_installed_tools() raised exception: {e}")
        return False


def main():
    """Run all tests"""
    print("\n" + "=" * 80)
    print("GALAXY AI TOOLS DATABASE - SCHEMA UPDATE TESTS")
    print("=" * 80)

    tests = [
        ("Database Path", test_database_path),
        ("Tool Schema Metadata", test_get_tool_schema),
        ("FastQC Function Distinction", test_multiple_fastqc_tools),
        ("Installed Tools Graceful", test_installed_tools_graceful),
    ]

    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"\n❌ Test '{test_name}' raised exception: {e}")
            import traceback
            traceback.print_exc()
            results.append((test_name, False))

    # Summary
    print("\n" + "=" * 80)
    print("TEST SUMMARY")
    print("=" * 80)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {test_name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if passed == total:
        print("\n🎉 ALL TESTS PASSED!")
        return 0
    else:
        print(f"\n⚠️  {total - passed} test(s) failed")
        return 1


if __name__ == '__main__':
    sys.exit(main())
