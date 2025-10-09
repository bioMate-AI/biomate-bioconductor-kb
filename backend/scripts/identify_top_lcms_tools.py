#!/usr/bin/env python3
"""
Identify top LC-MS/metabolomics tools from the search index
"""

import sqlite3
import sys
import os
import yaml

sys.path.insert(1, os.path.abspath(os.path.join(os.path.dirname(__file__), os.pardir, "lib")))


def find_lcms_tools(db_path: str) -> list:
    """Find and rank LC-MS related tools"""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Search for LC-MS related tools
    lcms_keywords = ['xcms', 'lcms', 'msnbase', 'camera', 'openms', 'mzmine', 'metabolomics']

    tools = []
    for keyword in lcms_keywords:
        cursor.execute('''
            SELECT t.*
            FROM tools t
            JOIN tools_fts fts ON t.id = fts.rowid
            WHERE tools_fts MATCH ?
        ''', (f'"{keyword}"',))

        for row in cursor.fetchall():
            tool = dict(row)
            # Priority scoring
            score = 0
            name_lower = tool['name'].lower()

            # Core LC-MS tools get highest priority
            if 'xcms' in name_lower:
                score += 100
            if 'camera' in name_lower and 'xcms' in name_lower:
                score += 90
            if 'msnbase' in name_lower:
                score += 80
            if 'openms' in name_lower:
                score += 70
            if 'mzmine' in name_lower:
                score += 60

            # Specific functionality
            if any(x in name_lower for x in ['peak', 'findchrompeaks', 'centwave']):
                score += 30
            if any(x in name_lower for x in ['annotation', 'identify']):
                score += 20
            if any(x in name_lower for x in ['quantif', 'normali']):
                score += 15

            tool['priority_score'] = score
            tools.append(tool)

    # Remove duplicates and sort by score
    unique_tools = {t['tool_id']: t for t in tools}
    sorted_tools = sorted(unique_tools.values(), key=lambda x: x['priority_score'], reverse=True)

    conn.close()
    return sorted_tools


def save_top_tools_config(tools: list, output_path: str, count: int = 20):
    """Save top tools to YAML configuration"""
    top_tools = []

    for tool in tools[:count]:
        top_tools.append({
            'name': tool['name'],
            'owner': tool['repo_owner'],
            'repo_name': tool['repo_name'],
            'tool_shed_url': tool['tool_shed'],
            'changeset_revision': tool['changeset_revision'] if tool['changeset_revision'] else 'latest',
            'tool_panel_section_label': 'LC-MS Metabolomics'
        })

    config = {
        'tools': top_tools,
        'install_repository_dependencies': True,
        'install_resolver_dependencies': True
    }

    with open(output_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)

    print(f"✓ Saved top {count} LC-MS tools to: {output_path}")


def main():
    db_path = '/tmp/lcms-platform-galaxy/database/tool_search_index.db'
    output_path = '/tmp/lcms-platform-galaxy/config/top_lcms_tools.yml'

    print("Identifying top LC-MS tools...")
    print("=" * 50)

    tools = find_lcms_tools(db_path)

    print(f"\nFound {len(tools)} LC-MS related tools")
    print(f"\nTop 10 LC-MS tools by priority:\n")

    for i, tool in enumerate(tools[:10], 1):
        print(f"{i}. {tool['name']} (Score: {tool['priority_score']})")
        print(f"   Repo: {tool['repo_owner']}/{tool['repo_name']} v{tool['version']}")
        print(f"   Changeset: {tool['changeset_revision'] or 'N/A'}")
        print()

    # Save top 20 for installation
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    save_top_tools_config(tools, output_path, count=20)

    print(f"\n✓ Configuration ready for installation")


if __name__ == '__main__':
    main()
