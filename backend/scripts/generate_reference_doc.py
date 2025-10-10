#!/usr/bin/env python3
"""
Generate comprehensive reference document for Galaxy data tools and datasets
"""
import json
import sqlite3
import os
from datetime import datetime

def get_metaboanalyst_schema(db_path):
    """Extract table schema from MetaboAnalyst SQLite database"""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get all tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = [row[0] for row in cursor.fetchall()]

    schema_info = {}
    for table in tables:
        cursor.execute(f"PRAGMA table_info({table})")
        columns = cursor.fetchall()
        schema_info[table] = {
            'columns': [{'name': col[1], 'type': col[2]} for col in columns],
            'column_count': len(columns)
        }

    conn.close()
    return schema_info

def main():
    print("Generating comprehensive reference document...")

    # Load tool details
    with open('/Users/jingqiwang/biomate/backend/data_tools_detailed.json', 'r') as f:
        tools_data = json.load(f)

    # Load dataset index
    with open('/Users/jingqiwang/Biomni/knowledge_data/dataset_index_comprehensive.json', 'r') as f:
        dataset_data = json.load(f)

    datasets = dataset_data.get('datasets', {})

    # Get MetaboAnalyst SQLite database info
    metaboanalyst_dir = '/Users/jingqiwang/Biomni/knowledge_data/metaboanalyst'
    sqlite_files = [f for f in os.listdir(metaboanalyst_dir) if f.endswith('.sqlite')]
    sqlite_files.sort()

    metaboanalyst_schemas = {}
    for sqlite_file in sqlite_files:
        db_path = os.path.join(metaboanalyst_dir, sqlite_file)
        file_size = os.path.getsize(db_path) / (1024**3)  # GB
        print(f"  Analyzing {sqlite_file} ({file_size:.1f} GB)...")
        metaboanalyst_schemas[sqlite_file] = {
            'size_gb': file_size,
            'schema': get_metaboanalyst_schema(db_path)
        }

    # Prepare output
    output = {
        'tools': tools_data,
        'datasets': datasets,
        'metaboanalyst_databases': metaboanalyst_schemas
    }

    # Save to JSON for easier document creation
    output_file = '/Users/jingqiwang/biomate/backend/reference_data_complete.json'
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\n✓ Reference data saved to: {output_file}")
    print(f"  Tools: {len(tools_data)}")
    print(f"  Datasets: {len(datasets)}")
    print(f"  MetaboAnalyst DBs: {len(metaboanalyst_schemas)}")

    return output

if __name__ == '__main__':
    main()
