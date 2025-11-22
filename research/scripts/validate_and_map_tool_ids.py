#!/usr/bin/env python3
"""
Validate and map workflow tool IDs to match the tool index.

Ensures all tool references in workflows are consistent with the AI tool database.
"""

import json
import sqlite3
import re
import os
from pathlib import Path
from collections import defaultdict
from datetime import datetime

# Configuration
DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
NFCORE_DIR = "/home/yzhang/biomate/backend/galaxy_workflows_reformatted"
IWC_DIR = "/home/yzhang/biomate/backend/galaxy_workflows_official_iwc"
OUTPUT_DIR = "/home/yzhang/biomate/research"


def load_tool_index():
    """Load all tool IDs from the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT tool_id, name, repo_owner, repo_name FROM tools")
    tools = {}

    for row in cursor.fetchall():
        tool_id, name, owner, repo = row
        tools[tool_id] = {
            'name': name,
            'owner': owner,
            'repo': repo
        }

    conn.close()
    return tools


def extract_workflow_tools(directory):
    """Extract all tool IDs from workflows in a directory."""

    workflow_tools = {}

    for ga_file in Path(directory).rglob("*.ga"):
        try:
            with open(ga_file, 'r') as f:
                workflow = json.load(f)

            tools = []
            steps = workflow.get('steps', {})

            for step_id, step in steps.items():
                if step.get('type') == 'tool':
                    tool_id = step.get('tool_id')
                    if tool_id:
                        tools.append({
                            'tool_id': tool_id,
                            'step_id': step_id,
                            'step_name': step.get('name', '')
                        })

            workflow_tools[str(ga_file)] = {
                'name': workflow.get('name', ga_file.stem),
                'tools': tools
            }

        except Exception as e:
            print(f"Error reading {ga_file}: {e}")

    return workflow_tools


def find_matching_tool(tool_id, tool_index):
    """Find a matching tool in the index for a given tool ID."""

    # Direct match
    if tool_id in tool_index:
        return tool_id, 'exact'

    # Try different matching strategies

    # 1. Extract tool name from ToolShed URL
    # toolshed.g2.bx.psu.edu/repos/owner/repo/tool_name/version
    toolshed_match = re.match(
        r'toolshed\.g2\.bx\.psu\.edu/repos/([^/]+)/([^/]+)/([^/]+)(?:/([^/]+))?',
        tool_id
    )

    if toolshed_match:
        owner, repo, tool_name, version = toolshed_match.groups()

        # Try to find by owner_repo pattern
        for db_tool_id in tool_index:
            # Check if it matches the ToolShed URL format in DB
            if db_tool_id.startswith(f'toolshed.g2.bx.psu.edu/repos/{owner}/{repo}/'):
                return db_tool_id, 'toolshed_match'

            # Check short format: owner_repo_name
            if db_tool_id.startswith(f'{owner}_{repo}_'):
                return db_tool_id, 'short_format_match'

        # Try matching by tool name in the short format
        for db_tool_id in tool_index:
            if f'_{tool_name}' in db_tool_id or tool_name.lower() in db_tool_id.lower():
                return db_tool_id, 'name_match'

    # 2. For custom tools like nfcore_*, check direct
    if tool_id.startswith('nfcore_') or tool_id.startswith('biomate_'):
        for db_tool_id in tool_index:
            if db_tool_id == tool_id or db_tool_id.startswith(tool_id):
                return db_tool_id, 'custom_match'

    # 3. Built-in Galaxy tools
    builtin_tools = ['Filter1', 'cat1', 'Cut1', 'Paste1', 'join1', 'sort1', 'Grep1']
    if tool_id in builtin_tools:
        return tool_id, 'builtin'

    # 4. Try fuzzy match by tool name
    tool_name_lower = tool_id.lower().replace('_', '').replace('-', '')
    for db_tool_id in tool_index:
        db_name_lower = db_tool_id.lower().replace('_', '').replace('-', '')
        if tool_name_lower in db_name_lower or db_name_lower in tool_name_lower:
            return db_tool_id, 'fuzzy_match'

    return None, 'not_found'


def update_workflow_tools(workflow_path, tool_mapping):
    """Update workflow with correct tool IDs from mapping."""

    with open(workflow_path, 'r') as f:
        workflow = json.load(f)

    updated = False
    steps = workflow.get('steps', {})

    for step_id, step in steps.items():
        if step.get('type') == 'tool':
            old_tool_id = step.get('tool_id')
            if old_tool_id and old_tool_id in tool_mapping:
                new_tool_id = tool_mapping[old_tool_id]
                if new_tool_id != old_tool_id:
                    step['tool_id'] = new_tool_id
                    if 'content_id' in step:
                        step['content_id'] = new_tool_id
                    updated = True

    if updated:
        with open(workflow_path, 'w') as f:
            json.dump(workflow, f, indent=2)

    return updated


def main():
    print("=" * 60)
    print("Tool ID Validation and Mapping")
    print("=" * 60)
    print()

    # Load tool index
    print("Loading tool index...")
    tool_index = load_tool_index()
    print(f"  Loaded {len(tool_index)} tools from database")
    print()

    # Extract tools from workflows
    print("Extracting tools from nf-core workflows...")
    nfcore_workflows = extract_workflow_tools(NFCORE_DIR)
    print(f"  Found {len(nfcore_workflows)} workflows")

    print("Extracting tools from IWC workflows...")
    iwc_workflows = extract_workflow_tools(IWC_DIR)
    print(f"  Found {len(iwc_workflows)} workflows")
    print()

    # Combine all workflows
    all_workflows = {**nfcore_workflows, **iwc_workflows}

    # Find all unique tool IDs
    all_tool_ids = set()
    for wf in all_workflows.values():
        for tool in wf['tools']:
            all_tool_ids.add(tool['tool_id'])

    print(f"Total unique tool IDs in workflows: {len(all_tool_ids)}")
    print()

    # Validate and map each tool
    print("Validating tool IDs against index...")

    results = {
        'exact': [],
        'toolshed_match': [],
        'short_format_match': [],
        'name_match': [],
        'custom_match': [],
        'builtin': [],
        'fuzzy_match': [],
        'not_found': []
    }

    tool_mapping = {}

    for tool_id in sorted(all_tool_ids):
        matched_id, match_type = find_matching_tool(tool_id, tool_index)
        results[match_type].append({
            'original': tool_id,
            'matched': matched_id
        })

        if matched_id:
            tool_mapping[tool_id] = matched_id

    # Print summary
    print("\nValidation Results:")
    print(f"  Exact match: {len(results['exact'])}")
    print(f"  ToolShed match: {len(results['toolshed_match'])}")
    print(f"  Short format match: {len(results['short_format_match'])}")
    print(f"  Name match: {len(results['name_match'])}")
    print(f"  Custom match: {len(results['custom_match'])}")
    print(f"  Built-in: {len(results['builtin'])}")
    print(f"  Fuzzy match: {len(results['fuzzy_match'])}")
    print(f"  NOT FOUND: {len(results['not_found'])}")

    # Update workflows with mapped tool IDs
    print("\nUpdating workflows with mapped tool IDs...")
    updated_count = 0

    for workflow_path in all_workflows.keys():
        if update_workflow_tools(workflow_path, tool_mapping):
            updated_count += 1

    print(f"  Updated {updated_count} workflows")

    # Generate report
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    report_path = f"{OUTPUT_DIR}/{timestamp}_TOOL_MAPPING_REPORT.md"

    with open(report_path, 'w') as f:
        f.write("# Tool ID Validation and Mapping Report\n\n")
        f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"**Total unique tools:** {len(all_tool_ids)}\n")
        f.write(f"**Tools in index:** {len(tool_index)}\n\n")

        total_found = len(all_tool_ids) - len(results['not_found'])
        f.write(f"**Match rate:** {total_found}/{len(all_tool_ids)} ({100*total_found/len(all_tool_ids):.1f}%)\n\n")

        f.write("---\n\n## Match Summary\n\n")
        f.write("| Match Type | Count |\n")
        f.write("|------------|-------|\n")
        for match_type, items in results.items():
            f.write(f"| {match_type} | {len(items)} |\n")

        f.write("\n---\n\n## Missing Tools\n\n")
        f.write("These tools need to be added to the tool index:\n\n")

        for item in sorted(results['not_found'], key=lambda x: x['original']):
            f.write(f"- `{item['original']}`\n")

        f.write("\n---\n\n## Tool Mappings Applied\n\n")
        f.write("| Original ID | Mapped ID | Match Type |\n")
        f.write("|-------------|-----------|------------|\n")

        for match_type in ['toolshed_match', 'short_format_match', 'name_match', 'fuzzy_match']:
            for item in results[match_type][:20]:
                orig = item['original'][:50] + '...' if len(item['original']) > 50 else item['original']
                matched = item['matched'][:50] + '...' if len(item['matched']) > 50 else item['matched']
                f.write(f"| `{orig}` | `{matched}` | {match_type} |\n")

    print(f"\nReport saved to: {report_path}")

    # Save mapping as JSON
    mapping_path = f"{OUTPUT_DIR}/{timestamp}_TOOL_MAPPING.json"
    with open(mapping_path, 'w') as f:
        json.dump({
            'mapping': tool_mapping,
            'not_found': [item['original'] for item in results['not_found']],
            'stats': {k: len(v) for k, v in results.items()}
        }, f, indent=2)

    print(f"Mapping saved to: {mapping_path}")


if __name__ == "__main__":
    main()
