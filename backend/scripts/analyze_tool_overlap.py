#!/usr/bin/env python3
"""
Analyze overlap between BioMni, nf-core, and Galaxy tools with updated database.
"""

import json
from pathlib import Path
from difflib import SequenceMatcher


def normalize_tool_name(name):
    """Normalize tool name for comparison."""
    return name.lower().replace('-', '').replace('_', '').replace(' ', '')


def is_similar(name1, name2, threshold=0.85):
    """Check if two tool names are similar."""
    norm1 = normalize_tool_name(name1)
    norm2 = normalize_tool_name(name2)

    # Exact match
    if norm1 == norm2:
        return True

    # One contains the other
    if norm1 in norm2 or norm2 in norm1:
        return True

    # Sequence similarity
    ratio = SequenceMatcher(None, norm1, norm2).ratio()
    return ratio >= threshold


def load_galaxy_tools(galaxy_db_path):
    """Load Galaxy tools from database."""
    with open(galaxy_db_path, 'r') as f:
        galaxy_data = json.load(f)

    # Extract tool names (normalized)
    galaxy_tools = set()
    galaxy_tools_raw = []

    # Handle both array and dict formats
    if isinstance(galaxy_data, list):
        tools_list = galaxy_data
    else:
        tools_list = galaxy_data.values()

    for tool in tools_list:
        # Try different name fields
        name = tool.get('name', '') or tool.get('toolName', '')
        name = name.strip()

        if name:
            # Remove "Repository Actions\n" prefix if present
            if '\n' in name:
                name = name.split('\n')[-1].strip()

            galaxy_tools.add(normalize_tool_name(name))
            galaxy_tools_raw.append(name)

    return galaxy_tools, galaxy_tools_raw


def load_biomni_tools(biomni_summary_path):
    """Load BioMni tools from conversion summary."""
    with open(biomni_summary_path, 'r') as f:
        biomni_data = json.load(f)

    converted = biomni_data.get('converted', [])

    # Count total functions from Biomni
    biomni_dir = Path('/Users/jingqiwang/Biomni/biomni/tool')
    total_functions = 0
    all_function_names = []

    if biomni_dir.exists():
        for module_file in biomni_dir.glob('*.py'):
            if module_file.stem.startswith('_'):
                continue

            import ast
            try:
                with open(module_file, 'r') as f:
                    tree = ast.parse(f.read())

                for node in ast.walk(tree):
                    if isinstance(node, ast.FunctionDef):
                        if not node.name.startswith('_'):
                            total_functions += 1
                            all_function_names.append(node.name)
            except:
                pass

    return converted, all_function_names, total_functions


def load_nfcore_tools(nfcore_dir):
    """Load nf-core module names."""
    nfcore_path = Path(nfcore_dir)

    if not nfcore_path.exists():
        print(f"⚠️  nf-core directory not found: {nfcore_dir}")
        return [], 0

    modules = []
    modules_dir = nfcore_path / 'modules' / 'nf-core'

    if modules_dir.exists():
        for module_dir in modules_dir.iterdir():
            if module_dir.is_dir() and not module_dir.name.startswith('.'):
                # Check if it has main.nf (actual module vs parent directory)
                if (module_dir / 'main.nf').exists():
                    modules.append(module_dir.name)
                else:
                    # Check subdirectories
                    for submodule in module_dir.iterdir():
                        if submodule.is_dir() and (submodule / 'main.nf').exists():
                            modules.append(f"{module_dir.name}/{submodule.name}")

    return modules, len(modules)


def analyze_overlap(galaxy_tools_norm, galaxy_tools_raw, biomni_functions, nfcore_modules):
    """Analyze overlap between all three sources (optimized)."""

    # Create normalized lookup for fast matching
    galaxy_norm_to_raw = {}
    for raw_name in galaxy_tools_raw:
        norm = normalize_tool_name(raw_name)
        if norm not in galaxy_norm_to_raw:
            galaxy_norm_to_raw[norm] = raw_name

    # BioMni overlap - use normalized set for fast lookup
    biomni_in_galaxy = []
    biomni_missing = []

    for func in biomni_functions:
        norm_func = normalize_tool_name(func)
        if norm_func in galaxy_norm_to_raw:
            biomni_in_galaxy.append((func, galaxy_norm_to_raw[norm_func]))
        else:
            biomni_missing.append(func)

    # nf-core overlap
    nfcore_in_galaxy = []
    nfcore_missing = []

    for module in nfcore_modules:
        module_name = module.split('/')[-1]  # Get last part of path
        norm_module = normalize_tool_name(module_name)

        if norm_module in galaxy_norm_to_raw:
            nfcore_in_galaxy.append((module, galaxy_norm_to_raw[norm_module]))
        else:
            nfcore_missing.append(module)

    return {
        'biomni_in_galaxy': biomni_in_galaxy,
        'biomni_missing': biomni_missing,
        'nfcore_in_galaxy': nfcore_in_galaxy,
        'nfcore_missing': nfcore_missing
    }


def main():
    print("=" * 80)
    print("BioMni & nf-core vs Galaxy Tool Overlap Analysis")
    print("Updated with parallel crawler results (7,359 tools)")
    print("=" * 80)

    # Load Galaxy tools
    galaxy_db = '/Users/jingqiwang/biomate/backend/database/all_unique_tools.json'
    print(f"\n📂 Loading Galaxy tools from: {galaxy_db}")
    galaxy_tools, galaxy_tools_raw = load_galaxy_tools(galaxy_db)
    print(f"   ✓ Loaded {len(galaxy_tools)} unique Galaxy tools")

    # Load BioMni tools
    biomni_summary = '/Users/jingqiwang/biomate/backend/tools/biomni_generated/biomni_conversion_summary.json'
    print(f"\n📂 Loading BioMni tools...")
    converted_biomni, all_biomni_functions, total_biomni = load_biomni_tools(biomni_summary)
    print(f"   ✓ Found {total_biomni} total BioMni functions")
    print(f"   ✓ Converted {len(converted_biomni)} to Galaxy")

    # Load nf-core modules
    nfcore_dir = '/Users/jingqiwang/nf-core-modules'
    print(f"\n📂 Loading nf-core modules from: {nfcore_dir}")
    nfcore_modules, total_nfcore = load_nfcore_tools(nfcore_dir)
    print(f"   ✓ Found {total_nfcore} nf-core modules")

    # Analyze overlap
    print(f"\n🔍 Analyzing overlap...")
    overlap = analyze_overlap(galaxy_tools, galaxy_tools_raw, all_biomni_functions, nfcore_modules)

    # Print results
    print("\n" + "=" * 80)
    print("📊 BIOMNI vs GALAXY OVERLAP")
    print("=" * 80)
    print(f"Total BioMni functions:    {total_biomni}")
    print(f"Found in Galaxy:           {len(overlap['biomni_in_galaxy'])} ({len(overlap['biomni_in_galaxy'])/total_biomni*100:.1f}%)")
    print(f"Missing from Galaxy:       {len(overlap['biomni_missing'])} ({len(overlap['biomni_missing'])/total_biomni*100:.1f}%)")
    print(f"Converted to Galaxy XML:   {len(converted_biomni)}")

    print("\n" + "=" * 80)
    print("📊 NF-CORE vs GALAXY OVERLAP")
    print("=" * 80)
    print(f"Total nf-core modules:     {total_nfcore}")
    print(f"Found in Galaxy:           {len(overlap['nfcore_in_galaxy'])} ({len(overlap['nfcore_in_galaxy'])/total_nfcore*100:.1f}%)")
    print(f"Missing from Galaxy:       {len(overlap['nfcore_missing'])} ({len(overlap['nfcore_missing'])/total_nfcore*100:.1f}%)")

    # Check how many converted tools exist
    nfcore_generated_dir = Path('/Users/jingqiwang/biomate/backend/tools/nfcore_generated')
    if nfcore_generated_dir.exists():
        nfcore_generated = len(list(nfcore_generated_dir.glob('*.xml')))
        print(f"Converted to Galaxy XML:   {nfcore_generated}")

    # Save detailed report
    output = {
        'timestamp': '2025-10-12',
        'galaxy_tools_count': len(galaxy_tools),
        'biomni': {
            'total_functions': total_biomni,
            'in_galaxy': len(overlap['biomni_in_galaxy']),
            'missing': len(overlap['biomni_missing']),
            'converted': len(converted_biomni),
            'in_galaxy_list': overlap['biomni_in_galaxy'],
            'missing_list': overlap['biomni_missing']
        },
        'nfcore': {
            'total_modules': total_nfcore,
            'in_galaxy': len(overlap['nfcore_in_galaxy']),
            'missing': len(overlap['nfcore_missing']),
            'in_galaxy_list': overlap['nfcore_in_galaxy'],
            'missing_list': overlap['nfcore_missing']
        }
    }

    output_file = '/Users/jingqiwang/biomate/backend/tool_overlap_analysis_2025-10-12.json'
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"\n💾 Detailed report saved to: {output_file}")

    print("\n" + "=" * 80)
    print("✅ ANALYSIS COMPLETE")
    print("=" * 80)

    return output


if __name__ == '__main__':
    main()
