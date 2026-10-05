#!/usr/bin/env python3
"""
register_wsi_pathology.py

Registers the pathology/wsi_he_nuclei_segmentation workflow in the workflows DB
(it is on disk + validated end-to-end on Batch, but has no DB row, so the AI
router can't surface it). Adds the row with executable=1 and rebuilds FTS.
Idempotent (skips if already present). Follows register_missing_biomate_workflows.py.

DB NOTES (verified 2026-10-04):
`scripts/sync_to_dev.sh` REPLACES dev's galaxy_ai_tools.db with the local one when
their MD5s differ (dev auto-backs-up to a .bak first, and refuses files <10 MB).
A normal local checkout's backend/database/galaxy_ai_tools.db is byte-IDENTICAL to
the canonical dev DB (same md5; ~322 MB; 4,209 workflow rows). Workflow search is
FTS-based: `workflow_embeddings` is 0 in BOTH local and dev (it is not the vector
store), so it is safe to add a row + rebuild FTS and sync — that only adds the WSI
row. The real danger is syncing a PARTIAL/degenerate DB over the full one, so the
guard below refuses a DB with far fewer than ~4,209 workflow rows.

Procedure:
  1. Ensure backend/database/galaxy_ai_tools.db is the full DB (md5 == dev's; the
     sync pre-flight logs the dev md5). It normally already is.
  2. python3 scripts/register_wsi_pathology.py      # adds the WSI row + rebuilds FTS
  3. scripts/sync_to_dev.sh                          # uploads the DB (+WSI row) to dev
  4. (optional) run the workflow-embedding/index step on dev if/when vector search
     for workflows is enabled; FTS/keyword routing finds WSI meanwhile.

Usage:
    python3 scripts/register_wsi_pathology.py [--db <path>] [--allow-stub]
"""
import argparse
import hashlib
import sqlite3
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
DB_DEFAULT = REPO_ROOT / "database" / "galaxy_ai_tools.db"

ENTRY = {
    "name": "wsi_he_nuclei_segmentation",
    "filename": "nextflow_nfcore/subworkflows/pathology/wsi_he_nuclei_segmentation/main.nf",
    "description": (
        "RESEARCH-USE-ONLY whole-slide-image (WSI) H&E preprocessing + nuclei "
        "segmentation. Ingests one WSI via OpenSlide (Aperio .svs or pyramidal "
        "OME-TIFF; param-less quick run auto-downloads the public CMU-1-Small-Region.svs "
        "demo), does deterministic tissue tiling (Otsu-on-saturation tissue detection + "
        "variance-of-Laplacian focus QC), segments nuclei with Cellpose (BSD-3-Clause, "
        "model_type='nuclei') on the hematoxylin channel (skimage rgb2hed), and emits "
        "per-tile labelled masks, a stitched QC overlay, a per-nucleus cell table (CSV "
        "with global centroids + areas in um^2), a QC summary JSON, a model/version "
        "manifest, and a 'RESEARCH USE ONLY — pathologist review required' report. "
        "NOT a diagnostic device. Input: one WSI (.svs / OME-TIFF). Output: cell table "
        "CSV, QC overlay PNG, per-tile masks, QC summary JSON, report."
    ),
    "annotation": (
        "WSI (.svs/OME-TIFF) -> OpenSlide tiling + Cellpose nuclei segmentation -> "
        "per-nucleus cell table CSV + QC overlay + masks (research use only)"
    ),
    "tags": (
        "whole slide image,wsi,h&e,he,histology,histopathology,nuclei segmentation,"
        "cell segmentation,cellpose,openslide,digital pathology,digital histology,"
        "aperio,svs,ome-tiff,tissue tiling,research use only,rgb2hed,hematoxylin"
    ),
    "domain": "pathology",
    "category": "Digital Pathology",
    # The .nf process `container` directive is the purpose-built image (OpenSlide +
    # cellpose + scikit-image); it OVERRIDES this docker_image on Batch, but keep it
    # consistent for display/provenance.
    "docker_image": "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-pathology:1.0",
    "input_types": ["svs", "ome-tiff", "tiff", "wsi"],
    "output_types": ["csv", "png", "json", "txt"],
    "step_count": 4,
    "tools_used": "OpenSlide, Cellpose (nuclei model), scikit-image",
}


def workflow_hash(entry: dict) -> str:
    return hashlib.md5(f"{entry['name']}|{entry['filename']}".encode()).hexdigest()


def rebuild_fts(conn: sqlite3.Connection) -> None:
    tabs = [r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    if "workflows_fts" not in tabs:
        return
    conn.execute("DELETE FROM workflows_fts")
    conn.execute(
        """
        INSERT INTO workflows_fts(rowid, name, description, annotation, tags, domain, tools_used)
        SELECT id, name, description, annotation, tags, domain, tools_used FROM workflows
        """
    )


def register(db_path: Path, allow_stub: bool) -> None:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    # Clobber guard: refuse to touch an obviously-degenerate DB (far fewer workflow rows
    # than the canonical ~4,209), because editing it + syncing would overwrite dev's full
    # DB with a partial one. NOTE (verified 2026-10-04): the canonical dev DB and a normal
    # local checkout are byte-identical (same md5) and BOTH have workflow_embeddings=0 —
    # workflow search is FTS-based, not that table — so row count, not embeddings, is the
    # real stub signal.
    try:
        n_wf = conn.execute("SELECT COUNT(*) FROM workflows").fetchone()[0]
    except sqlite3.Error:
        n_wf = 0
    if n_wf < 4000 and not allow_stub:
        conn.close()
        raise SystemExit(
            f"REFUSING: {db_path} has only {n_wf} workflow rows (expected ~4,209). This looks "
            "like a partial/stub DB; registering here and syncing would overwrite dev's full DB. "
            "Point --db at the full DB, or pass --allow-stub if you really mean it."
        )

    nf_path = REPO_ROOT / "biomni_workflows" / ENTRY["filename"]
    if not nf_path.exists():
        # fall back to the repo-root-relative path used by the executor
        nf_path = REPO_ROOT / ENTRY["filename"]
    if not nf_path.exists():
        conn.close()
        raise SystemExit(f"main.nf not found for {ENTRY['name']} (looked under biomni_workflows/ and repo root)")

    h = workflow_hash(ENTRY)
    existing = conn.execute(
        "SELECT id, executable FROM workflows WHERE name = ? OR filename = ? OR workflow_hash = ?",
        (ENTRY["name"], ENTRY["filename"], h),
    ).fetchone()
    if existing:
        if existing["executable"] != 1:
            conn.execute("UPDATE workflows SET executable=1 WHERE id=?", (existing["id"],))
            conn.commit()
            print(f"UPDATED existing row id={existing['id']} -> executable=1")
        else:
            print(f"SKIP: already present + executable=1 (id={existing['id']})")
        conn.close()
        return

    nf_content = nf_path.read_text(encoding="utf-8")
    conn.execute(
        """
        INSERT INTO workflows
            (name, filename, description, annotation, tags, domain, category,
             docker_image, input_types, output_types, step_count, tools_used,
             format, executable, source, workflow_hash, workflow_json)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """,
        (
            ENTRY["name"], ENTRY["filename"], ENTRY["description"], ENTRY["annotation"],
            ENTRY["tags"], ENTRY["domain"], ENTRY["category"], ENTRY["docker_image"],
            ",".join(ENTRY["input_types"]), ",".join(ENTRY["output_types"]),
            ENTRY["step_count"], ENTRY["tools_used"], "nextflow", 1, "biomate-ai-tools",
            h, nf_content,
        ),
    )
    conn.commit()
    rebuild_fts(conn)
    conn.commit()
    conn.close()
    print(f"ADDED {ENTRY['name']} (executable=1) to {db_path}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--db", type=Path, default=DB_DEFAULT)
    p.add_argument("--allow-stub", action="store_true",
                   help="override the stub clobber-guard (DANGEROUS — see header)")
    a = p.parse_args()
    register(a.db, a.allow_stub)
