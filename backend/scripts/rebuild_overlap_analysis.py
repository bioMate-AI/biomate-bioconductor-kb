#!/usr/bin/env python3
"""
Rebuild Overlap Analysis with Complete Lists

Fixes the truncated lists issue in tool_overlap_analysis_corrected_2025-10-12.json
"""

import json
from pathlib import Path
from collections import defaultdict


def load_galaxy_tools():
    """Load all Galaxy Toolshed tools from crawled data."""
    galaxy_dir = Path("/Users/jingqiwang/lcms-platform/galaxy_tools/latest_tools_complete")

    # Try parallel_crawler_merged.json first
    merged_file = galaxy_dir / "parallel_crawler_merged.json"
    if merged_file.exists():
        with open(merged_file) as f:
            data = json.load(f)

        # Extract tool names from the nested structure
        tools = []
        if "crawledData" in data:
            for category_id, category_data in data["crawledData"].items():
                if isinstance(category_data, dict) and "repositories" in category_data:
                    for repo in category_data["repositories"]:
                        if "tools" in repo and isinstance(repo["tools"], list):
                            for tool in repo["tools"]:
                                if "name" in tool:
                                    # Extract clean tool name
                                    name = tool["name"]
                                    if "Repository Actions\n" in name:
                                        name = name.split("Repository Actions\n")[1]
                                    tools.append(name.strip())

                        # Also add repo name as potential tool
                        if "repoName" in repo:
                            tools.append(repo["repoName"])

        return list(set(tools))  # Deduplicate

    return []


def normalize_tool_name(name: str) -> str:
    """Normalize tool names for comparison."""
    # Remove common prefixes/suffixes
    name = name.lower().strip()
    name = name.replace("_", "").replace("-", "").replace(" ", "")
    return name


def fuzzy_match(name1: str, name2: str) -> bool:
    """Check if two tool names are similar enough to match."""
    norm1 = normalize_tool_name(name1)
    norm2 = normalize_tool_name(name2)

    # Exact match
    if norm1 == norm2:
        return True

    # One contains the other
    if norm1 in norm2 or norm2 in norm1:
        return True

    # Check for common patterns
    # e.g., "fastqc" matches "FastQC" or "fastq_quality_control"
    if len(norm1) > 3 and len(norm2) > 3:
        if norm1 in norm2 or norm2 in norm1:
            return True

    return False


def main():
    """Rebuild overlap analysis with complete lists."""

    print("="*70)
    print("REBUILDING OVERLAP ANALYSIS WITH COMPLETE LISTS")
    print("="*70)

    # Load Galaxy tools
    print("\n1. Loading Galaxy Toolshed tools...")
    galaxy_tools = load_galaxy_tools()
    print(f"   Found {len(galaxy_tools)} unique Galaxy tools")

    # Load nf-core modules
    print("\n2. Loading nf-core modules...")
    nfcore_repo = Path("/tmp/nfcore-modules/modules/nf-core")
    nfcore_modules = []

    if nfcore_repo.exists():
        for tool_dir in nfcore_repo.iterdir():
            if tool_dir.is_dir():
                for subdir in tool_dir.iterdir():
                    if subdir.is_dir() and (subdir / "main.nf").exists():
                        module_name = f"{tool_dir.name}/{subdir.name}"
                        nfcore_modules.append(module_name)

                # Also check if tool_dir itself is a module
                if (tool_dir / "main.nf").exists():
                    nfcore_modules.append(tool_dir.name)

    print(f"   Found {len(nfcore_modules)} nf-core modules")

    # Load BioMni tools
    print("\n3. Loading BioMni tools...")
    biomni_file = Path("/Users/jingqiwang/biomate/backend/tool_index.json")
    biomni_tools = []

    if biomni_file.exists():
        with open(biomni_file) as f:
            data = json.load(f)
            if "biomni" in data and "tools" in data["biomni"]:
                biomni_tools = list(data["biomni"]["tools"].keys())

    print(f"   Found {len(biomni_tools)} BioMni tools")

    # Analyze overlap - nf-core vs Galaxy
    print("\n4. Analyzing nf-core vs Galaxy overlap...")
    nfcore_in_galaxy = []
    nfcore_missing = []

    for nf_module in nfcore_modules:
        found = False
        matched_galaxy_tool = None

        for galaxy_tool in galaxy_tools:
            if fuzzy_match(nf_module, galaxy_tool):
                found = True
                matched_galaxy_tool = galaxy_tool
                break

        if found:
            nfcore_in_galaxy.append([nf_module, matched_galaxy_tool])
        else:
            nfcore_missing.append(nf_module)

    print(f"   In Galaxy: {len(nfcore_in_galaxy)}")
    print(f"   Missing: {len(nfcore_missing)}")

    # Analyze overlap - BioMni vs Galaxy
    print("\n5. Analyzing BioMni vs Galaxy overlap...")
    biomni_in_galaxy = []
    biomni_missing = []

    for biomni_tool in biomni_tools:
        found = False
        matched_galaxy_tool = None

        for galaxy_tool in galaxy_tools:
            if fuzzy_match(biomni_tool, galaxy_tool):
                found = True
                matched_galaxy_tool = galaxy_tool
                break

        if found:
            biomni_in_galaxy.append([biomni_tool, matched_galaxy_tool])
        else:
            biomni_missing.append(biomni_tool)

    print(f"   In Galaxy: {len(biomni_in_galaxy)}")
    print(f"   Missing: {len(biomni_missing)}")

    # Build complete analysis
    analysis = {
        "timestamp": "2025-10-13T12:00:00",
        "galaxy_tools_count": len(galaxy_tools),
        "nfcore": {
            "total_modules": len(nfcore_modules),
            "in_galaxy": len(nfcore_in_galaxy),
            "missing": len(nfcore_missing),
            "in_galaxy_list": nfcore_in_galaxy,  # COMPLETE list
            "missing_list": nfcore_missing  # COMPLETE list
        },
        "biomni": {
            "total_software": len(biomni_tools),
            "in_galaxy": len(biomni_in_galaxy),
            "missing": len(biomni_missing),
            "in_galaxy_list": biomni_in_galaxy,  # COMPLETE list
            "missing_list": biomni_missing  # COMPLETE list
        }
    }

    # Save corrected analysis
    output_file = Path("backend/tool_overlap_analysis_FIXED_2025-10-13.json")
    with open(output_file, 'w') as f:
        json.dump(analysis, f, indent=2)

    print(f"\n6. Saved corrected analysis to: {output_file}")

    # Generate truly missing tools list
    truly_missing = {
        "metadata": {
            "timestamp": "2025-10-13T12:00:00",
            "total_missing": len(nfcore_missing) + len(biomni_missing),
            "nfcore_missing_count": len(nfcore_missing),
            "biomni_missing_count": len(biomni_missing)
        },
        "missing_nfcore_modules": nfcore_missing,
        "missing_biomni_tools": biomni_missing
    }

    missing_file = Path("backend/TRULY_MISSING_TOOLS_FIXED_2025-10-13.json")
    with open(missing_file, 'w') as f:
        json.dump(truly_missing, f, indent=2)

    print(f"   Saved missing tools list to: {missing_file}")

    # Summary
    print("\n" + "="*70)
    print("SUMMARY:")
    print("="*70)
    print(f"Total Galaxy Tools: {len(galaxy_tools)}")
    print(f"\nnf-core:")
    print(f"  Total: {len(nfcore_modules)}")
    print(f"  In Galaxy: {len(nfcore_in_galaxy)}")
    print(f"  Truly Missing: {len(nfcore_missing)}")
    print(f"\nBioMni:")
    print(f"  Total: {len(biomni_tools)}")
    print(f"  In Galaxy: {len(biomni_in_galaxy)}")
    print(f"  Truly Missing: {len(biomni_missing)}")
    print(f"\nTotal Truly Missing: {len(nfcore_missing) + len(biomni_missing)}")
    print("="*70)

    # Show sample of missing tools
    print("\nSample of truly missing nf-core tools (first 10):")
    for i, tool in enumerate(nfcore_missing[:10], 1):
        print(f"  {i}. {tool}")

    print("\nSample of truly missing BioMni tools (first 10):")
    for i, tool in enumerate(biomni_missing[:10], 1):
        print(f"  {i}. {tool}")

    # Compare with what we generated
    print("\n" + "="*70)
    print("COMPARISON WITH GENERATED TOOLS:")
    print("="*70)

    generated_file = Path("backend/tools/NFCORE_MISSING_INDEX_100_tools.json")
    if generated_file.exists():
        with open(generated_file) as f:
            generated = json.load(f)

        print(f"\nGenerated {generated['total_generated']} tools")
        print(f"Should have generated {len(nfcore_missing)} tools")
        print(f"Difference: {generated['total_generated'] - len(nfcore_missing)} extra tools")

        # Check for duplicates in generated
        duplicates = []
        for gen_tool in generated['generated_tools'][:20]:  # Sample check
            for match in nfcore_in_galaxy:
                if fuzzy_match(gen_tool, match[0]):
                    duplicates.append((gen_tool, match[1]))
                    break

        if duplicates:
            print(f"\nSample of DUPLICATE tools we generated (already in Galaxy):")
            for i, (gen, galaxy) in enumerate(duplicates[:5], 1):
                print(f"  {i}. {gen} -> Already in Galaxy as '{galaxy}'")


if __name__ == "__main__":
    main()
