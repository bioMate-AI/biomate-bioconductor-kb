"""Downstream multi-omics integration guard (step 8c of UnifiedWorkflowSearch._calculate_score).

A real cancer multi-omics user (docs/20261109 issue #2, "U-MOFA") already had processed RNA-seq DE
tables + proteomics abundance tables and wanted downstream integration (overlap, concordant/discordant
log2FC, enrichment, MOFA2). Routing keyed on the "proteomics" modality and kept selecting the RAW
pipeline nf-core/diaproteomics; the user had to forbid it twice. Step 8c detects the
"processed tables + integrate" intent deterministically: it down-ranks raw-only pipelines and up-ranks
integration workflows — and, unlike the input-kind term (8a), it also fires when the query names no
explicit input kind ("integrate my DE tables, find overlapping genes with MOFA").

Run: cd backend && PYTHONPATH=lib pytest tests/test_integration_intent_routing.py -v
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from galaxy.ai.unified_workflow_search import (  # noqa: E402
    _INTEGRATION_RAW_PENALTY as _RAW_PEN,
    _INTEGRATION_WF_BOOST as _BOOST,
)

# The issue's canonical ask. Mentions "protein-abundance tables" → 8a also sees protein_table.
CANON = ("Integrate my processed DE and protein-abundance tables; "
         "find concordant/discordant genes and enriched pathways")
# DE-only variant: no explicit input-kind is detectable (8a is silent here) — only 8c can act.
DE_ONLY = ("Integrate my DE tables and differential expression results; "
           "find overlapping genes with MOFA")


def _search(tmp_path):
    return UnifiedWorkflowSearch(db_path=tmp_path / "wf.db")


def _score(s, query, name, domain, kinds):
    return s._calculate_score(query, name, "", [], [], "nfcore", domain, 0.0,
                              input_types=["input"], input_kinds=kinds)


# ── Intent detector ───────────────────────────────────────────────────────────

def test_integration_intent_fires_on_processed_table_plus_integrate(tmp_path):
    s = _search(tmp_path)
    assert s._detect_integration_intent(CANON) is True
    assert s._detect_integration_intent(DE_ONLY) is True  # no input-kind, but intent is unambiguous


def test_integration_intent_abstains_without_both_signals(tmp_path):
    s = _search(tmp_path)
    # Raw-data request → must stay on the raw pipeline (no processed-table term).
    assert s._detect_integration_intent("Run DIA proteomics on my Thermo .raw files") is False
    assert s._detect_integration_intent("Integrate these FASTQ files into one pipeline") is False
    # Processed table but no integration ask → the plain DE method is still correct (8a/other terms own it).
    assert s._detect_integration_intent("Find differentially abundant proteins in my proteinGroups.txt") is False


def test_integration_workflow_predicate(tmp_path):
    s = _search(tmp_path)
    assert s._is_integration_workflow("nf-core/differentialabundance", "", "transcriptomics", None) is True
    assert s._is_integration_workflow("mofa2", "MOFA multi-omics factor analysis", "systems_biology", None) is True
    assert s._is_integration_workflow("gintomics_complete_multiomics_integration", "", "systems_biology", None) is True
    assert s._is_integration_workflow("nf-core/diaproteomics", "DIA proteomics pipeline", "proteomics", None) is False
    assert s._is_integration_workflow("nf-core/rnaseq", "RNA-seq alignment + quantification", "transcriptomics", None) is False


# ── Behavioural: integration beats raw on the issue's query ───────────────────

def test_integration_workflow_outranks_raw_pipeline_on_canonical_query(tmp_path):
    s = _search(tmp_path)
    raw = _score(s, CANON, "nf-core/diaproteomics", "proteomics", frozenset({"raw_spectra"}))
    integ = _score(s, CANON, "nf-core/differentialabundance", "transcriptomics",
                   frozenset({"counts_matrix", "h5ad"}))
    mofa = _score(s, CANON, "mofa2", "systems_biology", frozenset({"counts_matrix"}))
    assert integ > raw
    assert mofa > raw


def test_integration_beats_raw_even_without_detected_input_kind(tmp_path):
    # DE_ONLY detects no input kind → 8a is silent; 8c alone must still demote the raw pipeline.
    s = _search(tmp_path)
    raw = _score(s, DE_ONLY, "nf-core/diaproteomics", "proteomics", frozenset({"raw_spectra"}))
    integ = _score(s, DE_ONLY, "nf-core/differentialabundance", "transcriptomics",
                   frozenset({"counts_matrix", "h5ad"}))
    assert integ > raw


# ── Magnitude isolation (hold query + workflow constant; toggle only the guard) ─

def _score_named(s, name, domain, kinds):
    return s._calculate_score(CANON, name, "", [], [], "nfcore", domain, 0.0,
                              input_types=["input"], input_kinds=kinds)


def test_raw_only_pipeline_gets_exactly_the_penalty(tmp_path):
    s = _search(tmp_path)
    name, dom, kinds = "nf-core/diaproteomics", "proteomics", frozenset({"raw_spectra"})
    s._detect_integration_intent = lambda q: True
    on = _score_named(s, name, dom, kinds)
    s._detect_integration_intent = lambda q: False
    off = _score_named(s, name, dom, kinds)
    assert off - on == _RAW_PEN


def test_integration_workflow_gets_exactly_the_boost(tmp_path):
    s = _search(tmp_path)
    # counts_matrix is processed → no raw-only penalty, isolating the boost branch.
    name, dom, kinds = "nf-core/differentialabundance", "transcriptomics", frozenset({"counts_matrix"})
    s._detect_integration_intent = lambda q: True
    on = _score_named(s, name, dom, kinds)
    s._detect_integration_intent = lambda q: False
    off = _score_named(s, name, dom, kinds)
    assert on - off == _BOOST


def test_guard_is_inert_without_integration_intent(tmp_path):
    # A plain proteomics request (no integrate/overlap/MOFA) must not be perturbed by 8c.
    s = _search(tmp_path)
    q = "Find differentially abundant proteins in my proteinGroups.txt"
    assert s._detect_integration_intent(q) is False
    # Scoring the raw pipeline on this query is unchanged by the guard (it never fires).
    raw = s._calculate_score(q, "nf-core/diaproteomics", "", [], [], "nfcore", "proteomics", 0.0,
                             input_types=["input"], input_kinds=frozenset({"raw_spectra"}))
    s._detect_integration_intent = lambda _q: True  # if it HAD fired, score would drop
    raw_if_fired = s._calculate_score(q, "nf-core/diaproteomics", "", [], [], "nfcore", "proteomics", 0.0,
                                      input_types=["input"], input_kinds=frozenset({"raw_spectra"}))
    assert raw - raw_if_fired == _RAW_PEN  # proves the guard was inert on the real detector


def test_penalty_outweighs_source_priority_lead(tmp_path):
    # The raw pipeline's nfcore source priority (~6.7) must not let it survive the guard.
    assert _RAW_PEN > 6.7


# ── 8c demoted to a FALLBACK when the data shape is known (docs 2026-11-09) ──────
# When the user ATTACHED data, its profiled shape is threaded as user_input_kinds, step 8a's
# data-grounded compatibility is authoritative, and the prose keyword guard (8c) must stand down so
# the raw pipeline is not double-penalised. 8c still fires prose-only (no shape supplied).

def _score_uik(s, name, domain, kinds, user_input_kinds):
    return s._calculate_score(CANON, name, "", [], [], "nfcore", domain, 0.0,
                              input_types=["input"], input_kinds=kinds,
                              user_input_kinds=user_input_kinds)


def test_8c_suppressed_when_data_shape_known_no_double_penalty(tmp_path):
    s = _search(tmp_path)
    name, dom, kinds = "nf-core/diaproteomics", "proteomics", frozenset({"raw_spectra"})
    # Prose-only (CANON text detects protein_table): 8a (text) + 8c BOTH penalise the raw pipeline.
    prose = _score_uik(s, name, dom, kinds, None)
    # Data-grounded kinds supplied (user attached a processed table): 8a penalises ONCE, 8c stands down.
    data = _score_uik(s, name, dom, kinds, ["protein_table", "counts_matrix"])
    # The difference is exactly one _RAW_PEN — i.e. 8c's second penalty is gone, not doubled.
    assert data - prose == _RAW_PEN


def test_8c_still_fires_prose_only_fallback(tmp_path):
    # No kinds supplied (classifier returned nothing, nothing profilable): 8c remains the fallback.
    s = _search(tmp_path)
    raw = _score_uik(s, "nf-core/diaproteomics", "proteomics", frozenset({"raw_spectra"}), None)
    integ = _score_uik(s, "nf-core/differentialabundance", "transcriptomics",
                       frozenset({"counts_matrix", "h5ad"}), None)
    assert integ > raw  # the prose keyword guard still demotes raw / prefers integration


def test_8c_suppressed_also_up_rank_handled_by_8a(tmp_path):
    # With data-grounded counts_matrix, the integration workflow is preferred via 8a's +3 overlap
    # (not 8c's boost), and the raw pipeline is demoted via 8a's penalty — all without 8c.
    s = _search(tmp_path)
    uik = ["counts_matrix"]
    raw = _score_uik(s, "nf-core/diaproteomics", "proteomics", frozenset({"raw_spectra"}), uik)
    integ = _score_uik(s, "nf-core/differentialabundance", "transcriptomics",
                       frozenset({"counts_matrix", "h5ad"}), uik)
    assert integ > raw


# ── 8c BOOST preserved for UNLABELLED integration workflows even when a shape is known ──
# Finding 4 (committee review 2026-11-09): gating ALL of 8c on `not _user_shape_known` silently
# dropped the +6 up-rank for an UNLABELLED integration workflow (input_kinds NULL → 8a's
# `if input_kinds:` skips it, so 8a can't boost it either). The boost must survive; only the raw
# PENALTY is suppressed when a shape is known (8a owns it — no double-penalty).

def test_8c_boost_preserved_for_unlabelled_integration_when_shape_known(tmp_path):
    s = _search(tmp_path)
    # Processed table attached → shape known. An UNLABELLED integration workflow (input_kinds NULL).
    uik = ["counts_matrix"]
    name, dom = "gintomics_complete_multiomics_integration", "systems_biology"
    s._detect_integration_intent = lambda q: True
    on = s._calculate_score(CANON, name, "", [], [], "nfcore", dom, 0.0,
                            input_types=["input"], input_kinds=None, user_input_kinds=uik)
    s._detect_integration_intent = lambda q: False
    off = s._calculate_score(CANON, name, "", [], [], "nfcore", dom, 0.0,
                             input_types=["input"], input_kinds=None, user_input_kinds=uik)
    assert on - off == _BOOST  # the +6 up-rank still fires despite the known shape


def test_8c_no_double_boost_for_labelled_integration_when_shape_known(tmp_path):
    # A LABELLED integration workflow is already up-ranked by 8a's +3 overlap when the shape is
    # known; 8c must NOT also +6 it (that would double-count). Toggling the detector changes nothing.
    s = _search(tmp_path)
    uik = ["counts_matrix"]
    name, dom, kinds = "nf-core/differentialabundance", "transcriptomics", frozenset({"counts_matrix", "h5ad"})
    s._detect_integration_intent = lambda q: True
    on = s._calculate_score(CANON, name, "", [], [], "nfcore", dom, 0.0,
                            input_types=["input"], input_kinds=kinds, user_input_kinds=uik)
    s._detect_integration_intent = lambda q: False
    off = s._calculate_score(CANON, name, "", [], [], "nfcore", dom, 0.0,
                             input_types=["input"], input_kinds=kinds, user_input_kinds=uik)
    assert on == off  # 8c inert for labelled workflows once the shape is known (8a handled it)


def test_8c_unlabelled_integration_outranks_raw_with_known_shape(tmp_path):
    # End-to-end: processed table attached. The UNLABELLED integration workflow (boosted by 8c) must
    # still beat the raw-only pipeline (demoted by 8a's penalty, NOT double-penalised by 8c).
    s = _search(tmp_path)
    uik = ["counts_matrix"]
    raw = _score_uik(s, "nf-core/diaproteomics", "proteomics", frozenset({"raw_spectra"}), uik)
    integ_unlabelled = _score_uik(s, "gintomics_complete_multiomics_integration", "systems_biology",
                                  None, uik)
    assert integ_unlabelled > raw
