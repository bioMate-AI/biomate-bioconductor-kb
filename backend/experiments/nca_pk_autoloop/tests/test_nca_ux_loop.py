"""
UX-layer tests for NCA PK auto-loop (NUX-1 to NUX-12).

Tests:
  NUX-1  to NUX-4:  KnowledgeEnrichedNCAPKTuner — citations attached
  NUX-5  to NUX-8:  UXAwareNCAPKAutoLoop — auto_loop_enabled toggle
  NUX-9  to NUX-12: ProgressReporter — SSE events + JSON sink
"""
import json
from io import StringIO

import pytest
from rich.console import Console

from ..params import NCAPKParams
from ..qc_evaluator import NCAPKQCEvaluator
from ..enriched_tuner import KnowledgeEnrichedNCAPKTuner, EnrichedRemediation
from ..ux_loop import UXAwareNCAPKAutoLoop, ProgressReporter
from ..orchestrator import MockPhaseRunner

CLEAN = {"population_summary": {"auc_extrap_pct": 8.0, "subjects_with_no_terminal_slope": 0,
                                  "t_half_mean": 5.0, "auc_last_mean": 910.0,
                                  "auc_inf_mean": 994.0, "cmax_mean": 150.0}}
HIGH_EXTRAP = {"population_summary": {"auc_extrap_pct": 35.0, "subjects_with_no_terminal_slope": 0,
                                       "t_half_mean": 8.0, "auc_last_mean": 650.0,
                                       "auc_inf_mean": 1000.0, "cmax_mean": 120.0}}
NO_SLOPE = {"population_summary": {"auc_extrap_pct": 12.0, "subjects_with_no_terminal_slope": 4,
                                    "t_half_mean": 5.0, "auc_last_mean": 820.0,
                                    "auc_inf_mean": 1000.0, "cmax_mean": 200.0}}


# ── NUX-1: enriched tuner returns EnrichedRemediation ────────────────────────
def test_nux1_enriched_remediation_type():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = KnowledgeEnrichedNCAPKTuner()
    qc = ev.evaluate_phase_1(HIGH_EXTRAP)
    _, remeds = tuner.remediate(qc, NCAPKParams())
    assert all(isinstance(r, EnrichedRemediation) for r in remeds)


# ── NUX-2: citations for auc_extrapolation gate ───────────────────────────────
def test_nux2_auc_extrap_citations():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = KnowledgeEnrichedNCAPKTuner()
    qc = ev.evaluate_phase_1(HIGH_EXTRAP)
    _, remeds = tuner.remediate(qc, NCAPKParams())
    extrap_rem = next(r for r in remeds if r.gate == "auc_extrapolation")
    assert extrap_rem.has_citations()
    assert any("FDA" in c.paper_ref or "PKNCA" in c.paper_ref for c in extrap_rem.citations)


# ── NUX-3: citations for terminal_slope_coverage gate ────────────────────────
def test_nux3_terminal_slope_citations():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = KnowledgeEnrichedNCAPKTuner()
    qc = ev.evaluate_phase_1(NO_SLOPE)
    _, remeds = tuner.remediate(qc, NCAPKParams())
    slope_rem = next(r for r in remeds if r.gate == "terminal_slope_coverage")
    assert slope_rem.has_citations()
    assert len(slope_rem.citations) >= 1


# ── NUX-4: to_dict includes citations ────────────────────────────────────────
def test_nux4_to_dict_has_citations():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = KnowledgeEnrichedNCAPKTuner()
    qc = ev.evaluate_phase_1(HIGH_EXTRAP)
    _, remeds = tuner.remediate(qc, NCAPKParams())
    d = remeds[0].to_dict()
    assert "citations" in d
    assert len(d["citations"]) > 0
    assert "source_text" in d["citations"][0]
    assert "paper_doi" in d["citations"][0]


# ── NUX-5: UX loop clean pass ─────────────────────────────────────────────────
def test_nux5_ux_loop_clean_pass(tmp_path):
    loop = UXAwareNCAPKAutoLoop(run_id="nux5", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_nca_analysis": CLEAN})
    result = loop.run(runner)
    assert "phase_1_nca_analysis" in result.phases_passed
    assert result.total_attempts == 1


# ── NUX-6: auto_loop_enabled=False → no retry ────────────────────────────────
def test_nux6_auto_loop_disabled_no_retry(tmp_path):
    loop = UXAwareNCAPKAutoLoop(
        run_id="nux6", output_dir=tmp_path,
        max_retries_per_phase=3,
        auto_loop_enabled=False,
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": HIGH_EXTRAP})
    result = loop.run(runner)
    assert result.total_attempts == 1
    assert "phase_1_nca_analysis" in result.phases_escalated


# ── NUX-7: enabled_phases=empty → no retry ───────────────────────────────────
def test_nux7_enabled_phases_empty_no_retry(tmp_path):
    loop = UXAwareNCAPKAutoLoop(
        run_id="nux7", output_dir=tmp_path,
        max_retries_per_phase=2,
        auto_loop_enabled=True,
        enabled_phases=set(),
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": HIGH_EXTRAP})
    result = loop.run(runner)
    assert result.total_attempts == 1


# ── NUX-8: retry with enriched tuner mutates sampling time ───────────────────
def test_nux8_retry_mutates_sampling_time(tmp_path):
    initial_time = 24.0
    loop = UXAwareNCAPKAutoLoop(
        run_id="nux8",
        params=NCAPKParams(last_sampling_time_h=initial_time),
        output_dir=tmp_path,
        max_retries_per_phase=2,
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": [HIGH_EXTRAP, CLEAN]})
    loop.run(runner)
    assert loop.params.last_sampling_time_h > initial_time


# ── NUX-9: SSE events written to json_sink ───────────────────────────────────
def test_nux9_sse_events_written(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareNCAPKAutoLoop(run_id="nux9", output_dir=tmp_path, reporter=reporter)
    runner = MockPhaseRunner({"phase_1_nca_analysis": CLEAN})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    event_types = {e["event"] for e in events}
    assert "autoloop_phase_start" in event_types
    assert "autoloop_gate_results" in event_types
    assert "autoloop_phase_complete" in event_types
    assert "autoloop_complete" in event_types


# ── NUX-10: SSE retry event includes citations ───────────────────────────────
def test_nux10_sse_retry_includes_citations(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareNCAPKAutoLoop(
        run_id="nux10", output_dir=tmp_path,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": [HIGH_EXTRAP, CLEAN]})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    update_events = [e for e in events if e["event"] == "autoloop_update"]
    assert len(update_events) >= 1
    rem = update_events[0]["remediations"][0]
    assert "citations" in rem
    assert len(rem["citations"]) > 0


# ── NUX-11: escalation SSE event on persistent fail ──────────────────────────
def test_nux11_escalation_event(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareNCAPKAutoLoop(
        run_id="nux11", output_dir=tmp_path,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": HIGH_EXTRAP})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    assert any(e["event"] == "autoloop_escalation" for e in events)


# ── NUX-12: audit JSONL written with UX loop ─────────────────────────────────
def test_nux12_audit_written_ux_loop(tmp_path):
    loop = UXAwareNCAPKAutoLoop(run_id="nux12", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_nca_analysis": CLEAN})
    loop.run(runner)
    audit = tmp_path / "nux12_audit.jsonl"
    assert audit.exists()
    records = [json.loads(l) for l in audit.read_text().strip().split("\n") if l]
    assert any(r["event"] == "attempt" for r in records)
