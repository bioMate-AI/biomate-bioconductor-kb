#!/usr/bin/env python3
"""
Simple test script for tool parameter extraction from database
No Galaxy dependencies - just SQLite queries
"""

import sqlite3
import json
from pathlib import Path


def test_database_schema():
    """Test direct database access to check parameter storage"""

    db_path = Path(__file__).parent.parent / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return False

    print(f"✓ Database found at {db_path}")
    print("="*80)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Test 1: Check database schema
    print("\n📊 Test 1: Check database schema")
    print("-"*80)

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    tables = [row[0] for row in cursor.fetchall()]
    print(f"Tables: {', '.join(tables)}")

    # Test 2: Get column info for tools table
    print("\n📊 Test 2: Tools table columns")
    print("-"*80)

    cursor.execute("PRAGMA table_info(tools)")
    columns = [(row[1], row[2]) for row in cursor.fetchall()]
    print(f"Columns:")
    for col_name, col_type in columns:
        print(f"  - {col_name:20s} {col_type}")

    # Test 3: Count tools with parameters
    print("\n📊 Test 3: Count tools with parameters")
    print("-"*80)

    cursor.execute("SELECT COUNT(*) FROM tools WHERE parameters IS NOT NULL AND parameters != '[]'")
    param_count = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM tools")
    total_count = cursor.fetchone()[0]

    print(f"Total tools: {total_count}")
    print(f"Tools with parameters: {param_count} ({param_count/total_count*100:.1f}%)")

    # Test 4: Sample a tool with parameters
    print("\n📊 Test 4: Sample tool with parameters")
    print("-"*80)

    cursor.execute("""
        SELECT tool_id, name, version, description, parameters, inputs, outputs, help_text
        FROM tools
        WHERE parameters IS NOT NULL AND parameters != '[]'
        LIMIT 1
    """)

    row = cursor.fetchone()
    if row:
        tool = dict(row)
        print(f"Tool: {tool['name']} ({tool['tool_id']})")
        print(f"Version: {tool['version']}")
        print(f"Description: {tool['description'][:100] if tool['description'] else 'N/A'}...")

        # Parse parameters
        try:
            parameters = json.loads(tool['parameters']) if isinstance(tool['parameters'], str) else tool['parameters']
            print(f"\nParameters ({len(parameters)}):")
            for i, param in enumerate(parameters[:5], 1):
                print(f"  {i}. {param.get('label', param.get('name', 'unnamed'))}")
                print(f"     Type: {param.get('type', 'unknown')}")
                if param.get('help'):
                    print(f"     Help: {param['help'][:60]}...")

            if len(parameters) > 5:
                print(f"  ... and {len(parameters) - 5} more")

            # Show raw JSON
            print(f"\nRaw parameters JSON:")
            print(json.dumps(parameters[:2], indent=2))  # Show first 2

        except Exception as e:
            print(f"❌ Failed to parse parameters: {e}")
            print(f"Raw value: {tool['parameters'][:200]}")

        # Parse inputs
        try:
            inputs = json.loads(tool['inputs']) if isinstance(tool['inputs'], str) else tool['inputs']
            print(f"\nInputs: {len(inputs) if inputs else 0}")
        except:
            print(f"\nInputs: Failed to parse")

        # Parse outputs
        try:
            outputs = json.loads(tool['outputs']) if isinstance(tool['outputs'], str) else tool['outputs']
            print(f"Outputs: {len(outputs) if outputs else 0}")
        except:
            print(f"Outputs: Failed to parse")

    else:
        print("❌ No tools with parameters found")

    # Test 5: Search for specific tools
    print("\n📊 Test 5: Search for XCMS tools")
    print("-"*80)

    cursor.execute("""
        SELECT tool_id, name, parameters
        FROM tools
        WHERE name LIKE '%xcms%' OR tool_id LIKE '%xcms%'
        LIMIT 5
    """)

    xcms_tools = cursor.fetchall()
    if xcms_tools:
        print(f"Found {len(xcms_tools)} XCMS tools:")
        for row in xcms_tools:
            tool = dict(row)
            try:
                params = json.loads(tool['parameters']) if isinstance(tool['parameters'], str) else tool['parameters']
                param_count = len(params) if params else 0
            except:
                param_count = 0

            print(f"  - {tool['name'][:50]:50s} ({param_count} params)")
    else:
        print("No XCMS tools found")

    conn.close()
    print("\n" + "="*80)
    print("✅ Database structure tests complete")
    print("="*80)
    return True


if __name__ == '__main__':
    try:
        test_database_schema()
    except Exception as e:
        print(f"\n❌ Test error: {e}")
        import traceback
        traceback.print_exc()
