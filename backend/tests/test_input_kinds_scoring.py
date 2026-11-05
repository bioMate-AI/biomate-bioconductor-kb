"""Input-kind compatibility term (step 8a of UnifiedWorkflowSearch._calculate_score).

A MaxQuant proteinGroups.txt request routed to nf-core/proteomicslfq (raw spectra) because that
pipeline's input_types is the placeholder ["input"], so the raw-vs-processed term never fired
(domain_retag A/B, 2026-11-05). input_kinds is a closed vocabulary labelled per workflow.

Run: cd backend && PYTHONPATH=lib pytest tests/test_input_kinds_scoring.py -v
"""
import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from galaxy.ai.chain_composer.input_kinds_classifier import INPUT_KINDS, parse_kinds  # noqa: E402
from galaxy.ai.unified_workflow_search import _INPUT_KIND_MISMATCH_PENALTY as _PEN  # noqa: E402

Q_TABLE = "I have a MaxQuant proteinGroups.txt from label-free LC-MS/MS, 3 KO vs 3 WT. Find the differentially abundant proteins."


def _search(tmp_path):
    return UnifiedWorkflowSearch(db_path=tmp_path / "wf.db")


def _score(s, query, kinds, input_types=None):
    return s._calculate_score(query, "wf", "", [], [], "bioconductor", "proteomics", 0.0,
                              input_types=input_types or ["input"], input_kinds=kinds)


def test_processed_table_penalises_raw_only_pipeline_and_boosts_table_method(tmp_path):
    s = _search(tmp_path)
    raw = _score(s, Q_TABLE, frozenset({"raw_spectra"}))
    table = _score(s, Q_TABLE, frozenset({"protein_table"}))
    neutral = _score(s, Q_TABLE, None)
    assert table - neutral == 3.0
    assert neutral - raw == _PEN


def test_workflow_accepting_raw_and_processed_is_not_penalised(tmp_path):
    s = _search(tmp_path)
    both = frozenset({"raw_spectra", "peptide_table"})
    assert _score(s, Q_TABLE, both) == _score(s, Q_TABLE, None)


def test_raw_data_penalises_table_only_method(tmp_path):
    s = _search(tmp_path)
    q = "Quantify proteins from my Thermo raw files (.raw) and test KO vs WT."
    assert _score(s, q, frozenset({"protein_table"})) == _score(s, q, None) - _PEN
    assert _score(s, q, frozenset({"raw_spectra"})) == _score(s, q, None) + 3.0


def test_query_kinds_detection():
    k = UnifiedWorkflowSearch._query_input_kinds
    assert k(Q_TABLE) == {"protein_table"}  # "LC-MS/MS" alone is not raw-spectra data
    assert "peptide_table" in k("Run differential abundance on my DIA-NN precursor report")
    assert "beta_values" in k("EWAS on my EPIC array beta values")
    assert "idat" in k("Process these .idat files")
    assert k("What is DIA proteomics?") == frozenset()


def test_mismatch_penalty_outweighs_measured_fts_gap():
    assert _PEN > 24.0  # proteomicslfq's lexical lead on the MaxQuant proteinGroups request (docs §13.3)


def test_kind_sets_match_classifier_vocabulary():
    assert UnifiedWorkflowSearch._RAW_KINDS <= set(INPUT_KINDS)
    assert UnifiedWorkflowSearch._PROCESSED_KINDS <= set(INPUT_KINDS)
    assert set(UnifiedWorkflowSearch._QUERY_TYPE_TO_KIND.values()) <= set(INPUT_KINDS)


def test_input_kinds_map_reads_column_and_tolerates_bad_rows(tmp_path):
    s = _search(tmp_path)
    conn = sqlite3.connect(str(tmp_path / "wf.db"))
    cols = {r[1] for r in conn.execute("PRAGMA table_info(workflows)")}
    assert "input_kinds" in cols  # added by _migrate_schema
    conn.execute("INSERT INTO workflows(id, name, filename, workflow_json, input_kinds) VALUES (1, 'a', 'a.nf', '{}', ?)", (json.dumps(["raw_spectra"]),))
    conn.execute("INSERT INTO workflows(id, name, filename, workflow_json, input_kinds) VALUES (2, 'b', 'b.nf', '{}', 'not json')")
    conn.execute("INSERT INTO workflows(id, name, filename, workflow_json, input_kinds) VALUES (3, 'c', 'c.nf', '{}', '[]')")
    conn.commit(); conn.close()
    s._input_kinds_cache = None
    m = s._input_kinds_map()
    assert m == {1: frozenset({"raw_spectra"})}


def test_parse_kinds_rejects_out_of_vocabulary():
    assert parse_kinds('{"input_kinds": ["protein_table"], "reason": "x"}')["input_kinds"] == ["protein_table"]
    assert parse_kinds('{"input_kinds": ["mzml"]}') is None
    assert parse_kinds("not json") is None


def test_input_compatible_for_card_swap_guard(tmp_path):
    s = _search(tmp_path)
    s._input_kinds_cache = None
    s._input_kinds_map = lambda: {1: frozenset({"raw_spectra"}), 2: frozenset({"protein_table"}),
                                  3: frozenset({"raw_spectra", "peptide_table"})}
    assert s.input_compatible(Q_TABLE, 1) is False   # protein table → raw-spectra-only pipeline
    assert s.input_compatible(Q_TABLE, 2) is True
    assert s.input_compatible(Q_TABLE, 3) is True    # accepts both regimes
    assert s.input_compatible("What is DIA proteomics?", 1) is None  # no explicit data kind
    assert s.input_compatible(Q_TABLE, 99) is None   # workflow without kinds
