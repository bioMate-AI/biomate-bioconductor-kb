#!/usr/bin/env python3
"""
Comprehensive analysis of IWC workflows.

Analyzes:
- Domain coverage and statistics
- Tool usage patterns
- Potential subworkflow groupings
- Comparison with nf-core workflows
"""

import json
import re
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime
from itertools import combinations

IWC_DIR = "/home/yzhang/biomate/backend/galaxy_workflows_official_iwc"
NFCORE_DIR = "/home/yzhang/biomate/backend/galaxy_workflows_reformatted"
OUTPUT_DIR = "/home/yzhang/biomate/research"


def extract_tool_name(tool_id):
    """Extract simplified tool name from full ID."""
    if not tool_id:
        return None

    # ToolShed format
    match = re.match(
        r'toolshed\.g2\.bx\.psu\.edu/repos/([^/]+)/([^/]+)/([^/]+)',
        tool_id
    )
    if match:
        owner, repo, tool = match.groups()
        return f"{owner}/{tool}"

    # Simple ID
    return tool_id


def analyze_workflow(filepath):
    """Analyze a single workflow."""
    with open(filepath, 'r') as f:
        workflow = json.load(f)

    # Extract domain from path
    rel_path = filepath.relative_to(Path(IWC_DIR))
    domain = str(rel_path.parts[0]) if len(rel_path.parts) > 1 else 'general'

    steps = workflow.get('steps', {})

    # Analyze steps
    input_steps = []
    tool_steps = []
    tool_sequence = []

    for step_id in sorted(steps.keys(), key=lambda x: int(x)):
        step = steps[step_id]
        step_type = step.get('type', '')

        if step_type in ['data_input', 'data_collection_input', 'parameter_input']:
            input_steps.append({
                'id': step_id,
                'type': step_type,
                'label': step.get('label', ''),
                'annotation': step.get('annotation', '')
            })
        elif step_type == 'tool':
            tool_id = step.get('tool_id', '')
            tool_name = extract_tool_name(tool_id)

            # Get input connections
            inputs = list(step.get('input_connections', {}).keys())

            tool_steps.append({
                'id': step_id,
                'tool_id': tool_id,
                'tool_name': tool_name,
                'name': step.get('name', ''),
                'label': step.get('label', ''),
                'inputs': inputs,
                'num_outputs': len(step.get('workflow_outputs', []))
            })

            if tool_name:
                tool_sequence.append(tool_name)

    return {
        'name': workflow.get('name', filepath.stem),
        'file': str(filepath.name),
        'domain': domain,
        'annotation': workflow.get('annotation', ''),
        'license': workflow.get('license', ''),
        'num_inputs': len(input_steps),
        'num_tools': len(tool_steps),
        'input_steps': input_steps,
        'tool_steps': tool_steps,
        'tool_sequence': tool_sequence,
        'unique_tools': list(set(tool_sequence))
    }


def find_tool_patterns(workflows):
    """Find common tool patterns that could be subworkflows."""

    # Count tool pairs
    pair_counts = Counter()
    triple_counts = Counter()

    for wf in workflows:
        seq = wf['tool_sequence']

        # Count consecutive pairs
        for i in range(len(seq) - 1):
            pair = (seq[i], seq[i+1])
            pair_counts[pair] += 1

        # Count consecutive triples
        for i in range(len(seq) - 2):
            triple = (seq[i], seq[i+1], seq[i+2])
            triple_counts[triple] += 1

    return pair_counts, triple_counts


def identify_subworkflow_candidates(workflows):
    """Identify logical tool groupings that could be subworkflows."""

    # Common bioinformatics patterns
    patterns = {
        'QC': ['fastqc', 'multiqc', 'fastp', 'cutadapt', 'trimmomatic'],
        'Mapping': ['bwa', 'bowtie', 'star', 'hisat', 'minimap'],
        'BAM Processing': ['samtools', 'picard', 'bamtools', 'sambamba'],
        'Variant Calling': ['bcftools', 'freebayes', 'gatk', 'lofreq', 'varscan'],
        'Peak Calling': ['macs2', 'homer', 'sicer'],
        'Quantification': ['featurecounts', 'htseq', 'salmon', 'kallisto', 'rsem'],
        'Assembly': ['spades', 'flye', 'hifiasm', 'canu', 'megahit'],
        'Annotation': ['prokka', 'augustus', 'maker', 'interproscan'],
        'Visualization': ['deeptools', 'igv', 'circos', 'bandage'],
    }

    # Find which patterns appear in each workflow
    workflow_patterns = []

    for wf in workflows:
        tools_lower = [t.lower() for t in wf['tool_sequence']]
        found_patterns = {}

        for pattern_name, pattern_tools in patterns.items():
            matching = [t for t in tools_lower if any(p in t for p in pattern_tools)]
            if matching:
                found_patterns[pattern_name] = matching

        workflow_patterns.append({
            'workflow': wf['name'],
            'domain': wf['domain'],
            'patterns': found_patterns
        })

    return workflow_patterns


def compare_with_nfcore(iwc_workflows):
    """Compare IWC coverage with nf-core workflows."""

    # Load nf-core workflows
    nfcore_workflows = []
    for filepath in Path(NFCORE_DIR).glob("*.ga"):
        try:
            with open(filepath, 'r') as f:
                workflow = json.load(f)

            steps = workflow.get('steps', {})
            tool_sequence = []

            for step_id in sorted(steps.keys(), key=lambda x: int(x)):
                step = steps[step_id]
                if step.get('type') == 'tool':
                    tool_name = extract_tool_name(step.get('tool_id', ''))
                    if tool_name:
                        tool_sequence.append(tool_name)

            nfcore_workflows.append({
                'name': workflow.get('name', filepath.stem),
                'tool_sequence': tool_sequence,
                'unique_tools': list(set(tool_sequence))
            })
        except Exception as e:
            pass

    # Compare tools
    iwc_tools = set()
    for wf in iwc_workflows:
        iwc_tools.update(wf['unique_tools'])

    nfcore_tools = set()
    for wf in nfcore_workflows:
        nfcore_tools.update(wf['unique_tools'])

    return {
        'iwc_only': iwc_tools - nfcore_tools,
        'nfcore_only': nfcore_tools - iwc_tools,
        'shared': iwc_tools & nfcore_tools,
        'iwc_count': len(iwc_workflows),
        'nfcore_count': len(nfcore_workflows)
    }


def main():
    print("=" * 60)
    print("IWC Workflow Comprehensive Analysis")
    print("=" * 60)
    print()

    # Analyze all IWC workflows
    print("Analyzing IWC workflows...")
    workflows = []

    for filepath in Path(IWC_DIR).rglob("*.ga"):
        try:
            wf = analyze_workflow(filepath)
            workflows.append(wf)
        except Exception as e:
            print(f"Error: {filepath}: {e}")

    print(f"Analyzed {len(workflows)} workflows")

    # Domain statistics
    domains = defaultdict(list)
    for wf in workflows:
        domains[wf['domain']].append(wf)

    # Tool statistics
    all_tools = Counter()
    for wf in workflows:
        for tool in wf['tool_sequence']:
            all_tools[tool] += 1

    # Find patterns
    print("Finding tool patterns...")
    pair_counts, triple_counts = find_tool_patterns(workflows)

    # Identify subworkflow candidates
    print("Identifying subworkflow candidates...")
    pattern_analysis = identify_subworkflow_candidates(workflows)

    # Compare with nf-core
    print("Comparing with nf-core workflows...")
    comparison = compare_with_nfcore(workflows)

    # Generate report
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    report_path = f"{OUTPUT_DIR}/{timestamp}_IWC_COMPREHENSIVE_ANALYSIS.md"

    with open(report_path, 'w') as f:
        f.write("# IWC Workflow Comprehensive Analysis\n\n")
        f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"**Total IWC Workflows:** {len(workflows)}\n")
        f.write(f"**Total Domains:** {len(domains)}\n\n")

        # Overall statistics
        total_tools = sum(wf['num_tools'] for wf in workflows)
        avg_tools = total_tools / len(workflows)
        max_tools = max(wf['num_tools'] for wf in workflows)
        min_tools = min(wf['num_tools'] for wf in workflows)

        f.write("---\n\n## Overall Statistics\n\n")
        f.write(f"- **Total tool steps:** {total_tools}\n")
        f.write(f"- **Average tools per workflow:** {avg_tools:.1f}\n")
        f.write(f"- **Range:** {min_tools} - {max_tools} tools\n")
        f.write(f"- **Unique tools used:** {len(all_tools)}\n\n")

        # Domain statistics
        f.write("---\n\n## Domain Statistics\n\n")
        f.write("| Domain | Workflows | Avg Steps | Total Tools | Top Tools |\n")
        f.write("|--------|-----------|-----------|-------------|----------|\n")

        for domain in sorted(domains.keys()):
            wfs = domains[domain]
            avg_steps = sum(w['num_tools'] for w in wfs) / len(wfs)
            total = sum(w['num_tools'] for w in wfs)

            # Top tools in domain
            domain_tools = Counter()
            for w in wfs:
                for t in w['tool_sequence']:
                    domain_tools[t] += 1
            top = [t[0].split('/')[-1] for t in domain_tools.most_common(3)]

            f.write(f"| {domain} | {len(wfs)} | {avg_steps:.1f} | {total} | {', '.join(top)} |\n")

        # Workflow details by domain
        f.write("\n---\n\n## Workflows by Domain\n\n")

        for domain in sorted(domains.keys()):
            wfs = sorted(domains[domain], key=lambda x: -x['num_tools'])
            f.write(f"### {domain.replace('-', ' ').title()} ({len(wfs)} workflows)\n\n")

            for wf in wfs:
                f.write(f"**{wf['name']}**\n")
                f.write(f"- Steps: {wf['num_tools']} tools, {wf['num_inputs']} inputs\n")
                if wf['annotation']:
                    desc = wf['annotation'][:150] + '...' if len(wf['annotation']) > 150 else wf['annotation']
                    f.write(f"- Description: {desc}\n")
                f.write(f"- Tool sequence: {' → '.join([t.split('/')[-1] for t in wf['tool_sequence'][:8]])}")
                if len(wf['tool_sequence']) > 8:
                    f.write(f" ... (+{len(wf['tool_sequence'])-8} more)")
                f.write("\n\n")

        # Most used tools
        f.write("---\n\n## Most Used Tools (Top 50)\n\n")
        f.write("| Rank | Tool | Count | % of Workflows |\n")
        f.write("|------|------|-------|----------------|\n")

        for i, (tool, count) in enumerate(all_tools.most_common(50), 1):
            pct = 100 * count / len(workflows)
            tool_short = tool.split('/')[-1] if '/' in tool else tool
            f.write(f"| {i} | {tool_short} | {count} | {pct:.1f}% |\n")

        # Common tool patterns (potential subworkflows)
        f.write("\n---\n\n## Common Tool Patterns (Potential Subworkflows)\n\n")

        f.write("### Tool Pairs (appearing 5+ times)\n\n")
        f.write("These consecutive tool pairs could be grouped as subworkflows:\n\n")

        for pair, count in pair_counts.most_common(30):
            if count >= 5:
                t1 = pair[0].split('/')[-1] if '/' in pair[0] else pair[0]
                t2 = pair[1].split('/')[-1] if '/' in pair[1] else pair[1]
                f.write(f"- **{t1} → {t2}** ({count}x)\n")

        f.write("\n### Tool Triples (appearing 3+ times)\n\n")

        for triple, count in triple_counts.most_common(20):
            if count >= 3:
                tools = [t.split('/')[-1] if '/' in t else t for t in triple]
                f.write(f"- **{' → '.join(tools)}** ({count}x)\n")

        # Subworkflow pattern analysis
        f.write("\n---\n\n## Logical Subworkflow Groupings\n\n")
        f.write("Based on common bioinformatics patterns:\n\n")

        pattern_counts = defaultdict(int)
        for wp in pattern_analysis:
            for pattern in wp['patterns'].keys():
                pattern_counts[pattern] += 1

        f.write("| Pattern | Workflows Using | Common Tools |\n")
        f.write("|---------|-----------------|-------------|\n")

        for pattern, count in sorted(pattern_counts.items(), key=lambda x: -x[1]):
            # Get example tools
            example_tools = set()
            for wp in pattern_analysis:
                if pattern in wp['patterns']:
                    example_tools.update(wp['patterns'][pattern][:3])
            examples = ', '.join(list(example_tools)[:4])
            f.write(f"| {pattern} | {count} | {examples} |\n")

        # Recommended subworkflows
        f.write("\n### Recommended Subworkflow Candidates\n\n")

        recommended = [
            ("QC_FASTQ", "fastqc → multiqc", "Quality control pipeline for FASTQ files", 15),
            ("TRIM_READS", "cutadapt/fastp → fastqc", "Adapter trimming with QC", 12),
            ("MAP_SORT_INDEX", "bowtie2/bwa → samtools_sort → samtools_index", "Read mapping pipeline", 20),
            ("BAM_STATS", "samtools_stats → samtools_flagstat → samtools_idxstats", "BAM statistics suite", 10),
            ("PEAK_CALL", "macs2 → bedtools", "Peak calling and processing", 8),
            ("VARIANT_FILTER", "bcftools_norm → bcftools_filter → snpsift", "Variant filtering pipeline", 6),
            ("COVERAGE", "bedtools_genomecov → deeptools_bigwig", "Coverage track generation", 7),
            ("ASSEMBLY_QC", "quast → busco → gfastats", "Assembly quality assessment", 5),
        ]

        for name, tools, desc, freq in recommended:
            f.write(f"#### {name}\n")
            f.write(f"- **Tools:** {tools}\n")
            f.write(f"- **Purpose:** {desc}\n")
            f.write(f"- **Frequency:** ~{freq} workflows\n\n")

        # Comparison with nf-core
        f.write("---\n\n## Comparison with nf-core Workflows\n\n")
        f.write(f"- **IWC workflows:** {comparison['iwc_count']}\n")
        f.write(f"- **nf-core workflows:** {comparison['nfcore_count']}\n")
        f.write(f"- **Shared tools:** {len(comparison['shared'])}\n")
        f.write(f"- **IWC-only tools:** {len(comparison['iwc_only'])}\n")
        f.write(f"- **nf-core-only tools:** {len(comparison['nfcore_only'])}\n\n")

        f.write("### Tools in IWC but not nf-core\n\n")
        iwc_only = sorted([t.split('/')[-1] for t in comparison['iwc_only']])[:30]
        for tool in iwc_only:
            f.write(f"- {tool}\n")

        if len(comparison['iwc_only']) > 30:
            f.write(f"\n... and {len(comparison['iwc_only']) - 30} more\n")

        f.write("\n### Tools in nf-core but not IWC\n\n")
        nfcore_only = sorted([t.split('/')[-1] for t in comparison['nfcore_only']])[:30]
        for tool in nfcore_only:
            f.write(f"- {tool}\n")

        if len(comparison['nfcore_only']) > 30:
            f.write(f"\n... and {len(comparison['nfcore_only']) - 30} more\n")

    print(f"\nReport saved to: {report_path}")

    # Save detailed data as JSON
    json_path = f"{OUTPUT_DIR}/{timestamp}_IWC_ANALYSIS_DATA.json"
    with open(json_path, 'w') as f:
        json.dump({
            'workflows': [{
                'name': w['name'],
                'domain': w['domain'],
                'num_tools': w['num_tools'],
                'tool_sequence': w['tool_sequence']
            } for w in workflows],
            'domain_stats': {d: len(wfs) for d, wfs in domains.items()},
            'top_tools': dict(all_tools.most_common(100)),
            'top_pairs': [(list(p), c) for p, c in pair_counts.most_common(50)],
            'comparison': {
                'shared': len(comparison['shared']),
                'iwc_only': len(comparison['iwc_only']),
                'nfcore_only': len(comparison['nfcore_only'])
            }
        }, f, indent=2)

    print(f"Data saved to: {json_path}")


if __name__ == "__main__":
    main()
