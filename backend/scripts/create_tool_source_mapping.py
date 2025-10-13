#!/usr/bin/env python3
"""
Create comprehensive tool source mapping for RAG scoring.

This maps each tool to its sources: BioMni, nf-core, and/or Galaxy Toolshed.
Tools with more sources get higher confidence scores in RAG.
"""

import json
from pathlib import Path
from datetime import datetime


def create_tool_source_mapping():
    """Create a comprehensive mapping of tools to their sources."""

    # Load data files
    crossover_file = Path(__file__).parent.parent / "biomni_nfcore_crossover_2025-10-12.json"
    overlap_file = Path(__file__).parent.parent / "tool_overlap_analysis_corrected_2025-10-12.json"

    with open(crossover_file) as f:
        crossover = json.load(f)

    with open(overlap_file) as f:
        overlap = json.load(f)

    # Build comprehensive tool source map
    tool_sources = {}

    # 1. Process BioMni + nf-core crossover (23 tools in both)
    print("Processing BioMni + nf-core crossover tools...")
    for item in crossover['in_both']:
        biomni_name = item['biomni']
        nfcore_modules = item['nfcore_modules']

        # Check if in Galaxy (from overlap analysis)
        in_galaxy = any(biomni_name in str(g) for g in overlap['biomni']['in_galaxy_list'])

        # Add each nf-core module variant
        for nfcore_module in nfcore_modules:
            tool_key = nfcore_module  # Use nf-core module name as key
            tool_sources[tool_key] = {
                "tool_name": nfcore_module,
                "sources": ["biomni", "nfcore"] + (["galaxy"] if in_galaxy else []),
                "source_count": 3 if in_galaxy else 2,
                "biomni_name": biomni_name,
                "nfcore_module": nfcore_module,
                "in_toolshed": in_galaxy,
                "priority_score": 3 if in_galaxy else 2  # Higher score for more sources
            }

    print(f"  Added {len(tool_sources)} crossover tool variants")

    # 2. Process BioMni-only tools (76 tools)
    print("Processing BioMni-only tools...")
    biomni_only_count = 0
    for biomni_tool in crossover['biomni_only']:
        # Check if in Galaxy
        in_galaxy = any(biomni_tool in str(g) for g in overlap['biomni']['in_galaxy_list'])

        tool_sources[biomni_tool] = {
            "tool_name": biomni_tool,
            "sources": ["biomni"] + (["galaxy"] if in_galaxy else []),
            "source_count": 2 if in_galaxy else 1,
            "biomni_name": biomni_tool,
            "nfcore_module": None,
            "in_toolshed": in_galaxy,
            "priority_score": 2 if in_galaxy else 1
        }
        biomni_only_count += 1

    print(f"  Added {biomni_only_count} BioMni-only tools")

    # 3. Process nf-core-only modules (1,513 not in BioMni)
    print("Processing nf-core-only modules...")
    nfcore_file = Path(__file__).parent.parent / "nfcore_modules_list.json"
    with open(nfcore_file) as f:
        nfcore_data = json.load(f)
        all_nfcore = nfcore_data.get('modules', [])

    # Get list of nf-core modules already processed (in crossover)
    already_processed = set()
    for item in crossover['in_both']:
        for module in item['nfcore_modules']:
            already_processed.add(module)

    nfcore_only_count = 0
    for nfcore_module in all_nfcore:
        if nfcore_module not in already_processed:
            # Check if in Galaxy
            in_galaxy = any(nfcore_module in str(g) for g in overlap['nfcore']['in_galaxy_list'])

            tool_sources[nfcore_module] = {
                "tool_name": nfcore_module,
                "sources": ["nfcore"] + (["galaxy"] if in_galaxy else []),
                "source_count": 2 if in_galaxy else 1,
                "biomni_name": None,
                "nfcore_module": nfcore_module,
                "in_toolshed": in_galaxy,
                "priority_score": 2 if in_galaxy else 1
            }
            nfcore_only_count += 1

    print(f"  Added {nfcore_only_count} nf-core-only modules")

    # 4. Calculate statistics
    source_stats = {
        "all_three_sources": sum(1 for t in tool_sources.values() if t['source_count'] == 3),
        "two_sources": sum(1 for t in tool_sources.values() if t['source_count'] == 2),
        "one_source": sum(1 for t in tool_sources.values() if t['source_count'] == 1),
        "in_galaxy_toolshed": sum(1 for t in tool_sources.values() if t['in_toolshed']),
        "not_in_galaxy": sum(1 for t in tool_sources.values() if not t['in_toolshed']),
    }

    # 5. Create output structure
    output = {
        "metadata": {
            "created": datetime.now().isoformat(),
            "description": "Comprehensive tool source mapping for RAG scoring",
            "total_tools": len(tool_sources),
            "source_statistics": source_stats
        },
        "scoring_guidelines": {
            "3_sources": {
                "description": "Tool in BioMni + nf-core + Galaxy Toolshed",
                "priority_score": 3,
                "confidence_boost": 0.3,
                "reasoning": "Widely adopted, well-tested, immediately available"
            },
            "2_sources": {
                "description": "Tool in 2 of 3 sources",
                "priority_score": 2,
                "confidence_boost": 0.15,
                "reasoning": "Verified by multiple communities"
            },
            "1_source": {
                "description": "Tool in only 1 source",
                "priority_score": 1,
                "confidence_boost": 0.0,
                "reasoning": "May need custom wrapper or testing"
            },
            "in_toolshed": {
                "description": "Available in Galaxy Toolshed (can auto-install)",
                "availability_score": 1.0,
                "reasoning": "Immediately usable, no installation needed"
            },
            "not_in_toolshed": {
                "description": "Not in Galaxy Toolshed (needs local wrapper)",
                "availability_score": 0.5,
                "reasoning": "Requires manual installation or wrapper"
            }
        },
        "tools": tool_sources
    }

    # 6. Save output
    output_file = Path(__file__).parent.parent / "TOOL_SOURCE_MAPPING.json"
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\n{'='*70}")
    print("TOOL SOURCE MAPPING COMPLETE")
    print(f"{'='*70}\n")
    print(f"Total tools mapped: {len(tool_sources)}")
    print(f"\nBy source count:")
    print(f"  3 sources (BioMni + nf-core + Galaxy): {source_stats['all_three_sources']}")
    print(f"  2 sources: {source_stats['two_sources']}")
    print(f"  1 source: {source_stats['one_source']}")
    print(f"\nBy availability:")
    print(f"  In Galaxy Toolshed (auto-install): {source_stats['in_galaxy_toolshed']}")
    print(f"  Not in Toolshed (need wrapper): {source_stats['not_in_galaxy']}")
    print(f"\n✅ Saved to: {output_file}")

    return output


def main():
    """Main execution"""
    mapping = create_tool_source_mapping()

    # Show some examples
    print("\n" + "="*70)
    print("EXAMPLE TOOLS BY SOURCE COUNT")
    print("="*70 + "\n")

    # Tools with 3 sources
    three_source_tools = [k for k, v in mapping['tools'].items() if v['source_count'] == 3]
    if three_source_tools:
        print("3 Sources (BioMni + nf-core + Galaxy):")
        for tool in three_source_tools[:5]:
            print(f"  - {tool}")

    # Tools with 2 sources
    two_source_tools = [k for k, v in mapping['tools'].items() if v['source_count'] == 2]
    if two_source_tools:
        print(f"\n2 Sources (examples from {len(two_source_tools)} total):")
        for tool in two_source_tools[:5]:
            info = mapping['tools'][tool]
            print(f"  - {tool} ({' + '.join(info['sources'])})")

    # Tools with 1 source
    one_source_tools = [k for k, v in mapping['tools'].items() if v['source_count'] == 1]
    if one_source_tools:
        print(f"\n1 Source (examples from {len(one_source_tools)} total):")
        for tool in one_source_tools[:5]:
            info = mapping['tools'][tool]
            print(f"  - {tool} ({info['sources'][0]})")

    print("\n" + "="*70)
    print("✅ Tool source mapping ready for RAG scoring integration!")
    print("="*70)


if __name__ == "__main__":
    main()
