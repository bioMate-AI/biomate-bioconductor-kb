#!/usr/bin/env python3
"""
BioMni overlap analysis with Galaxy ToolShed (Updated 2025-10-13)
Uses the same accurate matching methodology as nf-core overlap analysis
"""

import sqlite3
from pathlib import Path

# BioMni tools list from corrected documentation
BIOMNI_TOOLS_IN_GALAXY = [
    "blast", "matrix", "bedtools", "scanpy", "seurat", "bwa", "dada2", "deseq2",
    "community", "blast+", "rdkit", "blastn", "cooler", "bowtie2", "wgcna",
    "biopython", "clusterprofile", "blastp", "clusterprofiler", "salmon",
    "samtools", "diamond", "muscle", "mafft", "trimmomatic", "fastqc",
    "fasttree", "homer", "iqtree", "limma", "edger", "macs", "macs2",
    "viennarna", "xcms", "tophat", "star", "hisat2", "kallisto", "rsem",
    "stringtie", "cufflinks", "gatk", "picard", "bamtools", "velvet",
    "spades", "trinity", "soap", "augustus", "maker", "glimmer", "prodigal",
    "abricate"
]

BIOMNI_TOOLS_NOT_IN_GALAXY = [
    # Python Bioinformatics (35 tools)
    "cellpose", "cellxgene-census", "scvelo", "scvi", "scvi-tools", "gseapy",
    "pysam", "pyfaidx", "pyranges", "pybedtools", "pybigwig", "cyvcf2",
    "pymzml", "PyMassSpec", "cobra", "python-libsbml", "gget", "scikit-bio",
    "biopandas", "biotite", "pyliftover", "segment-anything", "umap-learn",
    "faiss-cpu", "harmony-pytorch", "pymc3", "pystan", "hmmlearn", "pykalman",
    "msprime", "tskit", "fanc", "trackpy", "decoupler", "pytdc", "cryosparc-tools",

    # R Packages (8 tools)
    "AnnotationDbi", "GO.db", "FlowCore", "Rcpp", "devtools", "remotes",
    "dplyr", "tidyr", "stringr", "readr", "lme4", "preprocessCore",

    # CLI Tools (14 tools)
    "plannotate", "plink2", "gcta", "iqtree2", "ncbi-blast-plus",
    "entrez-direct", "trnascan-se", "qblast",

    # Utility/Infrastructure (8 tools)
    "arxiv", "scholarly", "pymed", "opencv-python", "reportlab",
    "flowcytometrytools", "biotraj", "blitzgsea"
]

class BioMniOverlapAnalysis:
    def __init__(self, db_path: str = "galaxy_ai_tools.db"):
        self.db_path = Path(db_path)

    def normalize_tool_name(self, name: str) -> str:
        """Normalize tool name for comparison"""
        if not name:
            return ""

        name = name.lower()

        # Remove common prefixes
        for prefix in ['toolshed_', 'galaxy_', 'r-', 'python-', 'bioconductor-']:
            if name.startswith(prefix):
                name = name[len(prefix):]

        # Remove separators
        name = name.replace('_', '').replace('-', '').replace(' ', '').replace('.', '')

        return name.strip()

    def get_galaxy_tools(self):
        """Get all clean tools from Galaxy database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            SELECT DISTINCT name, tool_id, repo_owner, repo_name
            FROM tools
            WHERE (is_dataset = 0 OR is_dataset IS NULL)
            ORDER BY name
        """)

        tools = []
        for row in cursor.fetchall():
            name, tool_id, repo_owner, repo_name = row

            if not name:
                continue

            # Filter out non-tool entries
            skip_patterns = [
                'Repository Actions',
                'Suite',
                'package_',
                'data_manager',
                'Workflow',
                'workflow',
            ]

            if any(pattern in name for pattern in skip_patterns):
                continue

            if len(name) < 2:
                continue

            tools.append({
                'name': name,
                'tool_id': tool_id,
                'repo_owner': repo_owner,
                'repo_name': repo_name,
                'normalized': self.normalize_tool_name(name)
            })

        conn.close()
        return tools

    def find_tool_in_galaxy(self, biomni_tool: str, galaxy_tools: list) -> list:
        """Find if a biomni tool exists in Galaxy"""
        normalized = self.normalize_tool_name(biomni_tool)
        matches = []

        for gal in galaxy_tools:
            if normalized == gal['normalized']:
                matches.append(gal)
            elif normalized in gal['normalized'] or gal['normalized'] in normalized:
                # Fuzzy match for tool name variations
                if len(normalized) > 3 and len(gal['normalized']) > 3:
                    matches.append(gal)

        return matches

    def run(self):
        """Run the overlap analysis"""
        print("=" * 80)
        print("BIOMNI vs GALAXY TOOLSHED OVERLAP ANALYSIS (Updated 2025-10-13)")
        print("=" * 80)
        print()

        # Get Galaxy tools
        print("Loading Galaxy tools from database...")
        galaxy_tools = self.get_galaxy_tools()
        print(f"  Found {len(galaxy_tools)} clean Galaxy tools")
        print()

        # Verify known overlaps
        print("Verifying bioMni tools ALREADY in Galaxy...")
        verified_in_galaxy = []
        for tool in BIOMNI_TOOLS_IN_GALAXY:
            matches = self.find_tool_in_galaxy(tool, galaxy_tools)
            if matches:
                verified_in_galaxy.append({
                    'biomni_tool': tool,
                    'match_count': len(matches),
                    'matches': matches[:5]  # First 5 matches
                })

        print(f"  Verified {len(verified_in_galaxy)}/{len(BIOMNI_TOOLS_IN_GALAXY)} tools in Galaxy")
        print()

        # Check "not in Galaxy" list
        print("Checking bioMni tools claimed NOT in Galaxy...")
        found_in_galaxy = []
        still_not_in_galaxy = []

        for tool in BIOMNI_TOOLS_NOT_IN_GALAXY:
            matches = self.find_tool_in_galaxy(tool, galaxy_tools)
            if matches:
                found_in_galaxy.append({
                    'biomni_tool': tool,
                    'match_count': len(matches),
                    'matches': matches[:3]
                })
            else:
                still_not_in_galaxy.append(tool)

        print(f"  Found {len(found_in_galaxy)} tools NOW in Galaxy!")
        print(f"  Still not in Galaxy: {len(still_not_in_galaxy)}")
        print()

        # Statistics
        total_biomni = len(BIOMNI_TOOLS_IN_GALAXY) + len(BIOMNI_TOOLS_NOT_IN_GALAXY)
        in_galaxy_count = len(verified_in_galaxy) + len(found_in_galaxy)
        not_in_galaxy_count = len(still_not_in_galaxy)

        print("=" * 80)
        print("UPDATED STATISTICS")
        print("=" * 80)
        print()
        print(f"Total bioMni tools:        {total_biomni}")
        print(f"Galaxy ToolShed tools:     {len(galaxy_tools):,}")
        print()
        print(f"BioMni tools in Galaxy:    {in_galaxy_count} ({in_galaxy_count/total_biomni*100:.1f}%)")
        print(f"  - Previously known:      {len(verified_in_galaxy)}")
        print(f"  - Newly found:           {len(found_in_galaxy)}")
        print()
        print(f"BioMni tools NOT in Galaxy: {not_in_galaxy_count} ({not_in_galaxy_count/total_biomni*100:.1f}%)")
        print()

        # Show newly found tools
        if found_in_galaxy:
            print("=" * 80)
            print(f"NEWLY FOUND IN GALAXY ({len(found_in_galaxy)} tools)")
            print("=" * 80)
            for item in found_in_galaxy:
                print(f"\n{item['biomni_tool']} - {item['match_count']} Galaxy wrappers")
                for match in item['matches']:
                    print(f"  → {match['name']} ({match['repo_owner']}/{match['repo_name']})")

        # Show high-value tools still missing
        print("\n" + "=" * 80)
        print(f"HIGH-PRIORITY TOOLS STILL MISSING ({len(still_not_in_galaxy)} tools)")
        print("=" * 80)

        # Categorize missing tools
        single_cell = [t for t in still_not_in_galaxy if t in ['cellpose', 'scvelo', 'scvi', 'scvi-tools', 'cellxgene-census', 'decoupler']]
        genomics_io = [t for t in still_not_in_galaxy if t in ['pysam', 'pyfaidx', 'pyranges', 'pybigwig', 'cyvcf2', 'pybedtools']]
        metabolomics = [t for t in still_not_in_galaxy if t in ['cobra', 'python-libsbml', 'pymzml', 'PyMassSpec']]
        ml_analysis = [t for t in still_not_in_galaxy if t in ['umap-learn', 'harmony-pytorch', 'scikit-bio', 'segment-anything']]

        print(f"\nSingle-Cell & Transcriptomics ({len(single_cell)}):")
        for tool in single_cell:
            print(f"  - {tool}")

        print(f"\nGenomics I/O ({len(genomics_io)}):")
        for tool in genomics_io:
            print(f"  - {tool}")

        print(f"\nMetabolomics & Systems ({len(metabolomics)}):")
        for tool in metabolomics:
            print(f"  - {tool}")

        print(f"\nML & Analysis ({len(ml_analysis)}):")
        for tool in ml_analysis:
            print(f"  - {tool}")

        # Save detailed report
        self.save_report(verified_in_galaxy, found_in_galaxy, still_not_in_galaxy, galaxy_tools)

        print("\n" + "=" * 80)
        print("Report saved to: BIOMNI_OVERLAP_ANALYSIS_2025-10-13.md")
        print("=" * 80)

    def save_report(self, verified, found, missing, galaxy_tools):
        """Save detailed markdown report"""
        with open("BIOMNI_OVERLAP_ANALYSIS_2025-10-13.md", "w") as f:
            f.write("# BioMni vs Galaxy ToolShed Overlap Analysis (Updated 2025-10-13)\n\n")
            f.write("## Executive Summary\n\n")

            total = len(BIOMNI_TOOLS_IN_GALAXY) + len(BIOMNI_TOOLS_NOT_IN_GALAXY)
            in_galaxy = len(verified) + len(found)

            f.write(f"**Total bioMni tools:** {total}\n")
            f.write(f"**Galaxy ToolShed tools:** {len(galaxy_tools):,}\n\n")
            f.write(f"**BioMni tools in Galaxy:** {in_galaxy} ({in_galaxy/total*100:.1f}%)\n")
            f.write(f"**BioMni tools NOT in Galaxy:** {len(missing)} ({len(missing)/total*100:.1f}%)\n\n")

            if found:
                f.write(f"### 🎉 Newly Found in Galaxy (with updated index): {len(found)} tools\n\n")
                for item in found:
                    f.write(f"- **{item['biomni_tool']}** - {item['match_count']} Galaxy wrappers\n")
                f.write("\n")

            f.write(f"## Tools Still Missing from Galaxy ({len(missing)} tools)\n\n")

            single_cell = [t for t in missing if t in ['cellpose', 'scvelo', 'scvi', 'scvi-tools', 'cellxgene-census', 'decoupler']]
            genomics_io = [t for t in missing if t in ['pysam', 'pyfaidx', 'pyranges', 'pybigwig', 'cyvcf2', 'pybedtools']]
            metabolomics = [t for t in missing if t in ['cobra', 'python-libsbml', 'pymzml', 'PyMassSpec']]
            ml_analysis = [t for t in missing if t in ['umap-learn', 'harmony-pytorch', 'scikit-bio', 'segment-anything']]

            f.write(f"### Single-Cell & Transcriptomics ({len(single_cell)} tools)\n\n")
            for tool in single_cell:
                f.write(f"- `{tool}`\n")

            f.write(f"\n### Genomics I/O ({len(genomics_io)} tools)\n\n")
            for tool in genomics_io:
                f.write(f"- `{tool}`\n")

            f.write(f"\n### Metabolomics ({len(metabolomics)} tools)\n\n")
            for tool in metabolomics:
                f.write(f"- `{tool}`\n")

            f.write(f"\n### ML & Analysis ({len(ml_analysis)} tools)\n\n")
            for tool in ml_analysis:
                f.write(f"- `{tool}`\n")

            f.write(f"\n### Other ({len(missing) - len(single_cell) - len(genomics_io) - len(metabolomics) - len(ml_analysis)} tools)\n\n")
            other = [t for t in missing if t not in single_cell + genomics_io + metabolomics + ml_analysis]
            for tool in other:
                f.write(f"- `{tool}`\n")

            f.write("\n## Comparison with Previous Analysis\n\n")
            f.write("| Analysis Date | Galaxy Tools | BioMni in Galaxy | BioMni NOT in Galaxy |\n")
            f.write("|---------------|--------------|------------------|----------------------|\n")
            f.write("| 2025-10-09 | 6,295 | 54 (45.4%) | 65 (54.6%) |\n")
            f.write(f"| **2025-10-13** | **{len(galaxy_tools):,}** | **{in_galaxy} ({in_galaxy/total*100:.1f}%)** | **{len(missing)} ({len(missing)/total*100:.1f}%)** |\n\n")

            f.write("## Strategic Implications\n\n")
            f.write("1. **Complementary Coverage:** BioMni provides tools NOT in Galaxy ToolShed\n")
            f.write("2. **High-Impact Additions:** Focus on single-cell, genomics I/O, and ML tools\n")
            f.write("3. **Database APIs:** 31 unique query APIs provide additional value\n")
            f.write("4. **Data Lakes:** 79 curated datasets provide analysis-ready data\n\n")

            f.write("---\n")
            f.write("*Generated: 2025-10-13*\n")

if __name__ == "__main__":
    analyzer = BioMniOverlapAnalysis()
    analyzer.run()
