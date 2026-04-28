"""
UX-layer tests for Docking auto-loop (DUX-1 to DUX-12).

Tests:
  DUX-1  to DUX-4:  KnowledgeEnrichedDockingTuner — citations attached
  DUX-5  to DUX-8:  UXAwareDockingAutoLoop — auto_loop_enabled toggle
  DUX-9  to DUX-12: ProgressReporter — SSE events + JSON sink
"""
import json
from io import StringIO

import pytest
from rich.console import Console

from ..params import DockingParams
from ..qc_evaluator import DockingQCEvaluator
from ..enriched_tuner import KnowledgeEnrichedDockingTuner, EnrichedRemediation
from ..ux_loop import UXAwareDockingAutoLoop, ProgressReporter
from ..orchestrator import MockPhaseRunner

STRONG_HIT = {"success": True, "best_score_kcal_mol": -9.2, "n_ligands_docked": 10, "mean_score": -7.5}
WEAK_SCORE = {"success": True, "best_score_kcal_mol": -5.0, "n_ligands_docked": 10, "mean_score": -4.0}
NO_POSES   = {"success": False, "best_score_kcal_mol": 0.0,  "n_ligands_docked":  0, "mean_score": 0.0}


# ── DUX-1: enriched tuner returns EnrichedRemediation ────────────────────────
def test_dux1_enriched_remediation_type():
    ev = DockingQCEvaluator("docking_hit_finding")
    tuner = KnowledgeEnrichedDockingTuner()
    qc = ev.evaluate_phase_1(WEAK_SCORE)
    _, remeds = tuner.remediate(qc, DockingParams())
    assert all(isinstance(r, EnrichedRemediation) for r in remeds)


# ── DUX-2: citations for best_binding_score gate ─────────────────────────────
def test_dux2_binding_score_citations():
    ev = DockingQCEvaluator("docking_hit_finding")
    tuner = KnowledgeEnrichedDockingTuner()
    qc = ev.evaluate_phase_1(WEAK_SCORE)
    _, remeds = tuner.remediate(qc, DockingParams())
    score_rem = next(r for r in remeds if r.gate == "best_binding_score")
    assert score_rem.has_citations()
    # Citations are from Vina and/or Glide papers; check source_file or paper_ref
    assert any(
        "Vina" in c.source_file or "Glide" in c.source_file
        or "Vina" in c.paper_ref or "Glide" in c.paper_ref
        for c in score_rem.citations
    )


# ── DUX-3: citations for valid_poses gate ────────────────────────────────────
def test_dux3_valid_poses_citations():
    ev = DockingQCEvaluator("docking_hit_finding")
    tuner = KnowledgeEnrichedDockingTuner()
    qc = ev.evaluate_phase_1(NO_POSES)
    _, remeds = tuner.remediate(qc, DockingParams())
    pose_rem = next((r for r in remeds if r.gate == "valid_poses"), None)
    assert pose_rem is not None
    assert pose_rem.has_citations()


# ── DUX-4: to_dict includes citations ────────────────────────────────────────
def test_dux4_to_dict_has_citations():
    ev = DockingQCEvaluator("docking_hit_finding")
    tuner = KnowledgeEnrichedDockingTuner()
    qc = ev.evaluate_phase_1(WEAK_SCORE)
    _, remeds = tuner.remediate(qc, DockingParams())
    d = remeds[0].to_dict()
    assert "citations" in d
    assert len(d["citations"]) > 0
    assert "source_text" in d["citations"][0]
    assert "paper_doi" in d["citations"][0]


# ── DUX-5: UX loop clean pass ─────────────────────────────────────────────────
def test_dux5_ux_loop_clean_pass(tmp_path):
    loop = UXAwareDockingAutoLoop(run_id="dux5", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_docking": STRONG_HIT})
    result = loop.run(runner)
    assert "phase_1_docking" in result.phases_passed
    assert result.total_attempts == 1


# ── DUX-6: auto_loop_enabled=False → no retry ────────────────────────────────
def test_dux6_auto_loop_disabled_no_retry(tmp_path):
    loop = UXAwareDockingAutoLoop(
        run_id="dux6", output_dir=tmp_path,
        max_retries_per_phase=3,
        auto_loop_enabled=False,
    )
    runner = MockPhaseRunner({"phase_1_docking": NO_POSES})
    result = loop.run(runner)
    assert result.total_attempts == 1
    assert "phase_1_docking" in result.phases_escalated


# ── DUX-7: enabled_phases=empty → no retry ───────────────────────────────────
def test_dux7_enabled_phases_empty_no_retry(tmp_path):
    loop = UXAwareDockingAutoLoop(
        run_id="dux7", output_dir=tmp_path,
        max_retries_per_phase=2,
        auto_loop_enabled=True,
        enabled_phases=set(),
    )
    runner = MockPhaseRunner({"phase_1_docking": NO_POSES})
    result = loop.run(runner)
    assert result.total_attempts == 1


# ── DUX-8: retry with enriched tuner mutates exhaustiveness ──────────────────
def test_dux8_retry_mutates_exhaustiveness(tmp_path):
    initial = 8
    loop = UXAwareDockingAutoLoop(
        run_id="dux8",
        params=DockingParams(exhaustiveness=initial),
        output_dir=tmp_path,
        max_retries_per_phase=2,
    )
    runner = MockPhaseRunner({"phase_1_docking": [WEAK_SCORE, STRONG_HIT]})
    loop.run(runner)
    assert loop.params.exhaustiveness > initial


# ── DUX-9: SSE events written to json_sink ───────────────────────────────────
def test_dux9_sse_events_written(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareDockingAutoLoop(run_id="dux9", output_dir=tmp_path, reporter=reporter)
    runner = MockPhaseRunner({"phase_1_docking": STRONG_HIT})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    event_types = {e["event"] for e in events}
    assert "autoloop_phase_start" in event_types
    assert "autoloop_gate_results" in event_types
    assert "autoloop_phase_complete" in event_types
    assert "autoloop_complete" in event_types


# ── DUX-10: SSE retry event includes citations ───────────────────────────────
def test_dux10_sse_retry_includes_citations(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareDockingAutoLoop(
        run_id="dux10", output_dir=tmp_path,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_1_docking": [WEAK_SCORE, STRONG_HIT]})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    update_events = [e for e in events if e["event"] == "autoloop_update"]
    assert len(update_events) >= 1
    rem = update_events[0]["remediations"][0]
    assert "citations" in rem
    assert len(rem["citations"]) > 0


# ── DUX-11: escalation SSE event on persistent fail ──────────────────────────
def test_dux11_escalation_event(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareDockingAutoLoop(
        run_id="dux11", output_dir=tmp_path,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_1_docking": NO_POSES})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    assert any(e["event"] == "autoloop_escalation" for e in events)


# ── DUX-12: audit JSONL written with UX loop ─────────────────────────────────
def test_dux12_audit_written_ux_loop(tmp_path):
    loop = UXAwareDockingAutoLoop(run_id="dux12", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_docking": STRONG_HIT})
    loop.run(runner)
    audit = tmp_path / "dux12_audit.jsonl"
    assert audit.exists()
    records = [json.loads(l) for l in audit.read_text().strip().split("\n") if l]
    assert any(r["event"] == "attempt" for r in records)
