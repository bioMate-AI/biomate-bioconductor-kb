"""
Batch Workflow Analysis Script

Analyzes all Galaxy workflows and generates statistics.
Helps understand the workflow dataset for BioMate integration.

Usage:
    python3 analyze_workflows_batch.py
"""

import json
from pathlib import Path
from collections import Counter, defaultdict
from galaxy_workflow_parser import GalaxyWorkflowParser


def analyze_all_workflows():
    """Analyze all workflows and generate statistics."""
    parser = GalaxyWorkflowParser()

    # Paths
    research_dir = Path("/home/yzhang/biomate/research/galaxy")
    ai_workflows_dir = research_dir / "lib/galaxy/ai/data/workflows"

    # Statistics collectors
    stats = {
        'total_ga_files': 0,
        'total_ai_files': 0,
        'total_parsed': 0,
        'parse_errors': 0,
        'total_steps': 0,
        'total_tool_steps': 0,
        'total_input_steps': 0,
        'all_tools': Counter(),
        'all_tags': Counter(),
        'step_count_distribution': Counter(),
        'owners': Counter(),
        'published_count': 0,
        'workflows_by_size': defaultdict(int)
    }

    errors = []

    print("="*70)
    print("GALAXY WORKFLOW BATCH ANALYSIS")
    print("="*70)

    # Analyze .ga files
    print("\n1. Analyzing .ga workflow files...")
    ga_files = list(research_dir.glob("*.ga"))
    stats['total_ga_files'] = len(ga_files)
    print(f"   Found {len(ga_files)} .ga files")

    for ga_file in ga_files:
        try:
            workflow = parser.parse_ga_file(ga_file)
            summary = parser.get_workflow_summary(workflow)

            stats['total_parsed'] += 1
            stats['total_steps'] += summary['total_steps']
            stats['total_tool_steps'] += summary['tool_steps']
            stats['total_input_steps'] += summary['input_steps']

            # Track tools
            for tool in summary['tools_used']:
                stats['all_tools'][tool] += 1

            # Track tags
            for tag in summary['tags']:
                stats['all_tags'][tag] += 1

            # Track step count distribution
            if summary['total_steps'] <= 5:
                stats['step_count_distribution']['1-5 steps'] += 1
            elif summary['total_steps'] <= 10:
                stats['step_count_distribution']['6-10 steps'] += 1
            elif summary['total_steps'] <= 20:
                stats['step_count_distribution']['11-20 steps'] += 1
            else:
                stats['step_count_distribution']['20+ steps'] += 1

        except Exception as e:
            stats['parse_errors'] += 1
            errors.append((ga_file.name, str(e)))

    # Analyze AI workflows (sample first 100 for speed)
    print("\n2. Analyzing AI workflow JSON files (sampling 100)...")
    ai_files = list(ai_workflows_dir.glob("*.json"))
    stats['total_ai_files'] = len(ai_files)
    print(f"   Found {len(ai_files)} AI workflow files")
    print(f"   Sampling first 100 for analysis...")

    for ai_file in ai_files[:100]:
        try:
            workflow = parser.parse_ai_workflow(ai_file)
            summary = parser.get_workflow_summary(workflow)

            stats['total_parsed'] += 1
            stats['total_steps'] += summary['total_steps']
            stats['total_tool_steps'] += summary['tool_steps']
            stats['total_input_steps'] += summary['input_steps']

            # Track tools
            for tool in summary['tools_used']:
                stats['all_tools'][tool] += 1

            # Track tags
            for tag in summary['tags']:
                stats['all_tags'][tag] += 1

            # Track owners
            if workflow.owner:
                stats['owners'][workflow.owner] += 1

            # Track published
            if workflow.published:
                stats['published_count'] += 1

            # Track step count distribution
            if summary['total_steps'] <= 5:
                stats['step_count_distribution']['1-5 steps'] += 1
            elif summary['total_steps'] <= 10:
                stats['step_count_distribution']['6-10 steps'] += 1
            elif summary['total_steps'] <= 20:
                stats['step_count_distribution']['11-20 steps'] += 1
            else:
                stats['step_count_distribution']['20+ steps'] += 1

            # Track by file size
            size_kb = ai_file.stat().st_size / 1024
            if size_kb < 40:
                stats['workflows_by_size']['< 40KB'] += 1
            elif size_kb < 80:
                stats['workflows_by_size']['40-80KB'] += 1
            else:
                stats['workflows_by_size']['> 80KB'] += 1

        except Exception as e:
            stats['parse_errors'] += 1
            errors.append((ai_file.name, str(e)))

    # Print statistics
    print("\n" + "="*70)
    print("ANALYSIS RESULTS")
    print("="*70)

    print("\n📊 Overall Statistics:")
    print(f"   Total .ga files: {stats['total_ga_files']}")
    print(f"   Total AI workflow files: {stats['total_ai_files']}")
    print(f"   Total parsed successfully: {stats['total_parsed']}")
    print(f"   Parse errors: {stats['parse_errors']}")

    print("\n📈 Workflow Composition:")
    print(f"   Total steps across all workflows: {stats['total_steps']}")
    print(f"   Average steps per workflow: {stats['total_steps'] / stats['total_parsed']:.1f}")
    print(f"   Total tool steps: {stats['total_tool_steps']}")
    print(f"   Total input steps: {stats['total_input_steps']}")

    print("\n📊 Step Count Distribution:")
    for range_name, count in sorted(stats['step_count_distribution'].items()):
        percentage = (count / stats['total_parsed']) * 100
        print(f"   {range_name:15s}: {count:3d} workflows ({percentage:.1f}%)")

    print("\n🔧 Top 15 Tools Used:")
    for tool, count in stats['all_tools'].most_common(15):
        print(f"   {tool:30s}: {count:3d} occurrences")

    print("\n🏷️  Top 10 Tags:")
    if stats['all_tags']:
        for tag, count in stats['all_tags'].most_common(10):
            print(f"   {tag:30s}: {count:3d} workflows")
    else:
        print("   No tags found")

    print("\n👥 Top 10 Workflow Creators:")
    if stats['owners']:
        for owner, count in stats['owners'].most_common(10):
            print(f"   {owner:30s}: {count:3d} workflows")
    else:
        print("   Owner information not available")

    print("\n📢 Publication Status (AI workflows sample):")
    print(f"   Published workflows: {stats['published_count']}")
    sample_size = min(100, stats['total_ai_files'])
    print(f"   Unpublished workflows: {sample_size - stats['published_count']}")
    if sample_size > 0:
        pub_percentage = (stats['published_count'] / sample_size) * 100
        print(f"   Publication rate: {pub_percentage:.1f}%")

    print("\n📦 Workflow Size Distribution (AI workflows):")
    for size_range, count in sorted(stats['workflows_by_size'].items()):
        print(f"   {size_range:15s}: {count:3d} workflows")

    # Print errors if any
    if errors:
        print("\n" + "="*70)
        print("PARSE ERRORS")
        print("="*70)
        for filename, error in errors[:10]:  # Show first 10 errors
            print(f"   {filename}")
            print(f"      Error: {error}")

    # Save detailed statistics to JSON
    output_file = Path("/home/yzhang/biomate/research/workflow_analysis_stats.json")
    output_data = {
        'summary': {
            'total_ga_files': stats['total_ga_files'],
            'total_ai_files': stats['total_ai_files'],
            'total_parsed': stats['total_parsed'],
            'parse_errors': stats['parse_errors'],
            'total_steps': stats['total_steps'],
            'avg_steps_per_workflow': stats['total_steps'] / stats['total_parsed'] if stats['total_parsed'] > 0 else 0
        },
        'step_distribution': dict(stats['step_count_distribution']),
        'top_tools': dict(stats['all_tools'].most_common(30)),
        'top_tags': dict(stats['all_tags'].most_common(20)),
        'top_owners': dict(stats['owners'].most_common(20)),
        'size_distribution': dict(stats['workflows_by_size'])
    }

    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    print("\n" + "="*70)
    print(f"✅ Detailed statistics saved to: {output_file}")
    print("="*70)


if __name__ == '__main__':
    analyze_all_workflows()
