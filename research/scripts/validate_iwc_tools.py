#!/usr/bin/env python3
"""
Validate IWC workflow tool IDs against BioMate AI tools database.

Identifies which tools exist in the database and which are missing.
"""

import json
import sqlite3
import re
from pathlib import Path
from collections import defaultdict
from datetime import datetime

# Configuration
IWC_DIR = "/home/yzhang/biomate/research/curated_workflows"
DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
OUTPUT_DIR = "/home/yzhang/biomate/research"


def extract_iwc_tool_ids():
    """Extract all unique tool IDs from IWC workflows."""

    tool_ids = defaultdict(int)
    ga_files = list(Path(IWC_DIR).glob("*.ga"))

    for filepath in ga_files:
        try:
            with open(filepath, 'r') as f:
                data = json.load(f)

            steps = data.get('steps', {})
            for step_id, step in steps.items():
                tool_id = step.get('tool_id')
                if tool_id and tool_id != 'null':
                    tool_ids[tool_id] += 1
        except Exception as e:
            print(f"Error processing {filepath}: {e}")

    return tool_ids


def check_database(tool_ids):
    """Check which tools exist in the AI database."""

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    found = {}
    missing = {}

    for tool_id, count in tool_ids.items():
        # Check exact match
        cursor.execute("SELECT tool_id FROM tools WHERE tool_id = ?", (tool_id,))
        result = cursor.fetchone()

        if result:
            found[tool_id] = count
        else:
            # Check partial match (without version)
            base_id = re.sub(r'/[^/]+$', '', tool_id)  # Remove version
            cursor.execute("SELECT tool_id FROM tools WHERE tool_id LIKE ?", (f"{base_id}%",))
            result = cursor.fetchone()

            if result:
                found[tool_id] = count
            else:
                missing[tool_id] = count

    conn.close()
    return found, missing


def categorize_missing(missing):
    """Categorize missing tools by type."""

    categories = {
        'builtin': [],
        'toolshed': [],
        'custom': []
    }

    for tool_id in missing:
        if tool_id.startswith('__') or tool_id in ['Filter1', 'cat1', 'Cut1', 'Paste1', 'join1', 'sort1', 'Grep1']:
            categories['builtin'].append(tool_id)
        elif 'toolshed.g2.bx.psu.edu' in tool_id:
            categories['toolshed'].append(tool_id)
        else:
            categories['custom'].append(tool_id)

    return categories


def main():
    print("=" * 60)
    print("IWC Tool Validation")
    print("=" * 60)
    print()

    # Extract tool IDs
    print("Extracting tool IDs from IWC workflows...")
    tool_ids = extract_iwc_tool_ids()
    print(f"  Found {len(tool_ids)} unique tool IDs")

    # Check against database
    print("\nChecking against AI database...")
    found, missing = check_database(tool_ids)
    print(f"  Found in database: {len(found)}")
    print(f"  Missing: {len(missing)}")

    # Categorize missing
    categories = categorize_missing(missing)

    # Generate report
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    report_path = f"{OUTPUT_DIR}/{timestamp}_IWC_TOOL_VALIDATION_REPORT.md"

    with open(report_path, 'w') as f:
        f.write("# IWC Tool Validation Report\n\n")
        f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"**Total unique tools:** {len(tool_ids)}\n")
        f.write(f"**Found in database:** {len(found)} ({100*len(found)/len(tool_ids):.1f}%)\n")
        f.write(f"**Missing:** {len(missing)} ({100*len(missing)/len(tool_ids):.1f}%)\n\n")

        f.write("---\n\n")
        f.write("## Missing Tools Summary\n\n")
        f.write(f"- **Built-in Galaxy tools:** {len(categories['builtin'])}\n")
        f.write(f"- **ToolShed tools:** {len(categories['toolshed'])}\n")
        f.write(f"- **Custom/other:** {len(categories['custom'])}\n\n")

        f.write("---\n\n")
        f.write("## Missing Built-in Tools\n\n")
        f.write("These are Galaxy built-in tools that should already be available:\n\n")
        for tool_id in sorted(categories['builtin']):
            f.write(f"- `{tool_id}` ({missing[tool_id]}x)\n")

        f.write("\n---\n\n")
        f.write("## Missing ToolShed Tools\n\n")
        f.write("These need to be added to the AI database or installed on-demand:\n\n")

        # Sort by usage count
        toolshed_sorted = sorted(
            [(tid, missing[tid]) for tid in categories['toolshed']],
            key=lambda x: -x[1]
        )

        for tool_id, count in toolshed_sorted[:100]:
            # Extract owner/tool name
            match = re.search(r'/repos/([^/]+)/([^/]+)/', tool_id)
            if match:
                owner, repo = match.groups()
                f.write(f"- `{owner}/{repo}` ({count}x)\n")
            else:
                f.write(f"- `{tool_id}` ({count}x)\n")

        if len(categories['toolshed']) > 100:
            f.write(f"\n... and {len(categories['toolshed']) - 100} more\n")

        f.write("\n---\n\n")
        f.write("## Missing Custom Tools\n\n")
        for tool_id in sorted(categories['custom']):
            f.write(f"- `{tool_id}` ({missing[tool_id]}x)\n")

    print(f"\nReport saved to: {report_path}")

    # Print summary
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"Total tools: {len(tool_ids)}")
    print(f"Found: {len(found)} ({100*len(found)/len(tool_ids):.1f}%)")
    print(f"Missing: {len(missing)} ({100*len(missing)/len(tool_ids):.1f}%)")
    print(f"  - Built-in: {len(categories['builtin'])}")
    print(f"  - ToolShed: {len(categories['toolshed'])}")
    print(f"  - Custom: {len(categories['custom'])}")


if __name__ == "__main__":
    main()
