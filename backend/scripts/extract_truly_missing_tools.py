#!/usr/bin/env python3
"""
Extract the list of TRULY missing tools that need to be implemented.

This identifies:
- 568 nf-core modules NOT in Galaxy Toolshed
- 34 BioMni tools NOT in Galaxy Toolshed

Total: 602 tools that actually need implementation
"""

import json
from pathlib import Path
from datetime import datetime


def extract_truly_missing_tools():
    """Extract only the tools that are truly missing from Galaxy."""

    # Load source files
    base_dir = Path(__file__).parent.parent

    nfcore_file = base_dir / "nfcore_modules_list.json"
    overlap_file = base_dir / "tool_overlap_analysis_corrected_2025-10-12.json"
    crossover_file = base_dir / "biomni_nfcore_crossover_2025-10-12.json"

    with open(nfcore_file) as f:
        nfcore_data = json.load(f)
        all_nfcore_modules = set(nfcore_data.get('modules', []))

    with open(overlap_file) as f:
        overlap = json.load(f)
        # in_galaxy_list contains arrays like [["DESeq2", "Repository Actions..."], ...]
        # Extract just the first element (tool name) from each array
        nfcore_in_galaxy = set([item[0] if isinstance(item, list) else item
                                for item in overlap['nfcore']['in_galaxy_list']])
        biomni_in_galaxy = set([item[0] if isinstance(item, list) else item
                                for item in overlap['biomni']['in_galaxy_list']])

    with open(crossover_file) as f:
        crossover = json.load(f)
        biomni_all = set([item['biomni'] for item in crossover['in_both']] + crossover['biomni_only'])

    # Calculate truly missing tools
    missing_nfcore = list(all_nfcore_modules - nfcore_in_galaxy)
    missing_biomni = list(biomni_all - biomni_in_galaxy)

    missing_nfcore.sort()
    missing_biomni.sort()

    # Create output structure
    output = {
        "metadata": {
            "created": datetime.now().isoformat(),
            "description": "List of tools truly missing from Galaxy Toolshed",
            "total_missing": len(missing_nfcore) + len(missing_biomni),
            "nfcore_missing_count": len(missing_nfcore),
            "biomni_missing_count": len(missing_biomni)
        },
        "statistics": {
            "nfcore": {
                "total_modules": len(all_nfcore_modules),
                "in_galaxy": len(nfcore_in_galaxy),
                "missing": len(missing_nfcore),
                "coverage_percent": round(len(nfcore_in_galaxy) / len(all_nfcore_modules) * 100, 1)
            },
            "biomni": {
                "total_tools": len(biomni_all),
                "in_galaxy": len(biomni_in_galaxy),
                "missing": len(missing_biomni),
                "coverage_percent": round(len(biomni_in_galaxy) / len(biomni_all) * 100, 1)
            }
        },
        "missing_nfcore_modules": missing_nfcore,
        "missing_biomni_tools": missing_biomni
    }

    # Save output
    output_file = base_dir / "TRULY_MISSING_TOOLS_2025-10-13.json"
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)

    # Print summary
    print(f"{'='*70}")
    print("TRULY MISSING TOOLS ANALYSIS")
    print(f"{'='*70}\n")

    print(f"nf-core Modules:")
    print(f"  Total: {len(all_nfcore_modules)}")
    print(f"  In Galaxy: {len(nfcore_in_galaxy)} ({output['statistics']['nfcore']['coverage_percent']}%)")
    print(f"  Missing: {len(missing_nfcore)}")

    print(f"\nBioMni Tools:")
    print(f"  Total: {len(biomni_all)}")
    print(f"  In Galaxy: {len(biomni_in_galaxy)} ({output['statistics']['biomni']['coverage_percent']}%)")
    print(f"  Missing: {len(missing_biomni)}")

    print(f"\n{'='*70}")
    print(f"TOTAL TOOLS TO IMPLEMENT: {len(missing_nfcore) + len(missing_biomni)}")
    print(f"{'='*70}\n")

    print(f"✅ Saved to: {output_file}\n")

    # Print sample missing tools
    print("Sample missing nf-core modules (first 20):")
    for tool in missing_nfcore[:20]:
        print(f"  - {tool}")

    print(f"\nSample missing BioMni tools (first 20):")
    for tool in missing_biomni[:20]:
        print(f"  - {tool}")

    return output


def analyze_priority_tools():
    """Analyze which tools should be prioritized based on usage/importance."""

    base_dir = Path(__file__).parent.parent
    missing_file = base_dir / "TRULY_MISSING_TOOLS_2025-10-13.json"

    with open(missing_file) as f:
        data = json.load(f)

    missing_nfcore = data['missing_nfcore_modules']

    # Common high-priority tool categories
    high_priority_patterns = [
        'gatk4/', 'samtools/', 'bcftools/', 'picard/',
        'star/', 'hisat2/', 'salmon/', 'kallisto/',
        'fastp', 'fastqc', 'trimmomatic', 'cutadapt',
        'deseq2', 'edger', 'limma',
        'macs2', 'homer', 'deeptools',
        'openms/', 'diann', 'maxquant',
        'cellranger', 'seurat', 'scanpy'
    ]

    priority_tools = []
    for tool in missing_nfcore:
        tool_lower = tool.lower()
        if any(pattern in tool_lower for pattern in high_priority_patterns):
            priority_tools.append(tool)

    print(f"\n{'='*70}")
    print("HIGH PRIORITY TOOLS ANALYSIS")
    print(f"{'='*70}\n")
    print(f"Found {len(priority_tools)} high-priority tools:\n")

    for tool in sorted(priority_tools)[:30]:
        print(f"  - {tool}")

    if len(priority_tools) > 30:
        print(f"\n  ... and {len(priority_tools) - 30} more")

    return priority_tools


if __name__ == "__main__":
    # Extract truly missing tools
    result = extract_truly_missing_tools()

    # Analyze priority
    priority = analyze_priority_tools()

    print(f"\n{'='*70}")
    print("✅ ANALYSIS COMPLETE")
    print(f"{'='*70}")
    print(f"\nNext steps:")
    print("1. Clone nf-core/modules repository for real tool metadata")
    print("2. Create wrapper generator that fetches from main.nf and meta.yml")
    print("3. Start with high-priority batch (top 50 tools)")
    print("4. Generate production-quality wrappers for all 602 tools")
