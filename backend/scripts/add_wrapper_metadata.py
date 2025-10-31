#!/usr/bin/env python3
"""
Add metadata to clarify that tools are wrappers/modules, not the underlying software.

Adds to help_text:
- wrapper_type: "galaxy_tool" or "nfcore_module"
- underlying_software: Name of actual software (from requirements)
- software_version: Version of underlying software
- wrapper_version: Version of the wrapper itself
"""

import sqlite3
import json
from pathlib import Path
from typing import Dict, Optional


def extract_underlying_software(requirements_json: str, version: str) -> Dict:
    """Extract underlying software information from requirements."""
    try:
        requirements = json.loads(requirements_json) if requirements_json else []
    except:
        requirements = []

    # Find the main software package (usually first non-meta requirement)
    software_name = None
    software_version = None

    for req in requirements:
        if not isinstance(req, dict):
            continue

        req_type = req.get('type', '')
        req_name = req.get('name', '')
        req_version = req.get('version')

        # Skip meta requirements
        if req_type in ['tool', 'set_environment'] or req_name in ['star', 'picard', 'several']:
            continue

        # Found likely main software
        if req_type in ['package', 'conda', 'pip']:
            # Clean conda prefix like "bioconda::fastqc"
            clean_name = req_name.split('::')[-1] if '::' in req_name else req_name
            software_name = clean_name
            software_version = req_version
            break

    return {
        'software_name': software_name,
        'software_version': software_version,
        'wrapper_version': version
    }


def determine_wrapper_type(tool_id: str, category: str, repo_owner: str) -> str:
    """Determine what type of wrapper this is."""
    if category == 'nf-core':
        return 'nfcore_module'
    elif 'toolshed' in tool_id.lower() or repo_owner:
        return 'galaxy_tool'
    else:
        return 'galaxy_builtin'


def add_wrapper_metadata(db_path: str):
    """Add wrapper metadata to all tools."""

    print("=" * 80)
    print("Adding Wrapper Metadata to Tools")
    print("=" * 80)
    print()
    print("This clarifies that each entry is a wrapper/module,")
    print("not the underlying software itself.")
    print()

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT id, tool_id, name, version, category, repo_owner, requirements, help_text FROM tools")
    tools = cursor.fetchall()

    print(f"Processing {len(tools)} tools...")
    print()

    stats = {
        'updated': 0,
        'errors': 0,
        'galaxy_tools': 0,
        'nfcore_modules': 0,
        'galaxy_builtins': 0
    }

    for tool in tools:
        try:
            # Parse existing help_text
            try:
                help_text = json.loads(tool['help_text']) if tool['help_text'] else {}
            except:
                help_text = {}

            # Determine wrapper type
            wrapper_type = determine_wrapper_type(
                tool['tool_id'],
                tool['category'],
                tool['repo_owner']
            )

            # Extract underlying software
            software_info = extract_underlying_software(
                tool['requirements'],
                tool['version']
            )

            # Add wrapper metadata
            help_text['wrapper_info'] = {
                'type': wrapper_type,
                'wrapper_name': tool['name'],
                'wrapper_version': software_info['wrapper_version'],
                'underlying_software': software_info['software_name'],
                'software_version': software_info['software_version'],
                'description': get_wrapper_description(wrapper_type)
            }

            # Update tool
            cursor.execute(
                "UPDATE tools SET help_text = ? WHERE id = ?",
                (json.dumps(help_text), tool['id'])
            )

            stats['updated'] += 1
            stats[f"{wrapper_type}s"] = stats.get(f"{wrapper_type}s", 0) + 1

            if stats['updated'] % 1000 == 0:
                print(f"  Processed {stats['updated']} tools...")
                conn.commit()

        except Exception as e:
            stats['errors'] += 1
            if stats['errors'] <= 5:
                print(f"  Error processing {tool['name']}: {str(e)}")

    conn.commit()
    conn.close()

    print()
    print("=" * 80)
    print("✅ Wrapper Metadata Added")
    print("=" * 80)
    print(f"   Total updated: {stats['updated']}")
    print(f"   Galaxy tools: {stats.get('galaxy_tools', 0)}")
    print(f"   nf-core modules: {stats.get('nfcore_modules', 0)}")
    print(f"   Galaxy builtins: {stats.get('galaxy_builtins', 0)}")
    print(f"   Errors: {stats['errors']}")

    return stats


def get_wrapper_description(wrapper_type: str) -> str:
    """Get description of what this wrapper type means."""
    descriptions = {
        'galaxy_tool': 'This is a Galaxy Tool wrapper that provides a web interface and parameter handling for the underlying software.',
        'nfcore_module': 'This is an nf-core module that wraps the software for use in Nextflow pipelines.',
        'galaxy_builtin': 'This is a Galaxy built-in tool.'
    }
    return descriptions.get(wrapper_type, 'This is a wrapper for the underlying software.')


def main():
    """Main function."""
    db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    try:
        stats = add_wrapper_metadata(str(db_path))
        return 0
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
