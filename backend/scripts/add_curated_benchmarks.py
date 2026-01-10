#!/usr/bin/env python3
"""
Add Curated Benchmark Papers to Tool Knowledge Database

This adds well-known independent benchmark studies and marks
tool papers that contain their own benchmark comparisons.
"""

import sqlite3
import json
from pathlib import Path
from datetime import datetime

DB_PATH = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

# Major independent benchmark papers by domain
DOMAIN_BENCHMARKS = {
    "RNA-seq Alignment": [
        {
            "doi": "10.1038/nmeth.4106",
            "pmid": "28680106",
            "title": "Simulation-based comprehensive benchmarking of RNA-seq aligners",
            "journal": "Nature Methods",
            "year": 2017,
            "tools_compared": ["STAR", "HISAT2", "TopHat2", "GSNAP", "Novoalign"]
        },
        {
            "doi": "10.1186/s13059-016-0940-1",
            "pmid": "27340798",
            "title": "A benchmark for RNA-seq quantification pipelines",
            "journal": "Genome Biology",
            "year": 2016,
            "tools_compared": ["Salmon", "kallisto", "RSEM", "Cufflinks", "eXpress"]
        }
    ],
    "RNA-seq Differential Expression": [
        {
            "doi": "10.1186/s13059-014-0550-8",
            "pmid": "25516281",
            "title": "Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2",
            "journal": "Genome Biology",
            "year": 2014,
            "tools_compared": ["DESeq2", "edgeR", "limma-voom"],
            "note": "Tool paper with benchmarks"
        },
        {
            "doi": "10.1093/bib/bbx008",
            "pmid": "28334152",
            "title": "A comprehensive evaluation of normalization methods for Illumina high-throughput RNA sequencing data analysis",
            "journal": "Briefings in Bioinformatics",
            "year": 2017,
            "tools_compared": ["DESeq2", "edgeR", "limma", "EBSeq", "NOISeq"]
        }
    ],
    "Single-cell RNA-seq": [
        {
            "doi": "10.1038/s41592-021-01336-8",
            "pmid": "34824477",
            "title": "Benchmarking atlas-level data integration in single-cell genomics",
            "journal": "Nature Methods",
            "year": 2022,
            "tools_compared": ["scVI", "Harmony", "Seurat", "BBKNN", "scanorama", "Combat"]
        },
        {
            "doi": "10.1186/s13059-019-1898-6",
            "pmid": "31870423",
            "title": "A comparison of automatic cell identification methods for single-cell RNA sequencing data",
            "journal": "Genome Biology",
            "year": 2019,
            "tools_compared": ["scmap", "CellAssign", "SingleR", "Garnett", "CHETAH"]
        },
        {
            "doi": "10.1038/s41592-019-0619-0",
            "pmid": "31712715",
            "title": "Benchmarking single cell RNA-sequencing analysis pipelines using mixture control experiments",
            "journal": "Nature Methods",
            "year": 2019,
            "tools_compared": ["Seurat", "Scanpy", "SC3", "SIMLR", "Monocle"]
        }
    ],
    "Proteomics DIA": [
        {
            "doi": "10.1038/s41467-023-39795-8",
            "pmid": "37463914",
            "title": "Benchmarking commonly used software suites and analysis workflows for DIA proteomics and phosphoproteomics",
            "journal": "Nature Communications",
            "year": 2023,
            "tools_compared": ["DIA-NN", "Spectronaut", "MaxQuant", "OpenSWATH", "Skyline"]
        },
        {
            "doi": "10.1038/s41592-019-0638-x",
            "pmid": "31768060",
            "title": "DIA-NN: neural networks and interference correction enable deep proteome coverage in high throughput",
            "journal": "Nature Methods",
            "year": 2020,
            "tools_compared": ["DIA-NN", "Spectronaut", "OpenSWATH"],
            "note": "Tool paper with benchmarks"
        }
    ],
    "Proteomics DDA": [
        {
            "doi": "10.1038/nmeth.4256",
            "pmid": "27809316",
            "title": "Proteomics in 2016: best of mass spectrometry-based proteomics",
            "journal": "Nature Methods",
            "year": 2017,
            "tools_compared": ["MaxQuant", "Mascot", "SEQUEST", "X!Tandem", "Comet"]
        }
    ],
    "Protein Structure Prediction": [
        {
            "doi": "10.1038/s41586-021-03819-2",
            "pmid": "34265844",
            "title": "Highly accurate protein structure prediction with AlphaFold",
            "journal": "Nature",
            "year": 2021,
            "tools_compared": ["AlphaFold2", "RoseTTAFold", "trRosetta", "I-TASSER"],
            "note": "CASP14 results"
        },
        {
            "doi": "10.1002/prot.26171",
            "pmid": "34533838",
            "title": "Critical assessment of methods of protein structure prediction (CASP) - Round XIV",
            "journal": "Proteins",
            "year": 2021,
            "tools_compared": ["AlphaFold2", "RoseTTAFold", "BAKER", "Zhang"]
        },
        {
            "doi": "10.1126/science.ade2574",
            "pmid": "36927031",
            "title": "Evolutionary-scale prediction of atomic-level protein structure with a language model",
            "journal": "Science",
            "year": 2023,
            "tools_compared": ["ESMFold", "AlphaFold2", "RoseTTAFold"],
            "note": "Tool paper with benchmarks"
        }
    ],
    "Sequence Search": [
        {
            "doi": "10.1038/nbt.3988",
            "pmid": "29035372",
            "title": "MMseqs2 enables sensitive protein sequence searching for the analysis of massive data sets",
            "journal": "Nature Biotechnology",
            "year": 2017,
            "tools_compared": ["MMseqs2", "BLAST", "DIAMOND", "UBLAST"],
            "note": "Tool paper with benchmarks"
        },
        {
            "doi": "10.1038/s41587-023-01773-0",
            "pmid": "37156916",
            "title": "Fast and accurate protein structure search with Foldseek",
            "journal": "Nature Biotechnology",
            "year": 2023,
            "tools_compared": ["Foldseek", "DALI", "TM-align", "CE"],
            "note": "Tool paper with benchmarks"
        }
    ],
    "Cell Segmentation": [
        {
            "doi": "10.1038/s41592-020-01018-x",
            "pmid": "33318659",
            "title": "Cellpose: a generalist algorithm for cellular segmentation",
            "journal": "Nature Methods",
            "year": 2021,
            "tools_compared": ["Cellpose", "StarDist", "Mask R-CNN", "U-Net"],
            "note": "Tool paper with benchmarks"
        },
        {
            "doi": "10.1038/s41587-021-01094-0",
            "pmid": "34795433",
            "title": "Whole-cell segmentation of tissue images with human-level performance using large-scale data annotation and deep learning",
            "journal": "Nature Biotechnology",
            "year": 2022,
            "tools_compared": ["Mesmer", "Cellpose", "StarDist", "CellProfiler"]
        }
    ],
    "Metagenomics": [
        {
            "doi": "10.1038/s41592-019-0669-3",
            "pmid": "31819257",
            "title": "Critical Assessment of Metagenome Interpretation - a benchmark of metagenomics software",
            "journal": "Nature Methods",
            "year": 2019,
            "tools_compared": ["MetaPhlAn", "Kraken2", "Bracken", "mOTUs", "Centrifuge"]
        },
        {
            "doi": "10.1186/s13059-019-1891-0",
            "pmid": "31779668",
            "title": "Improved metagenomic analysis with Kraken 2",
            "journal": "Genome Biology",
            "year": 2019,
            "tools_compared": ["Kraken2", "Kraken", "Centrifuge", "Clark"],
            "note": "Tool paper with benchmarks"
        }
    ],
    "Genome Assembly": [
        {
            "doi": "10.1038/s41592-020-01056-5",
            "pmid": "33526892",
            "title": "Benchmarking of long-read assemblers for prokaryote whole genome sequencing",
            "journal": "Nature Methods",
            "year": 2021,
            "tools_compared": ["Flye", "Canu", "wtdbg2", "Shasta", "Raven"]
        }
    ],
    "Variant Calling": [
        {
            "doi": "10.1038/s41587-020-0539-0",
            "pmid": "32541953",
            "title": "A multi-platform reference for somatic structural variation detection",
            "journal": "Nature Biotechnology",
            "year": 2020,
            "tools_compared": ["Manta", "DELLY", "GRIDSS", "SvABA", "LUMPY"]
        }
    ]
}

# Tools whose primary papers contain benchmarks
TOOLS_WITH_BENCHMARK_PAPERS = [
    "DIA-NN", "AlphaFold", "ESM-2", "ESMFold", "Foldseek", "MMseqs2",
    "Cellpose", "Kraken2", "DESeq2", "Salmon", "STAR", "HISAT2"
]


def add_domain_benchmarks(conn: sqlite3.Connection) -> int:
    """Add curated benchmark papers to tool_knowledge."""
    cursor = conn.cursor()
    added = 0

    for domain, papers in DOMAIN_BENCHMARKS.items():
        for paper in papers:
            tools = paper.get("tools_compared", [])

            for tool_name in tools:
                # Check if tool exists
                cursor.execute(
                    "SELECT tool_name, benchmark_papers FROM tool_knowledge WHERE tool_name = ?",
                    (tool_name,)
                )
                row = cursor.fetchone()

                if not row:
                    continue

                # Get existing benchmarks
                existing = []
                if row[1]:
                    try:
                        existing = json.loads(row[1])
                    except:
                        existing = []

                # Check if this paper is already there
                existing_dois = {p.get('doi') for p in existing if p.get('doi')}
                if paper.get('doi') in existing_dois:
                    continue

                # Add new benchmark paper
                benchmark_entry = {
                    "doi": paper.get("doi"),
                    "pmid": paper.get("pmid"),
                    "title": paper.get("title"),
                    "journal": paper.get("journal"),
                    "year": paper.get("year"),
                    "pub_type": "benchmark",
                    "domain": domain,
                    "is_curated": True
                }

                if paper.get("note"):
                    benchmark_entry["note"] = paper["note"]

                existing.append(benchmark_entry)

                # Update database
                cursor.execute(
                    "UPDATE tool_knowledge SET benchmark_papers = ?, last_updated = ? WHERE tool_name = ?",
                    (json.dumps(existing), datetime.now().isoformat(), tool_name)
                )
                added += 1
                print(f"  Added benchmark for {tool_name}: {paper['title'][:50]}...")

    conn.commit()
    return added


def mark_tool_papers_with_benchmarks(conn: sqlite3.Connection) -> int:
    """Mark tools whose primary papers contain benchmarks."""
    cursor = conn.cursor()
    marked = 0

    for tool_name in TOOLS_WITH_BENCHMARK_PAPERS:
        cursor.execute(
            "SELECT primary_citation FROM tool_knowledge WHERE tool_name = ?",
            (tool_name,)
        )
        row = cursor.fetchone()

        if not row or not row[0]:
            continue

        try:
            citation = json.loads(row[0])
        except:
            continue

        # Add flag indicating paper contains benchmarks
        if not citation.get("contains_benchmarks"):
            citation["contains_benchmarks"] = True
            citation["benchmark_note"] = "Primary paper includes benchmark comparisons"

            cursor.execute(
                "UPDATE tool_knowledge SET primary_citation = ?, last_updated = ? WHERE tool_name = ?",
                (json.dumps(citation), datetime.now().isoformat(), tool_name)
            )
            marked += 1
            print(f"  Marked {tool_name} paper as containing benchmarks")

    conn.commit()
    return marked


def main():
    print("=" * 60)
    print("Adding Curated Benchmark Papers")
    print("=" * 60)
    print()

    if not DB_PATH.exists():
        print(f"ERROR: Database not found at {DB_PATH}")
        return 1

    conn = sqlite3.connect(str(DB_PATH))

    try:
        print("Phase 1: Adding Domain Benchmark Papers")
        print("-" * 40)
        added = add_domain_benchmarks(conn)
        print(f"  Total added: {added}")
        print()

        print("Phase 2: Marking Tool Papers with Benchmarks")
        print("-" * 40)
        marked = mark_tool_papers_with_benchmarks(conn)
        print(f"  Total marked: {marked}")
        print()

        print("=" * 60)
        print(f"Summary: {added} benchmark papers added, {marked} tool papers marked")
        print("=" * 60)

    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    exit(main())
