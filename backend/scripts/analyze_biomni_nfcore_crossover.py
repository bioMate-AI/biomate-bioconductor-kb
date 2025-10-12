#!/usr/bin/env python3
"""
Analyze the cross-overlap between BioMni software and nf-core modules.
Find which tools exist in both BioMni and nf-core.
"""

import json
import re
from pathlib import Path
from typing import List, Set, Dict

def normalize_tool_name(name: str) -> str:
    """Normalize tool names for comparison."""
    name = re.sub(r'^repository actions\s*\n?\s*', '', name, flags=re.IGNORECASE)
    name = name.lower()
    name = re.sub(r'[-_\s](tools?|package|wrapper|suite)$', '', name)
    name = re.sub(r'[-_\s]*v?\d+(\.\d+)*$', '', name)
    name = re.sub(r'[^a-z0-9]', '', name)
    return name

def extract_biomni_tools() -> List[str]:
    """Extract BioMni tool names."""
    try:
        biomni_env_desc = Path.home() / "biomni" / "biomni" / "env_desc.py"
        if not biomni_env_desc.exists():
            print(f"⚠️  BioMni env_desc.py not found")
            return []

        with open(biomni_env_desc, 'r') as f:
            content = f.read()

        matches = re.findall(r'^\s+"([^"]+)":\s*"\[', content, re.MULTILINE)
        software_tools = [m for m in matches if not m.endswith('.parquet') and not m.endswith('.csv')]
        return sorted(set(software_tools))

    except Exception as e:
        print(f"Error reading env_desc.py: {e}")
        return []

def extract_nfcore_modules() -> List[str]:
    """Extract nf-core module names."""
    modules_file = Path(__file__).parent.parent / "nfcore_modules_list.json"
    if not modules_file.exists():
        print(f"⚠️  nf-core modules list not found")
        return []

    with open(modules_file) as f:
        data = json.load(f)
    return data.get('modules', [])

def analyze_crossover(biomni_tools: List[str], nfcore_modules: List[str]) -> Dict:
    """Analyze which tools are in both BioMni and nf-core."""

    # Normalize BioMni tools
    biomni_normalized = {normalize_tool_name(tool): tool for tool in biomni_tools}

    # Extract base tool names from nf-core modules (e.g., "samtools/sort" -> "samtools")
    nfcore_tools = {}
    for module in nfcore_modules:
        base_tool = module.split('/')[0]
        norm_tool = normalize_tool_name(base_tool)
        if norm_tool not in nfcore_tools:
            nfcore_tools[norm_tool] = []
        nfcore_tools[norm_tool].append(module)

    # Find overlap
    in_both = []
    biomni_only = []
    nfcore_only = []

    # Check BioMni tools
    for norm_biomni, biomni_tool in biomni_normalized.items():
        if norm_biomni in nfcore_tools:
            in_both.append({
                'biomni': biomni_tool,
                'nfcore_modules': nfcore_tools[norm_biomni],
                'nfcore_count': len(nfcore_tools[norm_biomni])
            })
        else:
            biomni_only.append(biomni_tool)

    # Check nf-core tools not in BioMni
    for norm_nfcore, modules in nfcore_tools.items():
        if norm_nfcore not in biomni_normalized:
            nfcore_only.extend(modules)

    return {
        'in_both': in_both,
        'in_both_count': len(in_both),
        'biomni_only': biomni_only,
        'biomni_only_count': len(biomni_only),
        'nfcore_only': nfcore_only[:50],  # First 50 for display
        'nfcore_only_count': len(nfcore_only),
        'biomni_total': len(biomni_tools),
        'nfcore_total': len(nfcore_modules)
    }

def main():
    print("Analyzing BioMni ↔ nf-core crossover...")

    # Extract tools
    print("\n1. Extracting BioMni tools...")
    biomni_tools = extract_biomni_tools()
    print(f"   Found {len(biomni_tools)} BioMni tools")

    print("\n2. Extracting nf-core modules...")
    nfcore_modules = extract_nfcore_modules()
    print(f"   Found {len(nfcore_modules)} nf-core modules")

    # Analyze crossover
    print("\n3. Analyzing crossover...")
    results = analyze_crossover(biomni_tools, nfcore_modules)

    # Save results
    output_file = Path(__file__).parent.parent / "biomni_nfcore_crossover_2025-10-12.json"
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n✅ Results saved to: {output_file}")

    # Print summary
    print("\n" + "="*60)
    print("CROSSOVER ANALYSIS")
    print("="*60)

    print(f"\n📊 Overall Statistics:")
    print(f"   BioMni tools: {results['biomni_total']}")
    print(f"   nf-core modules: {results['nfcore_total']}")

    print(f"\n🔗 In BOTH BioMni AND nf-core: {results['in_both_count']} tools")
    print(f"   ({100*results['in_both_count']/results['biomni_total']:.1f}% of BioMni)")

    print(f"\n🔵 BioMni ONLY: {results['biomni_only_count']} tools")
    print(f"   ({100*results['biomni_only_count']/results['biomni_total']:.1f}% of BioMni)")

    print(f"\n🟢 nf-core ONLY: {results['nfcore_only_count']} modules")

    print(f"\n\n✅ Tools in BOTH (showing all {results['in_both_count']}):")
    for i, item in enumerate(results['in_both'], 1):
        nfcore_str = ', '.join(item['nfcore_modules'][:3])
        if item['nfcore_count'] > 3:
            nfcore_str += f" ... (+{item['nfcore_count']-3} more)"
        print(f"{i:3}. {item['biomni']:20} → nf-core: {nfcore_str}")

    print(f"\n\n🔵 BioMni ONLY (showing first 20):")
    for i, tool in enumerate(results['biomni_only'][:20], 1):
        print(f"{i:3}. {tool}")

    print(f"\n\n🟢 nf-core ONLY (showing first 30):")
    for i, module in enumerate(results['nfcore_only'][:30], 1):
        print(f"{i:3}. {module}")

if __name__ == '__main__':
    main()
