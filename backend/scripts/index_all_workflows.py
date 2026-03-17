#!/usr/bin/env python3
"""
Unified Workflow Indexer

Indexes all workflow sources into the galaxy_ai_tools.db:
1. nf-core pipelines  (source=nfcore, format=nextflow)
2. Biomni Nextflow subworkflows from nextflow_nfcore/subworkflows/
   (source=biomni_nextflow, format=nextflow)  — preferred over Galaxy
3. Galaxy .ga workflows from galaxy_workflows/  (source=galaxy_local, format=galaxy_ga)

Galaxy-format biomni workflows (source=biomni) are no longer indexed;
use the Nextflow equivalents instead.

Usage:
    python scripts/index_all_workflows.py [--db-path PATH] [--no-bioconductor]
    python scripts/index_all_workflows.py --rebuild          # wipe biomni/biomni_nextflow and re-index

Author: BioMate Team
Updated: 2026-03-10
"""

import argparse
import json
import re
import sqlite3
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# ── Paths ──────────────────────────────────────────────────────────────────
BACKEND_PATH = Path(__file__).parent.parent
DB_PATH = BACKEND_PATH / "database" / "galaxy_ai_tools.db"

# Galaxy community workflows (nf-core Galaxy wrappers)
GALAXY_WORKFLOWS_PATH = BACKEND_PATH / "galaxy_workflows"

# Biomni Nextflow subworkflows  ← CORRECT path
BIOMNI_NF_PATH = BACKEND_PATH / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"

# nf-core full pipelines
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


# ── Helpers ────────────────────────────────────────────────────────────────

def compute_hash(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def extract_tools_from_ga(workflow_json: Dict) -> List[str]:
    tools = []
    for step in workflow_json.get("steps", {}).values():
        tool_id = step.get("tool_id") if isinstance(step, dict) else None
        if tool_id:
            tools.append(tool_id.split("/")[-1].lower())
    return list(set(tools))


def extract_nf_metadata(content: str) -> Dict:
    """Extract name, description, processes, and params from a main.nf file."""
    # Top-level comment block for description
    header_match = re.search(r'/\*\s*\n(.*?)\*/\s*\n', content, re.DOTALL)
    description = ""
    if header_match:
        desc_lines = [
            ln.strip().lstrip('* ').strip()
            for ln in header_match.group(1).splitlines()
            if ln.strip() and ln.strip() not in ('*', '/*', '*/')
        ]
        description = ' '.join(desc_lines)[:500]

    # Process names
    processes = re.findall(r'process\s+([A-Z][A-Z0-9_]+)', content)

    # Container image
    container_match = re.search(r"container\s+'([^']+)'", content)
    docker = container_match.group(1) if container_match else ""

    return {
        "description": description,
        "processes": processes,
        "docker": docker,
    }


def wf_name_from_path(domain: str, wf_dir: str) -> str:
    """Convert directory name to human-readable workflow name."""
    return wf_dir.replace("_", " ").title()


# ── Schema ─────────────────────────────────────────────────────────────────

def ensure_schema(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(workflows)")
    columns = {col[1] for col in cursor.fetchall()}
    new_cols = {
        "source": "TEXT DEFAULT 'unknown'",
        "format": "TEXT DEFAULT 'galaxy_ga'",
        "executable": "INTEGER DEFAULT 1",
        "docker_image": "TEXT",
        "category": "TEXT",
        "workflow_hash": "TEXT",
        "indexed_at": "TEXT",
    }
    for col, defn in new_cols.items():
        if col not in columns:
            try:
                cursor.execute(f"ALTER TABLE workflows ADD COLUMN {col} {defn}")
            except sqlite3.OperationalError as e:
                if "duplicate column" not in str(e).lower():
                    raise
    conn.commit()


# ── Indexers ───────────────────────────────────────────────────────────────

def _insert_workflow(cursor, *, name, filename, description, annotation, tags,
                     domain, workflow_json, step_count, tools_used,
                     source, format_, executable=1, docker_image="",
                     category="", workflow_hash, indexed_at):
    cursor.execute("""
        INSERT INTO workflows (
            name, filename, description, annotation, tags, domain,
            workflow_json, step_count, tools_used, source, format,
            executable, docker_image, category, workflow_hash, indexed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        name, filename, description, annotation, tags, domain,
        workflow_json, step_count, tools_used,
        source, format_, executable, docker_image, category,
        workflow_hash, indexed_at,
    ))


def extract_bioc_metadata(content: str, pkg_name: str) -> Dict:
    """Parse metadata from a Bioconductor module main.nf header comment block."""
    description, upstream, downstream, source_url, install_cmd = "", "", "", "", ""

    header = re.search(r'// ={10,}\n(.*?)// ={10,}', content, re.DOTALL)
    if header:
        for line in header.group(1).splitlines():
            line = line.lstrip("/ ").strip()
            if line.startswith("Bioconductor module:"):
                pass  # package name
            elif line.startswith("//") or not line:
                continue
            elif re.match(r'^(Estimate|Differential|Analyse|Compute|Test|Fit|Model|Provide|Perform|Implement|Detect|Identify|Run)', line):
                description = line[:500]
            elif line.startswith("Source"):
                source_url = line.split(":", 1)[-1].strip()[:200]
            elif line.startswith("Upstream"):
                upstream = line.split(":", 1)[-1].strip()
            elif line.startswith("Downstream"):
                downstream = line.split(":", 1)[-1].strip()
            elif line.startswith("Install"):
                install_cmd = line.split(":", 1)[-1].strip()

    # Container image
    docker_match = re.search(r"'quay\.io/[^']+bioconductor-([^:]+:[^']+)'", content)
    docker = docker_match.group(0).strip("'") if docker_match else f"quay.io/biocontainers/bioconductor-{pkg_name}:latest"

    return {
        "description": description or f"Bioconductor R package: {pkg_name}",
        "upstream": upstream,
        "downstream": downstream,
        "source_url": source_url,
        "install_cmd": install_cmd,
        "docker": docker,
    }


def index_bioconductor(conn: sqlite3.Connection,
                       skip_overlaps: bool = True) -> Tuple[int, List[str]]:
    """
    Index Bioconductor R-package module wrappers.
    Returns (indexed_count, skipped_overlap_names).
    """
    bioc_path = BIOMNI_NF_PATH / "bioconductor"
    cursor = conn.cursor()
    indexed = 0
    overlaps: List[str] = []
    now = datetime.now().isoformat()

    if not bioc_path.exists():
        print(f"  Path not found: {bioc_path}")
        return 0, []

    # Build set of existing workflow names (other domains) for overlap detection
    cursor.execute("SELECT LOWER(name) FROM workflows WHERE source='biomni_nextflow'")
    existing_names = {row[0] for row in cursor.fetchall()}
    cursor.execute("SELECT LOWER(name) FROM workflows WHERE source='nfcore'")
    nfcore_names = {row[0] for row in cursor.fetchall()}

    for pkg_dir in sorted(bioc_path.iterdir()):
        if not pkg_dir.is_dir():
            continue
        main_nf = pkg_dir / "main.nf"
        if not main_nf.exists():
            continue

        pkg_name = pkg_dir.name
        # Check overlap with other indexed workflows
        normalized = pkg_name.lower().replace("_", " ")
        if skip_overlaps and (normalized in existing_names or normalized in nfcore_names):
            overlaps.append(pkg_name)
            continue

        try:
            content = main_nf.read_text()
            wf_hash = compute_hash(content)

            cursor.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
            if cursor.fetchone():
                continue

            meta = extract_bioc_metadata(content, pkg_name)
            display_name = f"Bioconductor/{pkg_name}"
            description = meta["description"]
            annotation = description
            if meta["upstream"]:
                annotation += f" | Upstream: {meta['upstream']}"
            if meta["downstream"]:
                annotation += f" | Downstream: {meta['downstream']}"

            tags_list = ["bioconductor", "R", pkg_name]
            if meta["upstream"]:
                tags_list += [t.strip() for t in meta["upstream"].split(",")][:3]

            _insert_workflow(
                cursor,
                name=display_name,
                filename=f"nextflow_nfcore/bioconductor/{pkg_name}/main.nf",
                description=description[:500],
                annotation=annotation[:1000],
                tags=json.dumps(tags_list),
                domain="bioconductor",
                workflow_json=content,
                step_count=1,
                tools_used=json.dumps([pkg_name]),
                source="bioconductor",
                format_="nextflow",
                docker_image=meta["docker"][:300],
                category="bioconductor",
                workflow_hash=wf_hash,
                indexed_at=now,
            )
            indexed += 1

        except Exception as e:
            print(f"    Error indexing bioconductor/{pkg_name}: {e}")

    conn.commit()
    return indexed, overlaps


def index_biomni_nextflow(conn: sqlite3.Connection,
                          skip_bioconductor: bool = True) -> int:
    """
    Index Biomni Nextflow subworkflows from nextflow_nfcore/subworkflows/.
    Structure: <domain>/<workflow_name>/main.nf
    """
    cursor = conn.cursor()
    indexed = skipped = 0
    now = datetime.now().isoformat()

    if not BIOMNI_NF_PATH.exists():
        print(f"  Path not found: {BIOMNI_NF_PATH}")
        return 0

    for domain_dir in sorted(BIOMNI_NF_PATH.iterdir()):
        if not domain_dir.is_dir():
            continue
        domain = domain_dir.name

        if skip_bioconductor and domain == "bioconductor":
            skipped_count = sum(1 for _ in domain_dir.iterdir() if _.is_dir())
            print(f"    Skipping bioconductor ({skipped_count} workflows, use --include-bioconductor)")
            continue

        for wf_dir in sorted(domain_dir.iterdir()):
            if not wf_dir.is_dir():
                continue
            main_nf = wf_dir / "main.nf"
            if not main_nf.exists():
                continue

            try:
                content = main_nf.read_text()
                wf_hash = compute_hash(content)

                cursor.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
                if cursor.fetchone():
                    continue

                meta = extract_nf_metadata(content)
                wf_name = wf_name_from_path(domain, wf_dir.name)
                description = meta["description"] or f"Biomni {domain} Nextflow workflow: {wf_dir.name}"
                tags = json.dumps([domain, "biomni", "nextflow", wf_dir.name])

                _insert_workflow(
                    cursor,
                    name=wf_name,
                    filename=f"nextflow_nfcore/{domain}/{wf_dir.name}/main.nf",
                    description=description[:500],
                    annotation=description,
                    tags=tags,
                    domain=domain,
                    workflow_json=content,
                    step_count=len(meta["processes"]),
                    tools_used=json.dumps(meta["processes"]),
                    source="biomni_nextflow",
                    format_="nextflow",
                    docker_image=meta["docker"],
                    category=domain,
                    workflow_hash=wf_hash,
                    indexed_at=now,
                )
                indexed += 1

            except Exception as e:
                print(f"    Error indexing {wf_dir}: {e}")

    conn.commit()
    return indexed


def index_galaxy_local(conn: sqlite3.Connection) -> int:
    """Index nf-core community Galaxy wrappers from galaxy_workflows/."""
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()

    if not GALAXY_WORKFLOWS_PATH.exists():
        print(f"  Path not found: {GALAXY_WORKFLOWS_PATH}")
        return 0

    for ga_file in sorted(GALAXY_WORKFLOWS_PATH.glob("*.ga")):
        try:
            content = ga_file.read_text()
            wf_json = json.loads(content)
            wf_hash = compute_hash(content)

            cursor.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
            if cursor.fetchone():
                continue

            name = wf_json.get("name", ga_file.stem)
            annotation = wf_json.get("annotation", "")
            tools = extract_tools_from_ga(wf_json)
            tags = json.dumps(wf_json.get("tags", []))

            _insert_workflow(
                cursor,
                name=name,
                filename=ga_file.name,
                description=annotation[:500],
                annotation=annotation,
                tags=tags,
                domain="general",
                workflow_json=content,
                step_count=len(wf_json.get("steps", {})),
                tools_used=json.dumps(tools),
                source="galaxy_local",
                format_="galaxy_ga",
                workflow_hash=wf_hash,
                indexed_at=now,
            )
            indexed += 1

        except Exception as e:
            print(f"    Error indexing {ga_file.name}: {e}")

    conn.commit()
    return indexed


def index_nfcore(conn: sqlite3.Connection) -> int:
    """Index nf-core full pipelines."""
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()

    for pipeline_name, meta in NFCORE_PIPELINES.items():
        main_nf = NFCORE_WORKFLOWS_PATH / pipeline_name / "main.nf"
        if not main_nf.exists():
            continue
        try:
            content = main_nf.read_text()
            wf_hash = compute_hash(content)
            cursor.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
            if cursor.fetchone():
                continue

            _insert_workflow(
                cursor,
                name=meta["name"],
                filename=f"nfcore/{pipeline_name}/main.nf",
                description=meta["description"],
                annotation=meta["description"],
                tags=json.dumps(["nf-core", pipeline_name, meta["domain"]]),
                domain=meta["domain"],
                workflow_json=content,
                step_count=len(meta["tools"]),
                tools_used=json.dumps(meta["tools"]),
                source="nfcore",
                format_="nextflow",
                docker_image=meta.get("docker", ""),
                category=meta["domain"],
                workflow_hash=wf_hash,
                indexed_at=now,
            )
            indexed += 1
            print(f"    Indexed: {meta['name']}")

        except Exception as e:
            print(f"    Error indexing {pipeline_name}: {e}")

    conn.commit()
    return indexed


# ── Stats ──────────────────────────────────────────────────────────────────

def get_stats(conn: sqlite3.Connection) -> Dict:
    cur = conn.cursor()
    total = cur.execute("SELECT COUNT(*) FROM workflows").fetchone()[0]
    by_source = dict(cur.execute("SELECT source, COUNT(*) FROM workflows GROUP BY source").fetchall())
    by_format = dict(cur.execute("SELECT format, COUNT(*) FROM workflows GROUP BY format").fetchall())
    top_domains = dict(cur.execute(
        "SELECT domain, COUNT(*) FROM workflows GROUP BY domain ORDER BY COUNT(*) DESC LIMIT 12"
    ).fetchall())
    return {"total": total, "by_source": by_source, "by_format": by_format, "top_domains": top_domains}


def remove_old_galaxy_biomni(conn: sqlite3.Connection) -> int:
    """Remove old Galaxy-format biomni entries (now superseded by Nextflow)."""
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM workflows WHERE source='biomni' AND format='galaxy_ga'")
    count = cur.fetchone()[0]
    if count:
        cur.execute("DELETE FROM workflows WHERE source='biomni' AND format='galaxy_ga'")
        conn.commit()
        print(f"    Removed {count} old biomni Galaxy entries")
    return count


def remove_old_biomni_nextflow(conn: sqlite3.Connection) -> int:
    """Remove stale biomni_nextflow entries (were indexed from wrong path)."""
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM workflows WHERE source='biomni_nextflow'")
    count = cur.fetchone()[0]
    if count:
        cur.execute("DELETE FROM workflows WHERE source='biomni_nextflow'")
        conn.commit()
        print(f"    Removed {count} stale biomni_nextflow entries (wrong path)")
    return count


def remove_old_bioconductor(conn: sqlite3.Connection) -> int:
    """Remove existing bioconductor entries (for clean re-index)."""
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM workflows WHERE source='bioconductor'")
    count = cur.fetchone()[0]
    if count:
        cur.execute("DELETE FROM workflows WHERE source='bioconductor'")
        conn.commit()
        print(f"    Removed {count} existing bioconductor entries")
    return count


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Unified Workflow Indexer")
    parser.add_argument("--db-path", default=str(DB_PATH))
    parser.add_argument("--rebuild", action="store_true",
                        help="Remove old biomni Galaxy + stale NF entries, then re-index")
    parser.add_argument("--include-bioconductor", action="store_true",
                        help="Also index the 1800+ Bioconductor R-package workflows")
    parser.add_argument("--rebuild-bioconductor", action="store_true",
                        help="Remove existing bioconductor entries and re-index them")
    args = parser.parse_args()

    db_path = args.db_path
    skip_bioc = not args.include_bioconductor

    print("=" * 60)
    print("Unified Workflow Indexer")
    print("=" * 60)

    if not Path(db_path).exists():
        print(f"ERROR: Database not found at {db_path}")
        return 1

    conn = sqlite3.connect(db_path)

    try:
        print("\nPhase 0: Ensuring schema...")
        ensure_schema(conn)

        stats = get_stats(conn)
        print(f"\nInitial state: {stats['total']} workflows")
        print(f"  By source: {stats['by_source']}")

        if args.rebuild:
            print("\nPhase 1: Removing old entries...")
            remove_old_galaxy_biomni(conn)
            remove_old_biomni_nextflow(conn)

        if args.rebuild_bioconductor:
            print("\nPhase 1b: Removing old bioconductor entries...")
            remove_old_bioconductor(conn)

        print(f"\nPhase 2: Indexing Biomni Nextflow from nextflow_nfcore/subworkflows/")
        print(f"  Path: {BIOMNI_NF_PATH}")
        nf_count = index_biomni_nextflow(conn, skip_bioconductor=True)
        print(f"  Indexed: {nf_count} new Nextflow workflows")

        print("\nPhase 3: Indexing Galaxy community workflows from galaxy_workflows/")
        ga_count = index_galaxy_local(conn)
        print(f"  Indexed: {ga_count}")

        print("\nPhase 4: Indexing nf-core full pipelines")
        nfcore_count = index_nfcore(conn)
        print(f"  Indexed: {nfcore_count}")

        bioc_count = 0
        bioc_overlaps: List[str] = []
        if args.include_bioconductor or args.rebuild_bioconductor:
            print("\nPhase 5: Indexing Bioconductor R-package modules")
            bioc_count, bioc_overlaps = index_bioconductor(conn, skip_overlaps=True)
            print(f"  Indexed: {bioc_count} unique Bioconductor modules")
            if bioc_overlaps:
                print(f"  Skipped (overlap with nfcore/biomni): {', '.join(bioc_overlaps)}")

        final = get_stats(conn)
        print(f"\nFinal state: {final['total']} workflows")
        print(f"  By source: {final['by_source']}")
        print(f"  By format: {final['by_format']}")
        print(f"  Top domains: {final['top_domains']}")

        total_new = nf_count + ga_count + nfcore_count + bioc_count
        print(f"\nSummary: added {total_new} new entries")
        if bioc_overlaps:
            print(f"  ({len(bioc_overlaps)} bioconductor packages skipped as duplicates of nfcore/biomni tools)")
        print("=" * 60)

    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    exit(main())
