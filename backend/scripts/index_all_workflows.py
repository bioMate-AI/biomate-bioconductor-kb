#!/usr/bin/env python3
"""
Unified Workflow Indexer

Correct table split:
  workflows table  — composite pipelines and multi-step subworkflows
  tools table      — individual executors (single tool/package wrappers)

workflows table sources (in priority order):
  nfcore       (100) — Full nf-core pipelines (rnaseq, sarek, chipseq, …)
  nfcore_subwf  (95) — nf-core composite subworkflows (nf-core-modules/subworkflows/)
  biomni_nextflow(85) — BioMate domain analysis workflows (nextflow_nfcore/subworkflows/)
  galaxy_biomni  (35) — Unique BioMate Galaxy workflows with NO Nextflow equivalent (2 items)

tools table additions (on top of 10 k+ existing Galaxy ToolShed entries):
  nfcore_module      — nf-core individual tool modules (nf-core-modules/modules/)
                       e.g. star/align, samtools/sort, gatk4/haplotypecaller
  (bioconductor entries already exist in tools — 2241 entries, do not re-add)

NOT indexed any more:
  galaxy_local        — Removed: Galaxy copies of nfcore subworkflows (redundant)
  biomni (legacy)     — Removed: superseded by biomni_nextflow
  nfcore_module in workflows — Wrong table; moved to tools
  bioconductor in workflows  — Wrong table; already in tools (2241 entries)

Usage:
    python scripts/index_all_workflows.py              # incremental
    python scripts/index_all_workflows.py --rebuild    # wipe and re-index

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

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

# ── Paths ────────────────────────────────────────────────────────────────────
BACKEND_PATH = Path(__file__).parent.parent
DB_PATH = BACKEND_PATH / "database" / "galaxy_ai_tools.db"

BIOMNI_NF_PATH       = BACKEND_PATH / "biomni_workflows" / "nextflow_nfcore" / "subworkflows"
NFCORE_MODULES_PATH  = BACKEND_PATH / "nf-core-modules" / "modules" / "nf-core"
NFCORE_SUBWF_PATH    = BACKEND_PATH / "nf-core-modules" / "subworkflows" / "nf-core"
NFCORE_PIPELINES_PATH= BACKEND_PATH / "nf-core-workflows"

BIOMNI_GALAXY_UNIQUE_PATH = BACKEND_PATH / "biomni_workflows" / "galaxy" / "subworkflows"
GALAXY_UNIQUE_WORKFLOWS = [
    ("synthetic_biology", "identify_fas_functional_domains"),
    ("biophysics",        "predict_protein_disorder_regions"),
]

NFCORE_PIPELINES = {
    "rnaseq":               {"name": "nf-core/rnaseq",               "description": "RNA sequencing analysis pipeline using STAR, RSEM, HISAT2 or Salmon with extensive QC",             "domain": "transcriptomics",  "tools": ["star","salmon","hisat2","rsem","kallisto","deseq2","fastqc","multiqc"]},
    "chipseq":              {"name": "nf-core/chipseq",              "description": "ChIP-seq peak-calling and differential analysis pipeline",                                           "domain": "epigenomics",      "tools": ["bwa","bowtie2","macs2","homer","deeptools","multiqc"]},
    "sarek":                {"name": "nf-core/sarek",                "description": "Analysis pipeline to detect germline or somatic variants from WGS/WES",                             "domain": "variant_calling",  "tools": ["bwa","gatk","strelka","manta","freebayes","mutect2"]},
    "methylseq":            {"name": "nf-core/methylseq",            "description": "Methylation (Bisulfite-Sequencing) analysis pipeline",                                              "domain": "epigenomics",      "tools": ["bismark","bwa-meth","methyldackel","multiqc"]},
    "diaproteomics":        {"name": "nf-core/diaproteomics",        "description": "Automated quantitative analysis of DIA proteomics mass spectrometry data",                         "domain": "proteomics",       "tools": ["dia-nn","openswath","pyprophet"]},
    "proteomicslfq":        {"name": "nf-core/proteomicslfq",        "description": "Proteomics label-free quantification (LFQ) analysis pipeline",                                     "domain": "proteomics",       "tools": ["maxquant","openms","comet"]},
    "differentialabundance":{"name": "nf-core/differentialabundance","description": "Differential abundance analysis for count matrices from RNA-seq, ATAC-seq, etc.",                  "domain": "transcriptomics",  "tools": ["deseq2","limma","edger"]},
}

# Domain inference from keyword text
DOMAIN_KEYWORDS = [
    ("rna",         "transcriptomics"),
    ("rnaseq",      "transcriptomics"),
    ("expression",  "transcriptomics"),
    ("align",       "genomics"),
    ("assembly",    "genomics"),
    ("genome",      "genomics"),
    ("variant",     "variant_calling"),
    ("vcf",         "variant_calling"),
    ("snp",         "variant_calling"),
    ("methylat",    "epigenomics"),
    ("chip",        "epigenomics"),
    ("atac",        "epigenomics"),
    ("peak",        "epigenomics"),
    ("protein",     "proteomics"),
    ("proteom",     "proteomics"),
    ("peptide",     "proteomics"),
    ("metagen",     "metagenomics"),
    ("microbiome",  "metagenomics"),
    ("16s",         "metagenomics"),
    ("imaging",     "imaging"),
    ("image",       "imaging"),
]


def infer_domain(text: str) -> str:
    t = text.lower()
    for kw, dom in DOMAIN_KEYWORDS:
        if kw in t:
            return dom
    return "general"


# ── Helpers ───────────────────────────────────────────────────────────────────

def compute_hash(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()[:16]


def load_meta_yml(path: Path) -> Dict:
    if not HAS_YAML or not path.exists():
        return {}
    try:
        with open(path) as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def extract_tools_from_ga(wf_json: Dict) -> List[str]:
    tools = []
    for step in wf_json.get("steps", {}).values():
        tid = step.get("tool_id") if isinstance(step, dict) else None
        if tid:
            tools.append(tid.split("/")[-1].lower())
    return list(set(tools))


def extract_nf_metadata(content: str) -> Dict:
    header = re.search(r'/\*\s*\n(.*?)\*/\s*\n', content, re.DOTALL)
    description = ""
    if header:
        lines = [ln.strip().lstrip("* ").strip()
                 for ln in header.group(1).splitlines()
                 if ln.strip() and ln.strip() not in ("*", "/*", "*/")]
        description = " ".join(lines)[:500]
    processes = re.findall(r'process\s+([A-Z][A-Z0-9_]+)', content)
    docker_m = re.search(r"container\s+'([^']+)'", content)
    return {"description": description, "processes": processes,
            "docker": docker_m.group(1) if docker_m else ""}


def wf_name(s: str) -> str:
    return s.replace("_", " ").replace("/", " ").title()


# ── Schema ────────────────────────────────────────────────────────────────────

def ensure_schema(conn: sqlite3.Connection):
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(workflows)")
    cols = {c[1] for c in cursor.fetchall()}
    new_cols = {
        "source": "TEXT DEFAULT 'unknown'", "format": "TEXT DEFAULT 'galaxy_ga'",
        "executable": "INTEGER DEFAULT 1",  "docker_image": "TEXT",
        "category": "TEXT",                 "workflow_hash": "TEXT",
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


# ── Workflow insert ───────────────────────────────────────────────────────────

def _wf_insert(cursor, *, name, filename, description, annotation, tags, domain,
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
          executable, docker_image[:300], category, workflow_hash, indexed_at))


def _wf_exists(cursor, wf_hash: str) -> bool:
    cursor.execute("SELECT id FROM workflows WHERE workflow_hash=?", (wf_hash,))
    return cursor.fetchone() is not None


# ── Tool insert (into tools table) ───────────────────────────────────────────

def _tool_exists(cursor, tool_id: str) -> bool:
    cursor.execute("SELECT id FROM tools WHERE tool_id=?", (tool_id,))
    return cursor.fetchone() is not None


def _tool_insert(cursor, *, tool_id, name, category, description, language,
                 tags, nfcore_metadata, container_info, wrapper_path, indexed_at):
    cursor.execute("""
        INSERT OR IGNORE INTO tools (
            tool_id, name, category, description, language,
            tags, nfcore_metadata, container_info, wrapper_path,
            availability_status, auto_discovered, discovery_date
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'available', 1, ?)
    """, (tool_id, name, category, description[:500], language,
          tags, nfcore_metadata, container_info[:300] if container_info else "",
          wrapper_path, indexed_at))


# ── Workflow indexers ─────────────────────────────────────────────────────────

def index_nfcore_pipelines(conn: sqlite3.Connection) -> int:
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()
    for pipeline_name, meta in NFCORE_PIPELINES.items():
        main_nf = NFCORE_PIPELINES_PATH / pipeline_name / "main.nf"
        if not main_nf.exists():
            continue
        content = main_nf.read_text()
        wf_hash = compute_hash(content)
        if _wf_exists(cursor, wf_hash):
            continue
        try:
            _wf_insert(cursor,
                name=meta["name"], filename=f"nfcore/{pipeline_name}/main.nf",
                description=meta["description"], annotation=meta["description"],
                tags=json.dumps(["nf-core", pipeline_name, meta["domain"]]),
                domain=meta["domain"], workflow_json=content,
                step_count=len(meta["tools"]), tools_used=json.dumps(meta["tools"]),
                source="nfcore", format_="nextflow",
                category=meta["domain"], workflow_hash=wf_hash, indexed_at=now)
            indexed += 1
            print(f"    + {meta['name']}")
        except Exception as e:
            print(f"    Error {pipeline_name}: {e}")
    conn.commit()
    return indexed


def index_nfcore_subworkflows(conn: sqlite3.Connection) -> int:
    """
    nf-core composite subworkflows → workflows table.
    These compose multiple modules and represent a meaningful analysis step.
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
        if _wf_exists(cursor, wf_hash):
            continue
        meta = load_meta_yml(sw_dir / "meta.yml")
        name = meta.get("name", sw_dir.name)
        description = meta.get("description", "nf-core subworkflow")
        keywords = meta.get("keywords", [])
        components = meta.get("components", [])
        domain = infer_domain(" ".join(keywords))
        try:
            _wf_insert(cursor,
                name=wf_name(name), filename=f"nf-core-modules/subworkflows/nf-core/{sw_dir.name}/main.nf",
                description=description, annotation=description,
                tags=json.dumps(["nf-core", "subworkflow"] + keywords[:5]),
                domain=domain, workflow_json=content,
                step_count=len(components), tools_used=json.dumps(components),
                source="nfcore_subwf", format_="nextflow",
                category=domain, workflow_hash=wf_hash, indexed_at=now)
            indexed += 1
        except Exception as e:
            print(f"    Error {sw_dir.name}: {e}")
    conn.commit()
    return indexed


def index_biomni_nextflow(conn: sqlite3.Connection) -> int:
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
            if _wf_exists(cursor, wf_hash):
                continue
            meta = extract_nf_metadata(content)
            description = meta["description"] or f"BioMate {domain} workflow: {wf_dir.name}"
            try:
                _wf_insert(cursor,
                    name=wf_name(wf_dir.name),
                    filename=f"nextflow_nfcore/{domain}/{wf_dir.name}/main.nf",
                    description=description, annotation=description,
                    tags=json.dumps([domain, "biomni", "nextflow", wf_dir.name]),
                    domain=domain, workflow_json=content,
                    step_count=len(meta["processes"]), tools_used=json.dumps(meta["processes"]),
                    source="biomni_nextflow", format_="nextflow",
                    docker_image=meta["docker"], category=domain,
                    workflow_hash=wf_hash, indexed_at=now)
                indexed += 1
            except Exception as e:
                print(f"    Error {domain}/{wf_dir.name}: {e}")
    conn.commit()
    return indexed


def index_galaxy_biomni_unique(conn: sqlite3.Connection) -> int:
    """2 BioMate Galaxy workflows with no Nextflow equivalent (fallback)."""
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()
    for domain, wf_name_str in GALAXY_UNIQUE_WORKFLOWS:
        ga_file = BIOMNI_GALAXY_UNIQUE_PATH / domain / f"{wf_name_str}.ga"
        if not ga_file.exists():
            continue
        content = ga_file.read_text()
        wf_hash = compute_hash(content)
        if _wf_exists(cursor, wf_hash):
            continue
        try:
            wf_json = json.loads(content)
        except Exception:
            continue
        name = wf_json.get("name", wf_name_str)
        annotation = wf_json.get("annotation", "")
        tools = extract_tools_from_ga(wf_json)
        try:
            _wf_insert(cursor,
                name=name, filename=f"galaxy/subworkflows/{domain}/{wf_name_str}.ga",
                description=annotation or f"BioMate Galaxy unique: {wf_name_str}",
                annotation=annotation,
                tags=json.dumps([domain, "biomni", "galaxy", "pending-conversion"]),
                domain=domain, workflow_json=content,
                step_count=len(wf_json.get("steps", {})), tools_used=json.dumps(tools),
                source="galaxy_biomni", format_="galaxy_ga",
                category=domain, workflow_hash=wf_hash, indexed_at=now)
            indexed += 1
            print(f"    + {domain}/{wf_name_str}  [pending NF conversion]")
        except Exception as e:
            print(f"    Error {domain}/{wf_name_str}: {e}")
    conn.commit()
    return indexed


# ── Tool indexers (tools table) ───────────────────────────────────────────────

def link_bioconductor_nf_wrappers(conn: sqlite3.Connection) -> Tuple[int, int]:
    """
    Link the 1818 Bioconductor NF wrapper files to their tools table entries
    by populating wrapper_path.  Also inserts the ~32 packages that have an
    NF file but no existing tools entry.

    The tools table already has 2241 rich Bioconductor entries (from Bioconductor
    web scraping with vignette steps, function lists, container info, etc.).
    This step simply connects those rows to the .nf files on disk.

    Returns (updated, inserted).
    """
    bioc_nf_path = BIOMNI_NF_PATH / "bioconductor"
    if not bioc_nf_path.exists():
        return 0, 0

    cursor = conn.cursor()
    updated = inserted = 0
    now = datetime.now().isoformat()

    for pkg_dir in sorted(bioc_nf_path.iterdir()):
        if not pkg_dir.is_dir():
            continue
        main_nf = pkg_dir / "main.nf"
        if not main_nf.exists():
            continue

        pkg = pkg_dir.name
        tool_id = f"bioconductor/{pkg}"
        wrapper_path = f"nextflow_nfcore/bioconductor/{pkg}/main.nf"

        row = cursor.execute(
            "SELECT id, wrapper_path FROM tools WHERE tool_id=?", (tool_id,)
        ).fetchone()

        if row:
            if not row[1]:
                cursor.execute(
                    "UPDATE tools SET wrapper_path=? WHERE tool_id=?",
                    (wrapper_path, tool_id)
                )
                updated += 1
        else:
            content = main_nf.read_text()
            header = re.search(r'// ={10,}\n(.*?)// ={10,}', content, re.DOTALL)
            description = f"Bioconductor R package: {pkg}"
            if header:
                for line in header.group(1).splitlines():
                    line = line.lstrip("/ ").strip()
                    if re.match(r'^[A-Z]', line) and len(line) > 20:
                        description = line[:500]
                        break
            docker_m = re.search(r"'quay\.io/[^']+bioconductor-([^:]+:[^']+)'", content)
            container = docker_m.group(0).strip("'") if docker_m else ""

            cursor.execute("""
                INSERT OR IGNORE INTO tools (
                    tool_id, name, description, language, category,
                    wrapper_path, container_info, availability_status,
                    auto_discovered, discovery_date
                ) VALUES (?, ?, ?, 'nextflow', 'Bioconductor', ?, ?, 'available', 1, ?)
            """, (tool_id, pkg, description[:500], wrapper_path,
                  container[:300], now))
            if cursor.rowcount:
                inserted += 1

    conn.commit()
    return updated, inserted


def index_nfcore_modules_as_tools(conn: sqlite3.Connection) -> int:
    """
    nf-core individual tool modules → tools table (NOT workflows table).
    Each module wraps a single bioinformatics tool (e.g. star/align, samtools/sort).
    Uses meta.yml for description, keywords, and container info.
    """
    cursor = conn.cursor()
    indexed = 0
    now = datetime.now().isoformat()
    if not NFCORE_MODULES_PATH.exists():
        print(f"  Path not found: {NFCORE_MODULES_PATH}")
        return 0

    for tool_dir in sorted(NFCORE_MODULES_PATH.iterdir()):
        if not tool_dir.is_dir():
            continue
        # Collect (mod_id, main_nf, meta_yml) entries — direct or sub-command
        entries: List[Tuple[str, Path, Path]] = []
        direct_main = tool_dir / "main.nf"
        if direct_main.exists():
            entries.append((tool_dir.name, direct_main, tool_dir / "meta.yml"))
        else:
            for sub in sorted(tool_dir.iterdir()):
                if sub.is_dir() and (sub / "main.nf").exists():
                    entries.append((f"{tool_dir.name}/{sub.name}", sub / "main.nf", sub / "meta.yml"))

        for mod_id, main_nf, meta_yml in entries:
            tool_id = f"nfcore/{mod_id}"
            if _tool_exists(cursor, tool_id):
                continue

            meta = load_meta_yml(meta_yml)
            description = meta.get("description", f"nf-core module: {mod_id}")
            keywords = meta.get("keywords", [])
            tools_meta = meta.get("tools", [])

            # category from first tool's description or keywords
            category_text = " ".join(keywords)
            if tools_meta and isinstance(tools_meta[0], dict):
                first_tool = list(tools_meta[0].values())[0]
                if isinstance(first_tool, dict):
                    category_text += " " + first_tool.get("description", "")

            # container from main.nf
            content = main_nf.read_text()
            container_m = re.search(r"'(community\.wave\.seqera\.io[^']+|quay\.io[^']+|ghcr\.io[^']+)'", content)
            container = container_m.group(1) if container_m else ""

            # Store full meta as JSON for rich downstream use
            nfcore_meta_json = json.dumps({
                "keywords": keywords,
                "tools": tools_meta,
                "components": meta.get("components", []),
                "wrapper_path": f"nf-core-modules/modules/nf-core/{mod_id}/main.nf",
            })

            try:
                _tool_insert(cursor,
                    tool_id=tool_id,
                    name=wf_name(mod_id),
                    category=", ".join(keywords[:5]) if keywords else "Nextflow",
                    description=description,
                    language="nextflow",
                    tags=json.dumps(["nf-core", "module"] + keywords[:5]),
                    nfcore_metadata=nfcore_meta_json,
                    container_info=container,
                    wrapper_path=f"nf-core-modules/modules/nf-core/{mod_id}/main.nf",
                    indexed_at=now)
                indexed += 1
            except Exception as e:
                print(f"    Error {mod_id}: {e}")

    conn.commit()
    return indexed


# ── Stats ─────────────────────────────────────────────────────────────────────

def get_stats(conn: sqlite3.Connection) -> Dict:
    cur = conn.cursor()
    wf_total = cur.execute("SELECT COUNT(*) FROM workflows").fetchone()[0]
    wf_by_src = dict(cur.execute("SELECT source, COUNT(*) FROM workflows GROUP BY source ORDER BY COUNT(*) DESC").fetchall())
    tool_total = cur.execute("SELECT COUNT(*) FROM tools").fetchone()[0]
    tool_nfcore = cur.execute("SELECT COUNT(*) FROM tools WHERE tool_id LIKE 'nfcore/%'").fetchone()[0]
    tool_bioc = cur.execute("SELECT COUNT(*) FROM tools WHERE tool_id LIKE 'bioconductor/%'").fetchone()[0]
    return {
        "workflows": wf_total, "wf_by_source": wf_by_src,
        "tools": tool_total, "tools_nfcore": tool_nfcore, "tools_bioconductor": tool_bioc,
    }


# ── Cleanup ───────────────────────────────────────────────────────────────────

def _remove_wf_source(conn, source):
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM workflows WHERE source=?", (source,))
    count = cur.fetchone()[0]
    if count:
        cur.execute("DELETE FROM workflows WHERE source=?", (source,))
        conn.commit()
        print(f"    Removed {count} workflows[source={source}]")
    return count


def _remove_tools_like(conn, pattern):
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM tools WHERE tool_id LIKE ?", (pattern,))
    count = cur.fetchone()[0]
    if count:
        cur.execute("DELETE FROM tools WHERE tool_id LIKE ?", (pattern,))
        conn.commit()
        print(f"    Removed {count} tools[tool_id LIKE {pattern}]")
    return count


def rebuild_clean(conn: sqlite3.Connection):
    """Remove all entries that will be re-indexed."""
    for src in ("biomni", "biomni_nextflow", "galaxy_local", "galaxy_biomni",
                "nfcore_subwf", "nfcore_module", "bioconductor"):
        _remove_wf_source(conn, src)
    # Remove nf-core module entries from tools (will re-add)
    _remove_tools_like(conn, "nfcore/%")
    # Clear bioconductor wrapper_paths so link_bioconductor_nf_wrappers re-populates them
    cur = conn.cursor()
    cur.execute("UPDATE tools SET wrapper_path='' WHERE tool_id LIKE 'bioconductor/%'")
    conn.commit()
    print(f"    Cleared {cur.rowcount} bioconductor wrapper_path entries (will re-link)")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Unified Workflow + Tool Indexer")
    parser.add_argument("--db-path", default=str(DB_PATH))
    parser.add_argument("--rebuild", action="store_true",
                        help="Remove re-indexable entries and rebuild from scratch")
    args = parser.parse_args()

    print("=" * 60)
    print("Unified Workflow + Tool Indexer")
    print("=" * 60)

    if not Path(args.db_path).exists():
        print(f"ERROR: Database not found at {args.db_path}")
        return 1

    conn = sqlite3.connect(args.db_path)
    try:
        print("\nPhase 0: Schema...")
        ensure_schema(conn)

        s = get_stats(conn)
        print(f"\nInitial: {s['workflows']} workflows | {s['tools']} tools")
        print(f"  workflows by source: {s['wf_by_source']}")
        print(f"  tools: {s['tools_nfcore']} nfcore | {s['tools_bioconductor']} bioconductor")

        if args.rebuild:
            print("\nPhase 1: Cleanup...")
            rebuild_clean(conn)

        # ── WORKFLOWS TABLE ──────────────────────────────────────────────────
        print("\nPhase 2 [workflows]: nf-core full pipelines")
        n1 = index_nfcore_pipelines(conn)
        print(f"  Added: {n1}")

        print("\nPhase 3 [workflows]: nf-core composite subworkflows")
        n2 = index_nfcore_subworkflows(conn)
        print(f"  Added: {n2}")

        print("\nPhase 4 [workflows]: BioMate Nextflow subworkflows")
        n3 = index_biomni_nextflow(conn)
        print(f"  Added: {n3}")

        print("\nPhase 5 [workflows]: Unique BioMate Galaxy workflows (no NF equivalent)")
        n4 = index_galaxy_biomni_unique(conn)
        print(f"  Added: {n4}")

        # ── TOOLS TABLE ──────────────────────────────────────────────────────
        print("\nPhase 6 [tools]: nf-core individual modules → tools table")
        n5 = index_nfcore_modules_as_tools(conn)
        print(f"  Added: {n5}")

        print("\nPhase 7 [tools]: Link Bioconductor NF wrappers to tools table entries")
        bioc_upd, bioc_ins = link_bioconductor_nf_wrappers(conn)
        print(f"  wrapper_path linked: {bioc_upd}  |  new entries: {bioc_ins}")

        s2 = get_stats(conn)
        print(f"\nFinal:")
        print(f"  workflows: {s2['workflows']}  by source: {s2['wf_by_source']}")
        print(f"  tools:     {s2['tools']}  (nfcore={s2['tools_nfcore']}, bioconductor={s2['tools_bioconductor']})")
        print(f"\n  workflows added: {n1+n2+n3+n4}   tools added: {n5}+{bioc_ins}(bioc)   bioc linked: {bioc_upd}")
        print("=" * 60)

    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    exit(main())
