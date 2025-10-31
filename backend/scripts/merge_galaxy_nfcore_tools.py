#!/usr/bin/env python3
"""
Merge nf-core and Galaxy tool information for tools that exist in both sources.

Strategy:
- Keep Galaxy tool as primary (has parameters, Galaxy integration)
- Merge nf-core metadata into Galaxy tool:
  - Better descriptions (if Galaxy description is generic)
  - Examples (nf-core has better examples)
  - Structured I/O details
  - EDAM ontology terms
  - Exact version info from requirements
  - Homepage URL
- Delete nf-core duplicate after merge
- Add metadata to indicate merged sources
"""

import sqlite3
import json
from pathlib import Path
from typing import Dict, List, Any, Optional


def merge_tool_info(galaxy_tool: Dict, nfcore_tool: Dict) -> Dict:
    """Merge information from nf-core tool into Galaxy tool."""
    merged = galaxy_tool.copy()

    # 1. Description: Use nf-core if it's more detailed
    if nfcore_tool.get('description') and len(nfcore_tool['description']) > len(galaxy_tool.get('description', '')):
        merged['description'] = nfcore_tool['description']

    # 2. Examples: Prefer nf-core examples (they're better)
    nfcore_examples = json.loads(nfcore_tool.get('examples', '[]'))
    galaxy_examples = json.loads(galaxy_tool.get('examples', '[]'))
    if nfcore_examples:
        merged['examples'] = json.dumps(nfcore_examples)

    # 3. Usage guide: Use nf-core if available
    if nfcore_tool.get('usage_guide'):
        merged['usage_guide'] = nfcore_tool['usage_guide']

    # 4. EDAM operations: Merge both
    nfcore_edam = json.loads(nfcore_tool.get('edam_operations', '[]'))
    galaxy_edam = json.loads(galaxy_tool.get('edam_operations', '[]'))
    if nfcore_edam:
        all_edam = list(set(galaxy_edam + nfcore_edam))
        merged['edam_operations'] = json.dumps(all_edam)

    # 5. Requirements: Merge, preferring nf-core versions
    nfcore_reqs = json.loads(nfcore_tool.get('requirements', '[]'))
    galaxy_reqs = json.loads(galaxy_tool.get('requirements', '[]'))

    # Create lookup for nf-core requirements by name
    nfcore_req_map = {}
    for req in nfcore_reqs:
        if isinstance(req, dict):
            name = req.get('name', '').split('::')[-1]  # Remove conda prefix
            nfcore_req_map[name.lower()] = req

    # Merge: update Galaxy requirements with nf-core versions
    merged_reqs = []
    for req in galaxy_reqs:
        if isinstance(req, dict):
            name = req.get('name', '').lower()
            if name in nfcore_req_map and not req.get('version'):
                # Update with nf-core version
                req['version'] = nfcore_req_map[name].get('version')
            merged_reqs.append(req)

    # Add any nf-core requirements not in Galaxy
    for name, req in nfcore_req_map.items():
        if not any(r.get('name', '').lower() == name for r in galaxy_reqs):
            merged_reqs.append(req)

    if merged_reqs:
        merged['requirements'] = json.dumps(merged_reqs)

    # 6. Help text: Merge homepage/documentation from nf-core
    nfcore_help = json.loads(nfcore_tool.get('help_text', '{}'))
    galaxy_help = json.loads(galaxy_tool.get('help_text', '{}'))

    if nfcore_help.get('homepage'):
        galaxy_help['homepage'] = nfcore_help['homepage']
        merged['url'] = nfcore_help['homepage']  # Better URL
    if nfcore_help.get('documentation'):
        galaxy_help['documentation'] = nfcore_help['documentation']
    if nfcore_help.get('keywords'):
        # Merge keywords
        galaxy_keywords = galaxy_help.get('keywords', [])
        nfcore_keywords = nfcore_help.get('keywords', [])
        galaxy_help['keywords'] = list(set(galaxy_keywords + nfcore_keywords))

    merged['help_text'] = json.dumps(galaxy_help)

    # 7. Tags: Merge both
    nfcore_tags = json.loads(nfcore_tool.get('tags', '[]'))
    galaxy_tags = json.loads(galaxy_tool.get('tags', '[]'))
    if nfcore_tags or galaxy_tags:
        merged['tags'] = json.dumps(list(set(galaxy_tags + nfcore_tags)))

    # 8. Citations: Merge both
    nfcore_citations = json.loads(nfcore_tool.get('citations', '[]'))
    galaxy_citations = json.loads(galaxy_tool.get('citations', '[]'))
    if nfcore_citations or galaxy_citations:
        merged['citations'] = json.dumps(galaxy_citations + nfcore_citations)

    # 9. Structured inputs: If Galaxy has basic list, enhance with nf-core details
    galaxy_inputs = galaxy_tool.get('inputs', '[]')
    nfcore_inputs = nfcore_tool.get('inputs', '[]')

    try:
        galaxy_inputs_parsed = json.loads(galaxy_inputs)
        nfcore_inputs_parsed = json.loads(nfcore_inputs)

        # If Galaxy has simple list and nf-core has detailed list, prefer nf-core
        if isinstance(galaxy_inputs_parsed, list) and isinstance(nfcore_inputs_parsed, list):
            if nfcore_inputs_parsed and len(nfcore_inputs_parsed) > 0:
                if isinstance(nfcore_inputs_parsed[0], dict):
                    # nf-core has structured details
                    merged['inputs'] = nfcore_inputs
    except:
        pass

    # 10. Structured outputs: Same as inputs
    galaxy_outputs = galaxy_tool.get('outputs', '[]')
    nfcore_outputs = nfcore_tool.get('outputs', '[]')

    try:
        galaxy_outputs_parsed = json.loads(galaxy_outputs)
        nfcore_outputs_parsed = json.loads(nfcore_outputs)

        if isinstance(galaxy_outputs_parsed, list) and isinstance(nfcore_outputs_parsed, list):
            if nfcore_outputs_parsed and len(nfcore_outputs_parsed) > 0:
                if isinstance(nfcore_outputs_parsed[0], dict):
                    merged['outputs'] = nfcore_outputs
    except:
        pass

    return merged


def merge_galaxy_and_nfcore_tools(db_path: str):
    """Merge Galaxy and nf-core tools."""

    print("=" * 80)
    print("Merging Galaxy and nf-core Tool Information")
    print("=" * 80)
    print()

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Find matching tools
    cursor.execute("""
        SELECT
            g.id as galaxy_id,
            g.tool_id as galaxy_tool_id,
            g.name as name,
            n.id as nfcore_id,
            n.tool_id as nfcore_tool_id
        FROM tools g
        JOIN tools n ON LOWER(g.name) = LOWER(n.name)
        WHERE g.category != 'nf-core'
          AND n.category = 'nf-core'
    """)

    matches = cursor.fetchall()
    print(f"Found {len(matches)} tools that exist in both Galaxy and nf-core")
    print()

    stats = {
        'merged': 0,
        'deleted': 0,
        'errors': 0
    }

    for match in matches:
        try:
            # Get full Galaxy tool
            cursor.execute("SELECT * FROM tools WHERE id = ?", (match['galaxy_id'],))
            galaxy_tool = dict(cursor.fetchone())

            # Get full nf-core tool
            cursor.execute("SELECT * FROM tools WHERE id = ?", (match['nfcore_id'],))
            nfcore_tool = dict(cursor.fetchone())

            # Merge information
            merged = merge_tool_info(galaxy_tool, nfcore_tool)

            # Update Galaxy tool with merged info
            cursor.execute("""
                UPDATE tools SET
                    description = ?,
                    examples = ?,
                    usage_guide = ?,
                    edam_operations = ?,
                    requirements = ?,
                    help_text = ?,
                    tags = ?,
                    citations = ?,
                    inputs = ?,
                    outputs = ?,
                    url = ?
                WHERE id = ?
            """, (
                merged.get('description'),
                merged.get('examples'),
                merged.get('usage_guide'),
                merged.get('edam_operations'),
                merged.get('requirements'),
                merged.get('help_text'),
                merged.get('tags'),
                merged.get('citations'),
                merged.get('inputs'),
                merged.get('outputs'),
                merged.get('url'),
                match['galaxy_id']
            ))

            # Delete nf-core duplicate
            cursor.execute("DELETE FROM tools WHERE id = ?", (match['nfcore_id'],))

            stats['merged'] += 1
            stats['deleted'] += 1

            if stats['merged'] % 10 == 0:
                print(f"  Merged {stats['merged']} tools...")
                conn.commit()

        except Exception as e:
            stats['errors'] += 1
            if stats['errors'] <= 5:
                print(f"  Error merging {match['name']}: {str(e)[:100]}")

    conn.commit()
    conn.close()

    print()
    print("=" * 80)
    print("✅ Merge Complete")
    print("=" * 80)
    print(f"   Tools merged: {stats['merged']}")
    print(f"   Duplicates removed: {stats['deleted']}")
    print(f"   Errors: {stats['errors']}")
    print()
    print("Result: Galaxy tools now include best information from both sources")

    return stats


def main():
    """Main function."""
    db_path = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        print(f"❌ Database not found at {db_path}")
        return 1

    try:
        stats = merge_galaxy_and_nfcore_tools(str(db_path))
        return 0
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
