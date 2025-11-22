#!/usr/bin/env python3
"""
Analyze assembly workflow tools - categorize into utility vs biology tools.
"""

import json
from pathlib import Path
from collections import defaultdict, Counter

IWC_DIR = "/home/yzhang/biomate/backend/galaxy_workflows_official_iwc"

# Define utility/handling tools vs biology tools
UTILITY_TOOLS = {
    # Text processing
    'bgruening_text_processing', 'Cut1', 'Grep1', 'Paste1', 'join1', 'sort1',
    'Remove beginning1', 'Show beginning1', 'Show tail1', 'wc_gnu',
    'Convert characters1', 'Grouping1',

    # Parameter handling
    'param_value_from_file', 'Repository_Actions_Compose_text_parameter_value',
    'iuc_pick_value', 'iuc_map_param_value', 'expression_tools',

    # Collection operations
    '__APPLY_RULES__', '__BUILD_LIST__', '__EXTRACT_DATASET__',
    '__FILTER_EMPTY_DATASETS__', '__FILTER_FAILED_DATASETS__',
    '__FILTER_FROM_FILE__', '__FLATTEN__', '__MERGE_COLLECTION__',
    '__RELABEL_FROM_FILE__', '__SORTLIST__', '__UNZIP_COLLECTION__',
    '__ZIP_COLLECTION__', '__DUPLICATE_FILE_TO_COLLECTION__',
    '__HARMONIZELISTS__', 'Repository_Actions_Collapse_Collection',

    # Format conversion (generic)
    'CONVERTER_gz_to_uncompressed', 'CONVERTER_uncompressed_to_gz',
    'Repository_Actions_Convert', 'Repository_Actions_Tabular_to_FASTA',

    # Data manipulation
    'Repository_Actions_Add_column', 'Repository_Actions_Compute',
    'Repository_Actions_Column_join', 'iuc_datamash_ops',
    'bgruening_split_file_to_collection', 'galaxyp_regex_find_replace',
    'iuc_query_tabular', 'iuc_filter_tabular', 'Filter1',
    'Repository_Actions_Extract_element_identifiers',
    'Repository_Actions_Add_line_to_file', 'cat1',

    # Image/visualization utilities
    'Repository_Actions_Image_Montage',
}

def is_utility_tool(tool_id):
    """Check if tool is a utility/handling tool."""
    tool_lower = tool_id.lower()

    for util in UTILITY_TOOLS:
        if util.lower() in tool_lower:
            return True

    # Additional patterns
    if any(pattern in tool_lower for pattern in [
        'text_processing', 'text_reformatting', 'compose_text',
        'pick_value', 'map_param', 'param_value', 'extract_dataset',
        'filter_empty', 'filter_failed', 'apply_rules', 'build_list',
        'merge_collection', 'relabel', 'sortlist', 'unzip_collection',
        'zip_collection', 'flatten', 'collapse_collection', 'datamash',
        'split_file', 'regex_find', 'query_tabular', 'filter_tabular',
        'add_column', 'column_join', 'image_montage'
    ]):
        return True

    return False


def analyze_assembly_workflows():
    """Analyze all assembly-related workflows."""

    assembly_domains = ['VGP-assembly-v2', 'genome-assembly']

    results = []
    all_bio_tools = Counter()
    all_util_tools = Counter()

    for ga_file in Path(IWC_DIR).rglob("*.ga"):
        # Check if in assembly domain
        rel_path = ga_file.relative_to(Path(IWC_DIR))
        domain = str(rel_path.parts[0]) if len(rel_path.parts) > 1 else 'general'

        if domain not in assembly_domains:
            continue

        with open(ga_file, 'r') as f:
            workflow = json.load(f)

        steps = workflow.get('steps', {})

        bio_tools = []
        util_tools = []

        for step_id, step in steps.items():
            if step.get('type') != 'tool':
                continue

            tool_id = step.get('tool_id', '')
            tool_name = step.get('name', '')

            if not tool_id:
                continue

            # Categorize
            if is_utility_tool(tool_id):
                util_tools.append({
                    'id': tool_id,
                    'name': tool_name
                })
                # Extract short name
                short = tool_id.split('/')[-1] if '/' in tool_id else tool_id
                all_util_tools[short] += 1
            else:
                bio_tools.append({
                    'id': tool_id,
                    'name': tool_name
                })
                short = tool_id.split('/')[-1] if '/' in tool_id else tool_id
                all_bio_tools[short] += 1

        results.append({
            'name': workflow.get('name', ga_file.stem),
            'domain': domain,
            'total_tools': len(bio_tools) + len(util_tools),
            'bio_tools': bio_tools,
            'util_tools': util_tools,
            'bio_count': len(bio_tools),
            'util_count': len(util_tools)
        })

    return results, all_bio_tools, all_util_tools


def main():
    print("=" * 70)
    print("Assembly Workflow Tool Analysis")
    print("=" * 70)
    print()

    results, all_bio_tools, all_util_tools = analyze_assembly_workflows()

    # Sort by total tools
    results.sort(key=lambda x: -x['total_tools'])

    print(f"Analyzed {len(results)} assembly workflows\n")

    # Overall summary
    total_tools = sum(r['total_tools'] for r in results)
    total_bio = sum(r['bio_count'] for r in results)
    total_util = sum(r['util_count'] for r in results)

    print("=" * 70)
    print("OVERALL SUMMARY")
    print("=" * 70)
    print(f"Total tool steps:        {total_tools}")
    print(f"Biology/Analysis tools:  {total_bio} ({100*total_bio/total_tools:.1f}%)")
    print(f"Utility/Handling tools:  {total_util} ({100*total_util/total_tools:.1f}%)")
    print()

    # Per workflow breakdown
    print("=" * 70)
    print("PER WORKFLOW BREAKDOWN")
    print("=" * 70)
    print()
    print(f"{'Workflow':<55} {'Total':>6} {'Bio':>5} {'Util':>5} {'Bio%':>6}")
    print("-" * 70)

    for r in results:
        name = r['name'][:52] + '...' if len(r['name']) > 55 else r['name']
        bio_pct = 100 * r['bio_count'] / r['total_tools'] if r['total_tools'] > 0 else 0
        print(f"{name:<55} {r['total_tools']:>6} {r['bio_count']:>5} {r['util_count']:>5} {bio_pct:>5.1f}%")

    # Biology tools breakdown
    print()
    print("=" * 70)
    print("BIOLOGY/ANALYSIS TOOLS (Top 30)")
    print("=" * 70)
    print()

    for tool, count in all_bio_tools.most_common(30):
        # Clean up name
        tool_short = tool.replace('Repository_Actions_', '').replace('_', ' ')
        print(f"  {tool_short:<50} {count:>3}x")

    # Utility tools breakdown
    print()
    print("=" * 70)
    print("UTILITY/HANDLING TOOLS (Top 20)")
    print("=" * 70)
    print()

    for tool, count in all_util_tools.most_common(20):
        tool_short = tool.replace('Repository_Actions_', '').replace('_', ' ')
        print(f"  {tool_short:<50} {count:>3}x")

    # Detailed workflow analysis
    print()
    print("=" * 70)
    print("DETAILED WORKFLOW ANALYSIS")
    print("=" * 70)

    for r in results[:5]:  # Top 5 most complex
        print(f"\n### {r['name']}")
        print(f"Total: {r['total_tools']} | Bio: {r['bio_count']} | Util: {r['util_count']}")

        print("\nBiology tools:")
        bio_names = [t['name'] for t in r['bio_tools']]
        for i, name in enumerate(bio_names, 1):
            print(f"  {i}. {name}")

        print("\nUtility tools:")
        util_names = set(t['name'] for t in r['util_tools'])
        for name in sorted(util_names):
            count = sum(1 for t in r['util_tools'] if t['name'] == name)
            print(f"  - {name} ({count}x)")


if __name__ == "__main__":
    main()
