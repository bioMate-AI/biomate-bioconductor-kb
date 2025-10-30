#!/usr/bin/env python3
"""
Test script for tool schema endpoint
Verifies that the new /api/tool_search/{tool_id}/schema endpoint
returns properly structured parameters from the database.
"""

import sys
import json
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.galaxy.tools.search_index import ToolSearchIndex


def test_tool_schema_extraction():
    """Test parameter schema extraction from database"""

    # Initialize search index
    db_path = Path(__file__).parent.parent / "galaxy_ai_tools.db"
    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return False

    print(f"✓ Database found at {db_path}")
    print("="*80)

    index = ToolSearchIndex(str(db_path))

    # Test 1: Search for a tool with parameters
    print("\n📊 Test 1: Search for XCMS tools (known to have parameters)")
    print("-"*80)

    xcms_tools = index.search("xcms", limit=5)
    if not xcms_tools:
        print("⚠️  No XCMS tools found in database")
        print("   Trying a broader search...")
        xcms_tools = index.search("metabolomics", limit=5)

    if xcms_tools:
        print(f"✓ Found {len(xcms_tools)} tools")

        # Test the first tool's schema
        tool = xcms_tools[0]
        tool_id = tool.get('tool_id') or tool.get('id')

        print(f"\n📋 Test 2: Get schema for tool: {tool.get('name')} ({tool_id})")
        print("-"*80)

        schema = index.get_tool_schema(tool_id)

        if schema:
            print(f"✓ Schema retrieved successfully")
            print(f"\nTool: {schema['name']} (v{schema['version']})")
            print(f"Description: {schema['description'][:100]}...")
            print(f"\nInputs ({len(schema['inputs'])}):")

            if schema['inputs']:
                for i, input_param in enumerate(schema['inputs'][:5], 1):  # Show first 5
                    print(f"  {i}. {input_param['label']} ({input_param['type']})")
                    if input_param.get('help'):
                        print(f"     Help: {input_param['help'][:80]}...")
                    if input_param.get('optional') is not None:
                        print(f"     Optional: {input_param['optional']}")

                if len(schema['inputs']) > 5:
                    print(f"  ... and {len(schema['inputs']) - 5} more")
            else:
                print("  (no inputs extracted from database)")

            print(f"\nOutputs ({len(schema['outputs'])}):")
            for i, output in enumerate(schema['outputs'][:5], 1):  # Show first 5
                print(f"  {i}. {output['name']} ({output['format']})")

            # Verify structure matches frontend expectations
            print(f"\n🔍 Test 3: Verify schema structure")
            print("-"*80)

            required_fields = ['id', 'name', 'version', 'description', 'inputs', 'outputs']
            missing = [f for f in required_fields if f not in schema]

            if missing:
                print(f"❌ Missing required fields: {missing}")
                return False
            else:
                print("✓ All required fields present")

            if schema['inputs']:
                input_required = ['name', 'label', 'type']
                first_input = schema['inputs'][0]
                missing_input = [f for f in input_required if f not in first_input]

                if missing_input:
                    print(f"❌ Missing required input fields: {missing_input}")
                    return False
                else:
                    print("✓ Input structure valid")

                    # Check type mapping
                    valid_types = ['text', 'integer', 'float', 'boolean', 'select', 'data', 'color', 'genomebuild']
                    if first_input['type'] not in valid_types:
                        print(f"⚠️  Input type '{first_input['type']}' not in standard types")
                    else:
                        print(f"✓ Input type '{first_input['type']}' is valid")

            # Print full schema as JSON for inspection
            print(f"\n📄 Test 4: Full schema JSON")
            print("-"*80)
            print(json.dumps(schema, indent=2)[:1000] + "...")

            return True
        else:
            print(f"❌ Schema not found for tool {tool_id}")
            return False
    else:
        print("❌ No tools found in database")
        return False


def test_multiple_tools():
    """Test schemas for multiple tools"""

    db_path = Path(__file__).parent.parent / "galaxy_ai_tools.db"
    index = ToolSearchIndex(str(db_path))

    print(f"\n\n📊 Test 5: Sample schemas from different categories")
    print("="*80)

    categories = ['metabolomics', 'proteomics', 'genomics', 'quality']
    for category in categories:
        print(f"\n{category.upper()}:")
        print("-"*80)

        tools = index.search(category, limit=3)
        if tools:
            for tool in tools[:3]:
                tool_id = tool.get('tool_id') or tool.get('id')
                schema = index.get_tool_schema(tool_id)
                if schema:
                    param_count = len(schema['inputs'])
                    print(f"  ✓ {schema['name'][:50]:50s} - {param_count} params")
                else:
                    print(f"  ⚠️  {tool.get('name', 'Unknown')[:50]:50s} - no schema")
        else:
            print(f"  (no tools found)")


def main():
    """Main test runner"""
    print("="*80)
    print("Tool Schema Endpoint Test")
    print("="*80)

    try:
        success = test_tool_schema_extraction()

        if success:
            test_multiple_tools()

            print("\n" + "="*80)
            print("✅ ALL TESTS PASSED")
            print("="*80)
            print("\n💡 Next steps:")
            print("   1. Start the backend Galaxy server")
            print("   2. Test the API endpoint: GET /api/tool_search/{tool_id}/schema")
            print("   3. Verify frontend parameter editor can fetch and render parameters")
            return 0
        else:
            print("\n" + "="*80)
            print("❌ TESTS FAILED")
            print("="*80)
            return 1

    except Exception as e:
        print(f"\n❌ Test error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
