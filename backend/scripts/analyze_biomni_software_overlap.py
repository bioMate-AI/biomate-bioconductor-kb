#!/usr/bin/env python3
"""
Analyze overlap between BioMni SOFTWARE DEPENDENCIES (not Python functions) and Galaxy tools.

This script correctly analyzes:
- 119 BioMni external software dependencies (from library_content_dict)
- 1,629 nf-core modules
- 7,359 Galaxy tools (updated database)
"""

import json
import re
from pathlib import Path
from datetime import datetime
from typing import List, Tuple, Dict, Set

def normalize_tool_name(name: str) -> str:
    """Normalize tool names for comparison."""
    # Remove "Repository Actions" prefix (Galaxy-specific)
    name = re.sub(r'^repository actions\s*\n?\s*', '', name, flags=re.IGNORECASE)
    name = name.lower()
    # Remove common suffixes
    name = re.sub(r'[-_\s](tools?|package|wrapper|suite)$', '', name)
    # Remove version numbers
    name = re.sub(r'[-_\s]*v?\d+(\.\d+)*$', '', name)
    # Remove special characters
    name = re.sub(r'[^a-z0-9]', '', name)
    return name

def extract_biomni_software_list() -> List[str]:
    """Extract software names from BioMni's library_content_dict."""
    # Read from the actual env_desc.py file
    try:
        biomni_env_desc = Path.home() / "biomni" / "biomni" / "env_desc.py"
        if not biomni_env_desc.exists():
            print(f"⚠️  BioMni env_desc.py not found at {biomni_env_desc}")
            print("Using hardcoded list instead")
            return _get_hardcoded_tool_list()

        with open(biomni_env_desc, 'r') as f:
            content = f.read()

        # Extract tool names from library_content_dict
        # Format: "tool_name": "[Type] Description"
        import re
        matches = re.findall(r'^\s+\"([^\"]+)\":\s*\"\[', content, re.MULTILINE)

        # Filter out non-tools (data_lake entries have different format)
        software_tools = [m for m in matches if not m.endswith('.parquet') and not m.endswith('.csv')]

        return sorted(set(software_tools))

    except Exception as e:
        print(f"Error reading env_desc.py: {e}")
        return _get_hardcoded_tool_list()

def _get_hardcoded_tool_list() -> List[str]:
    """Fallback list of BioMni software tools."""
    return [
        # Python Packages
        "biopython", "biom-format", "scanpy", "scikit-bio", "anndata", "mudata",
        "pyliftover", "biopandas", "biotite", "lazyslide",
        "gget", "lifelines", "gseapy", "scrublet", "cellxgene-census",
        "hyperopt", "scvelo", "pysam", "pyfaidx", "pyranges", "pybedtools",
        "rdkit", "deeppurpose", "pyscreener", "openbabel", "descriptastorus",
        "openmm", "pytdc",
        "pandas", "numpy", "scipy", "scikit-learn", "matplotlib", "seaborn",
        "statsmodels", "pymc3", "umap-learn", "faiss-cpu", "harmony-pytorch",
        "tiledb", "tiledbsoma", "h5py", "tqdm", "joblib", "opencv-python",
        "PyPDF2", "googlesearch-python", "scikit-image", "pymed", "arxiv",
        "scholarly", "cryosparc-tools", "mageck", "igraph", "pyscenic", "cooler",
        "trackpy", "cellpose", "viennarna", "PyMassSpec", "python-libsbml",
        "cobra", "reportlab", "flowkit", "hmmlearn", "msprime", "tskit", "cyvcf2",
        "pykalman", "fanc", "loompy", "pyBigWig", "pymzml", "optlang", "FlowIO",
        "FlowUtils", "arboreto", "pdbfixer",
        # R Packages
        "ggplot2", "dplyr", "tidyr", "readr", "stringr", "Matrix",
        "DESeq2", "clusterProfiler", "edgeR", "limma", "harmony", "WGCNA",
        # CLI Tools
        "samtools", "bowtie2", "bwa", "bedtools", "macs2", "fastqc", "trimmomatic",
        "mafft", "Homer", "FastTree", "muscle", "plink", "plink2", "gcta64",
        "iqtree2", "ADFR", "diamond", "fcsparser", "plannotate", "vina", "autosite"
    ]

def load_galaxy_tools(db_path: str) -> Tuple[Set[str], Dict[str, str]]:
    """Load Galaxy tools from database."""
    with open(db_path, 'r') as f:
        data = json.load(f)

    galaxy_tools_raw = set()

    # Handle both list and dict formats
    if isinstance(data, list):
        tools_list = data
    else:
        tools_list = data.get('tools', [])

    for tool in tools_list:
        if 'name' in tool:
            galaxy_tools_raw.add(tool['name'])

    # Create normalized lookup
    galaxy_norm_to_raw = {}
    for raw_name in galaxy_tools_raw:
        norm = normalize_tool_name(raw_name)
        if norm not in galaxy_norm_to_raw:
            galaxy_norm_to_raw[norm] = raw_name

    return galaxy_tools_raw, galaxy_norm_to_raw

def load_nfcore_modules(modules_file: str) -> List[str]:
    """Load nf-core module names."""
    with open(modules_file, 'r') as f:
        data = json.load(f)

    return data.get('modules', [])

def analyze_biomni_overlap(biomni_software: List[str], galaxy_norm_lookup: Dict[str, str]) -> Dict:
    """Analyze overlap between BioMni software and Galaxy tools."""
    in_galaxy = []
    missing = []

    for software in biomni_software:
        norm_software = normalize_tool_name(software)

        # Try exact match first
        if norm_software in galaxy_norm_lookup:
            in_galaxy.append((software, galaxy_norm_lookup[norm_software]))
        else:
            # Try substring match (for tools like "scanpy" matching "scanpy cluster")
            found = False
            for galaxy_norm, galaxy_raw in galaxy_norm_lookup.items():
                if norm_software in galaxy_norm or galaxy_norm in norm_software:
                    in_galaxy.append((software, galaxy_raw))
                    found = True
                    break

            if not found:
                missing.append(software)

    return {
        'total_software': len(biomni_software),
        'in_galaxy': len(in_galaxy),
        'missing': len(missing),
        'in_galaxy_list': in_galaxy[:20],  # First 20 for display
        'missing_list': missing[:20]  # First 20 for display
    }

def analyze_nfcore_overlap(nfcore_modules: List[str], galaxy_norm_lookup: Dict[str, str]) -> Dict:
    """Analyze overlap between nf-core modules and Galaxy tools."""
    in_galaxy = []
    missing = []

    for module in nfcore_modules:
        # Extract tool name from module path (e.g., "samtools/sort" -> "samtools")
        tool_name = module.split('/')[0] if '/' in module else module
        norm_tool = normalize_tool_name(tool_name)

        # Try exact match first
        if norm_tool in galaxy_norm_lookup:
            in_galaxy.append((module, galaxy_norm_lookup[norm_tool]))
        else:
            # Try substring match (for tools like "samtools" matching "samtools sort")
            found = False
            for galaxy_norm, galaxy_raw in galaxy_norm_lookup.items():
                if norm_tool in galaxy_norm or galaxy_norm in norm_tool:
                    in_galaxy.append((module, galaxy_raw))
                    found = True
                    break

            if not found:
                missing.append(module)

    return {
        'total_modules': len(nfcore_modules),
        'in_galaxy': len(in_galaxy),
        'missing': len(missing),
        'in_galaxy_list': in_galaxy[:20],  # First 20 for display
        'missing_list': missing[:20]  # First 20 for display
    }

def main():
    # Paths
    backend_dir = Path(__file__).parent.parent
    galaxy_db = backend_dir / 'database' / 'all_unique_tools.json'
    nfcore_modules = backend_dir / 'nfcore_modules_list.json'
    output_file = backend_dir / 'tool_overlap_analysis_corrected_2025-10-12.json'

    # Check if Galaxy database exists
    if not galaxy_db.exists():
        print(f"❌ Galaxy database not found: {galaxy_db}")
        print("Please run the database update script first.")
        return

    # Load data
    print("Loading Galaxy tools database...")
    galaxy_tools_raw, galaxy_norm_lookup = load_galaxy_tools(galaxy_db)
    print(f"  Loaded {len(galaxy_tools_raw)} Galaxy tools")

    print("\nExtracting BioMni software dependencies...")
    biomni_software = extract_biomni_software_list()
    print(f"  Found {len(biomni_software)} software tools")

    print("\nAnalyzing BioMni overlap...")
    biomni_results = analyze_biomni_overlap(biomni_software, galaxy_norm_lookup)
    print(f"  In Galaxy: {biomni_results['in_galaxy']}/{biomni_results['total_software']}")
    print(f"  Missing: {biomni_results['missing']}")

    # Load and analyze nf-core if available
    nfcore_results = None
    if nfcore_modules.exists():
        print("\nLoading nf-core modules...")
        modules = load_nfcore_modules(nfcore_modules)
        print(f"  Loaded {len(modules)} modules")

        print("\nAnalyzing nf-core overlap...")
        nfcore_results = analyze_nfcore_overlap(modules, galaxy_norm_lookup)
        print(f"  In Galaxy: {nfcore_results['in_galaxy']}/{nfcore_results['total_modules']}")
        print(f"  Missing: {nfcore_results['missing']}")
    else:
        print("\n⚠️  nf-core modules list not found, skipping nf-core analysis")

    # Generate report
    report = {
        'timestamp': datetime.now().isoformat(),
        'galaxy_tools_count': len(galaxy_tools_raw),
        'biomni': biomni_results
    }

    if nfcore_results:
        report['nfcore'] = nfcore_results

    # Save results
    with open(output_file, 'w') as f:
        json.dump(report, f, indent=2)

    print(f"\n✅ Analysis complete! Results saved to: {output_file}")

    # Print summary
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    print(f"\nGalaxy Tools Database: {len(galaxy_tools_raw)} tools")
    print(f"\nBioMni Software Dependencies:")
    print(f"  Total: {biomni_results['total_software']}")
    print(f"  In Galaxy: {biomni_results['in_galaxy']} ({100*biomni_results['in_galaxy']/biomni_results['total_software']:.1f}%)")
    print(f"  Missing: {biomni_results['missing']} ({100*biomni_results['missing']/biomni_results['total_software']:.1f}%)")

    if nfcore_results:
        print(f"\nnf-core Modules:")
        print(f"  Total: {nfcore_results['total_modules']}")
        print(f"  In Galaxy: {nfcore_results['in_galaxy']} ({100*nfcore_results['in_galaxy']/nfcore_results['total_modules']:.1f}%)")
        print(f"  Missing: {nfcore_results['missing']} ({100*nfcore_results['missing']/nfcore_results['total_modules']:.1f}%)")

if __name__ == '__main__':
    main()
