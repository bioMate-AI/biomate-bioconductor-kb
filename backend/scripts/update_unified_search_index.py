#!/usr/bin/env python3
"""
Update unified search index with:
1. Dataset entries (as searchable tools)
2. Data Management tools (67 generated wrappers)
3. Compatible tools mappings
"""
import json
import sqlite3
import os
from pathlib import Path
from typing import Dict, Any, List

# Paths
GALAXY_TOOLS_DB = "/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db"
REFERENCE_DATA_JSON = "/Users/jingqiwang/biomate/backend/reference_data_with_compatible_tools.json"
DATA_MANAGEMENT_TOOLS_DIR = "/Users/jingqiwang/biomate/backend/tools/biomate_data_management"


def load_reference_data() -> Dict[str, Any]:
    """Load reference data with compatible_tools mappings"""
    with open(REFERENCE_DATA_JSON, 'r') as f:
        return json.load(f)


def create_dataset_tool_entry(dataset_key: str, dataset: Dict[str, Any]) -> Dict[str, str]:
    """
    Convert dataset into a tool entry for search index.
    Datasets become searchable as 'Data Source' tools.
    """
    # Build comprehensive text for search
    search_text_parts = [
        f"Dataset: {dataset['name']}",
        f"Category: {dataset.get('category', 'unknown')}",
        f"Format: {dataset.get('format', 'unknown')}",
        f"Use cases: {', '.join(dataset.get('use_cases', []))}",
        f"Columns: {', '.join(dataset.get('index_columns', [])[:20])}",
        f"Source: {dataset.get('source', '')}",
    ]

    # Add compatible tools information
    compatible_tools = dataset.get('compatible_tools', [])
    if compatible_tools:
        tool_names = [t['name'] for t in compatible_tools]
        search_text_parts.append(f"Compatible with tools: {', '.join(tool_names[:10])}")

    raw_text = "\n".join(search_text_parts)

    # Determine tool category
    access_method = dataset.get('access_method', 'unknown')
    if access_method == 'local_file':
        category = 'Data Management'
        tool_id_prefix = 'biomate_dm'
    else:
        category = 'Data Source'
        tool_id_prefix = 'biomate_ds'

    return {
        'tool_id': f"{tool_id_prefix}_{dataset_key}",
        'name': dataset['name'],
        'version': '1.0.0',
        'repo_owner': 'biomate',
        'repo_name': 'biomate_datasets',
        'category': category,
        'rawText': raw_text,
        'htmlContent': '',
        'url': f'biomate://datasets/{dataset_key}'
    }


def load_data_management_tools() -> List[Dict[str, str]]:
    """
    Load the 67 generated Data Management tool wrappers.
    Parse XML to extract tool metadata.
    """
    tools = []
    dm_dir = Path(DATA_MANAGEMENT_TOOLS_DIR)

    if not dm_dir.exists():
        print(f"Warning: Data Management tools directory not found: {dm_dir}")
        return tools

    # Find all XML files
    xml_files = list(dm_dir.glob("*.xml"))

    for xml_file in xml_files:
        try:
            # Simple XML parsing (assuming our generated format)
            with open(xml_file, 'r') as f:
                content = f.read()

            # Extract tool_id and name from XML
            import re
            tool_id_match = re.search(r'<tool id="([^"]+)"', content)
            name_match = re.search(r'name="([^"]+)"', content)
            desc_match = re.search(r'<description>([^<]+)</description>', content)

            if tool_id_match and name_match:
                tool_id = tool_id_match.group(1)
                name = name_match.group(1)
                description = desc_match.group(1) if desc_match else ''

                tools.append({
                    'tool_id': tool_id,
                    'name': name,
                    'version': '1.0.0',
                    'repo_owner': 'biomate',
                    'repo_name': 'biomate_data_management',
                    'category': 'Data Management',
                    'rawText': f"{name}\n{description}\n\nGenerated Data Management tool for BioMate platform.",
                    'htmlContent': '',
                    'url': f'file://{xml_file}'
                })
        except Exception as e:
            print(f"Warning: Failed to parse {xml_file}: {e}")
            continue

    return tools


def update_search_index():
    """Main update function"""
    print("="*70)
    print("UNIFIED SEARCH INDEX UPDATE")
    print("="*70)

    # Load data
    print("\n1. Loading reference data...")
    reference_data = load_reference_data()
    datasets = reference_data['datasets']
    print(f"   Loaded {len(datasets)} datasets")

    print("\n2. Loading Data Management tools...")
    dm_tools = load_data_management_tools()
    print(f"   Loaded {len(dm_tools)} Data Management tool wrappers")

    # Connect to database
    print("\n3. Connecting to database...")
    conn = sqlite3.connect(GALAXY_TOOLS_DB)
    cursor = conn.cursor()

    # Check current state
    cursor.execute("SELECT COUNT(*) FROM tools WHERE repo_owner = 'biomate'")
    existing_count = cursor.fetchone()[0]
    print(f"   Existing BioMate entries: {existing_count}")

    # Convert datasets to tool entries
    print("\n4. Converting datasets to searchable tool entries...")
    dataset_entries = []
    for dataset_key, dataset in datasets.items():
        entry = create_dataset_tool_entry(dataset_key, dataset)
        dataset_entries.append(entry)

    print(f"   Created {len(dataset_entries)} dataset tool entries")

    # Insert or update entries
    print("\n5. Updating database...")

    # Clear existing BioMate entries
    cursor.execute("DELETE FROM tools WHERE repo_owner = 'biomate'")
    deleted = cursor.rowcount
    print(f"   Deleted {deleted} old BioMate entries")

    # Insert dataset entries
    insert_count = 0
    for entry in dataset_entries:
        try:
            cursor.execute('''
                INSERT INTO tools (tool_id, name, version, repo_owner, repo_name,
                                   category, rawText, htmlContent, url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                entry['tool_id'],
                entry['name'],
                entry['version'],
                entry['repo_owner'],
                entry['repo_name'],
                entry['category'],
                entry['rawText'],
                entry['htmlContent'],
                entry['url']
            ))
            insert_count += 1
        except sqlite3.IntegrityError as e:
            print(f"   Warning: Duplicate entry {entry['tool_id']}: {e}")

    print(f"   Inserted {insert_count} dataset entries")

    # Insert Data Management tool wrappers
    dm_insert_count = 0
    for tool in dm_tools:
        try:
            cursor.execute('''
                INSERT INTO tools (tool_id, name, version, repo_owner, repo_name,
                                   category, rawText, htmlContent, url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                tool['tool_id'],
                tool['name'],
                tool['version'],
                tool['repo_owner'],
                tool['repo_name'],
                tool['category'],
                tool['rawText'],
                tool['htmlContent'],
                tool['url']
            ))
            dm_insert_count += 1
        except sqlite3.IntegrityError as e:
            print(f"   Warning: Duplicate entry {tool['tool_id']}: {e}")

    print(f"   Inserted {dm_insert_count} Data Management tool wrappers")

    # Commit changes
    conn.commit()

    # Summary
    print("\n" + "="*70)
    print("UPDATE SUMMARY")
    print("="*70)
    cursor.execute("SELECT COUNT(*) FROM tools WHERE repo_owner = 'biomate'")
    final_count = cursor.fetchone()[0]

    cursor.execute("SELECT category, COUNT(*) FROM tools WHERE repo_owner = 'biomate' GROUP BY category")
    category_counts = cursor.fetchall()

    print(f"\nTotal BioMate entries in index: {final_count}")
    print("\nBreakdown by category:")
    for category, count in category_counts:
        print(f"  - {category}: {count}")

    # Dataset statistics
    local_datasets = [d for d in datasets.values() if d.get('access_method') == 'local_file']
    datasets_with_tools = [d for d in local_datasets if d.get('compatible_tools')]
    total_mappings = sum(len(d.get('compatible_tools', [])) for d in local_datasets)

    print(f"\nDataset-Tool Compatibility:")
    print(f"  - Local datasets: {len(local_datasets)}")
    print(f"  - Datasets with compatible tools: {len(datasets_with_tools)} ({len(datasets_with_tools)/len(local_datasets)*100:.1f}%)")
    print(f"  - Total compatible tool mappings: {total_mappings}")

    # Close connection
    cursor.close()
    conn.close()

    print("\n✅ Unified search index updated successfully!")


if __name__ == '__main__':
    update_search_index()
