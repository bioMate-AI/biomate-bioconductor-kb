#!/usr/bin/env python3
"""
register_wsi_pathology.py

Registers the pathology/wsi_he_nuclei_segmentation workflow in the workflows DB
(it is on disk + validated end-to-end on Batch, but has no DB row, so the AI
router can't surface it). Adds the row with executable=1 and rebuilds FTS.
Idempotent (skips if already present). Follows register_missing_biomate_workflows.py.

⚠️ CLOBBER WARNING — READ BEFORE RUNNING ⚠️
The canonical workflows DB (~328 MB) lives on dev + S3 and carries the
`workflow_embeddings` used for vector search. A fresh local checkout's
backend/database/galaxy_ai_tools.db is a STUB with `workflow_embeddings` = 0 rows.
`scripts/sync_to_dev.sh` REPLACES dev's DB with the local one when their MD5s
differ (it keeps a .bak). So:

  DO NOT run this against the local stub and then sync — that uploads a
  zero-embedding DB and clobbers dev's vector search for ALL workflows.

Safe procedure (preserves every other row's embedding; registration does NOT
touch embeddings — those are enriched separately on dev):
  1. Fetch the ENRICHED dev DB to local, replacing the stub:
       # the sync stages it at s3://biomate-nextflow-outputs/tmp/db-sync/ during a deploy;
       # or copy from the dev container /opt/biomate/galaxy_db/galaxy_ai_tools.db
       aws s3 cp s3://.../galaxy_ai_tools.db backend/database/galaxy_ai_tools.db
     Confirm it is enriched, NOT a stub:
       python3 -c "import sqlite3;print(sqlite3.connect('backend/database/galaxy_ai_tools.db').execute('SELECT COUNT(*) FROM workflow_embeddings').fetchone())"
     (must be > 0 — abort if it is 0.)
  2. python3 scripts/register_wsi_pathology.py   # adds the WSI row + FTS
  3. scripts/sync_to_dev.sh                       # uploads enriched+WSI DB (no clobber)
  4. (optional) run the workflow-embedding indexer on dev so WSI is vector-searchable;
     until then FTS/keyword routing still finds it.

This script HARD-REFUSES to run against a stub (workflow_embeddings == 0) unless
--allow-stub is passed, specifically to prevent the clobber above.

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

    # Clobber guard: refuse to touch a stub (0 embeddings) unless explicitly allowed,
    # because editing it + syncing would wipe dev's vector search.
    try:
        n_emb = conn.execute("SELECT COUNT(*) FROM workflow_embeddings").fetchone()[0]
    except sqlite3.Error:
        n_emb = None
    if n_emb == 0 and not allow_stub:
        conn.close()
        raise SystemExit(
            f"REFUSING: {db_path} has workflow_embeddings=0 (a STUB). Registering here and "
            "syncing would clobber dev's vector search. Fetch the enriched dev DB first "
            "(see this script's header), or pass --allow-stub if you really mean it."
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
