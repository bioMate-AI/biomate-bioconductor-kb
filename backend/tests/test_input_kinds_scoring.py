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


def test_malformed_penalty_env_falls_back_instead_of_crashing(monkeypatch):
    from galaxy.ai.unified_workflow_search import _env_float
    monkeypatch.setenv("BIOMATE_INPUT_KIND_MISMATCH_PENALTY", "twenty-five")
    assert _env_float("BIOMATE_INPUT_KIND_MISMATCH_PENALTY", 25.0) == 25.0


def test_kinds_load_error_is_not_cached(tmp_path):
    s = _search(tmp_path)
    s._input_kinds_cache = None
    import sqlite3 as _sq
    orig = _sq.connect
    try:
        _sq.connect = lambda *a, **k: (_ for _ in ()).throw(_sq.OperationalError("locked"))
        assert s._input_kinds_map() == {}
    finally:
        _sq.connect = orig
    assert getattr(s, "_input_kinds_cache", None) is None  # retried next time, not stuck empty


def _score_k(s, query, wf_kinds, user_kinds):
    return s._calculate_score(query, "wf", "", [], [], "bioconductor", "proteomics", 0.0,
                              input_types=["input"], input_kinds=wf_kinds, user_input_kinds=user_kinds)


def test_classifier_kinds_override_text_detection(tmp_path):
    s = _search(tmp_path)
    raw = frozenset({"raw_spectra"})
    neg = "I don't have the raw .raw files any more, only the MaxQuant proteinGroups.txt."
    # The text regex ignores negation: it detects raw_spectra in "I don't have the raw files" and gives the
    # raw-spectra pipeline the +3 match bonus — the committee's finding. The classifier's kinds penalise it.
    assert _score_k(s, neg, raw, None) == _score_k(s, neg, None, None) + 3.0
    assert _score_k(s, neg, raw, ["protein_table"]) == _score_k(s, neg, None, None) - _PEN
    # [] = the user states no input data: the regex is not consulted (no false mismatch)
    assert _score_k(s, Q_TABLE, raw, []) == _score_k(s, Q_TABLE, None, [])
    # out-of-vocabulary values are ignored
    assert _score_k(s, Q_TABLE, raw, ["mzml"]) == _score_k(s, Q_TABLE, None, [])


def test_input_compatible_prefers_classifier_kinds(tmp_path):
    s = _search(tmp_path)
    s._input_kinds_map = lambda: {1: frozenset({"raw_spectra"})}
    assert s.input_compatible("I have Thermo .raw files", 1) is True
    assert s.input_compatible("I have Thermo .raw files", 1, user_input_kinds=["protein_table"]) is False
    assert s.input_compatible(Q_TABLE, 1, user_input_kinds=[]) is None


# ── Data-grounded input kinds (from the user's ACTUALLY-attached datasets) ──────
# The principled processed-vs-raw fix: user_input_kinds derived from the profiled shape of attached
# datasets (data_perception.infer_input_kinds, threaded from the generate_workflow endpoint) make
# step 8a fire GENERALLY — not from the prose guess. The prose here is deliberately modality-only
# ("DIA proteomics") with NO processed-table / raw-file wording, so text detection is silent and ONLY
# the attached-data kinds drive the raw-vs-processed decision. docs 2026-11-09.
Q_MODALITY_ONLY = "Analyse my DIA proteomics data and report the quantities."  # no raw/processed cue


def test_attached_processed_table_demotes_raw_and_boosts_processed(tmp_path):
    # (a) user with an abundance/protein TABLE attached → raw pipeline demoted, table method boosted.
    s = _search(tmp_path)
    attached = ["protein_table", "counts_matrix"]  # what infer_input_kinds() returns for an abundance table
    neutral_raw = _score_k(s, Q_MODALITY_ONLY, frozenset({"raw_spectra"}), None)
    data_raw = _score_k(s, Q_MODALITY_ONLY, frozenset({"raw_spectra"}), attached)
    assert neutral_raw - data_raw == _PEN  # diaproteomics (raw_spectra) can't consume the table
    neutral_tab = _score_k(s, Q_MODALITY_ONLY, frozenset({"counts_matrix", "h5ad"}), None)
    data_tab = _score_k(s, Q_MODALITY_ONLY, frozenset({"counts_matrix", "h5ad"}), attached)
    assert data_tab - neutral_tab == 3.0  # differentialabundance (counts_matrix) is compatible


def test_attached_raw_files_do_not_demote_raw_pipeline(tmp_path):
    # (b) user with raw FASTQ / spectra attached → the raw processing pipeline is NOT demoted.
    s = _search(tmp_path)
    q = "Run RNA-seq expression analysis."  # no file-type wording; kinds come from the attachment
    neutral = _score_k(s, q, frozenset({"fastq"}), None)
    data = _score_k(s, q, frozenset({"fastq"}), ["fastq"])
    assert data - neutral == 3.0  # fastq attached → nf-core/rnaseq (fastq) matches, never penalised
    # raw spectra attached → diaproteomics (raw_spectra) matches, not demoted
    assert _score_k(s, q, frozenset({"raw_spectra"}), ["raw_spectra"]) \
        == _score_k(s, q, frozenset({"raw_spectra"}), None) + 3.0
