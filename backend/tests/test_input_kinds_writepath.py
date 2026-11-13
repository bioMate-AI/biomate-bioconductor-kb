"""Step 2 of the 2026-11-12 example-routing fix: input_kinds is a FIRST-CLASS, DURABLE field of
the write path. The deterministic rule labeler runs at INSERT time so re-indexing a source
PRESERVES the data-shape gate instead of reverting input_kinds to NULL (a one-shot UPDATE backfill
would silently revert on the next re-index).
"""
import importlib.util
import json
import sqlite3
from pathlib import Path

import pytest

from galaxy.ai.chain_composer.input_kinds_classifier import rule_classify_kinds

_SCRIPTS = Path(__file__).resolve().parents[1] / "scripts" / "index_all_workflows.py"


def _load_indexer():
    spec = importlib.util.spec_from_file_location("iaw_under_test", _SCRIPTS)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


# ── Rule labeler (precision over recall) ─────────────────────────────────────

def test_labels_docking_as_structure_and_molecules():
    kinds = rule_classify_kinds({
        "name": "Dock Ligands With AutoDock Vina",
        "description": "Molecular docking of a SMILES ligand library against a receptor PDB structure.",
        "input_types": "[]", "annotation": "", "tags": "[]",
    })
    assert kinds == ["molecules", "structure"]


def test_labels_assay_ranker_as_tabular_only():
    # The incident mis-match (id 12814). It ingests a CSV assay table — NOT molecules/structure.
    kinds = rule_classify_kinds({
        "name": "Assay Ingestion And Ranking",
        "description": "Ingest multi-assay compound data; parse CSV assay data, normalise BCR-ABL1 "
                       "IC50 and hERG IC50, compute weighted composite score, rank compounds.",
        "input_types": "[]", "annotation": "", "tags": "[]",
    })
    assert kinds == ["tabular"]


def test_labels_rnaseq_as_fastq():
    kinds = rule_classify_kinds({
        "name": "nf-core/rnaseq", "description": "RNA-seq from raw FASTQ reads to a gene count matrix.",
        "input_types": "[]", "annotation": "", "tags": "[]",
    })
    assert "fastq" in kinds


def test_uncertain_row_returns_none_not_a_guess():
    assert rule_classify_kinds({"name": "Utility", "description": "A generic helper.",
                                "input_types": "[]", "annotation": "", "tags": "[]"}) is None
    assert rule_classify_kinds({"name": "", "description": "", "input_types": "", "annotation": "", "tags": ""}) is None


# ── Write-path ownership: re-index preserves non-null input_kinds ─────────────

_COLS = ("name,filename,description,annotation,tags,domain,workflow_json,step_count,tools_used,"
         "source,format,executable,docker_image,category,workflow_hash,indexed_at,input_types,"
         "output_types,input_kinds")


def _fresh_db(tmp_path: Path) -> Path:
    db = tmp_path / "wf.db"
    conn = sqlite3.connect(str(db))
    # Schema WITHOUT input_kinds — proves _ensure_input_kinds_column adds it (old DB).
    conn.execute(f"CREATE TABLE workflows (id INTEGER PRIMARY KEY AUTOINCREMENT, "
                 f"{','.join(c + ' TEXT' for c in _COLS.split(',') if c != 'input_kinds')})")
    conn.commit(); conn.close()
    return db


def _insert_docking(iaw, cursor, suffix=""):
    iaw._wf_insert(
        cursor, name="Dock Ligands" + suffix, filename="pharm/dock/main.nf" + suffix,
        description="Molecular docking of a SMILES ligand library against a receptor PDB structure.",
        annotation="", tags="[]", domain="drug_discovery", workflow_json="{}", step_count=1,
        tools_used="[]", source="biomni_nextflow", format_="nextflow", workflow_hash="h" + suffix,
        indexed_at="now", input_types=["receptor", "ligand_library"], output_types=["poses"],
    )


def test_reindex_preserves_non_null_input_kinds(tmp_path):
    iaw = _load_indexer()
    db = _fresh_db(tmp_path)
    conn = sqlite3.connect(str(db)); cur = conn.cursor()

    _insert_docking(iaw, cur)
    conn.commit()
    row = cur.execute("SELECT input_kinds FROM workflows WHERE source='biomni_nextflow'").fetchone()
    assert row is not None and row[0] is not None, "write path must populate input_kinds"
    assert json.loads(row[0]) == ["molecules", "structure"]

    # Simulate a re-index of this source: DELETE then re-insert through the SAME write path.
    cur.execute("DELETE FROM workflows WHERE source=?", ("biomni_nextflow",))
    conn.commit()
    _insert_docking(iaw, cur)
    conn.commit()
    row2 = cur.execute("SELECT input_kinds FROM workflows WHERE source='biomni_nextflow'").fetchone()
    assert row2 is not None and row2[0] is not None, "re-index must NOT revert input_kinds to NULL"
    assert json.loads(row2[0]) == ["molecules", "structure"]
    conn.close()
