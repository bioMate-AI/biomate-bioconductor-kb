#!/usr/bin/env python3
"""
Update galaxy_ai_tools.db with structured parameter information from crawled data.

This script:
1. Alters the database schema to add parameter columns
2. Loads structured parameter data from galaxy_crawl_v2_with_parameters.json
3. Updates each tool record with its parameters, inputs, outputs, requirements, and help_text
"""

import json
import sqlite3
import sys
from pathlib import Path

def alter_database_schema(db_path):
    """Add parameter columns to tools table if they don't exist."""
    print("Updating database schema...")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get existing columns
    cursor.execute("PRAGMA table_info(tools)")
    existing_columns = {row[1] for row in cursor.fetchall()}

    # Add missing columns
    columns_to_add = {
        'parameters': 'TEXT',  # JSON array
        'help_text': 'TEXT',   # JSON object
        'inputs': 'TEXT',      # JSON array
        'outputs': 'TEXT',     # JSON array
        'requirements': 'TEXT', # JSON array
        'tool_state_template': 'TEXT',  # JSON string
        'description': 'TEXT'  # Plain text description
    }

    for column_name, column_type in columns_to_add.items():
        if column_name not in existing_columns:
            print(f"  Adding column: {column_name}")
            cursor.execute(f"ALTER TABLE tools ADD COLUMN {column_name} {column_type}")

    conn.commit()
    conn.close()
    print("✅ Schema updated\n")

def load_parameter_data(json_path):
    """Load tool parameter data from JSON file."""
    print(f"Loading parameter data from {json_path}...")

    with open(json_path) as f:
        data = json.load(f)

    # Build tool_id -> tool data mapping
    tool_map = {}

    crawled_data = data.get('crawledData', [])

    for category in crawled_data:
        category_name = category.get('category', 'Unknown')

        for repo in category.get('repositories', []):
            repo_name = repo.get('repoName', '')
            repo_owner = repo.get('repoOwner', '')

            for tool in repo.get('tools', []):
                # Build tool_id from repo info
                tool_name = tool.get('name', '').strip()
                version = tool.get('version', '').strip()

                # Create various tool_id formats to match database
                tool_ids = []

                # Format 1: toolshed.g2.bx.psu.edu/repos/{owner}/{repo}/{name}/{version}
                if repo_owner and repo_name and tool_name and version:
                    tool_ids.append(f"toolshed.g2.bx.psu.edu/repos/{repo_owner}/{repo_name}/{tool_name}/{version}")

                # Format 2: {owner}/{repo}/{name}
                if repo_owner and repo_name and tool_name:
                    tool_ids.append(f"{repo_owner}/{repo_name}/{tool_name}")

                # Format 3: just tool name
                if tool_name:
                    tool_ids.append(tool_name)

                # Store tool data with all possible IDs
                tool_data = {
                    'name': tool.get('title', tool_name),
                    'version': version,
                    'category': category_name,
                    'repo_owner': repo_owner,
                    'repo_name': repo_name,
                    'parameters': tool.get('parameters', []),
                    'tool_state_template': tool.get('tool_state_template', ''),
                    'rawText': tool.get('rawText', ''),
                    'htmlContent': tool.get('htmlContent', ''),
                    'url': tool.get('url', ''),
                    # Extract description from rawText (first non-empty paragraph)
                    'description': extract_description(tool.get('rawText', ''))
                }

                # Derive inputs, outputs, requirements from parameters
                inputs, outputs, requirements = derive_io_from_parameters(tool.get('parameters', []))
                tool_data['inputs'] = inputs
                tool_data['outputs'] = outputs
                tool_data['requirements'] = requirements
                tool_data['help_text'] = build_help_text(tool.get('parameters', []))

                for tool_id in tool_ids:
                    tool_map[tool_id] = tool_data

    print(f"✅ Loaded {len(tool_map)} tool parameter mappings\n")
    return tool_map

def extract_description(raw_text):
    """Extract a clean description from rawText."""
    if not raw_text:
        return ""

    # Take first 500 characters, clean up whitespace
    desc = raw_text[:500].replace('\n', ' ').replace('\t', ' ')
    desc = ' '.join(desc.split())  # Normalize whitespace
    return desc

def derive_io_from_parameters(parameters):
    """Derive inputs, outputs, and requirements from parameters."""
    inputs = []
    outputs = []
    requirements = []

    for param in parameters:
        param_type = param.get('type', '')
        param_name = param.get('name', '')
        param_label = param.get('label', '')

        # Input data parameters
        if param_type in ['data', 'data_collection', 'file']:
            inputs.append({
                'name': param_name,
                'type': param_type,
                'label': param_label,
                'optional': param.get('optional', False)
            })

        # Output parameters (usually marked in name/label)
        if 'output' in param_name.lower() or 'result' in param_name.lower():
            outputs.append({
                'name': param_name,
                'type': param_type,
                'label': param_label
            })

    # Requirements - would need separate data source, for now empty
    requirements = []

    return inputs, outputs, requirements

def build_help_text(parameters):
    """Build help text object from parameters."""
    help_obj = {
        'parameters': {}
    }

    for param in parameters:
        param_name = param.get('name', '')
        param_help = param.get('help', '')
        if param_name and param_help:
            help_obj['parameters'][param_name] = param_help

    return help_obj

def update_database(db_path, tool_map):
    """Update database with parameter information."""
    print(f"Updating database at {db_path}...")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get all existing tools
    cursor.execute("SELECT id, tool_id, name FROM tools")
    existing_tools = cursor.fetchall()

    updated_count = 0
    not_found_count = 0

    for db_id, tool_id, tool_name in existing_tools:
        # Try to find matching tool data
        tool_data = None

        # Try exact match first
        if tool_id in tool_map:
            tool_data = tool_map[tool_id]
        # Try tool name match
        elif tool_name in tool_map:
            tool_data = tool_map[tool_name]
        # Try partial matches
        else:
            # Check if any key contains the tool name
            for key in tool_map:
                if tool_name in key or key in tool_name:
                    tool_data = tool_map[key]
                    break

        if tool_data:
            # Update tool with parameter data
            cursor.execute("""
                UPDATE tools
                SET parameters = ?,
                    help_text = ?,
                    inputs = ?,
                    outputs = ?,
                    requirements = ?,
                    tool_state_template = ?,
                    description = ?
                WHERE id = ?
            """, (
                json.dumps(tool_data['parameters']),
                json.dumps(tool_data['help_text']),
                json.dumps(tool_data['inputs']),
                json.dumps(tool_data['outputs']),
                json.dumps(tool_data['requirements']),
                tool_data['tool_state_template'],
                tool_data['description'],
                db_id
            ))
            updated_count += 1
        else:
            not_found_count += 1

    conn.commit()
    conn.close()

    print(f"✅ Updated {updated_count} tools with parameter data")
    print(f"⚠️  {not_found_count} tools not found in parameter data\n")

def main():
    # Paths
    db_path = '/Users/jingqiwang/biomate/backend/galaxy_ai_tools.db'
    json_path = '/Users/jingqiwang/lcms-platform/galaxy_tools/galaxy_crawl_v2_with_parameters.json'

    # Check files exist
    if not Path(db_path).exists():
        print(f"❌ Database not found: {db_path}")
        sys.exit(1)

    if not Path(json_path).exists():
        print(f"❌ Parameter JSON not found: {json_path}")
        sys.exit(1)

    print("=" * 80)
    print("Database Parameter Update Script")
    print("=" * 80)
    print()

    # Step 1: Alter schema
    alter_database_schema(db_path)

    # Step 2: Load parameter data
    tool_map = load_parameter_data(json_path)

    # Step 3: Update database
    update_database(db_path, tool_map)

    print("=" * 80)
    print("✅ Database update complete!")
    print("=" * 80)

if __name__ == '__main__':
    main()
