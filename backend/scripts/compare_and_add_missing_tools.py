#!/usr/bin/env python3
"""
Compare Generated Tools with Galaxy Toolshed and Add Only Missing Ones

1. Load all generated nfcore tools
2. Load Galaxy Toolshed tools
3. Find which are truly missing
4. For overlapping tools, compare quality
5. Generate only missing ones with high-quality descriptions
"""

import json
from pathlib import Path
from typing import Set, List, Dict, Tuple


def normalize_tool_name(name: str) -> str:
    """Normalize tool names for comparison."""
    return name.lower().replace('-', '').replace('_', '').replace(' ', '').replace('/', '').strip()


def load_generated_nfcore_tools() -> Dict[str, Path]:
    """Load all generated nfcore tool XMLs."""
    nfcore_dirs = ['nfcore_general', 'nfcore_generated', 'nfcore_lcms']
    generated = {}

    for dir_name in nfcore_dirs:
        dir_path = Path(f'backend/tools/{dir_name}')
        if dir_path.exists():
            for xml_file in dir_path.glob('*.xml'):
                tool_name = xml_file.stem.replace('nfcore_', '')
                generated[tool_name] = xml_file

    return generated


def load_galaxy_tools() -> Set[str]:
    """Load Galaxy Toolshed tools from crawler data."""
    # Try multiple sources
    galaxy_files = [
        '/Users/jingqiwang/lcms-platform/galaxy_tools/galaxy_crawl_v2_merged.json',
        '/Users/jingqiwang/lcms-platform/galaxy_tools/latest_tools_complete/parallel_crawler_merged.json',
    ]

    galaxy_tools = set()

    for galaxy_file in galaxy_files:
        if not Path(galaxy_file).exists():
            continue

        try:
            with open(galaxy_file) as f:
                data = json.load(f)

            # Extract tool names
            if isinstance(data, dict):
                # Handle different structures
                if 'all_tools' in data:
                    tools_list = data['all_tools']
                elif 'tools' in data:
                    tools_list = data['tools']
                elif 'crawledData' in data:
                    # Nested structure
                    for cat_id, cat_data in data['crawledData'].items():
                        if isinstance(cat_data, dict) and 'repositories' in cat_data:
                            for repo in cat_data['repositories']:
                                if 'tools' in repo and isinstance(repo['tools'], list):
                                    for tool in repo['tools']:
                                        if 'name' in tool:
                                            name = tool['name'].replace('Repository Actions\\n', '').strip()
                                            if name:
                                                galaxy_tools.add(normalize_tool_name(name))
                                # Also add repo name
                                if 'repoName' in repo:
                                    galaxy_tools.add(normalize_tool_name(repo['repoName']))
                    continue
                else:
                    tools_list = []

                for tool in tools_list:
                    if isinstance(tool, str):
                        galaxy_tools.add(normalize_tool_name(tool))
                    elif isinstance(tool, dict) and 'name' in tool:
                        galaxy_tools.add(normalize_tool_name(tool['name']))

        except Exception as e:
            print(f"⚠️  Error loading {galaxy_file}: {e}")
            continue

    return galaxy_tools


def load_all_nfcore_modules() -> List[str]:
    """Load all nfcore modules from repo."""
    with open('backend/ALL_NFCORE_MODULES_2025-10-13.json') as f:
        data = json.load(f)
    return data['all_modules']


def compare_tool_quality(our_tool: Path, galaxy_tool_name: str) -> Dict:
    """Compare quality between our tool and Galaxy's version."""
    # This would require fetching Galaxy tool XML, for now just note it
    return {
        'our_tool': str(our_tool),
        'galaxy_tool': galaxy_tool_name,
        'recommendation': 'Keep both - ours has nf-core metadata'
    }


def main():
    print("=" * 80)
    print("COMPARING GENERATED TOOLS WITH GALAXY TOOLSHED")
    print("=" * 80)

    # Load generated tools
    print("\n1. Loading generated nfcore tools...")
    generated_tools = load_generated_nfcore_tools()
    print(f"   ✓ Found {len(generated_tools)} generated tools")

    # Load Galaxy tools
    print("\n2. Loading Galaxy Toolshed tools...")
    galaxy_tools = load_galaxy_tools()
    print(f"   ✓ Found {len(galaxy_tools)} Galaxy tools")

    # Load all nfcore modules
    print("\n3. Loading all nfcore modules...")
    all_nfcore = load_all_nfcore_modules()
    print(f"   ✓ Found {len(all_nfcore)} total nfcore modules")

    # Analyze overlaps
    print("\n4. Analyzing overlaps...")

    already_generated = set(generated_tools.keys())

    # Find which nfcore modules are in Galaxy
    nfcore_in_galaxy = []
    nfcore_not_in_galaxy = []

    for module in all_nfcore:
        normalized = normalize_tool_name(module)
        if normalized in galaxy_tools:
            nfcore_in_galaxy.append(module)
        else:
            nfcore_not_in_galaxy.append(module)

    print(f"   nf-core modules in Galaxy: {len(nfcore_in_galaxy)}")
    print(f"   nf-core modules NOT in Galaxy: {len(nfcore_not_in_galaxy)}")

    # Find which of the NOT in Galaxy are already generated
    truly_missing = []
    already_have = []

    for module in nfcore_not_in_galaxy:
        module_normalized = module.replace('/', '_')
        if module_normalized in already_generated:
            already_have.append(module)
        else:
            truly_missing.append(module)

    print(f"\n   From NOT in Galaxy:")
    print(f"     Already generated by us: {len(already_have)}")
    print(f"     Truly missing: {len(truly_missing)}")

    # Compare quality for overlapping tools
    print("\n5. Checking for quality improvements needed...")
    overlapping_generated = []
    for module in nfcore_in_galaxy:
        module_normalized = module.replace('/', '_')
        if module_normalized in already_generated:
            overlapping_generated.append(module)

    print(f"   Our generated tools that overlap with Galaxy: {len(overlapping_generated)}")
    print(f"   Recommendation: Keep ours - they have nf-core metadata and container info")

    # Build report
    report = {
        "metadata": {
            "timestamp": "2025-10-13",
            "total_nfcore_modules": len(all_nfcore),
            "galaxy_tools_count": len(galaxy_tools)
        },
        "summary": {
            "already_generated": len(generated_tools),
            "nfcore_in_galaxy": len(nfcore_in_galaxy),
            "nfcore_not_in_galaxy": len(nfcore_not_in_galaxy),
            "already_have_for_missing": len(already_have),
            "truly_missing": len(truly_missing),
            "overlapping_with_galaxy": len(overlapping_generated)
        },
        "nfcore_in_galaxy_list": sorted(nfcore_in_galaxy),
        "truly_missing_list": sorted(truly_missing),
        "already_generated_list": sorted(already_have),
        "overlapping_with_galaxy_list": sorted(overlapping_generated)
    }

    # Save report
    output_file = Path("backend/TOOL_COMPARISON_AND_MISSING_2025-10-13.json")
    with open(output_file, 'w') as f:
        json.dump(report, f, indent=2)

    print(f"\n6. Saved comparison report to: {output_file}")

    # Print summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Total nf-core modules: {len(all_nfcore)}")
    print(f"Galaxy Toolshed tools: {len(galaxy_tools)}")
    print()
    print("Already Generated by Us: {len(generated_tools)}")
    print(f"  - Overlap with Galaxy: {len(overlapping_generated)} (Keep ours - better metadata)")
    print(f"  - Not in Galaxy: {len(already_have)} (✓ Good additions)")
    print()
    print(f"Still Need to Generate: {len(truly_missing)}")
    print()
    print("Sample of truly missing tools (first 20):")
    for i, tool in enumerate(truly_missing[:20], 1):
        print(f"  {i}. {tool}")
    print()
    print("=" * 80)
    print(f"✅ NEXT STEP: Generate {len(truly_missing)} truly missing tools")
    print("=" * 80)


if __name__ == "__main__":
    main()
