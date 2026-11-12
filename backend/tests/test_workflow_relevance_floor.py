"""Relevance floor (docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md §4).

Loaded by file path so it runs without importing the galaxy.ai package (scipy-heavy __init__).
"""
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace as M

HERE = Path(__file__).resolve()
_spec = importlib.util.spec_from_file_location(
    "workflow_relevance", HERE.parents[1] / "lib/galaxy/ai/workflow_relevance.py")
wr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wr)


def m(name, score, id_=1):
    return M(name=name, score=score, id=id_, match_type="high_confidence")


def test_unrelated_top_hit_is_rejected_with_honest_reason():
    v = wr.workflow_relevance_verdict([m("mmuphin", 28.1), m("Estimate Alpha Particle Radiotherapy Dosimetry", 25.5)], 28.1)
    assert v["reject"] and "relevance floor" in v["reason"]
    assert "won't attach an unrelated one" in v["message"]


def test_relevant_hit_is_kept():
    v = wr.workflow_relevance_verdict([m("nf-core/rnaseq", 110.2)], 110.2)
    assert not v["reject"] and v["promote"] is None


def test_input_incompatible_top_hit_promotes_compatible_one():
    a, b = m("nf-core/diaproteomics", 90, 1), m("protein_table_de", 70, 2)
    v = wr.workflow_relevance_verdict([a, b], 90, input_compatible=lambda r: r.id != 1)
    assert not v["reject"] and v["promote"] is b


def test_all_incompatible_is_rejected():
    v = wr.workflow_relevance_verdict([m("raw_only", 90, 1)], 90, input_compatible=lambda r: False)
    assert v["reject"] and "data kind" in v["reason"]


def test_unknown_compatibility_is_allowed():
    assert not wr.workflow_relevance_verdict([m("x", 60)], 60, input_compatible=lambda r: None)["reject"]


def test_floor_separates_the_recorded_calibration_set():
    """Scores recorded by scripts/routing_replay (real classifier subQuery/key_terms → catalog search)."""
    path = HERE.parents[2] / "scripts/routing_replay/out/calib_scores.jsonl"
    if not path.exists():
        return
    rows = [json.loads(l) for l in path.read_text().splitlines() if l.strip()]
    positives = [r["score"] for r in rows if r["final"] == "workflow"]
    junk = [r["score"] for r in rows if r["final"] == "direct_compute" and r["id"].startswith(("F", "DC")) and r["id"] not in ("DC5", "DC8")]
    assert positives and junk
    assert min(positives) >= wr.WORKFLOW_RELEVANCE_FLOOR > max(junk)


def test_card_swap_candidates_exclude_below_floor_hits():
    # Step 6c may move the card to a candidate the reply names; a sub-floor hit must not be one.
    hits = [m("nf-core/rnaseq", 110.2), m("mmuphin", 28.1), m("nf-core/differentialabundance", 61.0)]
    names = [r.name for r in wr.relevant_candidates(hits)]
    assert names == ["nf-core/rnaseq", "nf-core/differentialabundance"]
    assert wr.relevant_candidates([m("mmuphin", 28.1)]) == []
