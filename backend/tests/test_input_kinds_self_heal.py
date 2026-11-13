"""Durable self-healing input_kinds migration (2026-11-13). The rule backfill must run
automatically at schema init so ANY DB (dev/prod) gains rule coverage on deploy with NO manual
step — the catalog DB is gitignored, so a one-shot local backfill would otherwise live only on the
laptop. Requirements: labels only NULL rows, never clobbers an existing value, idempotent (second
run is a no-op via the version marker), bounded startup.
"""
import json
import sqlite3
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch, _RULE_INPUT_KINDS_VERSION  # noqa: E402

_ROWS = [
    (1, "Dock Ligands", "d.nf", "Molecular docking of a SMILES ligand library against a receptor PDB.", "drug_discovery"),
    (2, "Assay Ingestion And Ranking", "a.nf", "Parse CSV assay data, BCR-ABL1 IC50 and hERG IC50, composite score.", "drug_discovery"),
    (3, "nf-core rnaseq", "r.nf", "RNA-seq from raw FASTQ reads to a gene count matrix.", "transcriptomics"),
    (4, "Mystery Utility", "m.nf", "A generic helper with no recognisable inputs.", "general"),
]


def _db_with_null_rows(tmp_path, preset=None):
    """Build a DB with the real schema (via one init), insert rows with NULL input_kinds, then
    DELETE the version marker to simulate a DB built BEFORE this migration version (e.g. a DB
    synced to dev/prod as a binary). Returns the path; the NEXT init must self-heal it."""
    db = tmp_path / "wf.db"
    UnifiedWorkflowSearch(db_path=db)  # creates full schema incl input_kinds + ai_meta
    conn = sqlite3.connect(str(db))
    for (wid, name, fn, desc, dom) in _ROWS:
        conn.execute("INSERT INTO workflows(id,name,filename,description,domain,input_types,tags,"
                     "tools_used,executable,input_kinds) VALUES (?,?,?,?,?,'[]','[]','[]',1,NULL)",
                     (wid, name, fn, desc, dom))
    if preset:
        for wid, val in preset.items():
            conn.execute("UPDATE workflows SET input_kinds=? WHERE id=?", (json.dumps(val), wid))
    conn.execute("DELETE FROM ai_meta WHERE key='rule_input_kinds_version'")
    conn.commit(); conn.close()
    return db


def test_fresh_db_self_heals_on_init(tmp_path):
    db = _db_with_null_rows(tmp_path)
    UnifiedWorkflowSearch(db_path=db)  # init triggers _migrate_schema → _self_heal_input_kinds
    conn = sqlite3.connect(str(db))
    got = dict(conn.execute("SELECT id, input_kinds FROM workflows").fetchall())
    assert json.loads(got[1]) == ["molecules", "structure"]  # docking
    assert json.loads(got[2]) == ["tabular"]                  # assay ranker
    assert "fastq" in json.loads(got[3])                      # rnaseq
    assert got[4] is None                                     # unlabelable → stays NULL
    v = conn.execute("SELECT value FROM ai_meta WHERE key='rule_input_kinds_version'").fetchone()
    assert v and str(v[0]) == str(_RULE_INPUT_KINDS_VERSION)
    conn.close()


def test_second_init_is_a_noop_and_does_not_reclassify(tmp_path):
    db = _db_with_null_rows(tmp_path)
    UnifiedWorkflowSearch(db_path=db)  # first heal → sets marker
    conn = sqlite3.connect(str(db))
    conn.execute("UPDATE workflows SET input_kinds=? WHERE id=1", (json.dumps(["SENTINEL"]),))
    conn.commit(); conn.close()
    UnifiedWorkflowSearch(db_path=db)  # second init — marker present → no re-run
    conn = sqlite3.connect(str(db))
    assert json.loads(conn.execute("SELECT input_kinds FROM workflows WHERE id=1").fetchone()[0]) == ["SENTINEL"]
    conn.close()


def test_existing_non_null_values_are_never_clobbered(tmp_path):
    # id=2 already carries an LLM-style label BEFORE the heal; the rule pass must not overwrite it.
    db = _db_with_null_rows(tmp_path, preset={2: ["protein_table"]})
    UnifiedWorkflowSearch(db_path=db)
    conn = sqlite3.connect(str(db))
    assert json.loads(conn.execute("SELECT input_kinds FROM workflows WHERE id=2").fetchone()[0]) == ["protein_table"]
    assert json.loads(conn.execute("SELECT input_kinds FROM workflows WHERE id=1").fetchone()[0]) == ["molecules", "structure"]
    conn.close()


def test_startup_cost_is_bounded_after_first_heal(tmp_path):
    db = _db_with_null_rows(tmp_path)
    UnifiedWorkflowSearch(db_path=db)  # first heal
    t0 = time.perf_counter()
    for _ in range(10):
        UnifiedWorkflowSearch(db_path=db)  # should all short-circuit on the version marker
    elapsed = time.perf_counter() - t0
    assert elapsed < 5.0, f"repeated init too slow ({elapsed:.2f}s) — self-heal likely re-running"
