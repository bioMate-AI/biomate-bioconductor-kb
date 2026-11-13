"""Durable self-healing input_kinds migration (2026-11-13).

Default contract (post DEV clobber + [] follow-up): fill ONLY NULL/whitespace-empty
rows on schema init. Intentional classifier JSON ``[]`` ("cannot determine") is left
alone. Never mass-overwrite a populated classifier/LLM catalog. Destructive rewrite of
rule/null-method rows requires BIOMATE_INPUT_KINDS_DESTRUCTIVE_HEAL=1.
"""
import json
import sqlite3
import sys
import time
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

# backend/conftest.py installs a minimal unified_workflow_search stub (avoid SIGFPE on
# AIAssistant import). Evict it and stub optional embed deps so this file loads the REAL
# heal implementation under test.
if "numpy" not in sys.modules:
    _np = types.ModuleType("numpy")
    _np.ndarray = type("ndarray", (), {})  # type: ignore[attr-defined]
    sys.modules["numpy"] = _np
if "sentence_transformers" not in sys.modules:
    sys.modules["sentence_transformers"] = types.ModuleType("sentence_transformers")
sys.modules.pop("galaxy.ai.unified_workflow_search", None)

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
    synced to dev/prod as a binary). Returns the path; the NEXT init must self-heal it.

    preset maps id -> list[str] OR (list[str], method) to seed an existing label with provenance."""
    db = tmp_path / "wf.db"
    UnifiedWorkflowSearch(db_path=db)  # creates full schema incl input_kinds + ai_meta
    conn = sqlite3.connect(str(db))
    for (wid, name, fn, desc, dom) in _ROWS:
        conn.execute("INSERT INTO workflows(id,name,filename,description,domain,input_types,tags,"
                     "tools_used,executable,input_kinds) VALUES (?,?,?,?,?,'[]','[]','[]',1,NULL)",
                     (wid, name, fn, desc, dom))
    if preset:
        for wid, spec in preset.items():
            val, method = spec if isinstance(spec, tuple) else (spec, None)
            conn.execute("UPDATE workflows SET input_kinds=?, input_kinds_method=? WHERE id=?",
                         (json.dumps(val), method, wid))
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


def test_llm_values_are_never_clobbered_by_rule_heal(tmp_path):
    # id=2 carries an LLM label (method='llm') BEFORE the heal; the rule pass must NEVER touch it,
    # even on a version bump — LLM refinements always survive a rule correction.
    db = _db_with_null_rows(tmp_path, preset={2: (["protein_table"], "llm")})
    UnifiedWorkflowSearch(db_path=db)
    conn = sqlite3.connect(str(db))
    row = conn.execute("SELECT input_kinds, input_kinds_method FROM workflows WHERE id=2").fetchone()
    assert json.loads(row[0]) == ["protein_table"] and row[1] == "llm"
    assert json.loads(conn.execute("SELECT input_kinds FROM workflows WHERE id=1").fetchone()[0]) == ["molecules", "structure"]
    conn.close()


def test_populated_catalog_is_not_mass_overwritten(tmp_path):
    """Regression for 2026-11-13 DEV clobber: review-style catalog (meaningful kinds, method NULL)
    must survive schema init / version-marker absence without mass rewrite."""
    # Review-like seeds: classifier labels with no input_kinds_method provenance.
    preset = {
        1: (["molecules"], None),           # would become molecules+structure under rules
        2: (["protein_table"], None),       # stale vs rule tabular — must KEEP
        3: (["counts_matrix"], None),       # incomplete vs rule fastq — must KEEP
        4: ([], None),                      # intentional [] — must KEEP (cannot determine)
    }
    db = _db_with_null_rows(tmp_path, preset=preset)
    before = {}
    conn = sqlite3.connect(str(db))
    for wid, kinds in conn.execute("SELECT id, input_kinds FROM workflows").fetchall():
        before[wid] = kinds
    conn.close()

    UnifiedWorkflowSearch(db_path=db)

    conn = sqlite3.connect(str(db))
    after = dict(conn.execute("SELECT id, input_kinds FROM workflows").fetchall())
    # Meaningful non-empty labels unchanged (including wrong/stale ones).
    assert json.loads(after[1]) == ["molecules"]
    assert json.loads(after[2]) == ["protein_table"]
    assert json.loads(after[3]) == ["counts_matrix"]
    assert json.loads(after[4]) == []  # intentional empty array preserved
    # Provenance must stay NULL — do not stamp 'rule' onto classifier leftovers.
    methods = dict(conn.execute("SELECT id, input_kinds_method FROM workflows").fetchall())
    assert methods[1] is None and methods[2] is None and methods[3] is None and methods[4] is None
    # Marker stamped so a later init does not re-scan.
    v = conn.execute("SELECT value FROM ai_meta WHERE key='rule_input_kinds_version'").fetchone()
    assert v and str(v[0]) == str(_RULE_INPUT_KINDS_VERSION)
    conn.close()
    assert before[1] == after[1] and before[2] == after[2] and before[3] == after[3] and before[4] == after[4]


def test_empty_bracket_rows_left_alone_in_fill_only(tmp_path):
    """JSON ``[]`` is intentional classifier output — fill-only must NOT overwrite it.
    NULL siblings still get filled."""
    db = _db_with_null_rows(tmp_path, preset={
        1: (["molecules"], None),
        2: ([], None),  # intentional [] — must stay []
        # id=3 stays NULL from seed → fill with fastq
    })
    UnifiedWorkflowSearch(db_path=db)
    conn = sqlite3.connect(str(db))
    assert json.loads(conn.execute("SELECT input_kinds FROM workflows WHERE id=1").fetchone()[0]) == ["molecules"]
    assert json.loads(conn.execute("SELECT input_kinds FROM workflows WHERE id=2").fetchone()[0]) == []
    assert conn.execute("SELECT input_kinds_method FROM workflows WHERE id=2").fetchone()[0] is None
    assert "fastq" in json.loads(conn.execute("SELECT input_kinds FROM workflows WHERE id=3").fetchone()[0])
    assert conn.execute("SELECT input_kinds_method FROM workflows WHERE id=3").fetchone()[0] == "rule"
    conn.close()


def test_rule_origin_values_are_corrected_only_with_destructive_flag(tmp_path, monkeypatch):
    # Without the flag, stale rule labels must NOT be rewritten (same as populated null-method).
    db = _db_with_null_rows(tmp_path, preset={2: (["fastq"], "rule")})
    monkeypatch.delenv("BIOMATE_INPUT_KINDS_DESTRUCTIVE_HEAL", raising=False)
    UnifiedWorkflowSearch(db_path=db)
    conn = sqlite3.connect(str(db))
    row = conn.execute("SELECT input_kinds, input_kinds_method FROM workflows WHERE id=2").fetchone()
    assert json.loads(row[0]) == ["fastq"] and row[1] == "rule"
    conn.close()

    # With the flag, rule-origin rows are recomputed on the next version pass.
    conn = sqlite3.connect(str(db))
    conn.execute("DELETE FROM ai_meta WHERE key='rule_input_kinds_version'")
    conn.commit(); conn.close()
    monkeypatch.setenv("BIOMATE_INPUT_KINDS_DESTRUCTIVE_HEAL", "1")
    UnifiedWorkflowSearch(db_path=db)
    conn = sqlite3.connect(str(db))
    row = conn.execute("SELECT input_kinds, input_kinds_method FROM workflows WHERE id=2").fetchone()
    assert json.loads(row[0]) == ["tabular"] and row[1] == "rule"
    conn.close()


def test_startup_cost_is_bounded_after_first_heal(tmp_path):
    db = _db_with_null_rows(tmp_path)
    UnifiedWorkflowSearch(db_path=db)  # first heal
    t0 = time.perf_counter()
    for _ in range(10):
        UnifiedWorkflowSearch(db_path=db)  # should all short-circuit on the version marker
    elapsed = time.perf_counter() - t0
    assert elapsed < 5.0, f"repeated init too slow ({elapsed:.2f}s) — self-heal likely re-running"
