"""
UX-layer tests for ADMET auto-loop (AUX-1 to AUX-12).

Tests:
  AUX-1  to AUX-4:  KnowledgeEnrichedADMETTuner — citations attached
  AUX-5  to AUX-8:  UXAwareADMETAutoLoop — auto_loop_enabled toggle
  AUX-9  to AUX-12: ProgressReporter — SSE events + JSON sink
"""
import json
from io import StringIO

import pytest
from rich.console import Console

from ..params import ADMETParams
from ..qc_evaluator import ADMETQCEvaluator
from ..enriched_tuner import KnowledgeEnrichedADMETTuner, EnrichedRemediation
from ..ux_loop import UXAwareADMETAutoLoop, ProgressReporter
from ..orchestrator import MockPhaseRunner

CLEAN = {
    "herg_ic50_uM": 25.0, "dili_probability": 0.2, "dili_risk_level": "low",
    "ames_positive": False, "ames_probability": 0.1,
    "logp": 2.5, "molecular_weight_da": 380.0,
}
HERG_FAIL = {
    "herg_ic50_uM": 3.5, "dili_probability": 0.2, "dili_risk_level": "low",
    "ames_positive": False, "ames_probability": 0.1,
    "logp": 2.5, "molecular_weight_da": 380.0,
}
AMES_FAIL = {
    "herg_ic50_uM": 25.0, "dili_probability": 0.2, "dili_risk_level": "low",
    "ames_positive": True, "ames_probability": 0.75,
    "logp": 2.5, "molecular_weight_da": 380.0,
}
DILI_FAIL = {
    "herg_ic50_uM": 25.0, "dili_probability": 0.8, "dili_risk_level": "high",
    "ames_positive": False, "ames_probability": 0.1,
    "logp": 5.5, "molecular_weight_da": 480.0,
}


# ── AUX-1: enriched tuner returns EnrichedRemediation ────────────────────────
def test_aux1_enriched_remediation_type():
    ev = ADMETQCEvaluator("admet_standard")
    tuner = KnowledgeEnrichedADMETTuner()
    qc = ev.evaluate_phase_2(HERG_FAIL)
    _, remeds = tuner.remediate(qc, ADMETParams())
    assert all(isinstance(r, EnrichedRemediation) for r in remeds)


# ── AUX-2: hERG gate citations include Aronov 2008 ───────────────────────────
def test_aux2_herg_citations_aronov():
    ev = ADMETQCEvaluator("admet_standard")
    tuner = KnowledgeEnrichedADMETTuner()
    qc = ev.evaluate_phase_2(HERG_FAIL)
    _, remeds = tuner.remediate(qc, ADMETParams())
    herg_rem = next(r for r in remeds if r.gate == "herg_ic50")
    assert herg_rem.has_citations()
    assert any("Aronov" in c.paper_ref for c in herg_rem.citations)


# ── AUX-3: Ames gate citations include Kazius 2005 ───────────────────────────
def test_aux3_ames_citations_kazius():
    ev = ADMETQCEvaluator("admet_standard")
    tuner = KnowledgeEnrichedADMETTuner()
    qc = ev.evaluate_phase_2(AMES_FAIL)
    _, remeds = tuner.remediate(qc, ADMETParams())
    ames_rem = next(r for r in remeds if r.gate == "ames_mutagenicity")
    assert ames_rem.has_citations()
    assert any("Kazius" in c.paper_ref for c in ames_rem.citations)


# ── AUX-4: DILI gate citations include Lammert 2010 ──────────────────────────
def test_aux4_dili_citations_lammert():
    ev = ADMETQCEvaluator("admet_standard")
    tuner = KnowledgeEnrichedADMETTuner()
    qc = ev.evaluate_phase_2(DILI_FAIL)
    _, remeds = tuner.remediate(qc, ADMETParams())
    dili_rems = [r for r in remeds if "dili" in r.gate]
    assert len(dili_rems) > 0
    assert any(r.has_citations() for r in dili_rems)
    assert any(
        "Lammert" in c.paper_ref
        for r in dili_rems
        for c in r.citations
    )


# ── AUX-5: UX loop 3-phase clean pass ────────────────────────────────────────
def test_aux5_ux_loop_clean_pass(tmp_path):
    loop = UXAwareADMETAutoLoop(run_id="aux5", output_dir=tmp_path)
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": CLEAN,
        "phase_3_herg_screen": CLEAN,
        "phase_4_dili_ames": CLEAN,
    })
    result = loop.run(runner)
    assert len(result.phases_passed) == 3
    assert result.total_attempts == 3


# ── AUX-6: auto_loop_enabled=False → no retry on hERG fail ───────────────────
def test_aux6_auto_loop_disabled(tmp_path):
    loop = UXAwareADMETAutoLoop(
        run_id="aux6", output_dir=tmp_path,
        max_retries_per_phase=2,
        auto_loop_enabled=False,
    )
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": HERG_FAIL,
        "phase_3_herg_screen": CLEAN,
        "phase_4_dili_ames": CLEAN,
    })
    result = loop.run(runner)
    # phase_2 fails and escalates immediately (no retry); phases 3+4 still run
    assert "phase_2_admet_prediction" in result.phases_escalated
    # total_attempts = 1 (phase2) + 1 (phase3) + 1 (phase4) = 3
    assert result.total_attempts == 3


# ── AUX-7: enabled_phases partial — only phase_3 retries ─────────────────────
def test_aux7_enabled_phases_partial(tmp_path):
    loop = UXAwareADMETAutoLoop(
        run_id="aux7", output_dir=tmp_path,
        max_retries_per_phase=2,
        auto_loop_enabled=True,
        enabled_phases={"phase_3_herg_screen"},
    )
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": HERG_FAIL,  # not in enabled_phases → 1 attempt
        "phase_3_herg_screen": [HERG_FAIL, CLEAN],  # in enabled_phases → retries
        "phase_4_dili_ames": CLEAN,
    })
    result = loop.run(runner)
    assert "phase_2_admet_prediction" in result.phases_escalated
    assert "phase_3_herg_screen" in result.phases_passed


# ── AUX-8: params mutated through enriched tuner on retry ────────────────────
def test_aux8_retry_mutates_logp(tmp_path):
    initial_logp = 5.0
    loop = UXAwareADMETAutoLoop(
        run_id="aux8",
        params=ADMETParams(logp_max=initial_logp),
        output_dir=tmp_path,
        max_retries_per_phase=2,
    )
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": [HERG_FAIL, CLEAN],
        "phase_3_herg_screen": CLEAN,
        "phase_4_dili_ames": CLEAN,
    })
    loop.run(runner)
    assert loop.params.logp_max < initial_logp


# ── AUX-9: SSE event types all present ───────────────────────────────────────
def test_aux9_sse_event_types(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareADMETAutoLoop(run_id="aux9", output_dir=tmp_path, reporter=reporter)
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": CLEAN,
        "phase_3_herg_screen": CLEAN,
        "phase_4_dili_ames": CLEAN,
    })
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    types = {e["event"] for e in events}
    assert "autoloop_phase_start" in types
    assert "autoloop_gate_results" in types
    assert "autoloop_phase_complete" in types
    assert "autoloop_complete" in types


# ── AUX-10: SSE retry event includes citations ────────────────────────────────
def test_aux10_sse_retry_citations(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareADMETAutoLoop(
        run_id="aux10", output_dir=tmp_path,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": [HERG_FAIL, CLEAN],
        "phase_3_herg_screen": CLEAN,
        "phase_4_dili_ames": CLEAN,
    })
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    updates = [e for e in events if e["event"] == "autoloop_update"]
    assert len(updates) >= 1
    rem = updates[0]["remediations"][0]
    assert "citations" in rem
    assert len(rem["citations"]) > 0


# ── AUX-11: escalation event on persistent fail ───────────────────────────────
def test_aux11_escalation_event(tmp_path):
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareADMETAutoLoop(
        run_id="aux11", output_dir=tmp_path,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": HERG_FAIL,
        "phase_3_herg_screen": CLEAN,
        "phase_4_dili_ames": CLEAN,
    })
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    assert any(e["event"] == "autoloop_escalation" for e in events)


# ── AUX-12: audit JSONL written with 3 phases ────────────────────────────────
def test_aux12_audit_3_phases(tmp_path):
    loop = UXAwareADMETAutoLoop(run_id="aux12", output_dir=tmp_path)
    runner = MockPhaseRunner({
        "phase_2_admet_prediction": CLEAN,
        "phase_3_herg_screen": CLEAN,
        "phase_4_dili_ames": CLEAN,
    })
    loop.run(runner)
    audit = tmp_path / "aux12_audit.jsonl"
    assert audit.exists()
    records = [json.loads(l) for l in audit.read_text().strip().split("\n") if l]
    attempt_events = [r for r in records if r["event"] == "attempt"]
    assert len(attempt_events) == 3  # one per phase
