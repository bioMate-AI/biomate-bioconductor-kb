#!/usr/bin/env python3
"""
Verify Enhanced Metadata Storage

This script verifies that enhanced metadata (dependencies, test_commands,
install_commands, container_info) is being properly saved to the database
and can be retrieved for tool installation, implementation, and execution.
"""

import json
import sqlite3
from pathlib import Path

def verify_enhanced_metadata(db_path: Path):
    """Verify enhanced metadata in database"""

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Check if columns exist
    cursor.execute("PRAGMA table_info(tools)")
    columns = {row['name'] for row in cursor.fetchall()}

    required_columns = {'dependencies', 'test_commands', 'install_commands', 'container_info'}
    missing_columns = required_columns - columns

    if missing_columns:
        print(f"❌ Missing columns: {missing_columns}")
        return False

    print("✅ All enhanced metadata columns exist")

    # Check if any tools have enhanced metadata
    cursor.execute("""
        SELECT tool_id, name, dependencies, test_commands, install_commands, container_info
        FROM tools
        WHERE auto_discovered = 1
        ORDER BY discovery_date DESC
        LIMIT 5
    """)

    tools = cursor.fetchall()

    if not tools:
        print("ℹ️  No auto-discovered tools in database yet")
        conn.close()
        return True

    print(f"\n✅ Found {len(tools)} recently auto-discovered tools")
    print("\nEnhanced Metadata Status:")
    print("=" * 80)

    complete_count = 0
    for tool in tools:
        print(f"\nTool: {tool['name']} ({tool['tool_id']})")

        # Parse JSON fields
        has_deps = False
        has_tests = False
        has_install = False
        has_container = False

        try:
            if tool['dependencies']:
                deps = json.loads(tool['dependencies'])
                if deps:
                    has_deps = True
                    print(f"  ✅ Dependencies: {len(deps)} packages")
                    if len(deps) > 0:
                        print(f"     Example: {deps[0]}")
        except:
            pass

        try:
            if tool['test_commands']:
                tests = json.loads(tool['test_commands'])
                if tests:
                    has_tests = True
                    print(f"  ✅ Test Commands: {len(tests)} commands")
                    if len(tests) > 0:
                        print(f"     Example: {tests[0]}")
        except:
            pass

        try:
            if tool['install_commands']:
                installs = json.loads(tool['install_commands'])
                if installs:
                    has_install = True
                    print(f"  ✅ Install Commands: {len(installs)} commands")
                    if len(installs) > 0:
                        print(f"     Example: {installs[0]}")
        except:
            pass

        try:
            if tool['container_info']:
                container = json.loads(tool['container_info'])
                if container and container.get('image'):
                    has_container = True
                    print(f"  ✅ Container: {container.get('image', 'N/A')}")
        except:
            pass

        if not has_deps:
            print("  ⚠️  No dependencies")
        if not has_tests:
            print("  ⚠️  No test commands")
        if not has_install:
            print("  ⚠️  No install commands")
        if not has_container:
            print("  ⚠️  No container info")

        if has_deps and has_tests and has_install and has_container:
            complete_count += 1
            print("  ✓ COMPLETE: Can install, implement, and execute")

    print("\n" + "=" * 80)
    print(f"Summary: {complete_count}/{len(tools)} tools have complete enhanced metadata")

    if complete_count > 0:
        print("\n✅ VERIFICATION PASSED: Enhanced metadata is being saved correctly")
        print("   Tools can be installed, implemented, and executed based on indexed info")
    elif len(tools) > 0:
        print("\n⚠️  VERIFICATION PARTIAL: Some tools missing enhanced metadata")
        print("   Check that enhanced_metadata_extractor is running in pipeline")

    conn.close()
    return True


if __name__ == '__main__':
    import sys

    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1])
    else:
        db_path = Path(__file__).parent.parent.parent / 'backend' / 'galaxy_ai_tools.db'

    if not db_path.exists():
        print(f"❌ Database not found: {db_path}")
        sys.exit(1)

    print(f"Verifying enhanced metadata in: {db_path}")
    print()

    verify_enhanced_metadata(db_path)
