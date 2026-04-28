"""
UX-layer tests for CYP DDI auto-loop (CUX-1 to CUX-12).

Tests:
  CUX-1  to CUX-4:  KnowledgeEnrichedCYPTuner — citations attached
  CUX-5  to CUX-8:  UXAwareCYPDDIAutoLoop — auto_loop_enabled toggle
  CUX-9  to CUX-12: ProgressReporter — SSE events + JSON sink
"""
import json
from io import StringIO

import pytest
from rich.console import Console

from ..params import CYPDDIParams
from ..qc_evaluator import CYPDDIQCEvaluator
from ..enriched_tuner import KnowledgeEnrichedCYPTuner, EnrichedRemediation
from ..ux_loop import UXAwareCYPDDIAutoLoop, ProgressReporter
from ..orchestrator import MockPhaseRunner

CLEAN = {"summary": {"n_clinical": 0, "n_investigate": 0, "n_tdi": 0,
                     "overall_recommendation": "NOT_EXPECTED"}}
CLINICAL_1 = {"summary": {"n_clinical": 1, "n_investigate": 2, "n_tdi": 0,
                           "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}}
INVESTIGATE_3 = {"summary": {"n_clinical": 0, "n_investigate": 3, "n_tdi": 1,
                              "overall_recommendation": "INVESTIGATE"}}


# ── CUX-1: enriched tuner returns EnrichedRemediation ────────────────────────
def test_cux1_enriched_remediation_type():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = KnowledgeEnrichedCYPTuner()
    qc = ev.evaluate_phase_2(CLINICAL_1)
    _, remeds = tuner.remediate(qc, CYPDDIParams())
    assert all(isinstance(r, EnrichedRemediation) for r in remeds)


# ── CUX-2: citations attached for clinical gate ───────────────────────────────
def test_cux2_clinical_gate_has_citations():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = KnowledgeEnrichedCYPTuner()
    qc = ev.evaluate_phase_2(CLINICAL_1)
    _, remeds = tuner.remediate(qc, CYPDDIParams())
    clinical_rem = next(r for r in remeds if r.gate == "clinical_study_isoforms")
    assert clinical_rem.has_citations()
    assert any("FDA" in c.paper_ref for c in clinical_rem.citations)


# ── CUX-3: citations attached for investigate gate ────────────────────────────
def test_cux3_investigate_gate_has_citations():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = KnowledgeEnrichedCYPTuner()
    qc = ev.evaluate_phase_2(INVESTIGATE_3)
    _, remeds = tuner.remediate(qc, CYPDDIParams())
    inv_rem = next(r for r in remeds if r.gate == "investigate_isoforms")
    assert inv_rem.has_citations()


# ── CUX-4: to_dict includes citations ────────────────────────────────────────
def test_cux4_to_dict_has_citations():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = KnowledgeEnrichedCYPTuner()
    qc = ev.evaluate_phase_2(CLINICAL_1)
    _, remeds = tuner.remediate(qc, CYPDDIParams())
    d = remeds[0].to_dict()
    assert "citations" in d
    assert isinstance(d["citations"], list)
    assert len(d["citations"]) > 0
    assert "source_text" in d["citations"][0]
    assert "paper_doi" in d["citations"][0]


# ── CUX-5: UX loop clean pass ─────────────────────────────────────────────────
def test_cux5_ux_loop_clean_pass(tmp_path):
    loop = UXAwareCYPDDIAutoLoop(run_id="cux5", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    result = loop.run(runner)
    assert "phase_2_ddi_risk" in result.phases_passed
    assert result.total_attempts == 1


# ── CUX-6: auto_loop_enabled=False → no retry ────────────────────────────────
def test_cux6_auto_loop_disabled_no_retry(tmp_path):
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cux6", output_dir=tmp_path,
        max_retries_per_phase=3,
        auto_loop_enabled=False,
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLINICAL_1})
    result = loop.run(runner)
    # Even though 3 retries are configured, disabled → only 1 attempt
    assert result.total_attempts == 1
    assert "phase_2_ddi_risk" in result.phases_escalated


# ── CUX-7: enabled_phases controls per-phase retry ───────────────────────────
def test_cux7_enabled_phases_controls_retry(tmp_path):
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cux7", output_dir=tmp_path,
        max_retries_per_phase=2,
        auto_loop_enabled=True,
        enabled_phases=set(),  # no phases enabled → no retry
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLINICAL_1})
    result = loop.run(runner)
    assert result.total_attempts == 1  # no retry because phase not in enabled_phases


# ── CUX-8: retry with knowledge-enriched tuner mutates params ─────────────────
def test_cux8_retry_mutates_params(tmp_path):
    initial_cmax = 4.0
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cux8",
        params=CYPDDIParams(cmax_ss_uM=initial_cmax),
        output_dir=tmp_path,
        max_retries_per_phase=2,
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": [CLINICAL_1, CLEAN]})
    loop.run(runner)
    assert loop.params.cmax_ss_uM < initial_cmax


# ── CUX-9: SSE events written to json_sink ───────────────────────────────────
def test_cux9_sse_events_written(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareCYPDDIAutoLoop(run_id="cux9", output_dir=tmp_path, reporter=reporter)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    event_types = {e["event"] for e in events}
    assert "autoloop_phase_start" in event_types
    assert "autoloop_gate_results" in event_types
    assert "autoloop_phase_complete" in event_types
    assert "autoloop_complete" in event_types


# ── CUX-10: SSE retry event includes citations ────────────────────────────────
def test_cux10_sse_retry_includes_citations(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cux10", output_dir=tmp_path,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": [CLINICAL_1, CLEAN]})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    update_events = [e for e in events if e["event"] == "autoloop_update"]
    assert len(update_events) >= 1
    rem = update_events[0]["remediations"][0]
    assert "citations" in rem
    assert len(rem["citations"]) > 0


# ── CUX-11: SSE autoloop_escalation fired on persistent fail ─────────────────
def test_cux11_escalation_event(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=sink,
    )
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cux11", output_dir=tmp_path,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLINICAL_1})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    assert any(e["event"] == "autoloop_escalation" for e in events)


# ── CUX-12: audit JSONL written even with UX loop ────────────────────────────
def test_cux12_audit_written_ux_loop(tmp_path):
    loop = UXAwareCYPDDIAutoLoop(run_id="cux12", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    loop.run(runner)
    audit = tmp_path / "cux12_audit.jsonl"
    assert audit.exists()
    records = [json.loads(l) for l in audit.read_text().strip().split("\n") if l]
    assert any(r["event"] == "attempt" for r in records)
