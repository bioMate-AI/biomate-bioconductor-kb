#!/usr/bin/env python3
"""
Unified Workflow Indexer

Indexes all workflow sources into a single searchable database:
1. Galaxy .ga workflows from /backend/galaxy_workflows/
2. Biomni Galaxy subworkflows from /backend/biomni_workflows/galaxy/subworkflows/
3. Biomni Nextflow subworkflows from /backend/biomni_workflows/nextflow/subworkflows/
4. Existing JSON workflows (951 files)

Author: BioMate Team
Date: 2024-12-31
"""

import json
import sqlite3
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any
import re

# Paths
BACKEND_PATH = Path(__file__).parent.parent
DB_PATH = BACKEND_PATH / "database" / "galaxy_ai_tools.db"
GALAXY_WORKFLOWS_PATH = BACKEND_PATH / "galaxy_workflows"
BIOMNI_GALAXY_SUBWORKFLOWS = BACKEND_PATH / "biomni_workflows" / "galaxy" / "subworkflows"
BIOMNI_NEXTFLOW_SUBWORKFLOWS = BACKEND_PATH / "biomni_workflows" / "nextflow" / "subworkflows"
JSON_WORKFLOWS_PATH = BACKEND_PATH / "lib" / "galaxy" / "ai" / "data" / "workflows"
NFCORE_WORKFLOWS_PATH = BACKEND_PATH / "nf-core-workflows"

# nf-core pipeline metadata
NFCORE_PIPELINES = {
    "rnaseq": {
        "name": "nf-core/rnaseq",
        "description": "RNA sequencing analysis pipeline using STAR, RSEM, HISAT2 or Salmon with extensive QC",
        "domain": "transcriptomics",
        "tools": ["star", "salmon", "hisat2", "rsem", "kallisto", "deseq2", "fastqc", "multiqc"],
        "docker": "nfcore/rnaseq:3.14.0"
    },
    "chipseq": {
        "name": "nf-core/chipseq",
        "description": "ChIP-seq peak-calling and differential analysis pipeline",
        "domain": "epigenomics",
        "tools": ["bwa", "bowtie2", "macs2", "homer", "deeptools", "multiqc"],
        "docker": "nfcore/chipseq:2.0.0"
    },
    "sarek": {
        "name": "nf-core/sarek",
        "description": "Analysis pipeline to detect germline or somatic variants from WGS/WES",
        "domain": "variant_calling",
        "tools": ["bwa", "gatk", "strelka", "manta", "freebayes", "mutect2"],
        "docker": "nfcore/sarek:3.4.0"
    },
    "methylseq": {
        "name": "nf-core/methylseq",
        "description": "Methylation (Bisulfite-Sequencing) analysis pipeline",
        "domain": "epigenomics",
        "tools": ["bismark", "bwa-meth", "methyldackel", "multiqc"],
        "docker": "nfcore/methylseq:2.6.0"
    },
    "diaproteomics": {
        "name": "nf-core/diaproteomics",
        "description": "Automated quantitative analysis of DIA proteomics mass spectrometry data",
        "domain": "proteomics",
        "tools": ["dia-nn", "openswath", "pyprophet"],
        "docker": "nfcore/diaproteomics:1.2.4"
    },
    "proteomicslfq": {
        "name": "nf-core/proteomicslfq",
        "description": "Proteomics label-free quantification (LFQ) analysis pipeline",
        "domain": "proteomics",
        "tools": ["maxquant", "openms", "comet"],
        "docker": "nfcore/proteomicslfq:1.0.0"
    },
    "differentialabundance": {
        "name": "nf-core/differentialabundance",
        "description": "Differential abundance analysis for count matrices from RNA-seq, ATAC-seq, etc.",
        "domain": "transcriptomics",
        "tools": ["deseq2", "limma", "edger"],
        "docker": "nfcore/differentialabundance:1.5.0"
    }
}


def create_unified_schema(conn: sqlite3.Connection):
    """Extend workflows table with unified fields."""
    cursor = conn.cursor()

    # Check if columns exist, add if not
    cursor.execute("PRAGMA table_info(workflows)")
    columns = {col[1] for col in cursor.fetchall()}

    new_columns = {
        "source": "TEXT DEFAULT 'unknown'",  # galaxy_community, biomni, nfcore, user
        "format": "TEXT DEFAULT 'galaxy_ga'",  # galaxy_ga, nextflow, json
        "executable": "INTEGER DEFAULT 1",  # 1=yes, 0=no
        "docker_image": "TEXT",  # Docker image for execution
        "category": "TEXT",  # biochemistry, genomics, etc.
        "workflow_hash": "TEXT",  # For deduplication (can't add UNIQUE via ALTER)
        "indexed_at": "TEXT",
    }

    for col_name, col_def in new_columns.items():
        if col_name not in columns:
            try:
                cursor.execute(f"ALTER TABLE workflows ADD COLUMN {col_name} {col_def}")
                print(f"  Added column: {col_name}")
            except sqlite3.OperationalError as e:
                if "duplicate column" not in str(e).lower():
                    raise

    conn.commit()


def compute_workflow_hash(content: str) -> str:
    """Compute hash for deduplication."""
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def extract_tools_from_ga(workflow_json: Dict) -> List[str]:
    """Extract tool IDs from Galaxy workflow JSON."""
    tools = []
    steps = workflow_json.get("steps", {})

    for step_id, step in steps.items():
        if isinstance(step, dict):
            tool_id = step.get("tool_id")
            if tool_id:
                # Clean tool ID
                clean_id = tool_id.split("/")[-1].lower()
                tools.append(clean_id)

    return list(set(tools))


def infer_domain(name: str, description: str, tools: List[str]) -> str:
    """Infer domain from workflow metadata."""
    text = f"{name} {description} {' '.join(tools)}".lower()

    domain_keywords = {
        "variant_calling": ["variant", "snp", "indel", "gatk", "freebayes", "vcf"],
        "transcriptomics": ["rna", "rnaseq", "expression", "deseq", "salmon", "kallisto"],
        "genomics": ["genome", "assembly", "alignment", "bwa", "bowtie", "mapping"],
        "proteomics": ["protein", "proteom", "mass spec", "peptide", "dia", "dda"],
        "metagenomics": ["metagen", "microbiome", "16s", "kraken", "metaphlan"],
        "epigenomics": ["chip", "atac", "methylation", "histone", "peak"],
        "imaging": ["image", "segment", "cell", "microscop"],
    }

    for domain, keywords in domain_keywords.items():
        if any(kw in text for kw in keywords):
            return domain

    return "general"


def index_galaxy_workflows(conn: sqlite3.Connection) -> int:
    """Index .ga workflows from galaxy_workflows directory."""
    cursor = conn.cursor()
    indexed = 0

    if not GALAXY_WORKFLOWS_PATH.exists():
        print(f"  Path not found: {GALAXY_WORKFLOWS_PATH}")
        return 0

    for ga_file in GALAXY_WORKFLOWS_PATH.glob("*.ga"):
        try:
            with open(ga_file, 'r') as f:
                content = f.read()
                workflow_json = json.loads(content)

            workflow_hash = compute_workflow_hash(content)

            # Check if already indexed
            cursor.execute("SELECT id FROM workflows WHERE workflow_hash = ?", (workflow_hash,))
            if cursor.fetchone():
                continue

            name = workflow_json.get("name", ga_file.stem)
            annotation = workflow_json.get("annotation", "")
            tags = json.dumps(workflow_json.get("tags", []))
            tools = extract_tools_from_ga(workflow_json)
            domain = infer_domain(name, annotation, tools)
            step_count = len(workflow_json.get("steps", {}))

            cursor.execute("""
                INSERT INTO workflows (
                    name, filename, description, annotation, tags, domain,
                    workflow_json, step_count, tools_used, source, format,
                    executable, workflow_hash, indexed_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                name,
                ga_file.name,
                annotation[:500] if annotation else "",
                annotation,
                tags,
                domain,
                content,
                step_count,
                json.dumps(tools),
                "galaxy_local",
                "galaxy_ga",
                1,
                workflow_hash,
                datetime.now().isoformat()
            ))
            indexed += 1

        except Exception as e:
            print(f"  Error indexing {ga_file.name}: {e}")

    conn.commit()
    return indexed


def index_biomni_galaxy_subworkflows(conn: sqlite3.Connection) -> int:
    """Index Biomni Galaxy subworkflows."""
    cursor = conn.cursor()
    indexed = 0

    if not BIOMNI_GALAXY_SUBWORKFLOWS.exists():
        print(f"  Path not found: {BIOMNI_GALAXY_SUBWORKFLOWS}")
        return 0

    for domain_dir in BIOMNI_GALAXY_SUBWORKFLOWS.iterdir():
        if not domain_dir.is_dir():
            continue

        domain = domain_dir.name

        for ga_file in domain_dir.glob("*.ga"):
            try:
                with open(ga_file, 'r') as f:
                    content = f.read()
                    workflow_json = json.loads(content)

                workflow_hash = compute_workflow_hash(content)

                # Check if already indexed
                cursor.execute("SELECT id FROM workflows WHERE workflow_hash = ?", (workflow_hash,))
                if cursor.fetchone():
                    continue

                name = workflow_json.get("name", ga_file.stem)
                annotation = workflow_json.get("annotation", "")
                tags = json.dumps(workflow_json.get("tags", []) + [domain, "biomni"])
                tools = extract_tools_from_ga(workflow_json)
                step_count = len(workflow_json.get("steps", {}))

                cursor.execute("""
                    INSERT INTO workflows (
                        name, filename, description, annotation, tags, domain,
                        workflow_json, step_count, tools_used, source, format,
                        executable, category, workflow_hash, indexed_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    name,
                    f"biomni/{domain}/{ga_file.name}",
                    annotation[:500] if annotation else f"Biomni {domain} subworkflow",
                    annotation,
                    tags,
                    domain,
                    content,
                    step_count,
                    json.dumps(tools),
                    "biomni",
                    "galaxy_ga",
                    1,
                    domain,
                    workflow_hash,
                    datetime.now().isoformat()
                ))
                indexed += 1

            except Exception as e:
                print(f"  Error indexing {ga_file}: {e}")

    conn.commit()
    return indexed


def index_biomni_nextflow_subworkflows(conn: sqlite3.Connection) -> int:
    """Index Biomni Nextflow subworkflows."""
    cursor = conn.cursor()
    indexed = 0

    if not BIOMNI_NEXTFLOW_SUBWORKFLOWS.exists():
        print(f"  Path not found: {BIOMNI_NEXTFLOW_SUBWORKFLOWS}")
        return 0

    for domain_dir in BIOMNI_NEXTFLOW_SUBWORKFLOWS.iterdir():
        if not domain_dir.is_dir():
            continue

        domain = domain_dir.name

        for nf_file in domain_dir.glob("*.nf"):
            try:
                with open(nf_file, 'r') as f:
                    content = f.read()

                workflow_hash = compute_workflow_hash(content)

                # Check if already indexed
                cursor.execute("SELECT id FROM workflows WHERE workflow_hash = ?", (workflow_hash,))
                if cursor.fetchone():
                    continue

                name = nf_file.stem.replace("_", " ").title()

                # Extract processes from Nextflow
                processes = re.findall(r'process\s+(\w+)', content)

                cursor.execute("""
                    INSERT INTO workflows (
                        name, filename, description, annotation, tags, domain,
                        workflow_json, step_count, tools_used, source, format,
                        executable, category, workflow_hash, indexed_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    name,
                    f"biomni_nf/{domain}/{nf_file.name}",
                    f"Biomni Nextflow {domain} subworkflow",
                    "",
                    json.dumps([domain, "biomni", "nextflow"]),
                    domain,
                    content,  # Store Nextflow code as workflow_json
                    len(processes),
                    json.dumps(processes),
                    "biomni_nextflow",
                    "nextflow",
                    1,
                    domain,
                    workflow_hash,
                    datetime.now().isoformat()
                ))
                indexed += 1

            except Exception as e:
                print(f"  Error indexing {nf_file}: {e}")

    conn.commit()
    return indexed


def index_nfcore_workflows(conn: sqlite3.Connection) -> int:
    """Index nf-core pipelines."""
    cursor = conn.cursor()
    indexed = 0

    for pipeline_name, metadata in NFCORE_PIPELINES.items():
        pipeline_dir = NFCORE_WORKFLOWS_PATH / pipeline_name

        if not pipeline_dir.exists():
            print(f"  Pipeline not found: {pipeline_name}")
            continue

        main_nf = pipeline_dir / "main.nf"
        if not main_nf.exists():
            continue

        try:
            with open(main_nf, 'r') as f:
                content = f.read()

            workflow_hash = compute_workflow_hash(content)

            # Check if already indexed
            cursor.execute("SELECT id FROM workflows WHERE workflow_hash = ?", (workflow_hash,))
            if cursor.fetchone():
                continue

            cursor.execute("""
                INSERT INTO workflows (
                    name, filename, description, annotation, tags, domain,
                    workflow_json, step_count, tools_used, source, format,
                    executable, docker_image, category, workflow_hash, indexed_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                metadata["name"],
                f"nfcore/{pipeline_name}/main.nf",
                metadata["description"],
                metadata["description"],
                json.dumps(["nf-core", pipeline_name, metadata["domain"]]),
                metadata["domain"],
                content,
                len(metadata["tools"]),
                json.dumps(metadata["tools"]),
                "nfcore",
                "nextflow",
                1,
                metadata["docker"],
                metadata["domain"],
                workflow_hash,
                datetime.now().isoformat()
            ))
            indexed += 1
            print(f"  Indexed: {metadata['name']}")

        except Exception as e:
            print(f"  Error indexing {pipeline_name}: {e}")

    conn.commit()
    return indexed


def get_stats(conn: sqlite3.Connection) -> Dict[str, Any]:
    """Get workflow index statistics."""
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM workflows")
    total = cursor.fetchone()[0]

    cursor.execute("SELECT source, COUNT(*) FROM workflows GROUP BY source")
    by_source = dict(cursor.fetchall())

    cursor.execute("SELECT format, COUNT(*) FROM workflows GROUP BY format")
    by_format = dict(cursor.fetchall())

    cursor.execute("SELECT domain, COUNT(*) FROM workflows GROUP BY domain ORDER BY COUNT(*) DESC LIMIT 10")
    by_domain = dict(cursor.fetchall())

    return {
        "total": total,
        "by_source": by_source,
        "by_format": by_format,
        "by_domain": by_domain
    }


def main():
    print("=" * 60)
    print("Unified Workflow Indexer")
    print("=" * 60)
    print()

    if not DB_PATH.exists():
        print(f"ERROR: Database not found at {DB_PATH}")
        return 1

    conn = sqlite3.connect(str(DB_PATH))

    try:
        # Extend schema FIRST
        print("Phase 1: Extending schema...")
        create_unified_schema(conn)
        print()

        # Get initial stats (after schema extension)
        print("Initial state:")
        initial_stats = get_stats(conn)
        print(f"  Total workflows: {initial_stats['total']}")
        print()

        # Index Galaxy workflows
        print("Phase 2: Indexing Galaxy .ga workflows...")
        galaxy_count = index_galaxy_workflows(conn)
        print(f"  Indexed: {galaxy_count}")
        print()

        # Index Biomni Galaxy subworkflows
        print("Phase 3: Indexing Biomni Galaxy subworkflows...")
        biomni_galaxy_count = index_biomni_galaxy_subworkflows(conn)
        print(f"  Indexed: {biomni_galaxy_count}")
        print()

        # Index Biomni Nextflow subworkflows
        print("Phase 4: Indexing Biomni Nextflow subworkflows...")
        biomni_nf_count = index_biomni_nextflow_subworkflows(conn)
        print(f"  Indexed: {biomni_nf_count}")
        print()

        # Index nf-core pipelines
        print("Phase 5: Indexing nf-core pipelines...")
        nfcore_count = index_nfcore_workflows(conn)
        print(f"  Indexed: {nfcore_count}")
        print()

        # Final stats
        print("Final state:")
        final_stats = get_stats(conn)
        print(f"  Total workflows: {final_stats['total']}")
        print(f"  By source: {final_stats['by_source']}")
        print(f"  By format: {final_stats['by_format']}")
        print()

        print("=" * 60)
        total_new = galaxy_count + biomni_galaxy_count + biomni_nf_count + nfcore_count
        print(f"Summary: Indexed {total_new} new workflows")
        print(f"  - Galaxy local: {galaxy_count}")
        print(f"  - Biomni Galaxy: {biomni_galaxy_count}")
        print(f"  - Biomni Nextflow: {biomni_nf_count}")
        print(f"  - nf-core: {nfcore_count}")
        print("=" * 60)

    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    exit(main())
