#!/usr/bin/env python3
"""
Test script for complete metadata extraction and integration.

Tests the integration of ComprehensiveMetadataExtractor with the database integration.
"""

import json
import sys
from pathlib import Path

# Add scripts directory to path
scripts_dir = Path(__file__).parent
sys.path.insert(0, str(scripts_dir))

from integrate_tools import ToolIntegrator
from documentation_fetcher import DocumentationFetcher

def test_integration():
    """Test complete metadata extraction and integration."""

    print("=" * 80)
    print("Testing Complete Metadata Extraction & Integration")
    print("=" * 80)
    print()

    # Paths
    auto_update_dir = Path(__file__).parent.parent
    wrappers_dir = auto_update_dir / "data" / "wrappers"
    discoveries_file = auto_update_dir / "data" / "discoveries" / "github_tools_20251106_090523.json"
    db_path = auto_update_dir.parent / "backend" / "database" / "galaxy_ai_tools.db"
    tools_dir = auto_update_dir.parent / "backend" / "tools"

    # Load tool metadata
    print(f"Loading metadata from: {discoveries_file}")
    with open(discoveries_file) as f:
        all_metadata = json.load(f)

    print(f"Found {len(all_metadata)} tools in discoveries file")
    print()

    # Create metadata lookup
    metadata_lookup = {m['name']: m for m in all_metadata}

    # Initialize integrator
    print("Initializing ToolIntegrator with ComprehensiveMetadataExtractor...")
    integrator = ToolIntegrator(
        db_path=db_path,
        tools_dir=tools_dir,
        enable_llm=False  # Disable LLM for faster testing
    )
    print()

    # Initialize documentation fetcher
    import os
    github_token = os.environ.get('GITHUB_TOKEN')
    doc_fetcher = DocumentationFetcher(github_token=github_token)

    # Test with each wrapper
    wrappers = list(wrappers_dir.glob("*.xml"))
    print(f"Found {len(wrappers)} wrappers to test")
    print()

    results = []

    # Test with dash first (has more parameters)
    test_tools = ['dash', 'biopython']
    for tool_name in test_tools:
        wrapper_path = wrappers_dir / f"{tool_name}.xml"
        if not wrapper_path.exists():
            print(f"⚠️  Wrapper not found: {wrapper_path}")
            continue
        print(f"{'=' * 80}")
        print(f"Testing tool: {tool_name}")
        print(f"{'=' * 80}")

        # Get metadata
        metadata = metadata_lookup.get(tool_name)
        if not metadata:
            print(f"⚠️  No metadata found for {tool_name}, skipping")
            print()
            continue

        print(f"Tool info:")
        print(f"  - Name: {metadata['name']}")
        print(f"  - Stars: {metadata['stars']}")
        print(f"  - Language: {metadata['language']}")
        print(f"  - Quality score: {metadata['quality_score']}")
        print(f"  - URL: {metadata['url']}")
        print()

        # Fetch fresh documentation
        print("Fetching documentation from GitHub...")
        try:
            documentation = doc_fetcher.fetch_documentation(
                repo_full_name=metadata['full_name']
            )
            print(f"✓ Documentation fetched")
            print(f"  - README: {len(documentation.get('readme', ''))} chars")
            print(f"  - Has installation: {bool(documentation.get('installation'))}")
            print(f"  - Examples: {len(documentation.get('usage_examples', []))}")
        except Exception as e:
            print(f"⚠️  Failed to fetch documentation: {e}")
            # Use minimal documentation
            documentation = {
                'readme': metadata.get('description', ''),
                'installation': '',
                'usage_examples': [],
                'help_text': ''
            }
        print()

        # Test integration
        print("Integrating tool with complete metadata extraction...")
        try:
            success = integrator.integrate_tool(
                wrapper_path=wrapper_path,
                metadata=metadata,
                documentation=documentation,
                test_result=None  # Skip test validation for now
            )

            if success:
                print()
                print(f"✅ Successfully integrated {tool_name} with complete metadata!")
                results.append({
                    'tool': tool_name,
                    'success': True,
                    'error': None
                })
            else:
                print()
                print(f"❌ Failed to integrate {tool_name}")
                results.append({
                    'tool': tool_name,
                    'success': False,
                    'error': 'Integration returned False'
                })
        except Exception as e:
            print()
            print(f"❌ Error integrating {tool_name}: {e}")
            import traceback
            traceback.print_exc()
            results.append({
                'tool': tool_name,
                'success': False,
                'error': str(e)
            })

        print()

    # Summary
    print("=" * 80)
    print("Test Summary")
    print("=" * 80)
    successful = sum(1 for r in results if r['success'])
    failed = sum(1 for r in results if not r['success'])

    print(f"Total: {len(results)}")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    print()

    if failed > 0:
        print("Failed tools:")
        for r in results:
            if not r['success']:
                print(f"  - {r['tool']}: {r['error']}")

    print()
    print("=" * 80)

    # Verify database entries
    if successful > 0:
        print()
        print("Verifying database entries...")
        import sqlite3

        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        for r in results:
            if r['success']:
                tool_name = r['tool']
                tool_id = f"auto_{tool_name}"

                # Query database
                cursor.execute("""
                    SELECT
                        tool_id, name, version, category,
                        parameters, inputs, outputs, requirements,
                        citations, edam_operations, edam_topics,
                        scientific_context, quality_score
                    FROM tools
                    WHERE tool_id = ?
                """, (tool_id,))

                row = cursor.fetchone()
                if row:
                    print(f"\n✓ Found {tool_id} in database:")
                    print(f"  - Name: {row[1]}")
                    print(f"  - Version: {row[2]}")
                    print(f"  - Category: {row[3]}")

                    # Parse JSON fields
                    try:
                        parameters = json.loads(row[4]) if row[4] else []
                        inputs = json.loads(row[5]) if row[5] else []
                        outputs = json.loads(row[6]) if row[6] else []
                        requirements = json.loads(row[7]) if row[7] else []
                        citations = json.loads(row[8]) if row[8] else []
                        edam_ops = json.loads(row[9]) if row[9] else []
                        edam_topics = json.loads(row[10]) if row[10] else []

                        print(f"  - Parameters: {len(parameters)} defined")
                        print(f"  - Inputs: {len(inputs)} formats")
                        print(f"  - Outputs: {len(outputs)} formats")
                        print(f"  - Requirements: {len(requirements)} items")
                        print(f"  - Citations: {len(citations)} found")
                        print(f"  - EDAM operations: {len(edam_ops)}")
                        print(f"  - EDAM topics: {len(edam_topics)}")
                        print(f"  - Quality score: {row[12]}")

                        # Calculate field completeness
                        total_fields = 38
                        populated_fields = 0
                        for val in row:
                            if val is not None and val != '' and val != '[]' and val != '{}':
                                populated_fields += 1

                        completeness = (populated_fields / total_fields) * 100
                        print(f"  - Field completeness: {completeness:.1f}% ({populated_fields}/{total_fields})")

                    except json.JSONDecodeError as e:
                        print(f"  ⚠️  Error parsing JSON fields: {e}")
                else:
                    print(f"\n⚠️  Tool {tool_id} not found in database")

        conn.close()
        print()

    return successful > 0


if __name__ == '__main__':
    success = test_integration()
    sys.exit(0 if success else 1)
