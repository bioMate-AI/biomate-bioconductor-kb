#!/usr/bin/env python3
"""
Unified Workflow Indexer

Sources indexed (in priority order):
  nfcore          (100) — Full nf-core pipelines (rnaseq, sarek, chipseq, …)
  nfcore_subwf    (95)  — nf-core composite subworkflows (94, from nf-core-modules/subworkflows/)
  nfcore_module   (90)  — nf-core individual tool modules (1651, from nf-core-modules/modules/)
  biomni_nextflow (85)  — BioMate domain analysis workflows (nextflow_nfcore/subworkflows/)
  bioconductor    (75)  — Bioconductor R-package nf-core module wrappers
  galaxy_biomni   (40)  — Unique BioMate Galaxy workflows with NO Nextflow equivalent (2 items)

NOT indexed any more:
  galaxy_local        — Removed: these were just Galaxy-format copies of nf-core subworkflows
  biomni (legacy)     — Removed: superseded by biomni_nextflow

Usage:
    python scripts/index_all_workflows.py            # incremental (add new only)
    python scripts/index_all_workflows.py --rebuild  # wipe biomni/bioconductor and re-index
    python scripts/index_all_workflows.py --rebuild --include-bioconductor

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

import yaml  # PyYAML — available in the biomni venv

# ── Paths ───────────────────────────────────────────────────────────────────
BACKEND_PATH = Path(__file__).parent.parent
DB_PATH = BACKEND_PATH / "database" / "galaxy_ai_tools.db"

# BioMate Nextflow subworkflows (non-bioconductor)
BIOMNI_NF_PATH = BACKEND_PATH / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"

# nf-core community modules + subworkflows
NFCORE_MODULES_PATH = BACKEND_PATH / "nf-core-modules" / "modules" / "nf-core"
NFCORE_SUBWF_PATH   = BACKEND_PATH / "nf-core-modules" / "subworkflows" / "nf-core"

# Full nf-core pipelines
NFCORE_PIPELINES_PATH = BACKEND_PATH / "nf-core-workflows"

# BioMate Galaxy workflows that have NO Nextflow equivalent
BIOMNI_GALAXY_UNIQUE_PATH = BACKEND_PATH / "biomni_workflows" / "galaxy" / "subworkflows"
GALAXY_UNIQUE_WORKFLOWS = [
    ("synthetic_biology", "identify_fas_functional_domains"),
    ("biophysics",        "predict_protein_disorder_regions"),
]

# nf-core full pipeline metadata
NFCORE_PIPELINES = {
    "rnaseq":               {"name": "nf-core/rnaseq",               "description": "RNA sequencing analysis pipeline using STAR, RSEM, HISAT2 or Salmon with extensive QC",             "domain": "transcriptomics",  "tools": ["star","salmon","hisat2","rsem","kallisto","deseq2","fastqc","multiqc"]},
    "chipseq":              {"name": "nf-core/chipseq",              "description": "ChIP-seq peak-calling and differential analysis pipeline",                                           "domain": "epigenomics",      "tools": ["bwa","bowtie2","macs2","homer","deeptools","multiqc"]},
    "sarek":                {"name": "nf-core/sarek",                "description": "Analysis pipeline to detect germline or somatic variants from WGS/WES",                             "domain": "variant_calling",  "tools": ["bwa","gatk","strelka","manta","freebayes","mutect2"]},
    "methylseq":            {"name": "nf-core/methylseq",            "description": "Methylation (Bisulfite-Sequencing) analysis pipeline",                                              "domain": "epigenomics",      "tools": ["bismark","bwa-meth","methyldackel","multiqc"]},
    "diaproteomics":        {"name": "nf-core/diaproteomics",        "description": "Automated quantitative analysis of DIA proteomics mass spectrometry data",                         "domain": "proteomics",       "tools": ["dia-nn","openswath","pyprophet"]},
    "proteomicslfq":        {"name": "nf-core/proteomicslfq",        "description": "Proteomics label-free quantification (LFQ) analysis pipeline",                                     "domain": "proteomics",       "tools": ["maxquant","openms","comet"]},
    "differentialabundance":{"name": "nf-core/differentialabundance","description": "Differential abundance analysis for count matrices from RNA-seq, ATAC-seq, etc.",                  "domain": "transcriptomics",  "tools": ["deseq2","limma","edger"]},
}


# ── Helpers ──────────────────────────────────────────────────────────────────

def compute_hash(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def extract_tools_from_ga(wf_json: Dict) -> List[str]:
    tools = []
    for step in wf_json.get("steps", {}).values():
        tid = step.get("tool_id") if isinstance(step, dict) else None
        if tid:
            tools.append(tid.split("/")[-1].lower())
    return list(set(tools))


def extract_nf_metadata(content: str) -> Dict:
    """Extract description, processes and docker image from main.nf."""
    header = re.search(r'/\*\s*\n(.*?)\*/\s*\n', content, re.DOTALL)
    description = ""
    if header:
        lines = [ln.strip().lstrip("* ").strip()
                 for ln in header.group(1).splitlines()
                 if ln.strip() and ln.strip() not in ("*", "/*", "*/")]
        description = " ".join(lines)[:500]

    processes = re.findall(r'process\s+([A-Z][A-Z0-9_]+)', content)
    docker_m = re.search(r"container\s+'([^']+)'", content)
    return {
        "description": description,
        "processes": processes,
        "docker": docker_m.group(1) if docker_m else "",
    }


def load_meta_yml(path: Path) -> Dict:
    """Load nf-core meta.yml if present, return {} on failure."""
    try:
        with open(path) as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def wf_name_from_dir(name: str) -> str:
    return name.replace("_", " ").title()


# ── Schema ───────────────────────────────────────────────────────────────────

def ensure_schema(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(workflows)")
    cols = {c[1] for c in cursor.fetchall()}
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
        if col not in cols:
            try:
                cursor.execute(f"ALTER TABLE workflows ADD COLUMN {col} {defn}")
            except sqlite3.OperationalError as e:
                if "duplicate column" not in str(e).lower():
                    raise
    conn.commit()


# ── Insert helper ─────────────────────────────────────────────────────────────

def _insert(cursor, *, name, filename, description, annotation, tags, domain,
            workflow_json, step_count, tools_used, source, format_,
            executable=1, docker_image="", category="", workflow_hash, indexed_at):
    cursor.execute("""
        INSERT INTO workflows (
            name, filename, description, annotation, tags, domain,
            workflow_json, step_count, tools_used, source, format,
            executable, docker_image, category, workflow_hash, indexed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (name, filename, description[:500], annotation, tags, domain,
          workflow_json, step_count, tools_used, source, format_,
          executable, docker_image[:300], category,
          workflow_hash, indexed_at))


def _already_indexed(cursor, wf_hash: str) -> bool:
    cursor.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
    return cursor.fetchone() is not None


# ── Indexers ──────────────────────────────────────────────────────────────────

def index_nfcore_pipelines(conn: sqlite3.Connection) -> int:
    """Full nf-core pipelines (rnaseq, sarek, …)."""
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()

    for pipeline_name, meta in NFCORE_PIPELINES.items():
        main_nf = NFCORE_PIPELINES_PATH / pipeline_name / "main.nf"
        if not main_nf.exists():
            continue
        content = main_nf.read_text()
        wf_hash = compute_hash(content)
        if _already_indexed(cursor, wf_hash):
            continue
        try:
            _insert(cursor,
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
                category=meta["domain"],
                workflow_hash=wf_hash,
                indexed_at=now)
            indexed += 1
            print(f"    + {meta['name']}")
        except Exception as e:
            print(f"    Error {pipeline_name}: {e}")
    conn.commit()
    return indexed


def index_nfcore_subworkflows(conn: sqlite3.Connection) -> int:
    """
    nf-core composite subworkflows from nf-core-modules/subworkflows/nf-core/.
    Each has main.nf + meta.yml with rich metadata.
    """
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()

    if not NFCORE_SUBWF_PATH.exists():
        print(f"  Path not found: {NFCORE_SUBWF_PATH}")
        return 0

    for sw_dir in sorted(NFCORE_SUBWF_PATH.iterdir()):
        if not sw_dir.is_dir():
            continue
        main_nf = sw_dir / "main.nf"
        if not main_nf.exists():
            continue

        content = main_nf.read_text()
        wf_hash = compute_hash(content)
        if _already_indexed(cursor, wf_hash):
            continue

        meta = load_meta_yml(sw_dir / "meta.yml")
        name = meta.get("name", sw_dir.name)
        description = meta.get("description", "nf-core subworkflow")
        keywords = meta.get("keywords", [])
        components = meta.get("components", [])

        # Infer domain from keywords
        domain = "general"
        kw_text = " ".join(keywords).lower()
        for kw, dom in [("rna","transcriptomics"), ("bam","genomics"), ("vcf","variant_calling"),
                        ("methylat","epigenomics"), ("chip","epigenomics"), ("variant","variant_calling"),
                        ("protein","proteomics"), ("metagen","metagenomics"), ("atac","epigenomics")]:
            if kw in kw_text:
                domain = dom
                break

        try:
            _insert(cursor,
                name=wf_name_from_dir(name),
                filename=f"nf-core-modules/subworkflows/nf-core/{sw_dir.name}/main.nf",
                description=description,
                annotation=description,
                tags=json.dumps(["nf-core", "subworkflow"] + keywords[:5]),
                domain=domain,
                workflow_json=content,
                step_count=len(components),
                tools_used=json.dumps(components),
                source="nfcore_subwf",
                format_="nextflow",
                category=domain,
                workflow_hash=wf_hash,
                indexed_at=now)
            indexed += 1
        except Exception as e:
            print(f"    Error {sw_dir.name}: {e}")

    conn.commit()
    return indexed


def index_nfcore_modules(conn: sqlite3.Connection) -> int:
    """
    nf-core individual tool modules from nf-core-modules/modules/nf-core/.
    Each tool may have sub-commands (e.g. samtools/sort, samtools/index).
    Uses meta.yml for rich metadata.
    """
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()

    if not NFCORE_MODULES_PATH.exists():
        print(f"  Path not found: {NFCORE_MODULES_PATH}")
        return 0

    # Walk one or two levels: tool/main.nf  OR  tool/subcommand/main.nf
    for tool_dir in sorted(NFCORE_MODULES_PATH.iterdir()):
        if not tool_dir.is_dir():
            continue

        # Collect main.nf files: direct child or one level deeper
        nf_files = []
        direct = tool_dir / "main.nf"
        if direct.exists():
            nf_files.append((tool_dir.name, direct, tool_dir / "meta.yml"))
        else:
            for sub in sorted(tool_dir.iterdir()):
                if sub.is_dir() and (sub / "main.nf").exists():
                    nf_files.append((f"{tool_dir.name}/{sub.name}", sub / "main.nf", sub / "meta.yml"))

        for entry in nf_files:
            if isinstance(entry, tuple) and len(entry) == 3:
                mod_name, main_nf, meta_yml = entry
            else:
                continue

            content = main_nf.read_text()
            wf_hash = compute_hash(content)
            if _already_indexed(cursor, wf_hash):
                continue

            meta = load_meta_yml(meta_yml)
            description = meta.get("description", f"nf-core module: {mod_name}")
            keywords = meta.get("keywords", [])
            tools_meta = meta.get("tools", [])
            tool_names = list(tools_meta[0].keys()) if tools_meta else [tool_dir.name]

            domain = "general"
            kw_text = " ".join(keywords).lower()
            for kw, dom in [("rna","transcriptomics"), ("align","genomics"), ("variant","variant_calling"),
                            ("methylat","epigenomics"), ("chip","epigenomics"), ("protein","proteomics"),
                            ("assembly","genomics"), ("metagenom","metagenomics"), ("peak","epigenomics")]:
                if kw in kw_text:
                    domain = dom
                    break

            try:
                _insert(cursor,
                    name=wf_name_from_dir(mod_name.replace("/", " ")),
                    filename=f"nf-core-modules/modules/nf-core/{mod_name}/main.nf",
                    description=description,
                    annotation=description,
                    tags=json.dumps(["nf-core", "module"] + keywords[:5]),
                    domain=domain,
                    workflow_json=content,
                    step_count=1,
                    tools_used=json.dumps(tool_names),
                    source="nfcore_module",
                    format_="nextflow",
                    category=domain,
                    workflow_hash=wf_hash,
                    indexed_at=now)
                indexed += 1
            except Exception as e:
                print(f"    Error {mod_name}: {e}")

    conn.commit()
    return indexed


def index_biomni_nextflow(conn: sqlite3.Connection) -> int:
    """BioMate domain analysis workflows (Python-based, Docker-native)."""
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()

    if not BIOMNI_NF_PATH.exists():
        print(f"  Path not found: {BIOMNI_NF_PATH}")
        return 0

    for domain_dir in sorted(BIOMNI_NF_PATH.iterdir()):
        if not domain_dir.is_dir() or domain_dir.name == "bioconductor":
            continue
        domain = domain_dir.name

        for wf_dir in sorted(domain_dir.iterdir()):
            if not wf_dir.is_dir():
                continue
            main_nf = wf_dir / "main.nf"
            if not main_nf.exists():
                continue

            content = main_nf.read_text()
            wf_hash = compute_hash(content)
            if _already_indexed(cursor, wf_hash):
                continue

            meta = extract_nf_metadata(content)
            description = meta["description"] or f"BioMate {domain} workflow: {wf_dir.name}"
            try:
                _insert(cursor,
                    name=wf_name_from_dir(wf_dir.name),
                    filename=f"nextflow_nfcore/{domain}/{wf_dir.name}/main.nf",
                    description=description,
                    annotation=description,
                    tags=json.dumps([domain, "biomni", "nextflow", wf_dir.name]),
                    domain=domain,
                    workflow_json=content,
                    step_count=len(meta["processes"]),
                    tools_used=json.dumps(meta["processes"]),
                    source="biomni_nextflow",
                    format_="nextflow",
                    docker_image=meta["docker"],
                    category=domain,
                    workflow_hash=wf_hash,
                    indexed_at=now)
                indexed += 1
            except Exception as e:
                print(f"    Error {domain}/{wf_dir.name}: {e}")

    conn.commit()
    return indexed


def index_bioconductor(conn: sqlite3.Connection,
                       skip_overlaps: bool = True) -> Tuple[int, List[str]]:
    """Bioconductor R-package nf-core module wrappers."""
    bioc_path = BIOMNI_NF_PATH / "bioconductor"
    cursor = conn.cursor()
    indexed = 0
    overlaps: List[str] = []
    now = datetime.now().isoformat()

    if not bioc_path.exists():
        print(f"  Path not found: {bioc_path}")
        return 0, []

    if skip_overlaps:
        cursor.execute("SELECT LOWER(name) FROM workflows WHERE source IN ('biomni_nextflow','nfcore','nfcore_subwf','nfcore_module')")
        existing = {r[0] for r in cursor.fetchall()}
    else:
        existing = set()

    for pkg_dir in sorted(bioc_path.iterdir()):
        if not pkg_dir.is_dir():
            continue
        main_nf = pkg_dir / "main.nf"
        if not main_nf.exists():
            continue

        pkg_name = pkg_dir.name
        if skip_overlaps and pkg_name.lower() in existing:
            overlaps.append(pkg_name)
            continue

        content = main_nf.read_text()
        wf_hash = compute_hash(content)
        if _already_indexed(cursor, wf_hash):
            continue

        # Extract header metadata
        description = f"Bioconductor R package: {pkg_name}"
        upstream = downstream = ""
        header = re.search(r'// ={10,}\n(.*?)// ={10,}', content, re.DOTALL)
        if header:
            for line in header.group(1).splitlines():
                line = line.lstrip("/ ").strip()
                if re.match(r'^(Estimate|Differential|Analyse|Compute|Test|Fit|Model|Provide|Perform|Implement|Detect|Identify|Run)', line):
                    description = line[:500]
                elif line.startswith("Upstream"):
                    upstream = line.split(":", 1)[-1].strip()
                elif line.startswith("Downstream"):
                    downstream = line.split(":", 1)[-1].strip()

        annotation = description
        if upstream:
            annotation += f" | Upstream: {upstream}"
        if downstream:
            annotation += f" | Downstream: {downstream}"

        docker_m = re.search(r"'quay\.io/[^']+bioconductor-([^:]+:[^']+)'", content)
        docker = docker_m.group(0).strip("'") if docker_m else f"quay.io/biocontainers/bioconductor-{pkg_name}:latest"

        tags = ["bioconductor", "R", pkg_name]
        if upstream:
            tags += [t.strip() for t in upstream.split(",")][:3]

        try:
            _insert(cursor,
                name=f"Bioconductor/{pkg_name}",
                filename=f"nextflow_nfcore/bioconductor/{pkg_name}/main.nf",
                description=description,
                annotation=annotation[:1000],
                tags=json.dumps(tags),
                domain="bioconductor",
                workflow_json=content,
                step_count=1,
                tools_used=json.dumps([pkg_name]),
                source="bioconductor",
                format_="nextflow",
                docker_image=docker,
                category="bioconductor",
                workflow_hash=wf_hash,
                indexed_at=now)
            indexed += 1
        except Exception as e:
            print(f"    Error bioconductor/{pkg_name}: {e}")

    conn.commit()
    return indexed, overlaps


def index_galaxy_biomni_unique(conn: sqlite3.Connection) -> int:
    """
    Index the small set of BioMate Galaxy workflows that have NO Nextflow equivalent.
    These are kept in the index as fallback only.
    Currently: identify_fas_functional_domains, predict_protein_disorder_regions
    """
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()

    for domain, wf_name in GALAXY_UNIQUE_WORKFLOWS:
        ga_file = BIOMNI_GALAXY_UNIQUE_PATH / domain / f"{wf_name}.ga"
        if not ga_file.exists():
            print(f"    Not found: {ga_file}")
            continue

        content = ga_file.read_text()
        wf_hash = compute_hash(content)
        if _already_indexed(cursor, wf_hash):
            continue

        try:
            wf_json = json.loads(content)
        except Exception as e:
            print(f"    Bad JSON {ga_file}: {e}")
            continue

        name = wf_json.get("name", wf_name)
        annotation = wf_json.get("annotation", "")
        tools = extract_tools_from_ga(wf_json)

        try:
            _insert(cursor,
                name=name,
                filename=f"galaxy/subworkflows/{domain}/{wf_name}.ga",
                description=annotation or f"BioMate Galaxy unique: {wf_name}",
                annotation=annotation,
                tags=json.dumps([domain, "biomni", "galaxy", "pending-conversion"]),
                domain=domain,
                workflow_json=content,
                step_count=len(wf_json.get("steps", {})),
                tools_used=json.dumps(tools),
                source="galaxy_biomni",
                format_="galaxy_ga",
                category=domain,
                workflow_hash=wf_hash,
                indexed_at=now)
            indexed += 1
            print(f"    + {domain}/{wf_name} (pending Nextflow conversion)")
        except Exception as e:
            print(f"    Error {domain}/{wf_name}: {e}")

    conn.commit()
    return indexed


# ── Stats ─────────────────────────────────────────────────────────────────────

def get_stats(conn: sqlite3.Connection) -> Dict:
    cur = conn.cursor()
    total = cur.execute("SELECT COUNT(*) FROM workflows").fetchone()[0]
    by_source = dict(cur.execute("SELECT source, COUNT(*) FROM workflows GROUP BY source ORDER BY COUNT(*) DESC").fetchall())
    by_format = dict(cur.execute("SELECT format, COUNT(*) FROM workflows GROUP BY format").fetchall())
    top_domains = dict(cur.execute(
        "SELECT domain, COUNT(*) FROM workflows GROUP BY domain ORDER BY COUNT(*) DESC LIMIT 15"
    ).fetchall())
    return {"total": total, "by_source": by_source, "by_format": by_format, "top_domains": top_domains}


# ── Cleanup helpers ───────────────────────────────────────────────────────────

def _remove_source(conn, source, label=None):
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM workflows WHERE source=?", (source,))
    count = cur.fetchone()[0]
    if count:
        cur.execute("DELETE FROM workflows WHERE source=?", (source,))
        conn.commit()
        print(f"    Removed {count} {label or source} entries")
    return count


def remove_all_for_rebuild(conn: sqlite3.Connection):
    """Remove all non-nfcore entries for a full rebuild."""
    for src, label in [
        ("biomni",          "legacy Galaxy biomni"),
        ("biomni_nextflow", "biomni_nextflow"),
        ("bioconductor",    "bioconductor"),
        ("galaxy_local",    "galaxy_local (duplicate nfcore subwf wrappers)"),
        ("galaxy_biomni",   "galaxy_biomni unique"),
        ("nfcore_subwf",    "nfcore_subwf"),
        ("nfcore_module",   "nfcore_module"),
    ]:
        _remove_source(conn, src, label)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Unified Workflow Indexer")
    parser.add_argument("--db-path", default=str(DB_PATH))
    parser.add_argument("--rebuild", action="store_true",
                        help="Wipe and re-index all non-nfcore sources")
    parser.add_argument("--include-bioconductor", action="store_true",
                        help="Index 1800+ Bioconductor R-package modules")
    args = parser.parse_args()

    print("=" * 60)
    print("Unified Workflow Indexer")
    print("=" * 60)

    if not Path(args.db_path).exists():
        print(f"ERROR: Database not found at {args.db_path}")
        return 1

    conn = sqlite3.connect(args.db_path)

    try:
        print("\nPhase 0: Schema...")
        ensure_schema(conn)

        initial = get_stats(conn)
        print(f"\nInitial: {initial['total']} workflows")
        print(f"  By source: {initial['by_source']}")

        if args.rebuild:
            print("\nPhase 1: Removing old entries...")
            remove_all_for_rebuild(conn)

        print("\nPhase 2: nf-core full pipelines")
        n1 = index_nfcore_pipelines(conn)
        print(f"  Added: {n1}")

        print("\nPhase 3: nf-core subworkflows (nf-core-modules/subworkflows/nf-core/)")
        n2 = index_nfcore_subworkflows(conn)
        print(f"  Added: {n2}")

        print("\nPhase 4: nf-core modules (nf-core-modules/modules/nf-core/)")
        n3 = index_nfcore_modules(conn)
        print(f"  Added: {n3}")

        print("\nPhase 5: BioMate Nextflow subworkflows (nextflow_nfcore/subworkflows/)")
        n4 = index_biomni_nextflow(conn)
        print(f"  Added: {n4}")

        n5 = 0
        bioc_overlaps: List[str] = []
        if args.include_bioconductor:
            print("\nPhase 6: Bioconductor R-package modules")
            n5, bioc_overlaps = index_bioconductor(conn, skip_overlaps=True)
            print(f"  Added: {n5}  (skipped {len(bioc_overlaps)} duplicates: {', '.join(bioc_overlaps[:5])}{'...' if len(bioc_overlaps)>5 else ''})")

        print("\nPhase 7: Unique BioMate Galaxy workflows (no NF equivalent)")
        n6 = index_galaxy_biomni_unique(conn)
        print(f"  Added: {n6}")

        final = get_stats(conn)
        print(f"\nFinal: {final['total']} workflows")
        print(f"  By source:     {final['by_source']}")
        print(f"  By format:     {final['by_format']}")
        print(f"  Top domains:   {final['top_domains']}")

        total_new = n1 + n2 + n3 + n4 + n5 + n6
        print(f"\nSummary: added {total_new} new entries")
        print("=" * 60)

    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    exit(main())
