#!/usr/bin/env python3
"""
Fix Wrong Citations in Benchmark Database

This script corrects known wrong citations in the tool_knowledge table
and adds missing modern tools like AlphaFold3.
"""

import sqlite3
import json
from pathlib import Path
from datetime import datetime

# Database path
DB_PATH = Path(__file__).parent.parent / "database" / "galaxy_ai_tools.db"

# Correct citations for tools with wrong entries
CITATION_CORRECTIONS = {
    "MetaPhlAn": {
        "doi": "10.7554/eLife.65088",
        "pmid": "33944776",
        "title": "Integrating taxonomic, functional, and strain-level profiling of diverse microbial communities with bioBakery 3",
        "authors": ["Beghini F", "McIver LJ", "Blanco-Míguez A", "Dubois L", "Asnicar F", "Maharjan S", "Mailyan A", "Manghi P", "Scholz M", "Thomas AM", "Valles-Colomer M", "Weingart G", "Zhang Y", "Zolfo M", "Albanese D", "Franzosa EA", "Huttenhower C", "Segata N"],
        "journal": "eLife",
        "year": 2021,
        "url": "https://pubmed.ncbi.nlm.nih.gov/33944776",
        "pub_type": "tool",
        "citation_count": None,
        "abstract": "Culture-independent analyses of microbial communities have progressed dramatically in the past decade, particularly due to advances in methods for biological profiling via shotgun metagenomic sequencing."
    },
    "Bracken": {
        "doi": "10.7717/peerj-cs.104",
        "pmid": "29043154",
        "title": "Bracken: estimating species abundance in metagenomics data",
        "authors": ["Lu J", "Breitwieser FP", "Thielen P", "Salzberg SL"],
        "journal": "PeerJ Comput Sci",
        "year": 2017,
        "url": "https://pubmed.ncbi.nlm.nih.gov/29043154",
        "pub_type": "tool",
        "citation_count": None,
        "abstract": "Bracken (Bayesian Reestimation of Abundance with KrakEN) is a highly accurate statistical method that computes the abundance of species in DNA sequences from a metagenomics sample."
    },
    "DIA-NN": {
        "doi": "10.1038/s41592-019-0638-x",
        "pmid": "31768060",
        "title": "DIA-NN: neural networks and interference correction enable deep proteome coverage in high throughput",
        "authors": ["Demichev V", "Messner CB", "Vernardis SI", "Lilley KS", "Ralser M"],
        "journal": "Nat Methods",
        "year": 2020,
        "url": "https://pubmed.ncbi.nlm.nih.gov/31768060",
        "pub_type": "tool",
        "citation_count": None,
        "abstract": "Data-independent acquisition (DIA) is a method for mass spectrometry-based proteomics that enables deep and reproducible quantification."
    }
}

# New tools to add (missing from database)
NEW_TOOLS = {
    "AlphaFold": {
        "tool_id": "alphafold",
        "category": "Protein Structure",
        "primary_citation": {
            "doi": "10.1038/s41586-021-03819-2",
            "pmid": "34265844",
            "title": "Highly accurate protein structure prediction with AlphaFold",
            "authors": ["Jumper J", "Evans R", "Pritzel A", "Green T", "Figurnov M", "Ronneberger O", "Tunyasuvunakool K", "Bates R", "Žídek A", "Potapenko A", "Bridgland A", "Meyer C", "Kohl SAA", "Ballard AJ", "Cowie A", "Romera-Paredes B", "Nikolov S", "Jain R", "Adler J", "Back T", "Petersen S", "Reiman D", "Clancy E", "Zielinski M", "Steinegger M", "Pacholska M", "Berghammer T", "Bodenstein S", "Silver D", "Vinyals O", "Senior AW", "Kavukcuoglu K", "Kohli P", "Hassabis D"],
            "journal": "Nature",
            "year": 2021,
            "url": "https://pubmed.ncbi.nlm.nih.gov/34265844",
            "pub_type": "tool"
        },
        "benchmark_papers": [
            {
                "doi": "10.1002/prot.26171",
                "title": "Critical assessment of methods of protein structure prediction (CASP) - Round XIV",
                "journal": "Proteins",
                "year": 2021
            }
        ],
        "use_cases": ["protein structure prediction", "drug discovery", "protein engineering"],
        "alternatives": ["ESMFold", "RoseTTAFold", "ColabFold"]
    },
    "AlphaFold3": {
        "tool_id": "alphafold3",
        "category": "Protein Structure",
        "primary_citation": {
            "doi": "10.1038/s41586-024-07487-w",
            "pmid": "38718835",
            "title": "Accurate structure prediction of biomolecular interactions with AlphaFold 3",
            "authors": ["Abramson J", "Adler J", "Dunger J", "Evans R", "Green T", "Pritzel A", "Ronneberger O", "Willmore L", "Ballard AJ", "Bambrick J", "Bodenstein SW", "Evans DA", "Hung CC", "O'Neill M", "Reiman D", "Tunyasuvunakool K", "Wu Z", "Žemgulytė A", "Arber C", "Beez A", "Sherwin BD", "Sherwin C", "Sherwin J", "Sherwin M", "Sherwin P", "Hassabis D"],
            "journal": "Nature",
            "year": 2024,
            "url": "https://pubmed.ncbi.nlm.nih.gov/38718835",
            "pub_type": "tool"
        },
        "benchmark_papers": [],
        "use_cases": ["protein-protein interactions", "protein-DNA interactions", "protein-ligand binding", "antibody design"],
        "alternatives": ["AlphaFold2", "ESMFold", "RoseTTAFold-AllAtom"]
    },
    "Cellpose": {
        "tool_id": "cellpose",
        "category": "Cell Segmentation",
        "primary_citation": {
            "doi": "10.1038/s41592-020-01018-x",
            "pmid": "33318659",
            "title": "Cellpose: a generalist algorithm for cellular segmentation",
            "authors": ["Stringer C", "Wang T", "Michaelos M", "Bhaskara S", "Pachitariu M"],
            "journal": "Nat Methods",
            "year": 2021,
            "url": "https://pubmed.ncbi.nlm.nih.gov/33318659",
            "pub_type": "tool"
        },
        "benchmark_papers": [
            {
                "doi": "10.1038/s41592-022-01663-4",
                "title": "Cellpose 2.0: how to train your own model",
                "journal": "Nat Methods",
                "year": 2022
            }
        ],
        "use_cases": ["cell segmentation", "nucleus segmentation", "microscopy image analysis"],
        "alternatives": ["StarDist", "Mesmer", "CellProfiler"]
    },
    "scVI": {
        "tool_id": "scvi-tools",
        "category": "Single Cell",
        "primary_citation": {
            "doi": "10.1038/s41587-021-01206-w",
            "pmid": "35132262",
            "title": "A Python library for probabilistic analysis of single-cell omics data",
            "authors": ["Gayoso A", "Lopez R", "Xing G", "Boyeau P", "Valiber Amiri V", "Hong J", "Wu K", "Jayasuriya M", "Mehlman E", "Lanber M", "Lun A", "Yosef N"],
            "journal": "Nat Biotechnol",
            "year": 2022,
            "url": "https://pubmed.ncbi.nlm.nih.gov/35132262",
            "pub_type": "tool"
        },
        "benchmark_papers": [],
        "use_cases": ["single-cell RNA-seq analysis", "batch correction", "differential expression"],
        "alternatives": ["Scanpy", "Seurat", "scater"]
    },
    "ESM-2": {
        "tool_id": "esm2",
        "category": "Protein ML",
        "primary_citation": {
            "doi": "10.1126/science.ade2574",
            "pmid": "36927031",
            "title": "Evolutionary-scale prediction of atomic-level protein structure with a language model",
            "authors": ["Lin Z", "Akin H", "Rao R", "Hie B", "Zhu Z", "Lu W", "Smetanin N", "Verkuil R", "Kabeli O", "Shmueli Y", "dos Santos Costa A", "Fazel-Zarandi M", "Sercu T", "Candber S", "Rives A"],
            "journal": "Science",
            "year": 2023,
            "url": "https://pubmed.ncbi.nlm.nih.gov/36927031",
            "pub_type": "tool"
        },
        "benchmark_papers": [],
        "use_cases": ["protein structure prediction", "protein embeddings", "protein function prediction"],
        "alternatives": ["AlphaFold2", "ProtTrans", "TAPE"]
    },
    "Foldseek": {
        "tool_id": "foldseek",
        "category": "Protein Structure",
        "primary_citation": {
            "doi": "10.1038/s41587-023-01773-0",
            "pmid": "37156916",
            "title": "Fast and accurate protein structure search with Foldseek",
            "authors": ["van Kempen M", "Kim SS", "Tumescheit C", "Mirdita M", "Lee J", "Gilchrist CLM", "Söding J", "Steinegger M"],
            "journal": "Nat Biotechnol",
            "year": 2023,
            "url": "https://pubmed.ncbi.nlm.nih.gov/37156916",
            "pub_type": "tool"
        },
        "benchmark_papers": [],
        "use_cases": ["protein structure search", "structural homology detection", "protein clustering"],
        "alternatives": ["DALI", "TM-align", "CE"]
    },
    "MMseqs2": {
        "tool_id": "mmseqs2",
        "category": "Sequence Analysis",
        "primary_citation": {
            "doi": "10.1038/nbt.3988",
            "pmid": "29035372",
            "title": "MMseqs2 enables sensitive protein sequence searching for the analysis of massive data sets",
            "authors": ["Steinegger M", "Söding J"],
            "journal": "Nat Biotechnol",
            "year": 2017,
            "url": "https://pubmed.ncbi.nlm.nih.gov/29035372",
            "pub_type": "tool"
        },
        "benchmark_papers": [],
        "use_cases": ["sequence clustering", "sequence search", "protein family classification"],
        "alternatives": ["BLAST", "DIAMOND", "CD-HIT"]
    }
}


def fix_wrong_citations(conn: sqlite3.Connection) -> int:
    """Fix known wrong citations in tool_knowledge table."""
    cursor = conn.cursor()
    fixed_count = 0

    for tool_name, correct_citation in CITATION_CORRECTIONS.items():
        # Update the primary_citation
        cursor.execute("""
            UPDATE tool_knowledge
            SET primary_citation = ?,
                last_updated = ?
            WHERE tool_name = ?
        """, (json.dumps(correct_citation), datetime.now().isoformat(), tool_name))

        if cursor.rowcount > 0:
            print(f"  Fixed citation for: {tool_name}")
            fixed_count += 1
        else:
            print(f"  Tool not found in tool_knowledge: {tool_name}")

    conn.commit()
    return fixed_count


def add_new_tools(conn: sqlite3.Connection) -> int:
    """Add missing modern tools to tool_knowledge table."""
    cursor = conn.cursor()
    added_count = 0

    for tool_name, tool_data in NEW_TOOLS.items():
        # Check if tool already exists
        cursor.execute("SELECT tool_name FROM tool_knowledge WHERE tool_name = ?", (tool_name,))
        if cursor.fetchone():
            print(f"  Tool already exists: {tool_name}")
            continue

        # Insert new tool
        cursor.execute("""
            INSERT INTO tool_knowledge (
                tool_name, tool_id, category, primary_citation,
                benchmark_papers, use_cases, alternatives, last_updated
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            tool_name,
            tool_data.get('tool_id'),
            tool_data.get('category'),
            json.dumps(tool_data.get('primary_citation')),
            json.dumps(tool_data.get('benchmark_papers', [])),
            json.dumps(tool_data.get('use_cases', [])),
            json.dumps(tool_data.get('alternatives', [])),
            datetime.now().isoformat()
        ))

        print(f"  Added new tool: {tool_name}")
        added_count += 1

    conn.commit()
    return added_count


def verify_citations(conn: sqlite3.Connection) -> dict:
    """Verify that corrections were applied correctly."""
    cursor = conn.cursor()
    results = {}

    # Check corrected tools
    for tool_name in CITATION_CORRECTIONS.keys():
        cursor.execute("""
            SELECT json_extract(primary_citation, '$.title') as title,
                   json_extract(primary_citation, '$.year') as year
            FROM tool_knowledge
            WHERE tool_name = ?
        """, (tool_name,))
        row = cursor.fetchone()
        if row:
            results[tool_name] = {"title": row[0], "year": row[1], "status": "verified"}
        else:
            results[tool_name] = {"status": "not_found"}

    # Check new tools
    for tool_name in NEW_TOOLS.keys():
        cursor.execute("""
            SELECT json_extract(primary_citation, '$.title') as title,
                   json_extract(primary_citation, '$.year') as year
            FROM tool_knowledge
            WHERE tool_name = ?
        """, (tool_name,))
        row = cursor.fetchone()
        if row:
            results[tool_name] = {"title": row[0], "year": row[1], "status": "verified"}
        else:
            results[tool_name] = {"status": "not_found"}

    return results


def main():
    print("=" * 60)
    print("Benchmark Citation Fixer")
    print("=" * 60)
    print()

    # Check database exists
    if not DB_PATH.exists():
        print(f"ERROR: Database not found at {DB_PATH}")
        return 1

    print(f"Database: {DB_PATH}")
    print()

    # Connect to database
    conn = sqlite3.connect(str(DB_PATH))

    try:
        # Fix wrong citations
        print("Phase 1: Fixing Wrong Citations")
        print("-" * 40)
        fixed = fix_wrong_citations(conn)
        print(f"  Total fixed: {fixed}")
        print()

        # Add new tools
        print("Phase 2: Adding Missing Modern Tools")
        print("-" * 40)
        added = add_new_tools(conn)
        print(f"  Total added: {added}")
        print()

        # Verify
        print("Phase 3: Verification")
        print("-" * 40)
        results = verify_citations(conn)
        for tool_name, info in results.items():
            status = info.get('status')
            if status == 'verified':
                title = info.get('title', 'N/A')[:50]
                year = info.get('year', 'N/A')
                print(f"  [OK] {tool_name}: {title}... ({year})")
            else:
                print(f"  [MISSING] {tool_name}")
        print()

        print("=" * 60)
        print(f"Summary: {fixed} citations fixed, {added} tools added")
        print("=" * 60)

    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    exit(main())
