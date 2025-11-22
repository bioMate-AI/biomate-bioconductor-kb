#!/usr/bin/env python3
"""
Tool ID Inventory and Mapping Script

Creates a unified tool ID mapping between nf-core workflows and IWC workflows.
Ensures consistency and identifies tools by source.

Author: AI Assistant (Claude)
Date: 2025-11-19
"""

import json
import os
import re
from pathlib import Path
from collections import defaultdict
from datetime import datetime

# Directories
NFCORE_DIR = "/home/yzhang/biomate/backend/galaxy_workflows"
IWC_DIR = "/home/yzhang/biomate/research/curated_workflows"
OUTPUT_DIR = "/home/yzhang/biomate/research"

def extract_tool_ids(directory: str) -> dict:
    """Extract all tool IDs from .ga files in a directory."""

    tools = defaultdict(lambda: {
        'count': 0,
        'workflows': [],
        'versions': set(),
        'source': 'unknown'
    })

    ga_files = list(Path(directory).glob("*.ga"))

    for filepath in ga_files:
        try:
            with open(filepath, 'r') as f:
                data = json.load(f)

            steps = data.get('steps', {})
            workflow_name = data.get('name', filepath.stem)

            for step_id, step in steps.items():
                tool_id = step.get('tool_id')
                if tool_id and tool_id != 'null':
                    # Normalize tool ID
                    tool_info = parse_tool_id(tool_id)

                    tools[tool_info['canonical']]['count'] += 1
                    tools[tool_info['canonical']]['workflows'].append(workflow_name)
                    tools[tool_info['canonical']]['versions'].add(tool_info['version'])
                    tools[tool_info['canonical']]['source'] = tool_info['source']
                    tools[tool_info['canonical']]['full_id'] = tool_id
                    tools[tool_info['canonical']]['owner'] = tool_info['owner']
                    tools[tool_info['canonical']]['tool_name'] = tool_info['tool_name']

        except Exception as e:
            print(f"Error processing {filepath}: {e}")

    return tools


def parse_tool_id(tool_id: str) -> dict:
    """Parse a tool ID and extract components."""

    result = {
        'full_id': tool_id,
        'canonical': tool_id,
        'source': 'unknown',
        'owner': 'unknown',
        'tool_name': tool_id,
        'version': 'unknown'
    }

    # Galaxy ToolShed format
    # toolshed.g2.bx.psu.edu/repos/{owner}/{repo}/{tool_id}/{version}
    toolshed_match = re.match(
        r'toolshed\.g2\.bx\.psu\.edu/repos/([^/]+)/([^/]+)/([^/]+)(?:/([^/]+))?',
        tool_id
    )

    if toolshed_match:
        owner, repo, tool_name, version = toolshed_match.groups()
        result['source'] = 'toolshed'
        result['owner'] = owner
        result['tool_name'] = tool_name
        result['version'] = version or 'unknown'
        # Canonical: owner/tool_name (without version for grouping)
        result['canonical'] = f"{owner}/{tool_name}"
        return result

    # Built-in Galaxy tools (no toolshed prefix)
    builtin_tools = [
        'Filter1', 'cat1', 'Cut1', 'Paste1', 'join1', 'sort1',
        'Grep1', 'Grouping1', 'Count1', 'Show beginning1', 'Remove beginning1',
        'addValue', 'Summary_Statistics1', 'random_lines1',
        '__APPLY_RULES__', '__BUILD_LIST__', '__EXTRACT_DATASET__',
        '__MERGE_COLLECTION__', '__FILTER_EMPTY_DATASETS__', '__FILTER_FAILED_DATASETS__',
        '__FILTER_FROM_FILE__', '__FLATTEN__', '__SORTLIST__', '__RELABEL_FROM_FILE__',
        '__HARMONIZELISTS__', '__DUPLICATE_FILE_TO_COLLECTION__',
        'param_value_from_file', 'pick_value', 'wig_to_bigWig',
        'CONVERTER_fasta_to_fai', 'CONVERTER_gz_to_uncompressed',
        'CONVERTER_uncompressed_to_gz', 'csv_to_tabular', 'Convert characters1',
        'gene2exon1'
    ]

    if tool_id in builtin_tools or tool_id.startswith('__'):
        result['source'] = 'builtin'
        result['owner'] = 'galaxy'
        result['tool_name'] = tool_id
        result['canonical'] = f"galaxy/{tool_id}"
        return result

    # nf-core custom tools
    if tool_id.startswith('nfcore_') or tool_id.startswith('nf_'):
        result['source'] = 'nfcore'
        result['owner'] = 'nfcore'
        result['tool_name'] = tool_id
        result['canonical'] = f"nfcore/{tool_id}"
        return result

    # BioMate custom tools
    if tool_id.startswith('biomate_'):
        result['source'] = 'biomate'
        result['owner'] = 'biomate'
        result['tool_name'] = tool_id
        result['canonical'] = f"biomate/{tool_id}"
        return result

    # Galaxy utility tools
    if tool_id.startswith('galaxy_'):
        result['source'] = 'galaxy'
        result['owner'] = 'galaxy'
        result['tool_name'] = tool_id
        result['canonical'] = f"galaxy/{tool_id}"
        return result

    # Custom tools with owner prefix (owner_toolname_version)
    custom_match = re.match(r'([a-z]+)_([a-z0-9_]+)_([A-Za-z0-9_\.+]+)$', tool_id)
    if custom_match:
        owner, tool_name, version = custom_match.groups()
        result['source'] = 'custom'
        result['owner'] = owner
        result['tool_name'] = f"{owner}_{tool_name}"
        result['version'] = version
        result['canonical'] = f"{owner}/{tool_name}"
        return result

    # Fallback: unknown format
    result['source'] = 'custom'
    result['canonical'] = f"custom/{tool_id}"

    return result


def create_inventory():
    """Create comprehensive tool inventory."""

    print("=" * 60)
    print("Tool ID Inventory Generator")
    print("=" * 60)
    print()

    # Extract tools from both sources
    print("Extracting tools from nf-core workflows...")
    nfcore_tools = extract_tool_ids(NFCORE_DIR)
    print(f"  Found {len(nfcore_tools)} unique tools")

    print("Extracting tools from IWC workflows...")
    iwc_tools = extract_tool_ids(IWC_DIR)
    print(f"  Found {len(iwc_tools)} unique tools")

    # Merge and analyze
    all_tools = {}

    for tool_id, info in nfcore_tools.items():
        all_tools[tool_id] = {
            **info,
            'in_nfcore': True,
            'in_iwc': False,
            'versions': list(info['versions'])
        }

    for tool_id, info in iwc_tools.items():
        if tool_id in all_tools:
            all_tools[tool_id]['in_iwc'] = True
            all_tools[tool_id]['count'] += info['count']
            all_tools[tool_id]['workflows'].extend(info['workflows'])
            all_tools[tool_id]['versions'] = list(
                set(all_tools[tool_id]['versions']) | info['versions']
            )
        else:
            all_tools[tool_id] = {
                **info,
                'in_nfcore': False,
                'in_iwc': True,
                'versions': list(info['versions'])
            }

    # Generate reports
    generate_reports(all_tools, nfcore_tools, iwc_tools)

    return all_tools


def generate_reports(all_tools: dict, nfcore_tools: dict, iwc_tools: dict):
    """Generate inventory reports."""

    timestamp = datetime.now().strftime("%Y%m%d_%H%M")

    # JSON inventory
    json_path = os.path.join(OUTPUT_DIR, f"{timestamp}_TOOL_INVENTORY.json")

    # Convert for JSON serialization
    json_data = {}
    for tool_id, info in all_tools.items():
        json_data[tool_id] = {
            'count': info['count'],
            'source': info['source'],
            'owner': info.get('owner', 'unknown'),
            'tool_name': info.get('tool_name', tool_id),
            'versions': info['versions'],
            'in_nfcore': info['in_nfcore'],
            'in_iwc': info['in_iwc'],
            'full_id': info.get('full_id', tool_id)
        }

    with open(json_path, 'w') as f:
        json.dump(json_data, f, indent=2, sort_keys=True)

    print(f"\nJSON inventory: {json_path}")

    # Markdown report
    md_path = os.path.join(OUTPUT_DIR, f"{timestamp}_TOOL_INVENTORY_REPORT.md")

    report = []
    report.append("# Tool ID Inventory Report\n\n")
    report.append(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
    report.append(f"**Total Unique Tools:** {len(all_tools)}\n")
    report.append(f"**nf-core Tools:** {len(nfcore_tools)}\n")
    report.append(f"**IWC Tools:** {len(iwc_tools)}\n\n")

    # Tools by source
    by_source = defaultdict(list)
    for tool_id, info in all_tools.items():
        by_source[info['source']].append((tool_id, info))

    report.append("## Tools by Source\n\n")
    for source, tools in sorted(by_source.items()):
        report.append(f"### {source.upper()} ({len(tools)} tools)\n\n")
        for tool_id, info in sorted(tools, key=lambda x: -x[1]['count'])[:30]:
            in_both = "✓" if info['in_nfcore'] and info['in_iwc'] else ""
            report.append(f"- `{tool_id}` (used {info['count']}x) {in_both}\n")
        if len(tools) > 30:
            report.append(f"- ... and {len(tools) - 30} more\n")
        report.append("\n")

    # Shared tools (in both nf-core and IWC)
    shared = [(k, v) for k, v in all_tools.items() if v['in_nfcore'] and v['in_iwc']]
    report.append(f"## Shared Tools ({len(shared)} tools in both collections)\n\n")
    report.append("These tools should have consistent IDs:\n\n")
    for tool_id, info in sorted(shared, key=lambda x: -x[1]['count']):
        report.append(f"- `{tool_id}` ({info['count']}x)\n")
    report.append("\n")

    # Tools only in nf-core
    nfcore_only = [(k, v) for k, v in all_tools.items() if v['in_nfcore'] and not v['in_iwc']]
    report.append(f"## nf-core Only Tools ({len(nfcore_only)} tools)\n\n")
    for tool_id, info in sorted(nfcore_only, key=lambda x: -x[1]['count'])[:50]:
        report.append(f"- `{tool_id}` ({info['count']}x)\n")
    if len(nfcore_only) > 50:
        report.append(f"- ... and {len(nfcore_only) - 50} more\n")
    report.append("\n")

    # Tools only in IWC
    iwc_only = [(k, v) for k, v in all_tools.items() if v['in_iwc'] and not v['in_nfcore']]
    report.append(f"## IWC Only Tools ({len(iwc_only)} tools)\n\n")
    report.append("These are candidates for on-demand installation:\n\n")
    for tool_id, info in sorted(iwc_only, key=lambda x: -x[1]['count'])[:100]:
        versions = ', '.join(info['versions'][:3])
        report.append(f"- `{tool_id}` ({info['count']}x) [{versions}]\n")
    if len(iwc_only) > 100:
        report.append(f"- ... and {len(iwc_only) - 100} more\n")
    report.append("\n")

    # Version conflicts
    report.append("## Tools with Multiple Versions\n\n")
    multi_version = [(k, v) for k, v in all_tools.items() if len(v['versions']) > 1]
    for tool_id, info in sorted(multi_version, key=lambda x: -len(x[1]['versions']))[:50]:
        versions = ', '.join(sorted(info['versions']))
        report.append(f"- `{tool_id}`: {versions}\n")
    report.append("\n")

    with open(md_path, 'w') as f:
        f.write(''.join(report))

    print(f"Markdown report: {md_path}")

    # Summary
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"Total unique tools: {len(all_tools)}")
    print(f"Shared tools: {len(shared)}")
    print(f"nf-core only: {len(nfcore_only)}")
    print(f"IWC only: {len(iwc_only)}")
    print()
    print("By source:")
    for source, tools in sorted(by_source.items(), key=lambda x: -len(x[1])):
        print(f"  {source}: {len(tools)}")


if __name__ == "__main__":
    create_inventory()
