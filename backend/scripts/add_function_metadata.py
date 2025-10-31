#!/usr/bin/env python3
"""
Add clear function metadata to distinguish different wrappers of the same software.

For each tool, adds to help_text:
- underlying_software: The base software (e.g., "FastQC")
- wrapper_function: What THIS specific wrapper does (e.g., "Run QC analysis", "Summarize reports")
- operation_type: Category of operation (e.g., "primary_analysis", "post_processing", "visualization")
"""

import sqlite3
import json
import re
from pathlib import Path
from typing import Dict, Optional, Tuple


def extract_underlying_software_name(tool_name: str, requirements_json: str) -> str:
    """Extract the name of the underlying software."""

    # First try requirements
    try:
        requirements = json.loads(requirements_json) if requirements_json else []
        for req in requirements:
            if isinstance(req, dict) and req.get('type') in ['package', 'conda', 'pip']:
                name = req.get('name', '').split('::')[-1]
                if name and name not in ['star', 'picard', 'several']:
                    return name
    except:
        pass

    # Fall back to parsing tool name
    # Remove common suffixes/prefixes
    base_name = tool_name.lower()

    # Remove wrapper-specific parts
    for suffix in ['_site', '_report', '_summary', 'summary', 'aurora_', 'sum_']:
        base_name = base_name.replace(suffix, '')

    return base_name.strip('_')


def infer_wrapper_function(tool_name: str, description: str, tool_id: str) -> Tuple[str, str]:
    """
    Infer what specific function this wrapper performs.

    Returns: (function_description, operation_type)
    """

    name_lower = tool_name.lower()
    desc_lower = description.lower() if description else ''

    # Detect operation type from name/description

    # Post-processing tools
    if any(word in name_lower for word in ['summary', 'summarize', 'aggregate']):
        return ("Summarize or aggregate results from the base tool", "post_processing")

    # Visualization/reporting tools
    if any(word in name_lower for word in ['site', 'report', 'plot', 'graph', 'visuali']):
        if 'site' in name_lower:
            return ("Generate website/portal with results", "visualization")
        else:
            return ("Generate report or visualization", "visualization")

    # Format conversion
    if any(word in name_lower for word in ['convert', 'export', 'import']):
        return ("Convert data format", "format_conversion")

    # Filtering/selection
    if any(word in desc_lower for word in ['filter', 'select', 'subset', 'extract']):
        return ("Filter or select data", "data_manipulation")

    # Batch processing
    if any(word in name_lower for word in ['batch', 'multi', 'parallel']):
        return ("Batch processing version", "batch_processing")

    # Domain-specific versions
    if 'rna' in name_lower or 'rna' in desc_lower:
        return ("RNA-specific version", "primary_analysis")
    if 'dna' in name_lower or 'dna' in desc_lower:
        return ("DNA-specific version", "primary_analysis")
    if 'protein' in name_lower or 'protein' in desc_lower:
        return ("Protein-specific version", "primary_analysis")

    # Analysis keywords
    analysis_keywords = ['quality control', 'qc', 'analyze', 'analysis', 'assess', 'check']
    if any(keyword in desc_lower for keyword in analysis_keywords):
        return ("Perform primary analysis", "primary_analysis")

    # Default: assume primary function
    return ("Primary function of the software", "primary_analysis")


def add_function_metadata(db_path: str):
    """Add function metadata to all tools."""

    print("=" * 80)
    print("Adding Function Metadata to Tools")
    print("=" * 80)
    print()
    print("This clearly distinguishes different wrappers of the same software")
    print("by documenting their specific functions.")
    print()

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT id, tool_id, name, version, description, requirements, help_text FROM tools")
    tools = cursor.fetchall()

    print(f"Processing {len(tools)} tools...")
    print()

    stats = {
        'updated': 0,
        'errors': 0,
        'by_operation': {}
    }

    for tool in tools:
        try:
            # Parse existing help_text
            try:
                help_text = json.loads(tool['help_text']) if tool['help_text'] else {}
            except:
                help_text = {}

            # Extract underlying software name
            underlying_software = extract_underlying_software_name(
                tool['name'],
                tool['requirements']
            )

            # Infer wrapper function
            function_desc, operation_type = infer_wrapper_function(
                tool['name'],
                tool['description'],
                tool['tool_id']
            )

            # Add function metadata
            help_text['function_info'] = {
                'underlying_software': underlying_software,
                'wrapper_name': tool['name'],
                'wrapper_function': function_desc,
                'operation_type': operation_type,
                'is_primary_function': operation_type == 'primary_analysis'
            }

            # Update tool
            cursor.execute(
                "UPDATE tools SET help_text = ? WHERE id = ?",
                (json.dumps(help_text), tool['id'])
            )

            stats['updated'] += 1
            stats['by_operation'][operation_type] = stats['by_operation'].get(operation_type, 0) + 1

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
    print("✅ Function Metadata Added")
    print("=" * 80)
    print(f"   Total updated: {stats['updated']}")
    print()
    print("   By operation type:")
    for op_type, count in sorted(stats['by_operation'].items(), key=lambda x: -x[1]):
        print(f"     {op_type}: {count}")
    print()
    print(f"   Errors: {stats['errors']}")

    return stats


def main():
    """Main function."""
    db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    try:
        stats = add_function_metadata(str(db_path))

        print()
        print("Now each tool has clear metadata showing:")
        print("  • What underlying software it wraps")
        print("  • What specific function this wrapper performs")
        print("  • Whether it's primary analysis vs post-processing vs visualization")
        print()
        print("Multiple wrappers of the same software are clearly distinguished.")

        return 0
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
