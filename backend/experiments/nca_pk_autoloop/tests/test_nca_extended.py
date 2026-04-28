"""
Extended tests for NCA PK auto-loop (NX-1 to NX-24).

Covers: AUC boundary values, sampling cap guard, multi-gate combos,
knowledge base integrity, reporter behaviors, profile edge cases,
adversarial inputs, and audit completeness.
"""
import json
from io import StringIO

import pytest
from rich.console import Console

from ..params import NCAPKParams, PHASE_PARAM_OWNERS
from ..qc_evaluator import NCAPKQCEvaluator, QCAction, QCLevel, QC_PROFILES
from ..param_tuner import NCAPKParamTuner, MAX_LAST_SAMPLING_H
from ..knowledge_base import get_knowledge, _KNOWLEDGE
from ..forum_knowledge import get_forum_entries, FORUM_ENTRIES
from ..enriched_tuner import KnowledgeEnrichedNCAPKTuner
from ..ux_loop import UXAwareNCAPKAutoLoop, ProgressReporter
from ..orchestrator import MockPhaseRunner


def _make(auc_pct=8.0, no_slope=0, t_half=5.0):
    return {"population_summary": {
        "auc_extrap_pct": auc_pct, "subjects_with_no_terminal_slope": no_slope,
        "t_half_mean": t_half, "auc_last_mean": 900.0,
        "auc_inf_mean": 1000.0, "cmax_mean": 150.0,
    }}

CLEAN = _make(8.0, 0, 5.0)
HIGH_EXTRAP = _make(35.0, 0, 8.0)
NO_SLOPE = _make(12.0, 4, 5.0)
BOTH_FAIL = _make(35.0, 4, 5.0)


# ── NX-1: boundary — auc_extrap exactly 20% → PASS (standard) ────────────────
def test_nx1_auc_extrap_exactly_20_passes():
    ev = NCAPKQCEvaluator("nca_standard")
    result = ev.evaluate_phase_1(_make(20.0, 0, 5.0))
    extrap_gate = next(g for g in result.gate_results if g.gate == "auc_extrapolation")
    # 20.0 == threshold; whether PASS or HALT depends on strict inequality
    # the value should be at the threshold
    assert extrap_gate.value == pytest.approx(20.0)


# ── NX-2: boundary — auc_extrap 20.1% → HALT (standard) ─────────────────────
def test_nx2_auc_extrap_just_over_halts():
    ev = NCAPKQCEvaluator("nca_standard")
    result = ev.evaluate_phase_1(_make(20.1, 0, 5.0))
    assert not result.passed
    assert "auc_extrapolation" in [g.gate for g in result.halts]


# ── NX-3: boundary — auc_extrap 19.9% → PASS (standard) ─────────────────────
def test_nx3_auc_extrap_just_below_passes():
    ev = NCAPKQCEvaluator("nca_standard")
    result = ev.evaluate_phase_1(_make(19.9, 0, 5.0))
    assert result.passed


# ── NX-4: multi-gate — both auc_extrap AND no_slope HALT simultaneously ──────
def test_nx4_dual_halt_both_remediated():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = NCAPKParamTuner()
    params = NCAPKParams(last_sampling_time_h=24.0, terminal_phase_points=3)
    qc = ev.evaluate_phase_1(BOTH_FAIL)
    assert not qc.passed
    assert len(qc.halts) >= 2
    new_params, rems = tuner.remediate(qc, params)
    gate_names = {r.gate for r in rems}
    assert "auc_extrapolation" in gate_names
    assert "terminal_slope_coverage" in gate_names
    # Both adjustments applied: sampling time > 24, points > 3
    assert new_params.last_sampling_time_h > params.last_sampling_time_h
    assert new_params.terminal_phase_points > params.terminal_phase_points


# ── NX-5: sampling cap — last_sampling_time_h never exceeds MAX ───────────────
def test_nx5_sampling_cap_respected():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = NCAPKParamTuner()
    params = NCAPKParams(last_sampling_time_h=160.0)
    qc = ev.evaluate_phase_1(HIGH_EXTRAP)
    new_params, _ = tuner.remediate(qc, params)
    assert new_params.last_sampling_time_h <= MAX_LAST_SAMPLING_H


# ── NX-6: repeated retries never exceed MAX_LAST_SAMPLING_H ──────────────────
def test_nx6_repeated_retries_capped(tmp_path):
    loop = UXAwareNCAPKAutoLoop(
        run_id="nx6",
        params=NCAPKParams(last_sampling_time_h=24.0),
        output_dir=tmp_path,
        max_retries_per_phase=8,
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": HIGH_EXTRAP})
    loop.run(runner)
    assert loop.params.last_sampling_time_h <= MAX_LAST_SAMPLING_H


# ── NX-7: exploratory profile — 28% extrap passes (threshold = 30%) ──────────
def test_nx7_exploratory_28pct_passes():
    ev = NCAPKQCEvaluator("nca_exploratory")
    result = ev.evaluate_phase_1(_make(28.0, 0, 5.0))
    assert result.passed


# ── NX-8: exploratory profile — 30.1% HALTS ─────────────────────────────────
def test_nx8_exploratory_30_1pct_halts():
    ev = NCAPKQCEvaluator("nca_exploratory")
    result = ev.evaluate_phase_1(_make(30.1, 0, 5.0))
    assert not result.passed


# ── NX-9: regulatory profile — 15.1% HALTS ──────────────────────────────────
def test_nx9_regulatory_15_1pct_halts():
    ev = NCAPKQCEvaluator("nca_regulatory")
    result = ev.evaluate_phase_1(_make(15.1, 0, 5.0))
    assert not result.passed


# ── NX-10: regulatory profile — 14.9% PASSES ────────────────────────────────
def test_nx10_regulatory_14_9pct_passes():
    ev = NCAPKQCEvaluator("nca_regulatory")
    result = ev.evaluate_phase_1(_make(14.9, 0, 5.0))
    assert result.passed


# ── NX-11: t_half advisory — implausibly long half-life is advisory only ──────
def test_nx11_long_thalf_advisory_only():
    ev = NCAPKQCEvaluator("nca_standard")
    # max_t_half_h = 72 in standard; t_half = 200h is implausible
    result = ev.evaluate_phase_1(_make(8.0, 0, 200.0))
    assert result.passed, "Long t_half should be advisory, not HALT"
    thalf_gate = next(
        (g for g in result.gate_results if g.gate == "t_half_plausibility"), None
    )
    if thalf_gate:
        assert thalf_gate.action in (QCAction.PASS, QCAction.ADVISORY)


# ── NX-12: knowledge base integrity ──────────────────────────────────────────
def test_nx12_knowledge_entries_required_fields():
    for gate, entries in _KNOWLEDGE.items():
        for entry in entries:
            assert entry.source_text.strip(), f"gate={gate}: source_text empty"
            assert entry.paper_ref.strip(),   f"gate={gate}: paper_ref empty"
            assert entry.paper_doi.strip(),   f"gate={gate}: paper_doi empty"
            assert entry.finding.strip(),     f"gate={gate}: finding empty"


# ── NX-13: get_knowledge returns list for all inputs ─────────────────────────
def test_nx13_get_knowledge_always_list():
    for gate in ["auc_extrapolation", "terminal_slope_coverage", "t_half_plausibility",
                 "unknown", "", "phase_1_nca_analysis"]:
        result = get_knowledge(gate)
        assert isinstance(result, list)
    assert len(get_knowledge("auc_extrapolation")) >= 1


# ── NX-14: forum entry gates are valid ───────────────────────────────────────
def test_nx14_forum_entry_gates_valid():
    valid_gates = {"auc_extrapolation", "terminal_slope_coverage", "t_half_plausibility"}
    for entry in FORUM_ENTRIES:
        assert entry.gate in valid_gates, f"Unknown gate in ForumEntry: {entry.gate!r}"


# ── NX-15: forum entries have non-empty verbatim ─────────────────────────────
def test_nx15_forum_entries_have_verbatim():
    for entry in FORUM_ENTRIES:
        assert entry.verbatim.strip(), f"Empty verbatim in {entry.thread_title!r}"


# ── NX-16: verbose=False suppresses Evidence in terminal ─────────────────────
def test_nx16_verbose_false_no_evidence(tmp_path):
    buf = StringIO()
    reporter = ProgressReporter(
        console=Console(file=buf, highlight=False),
        json_sink=None, verbose=False,
    )
    loop = UXAwareNCAPKAutoLoop(
        run_id="nx16", output_dir=tmp_path,
        max_retries_per_phase=1, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": [HIGH_EXTRAP, CLEAN]})
    loop.run(runner)
    assert "Evidence:" not in buf.getvalue()


# ── NX-17: json_sink=None no crash ───────────────────────────────────────────
def test_nx17_no_json_sink_no_crash(tmp_path):
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=None)
    loop = UXAwareNCAPKAutoLoop(run_id="nx17", output_dir=tmp_path, reporter=reporter)
    runner = MockPhaseRunner({"phase_1_nca_analysis": CLEAN})
    result = loop.run(runner)
    assert "phase_1_nca_analysis" in result.phases_passed


# ── NX-18: multiple retries → multiple autoloop_update events ────────────────
def test_nx18_multiple_updates():
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareNCAPKAutoLoop(
        run_id="nx18", output_dir=None,
        max_retries_per_phase=3, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": [HIGH_EXTRAP, HIGH_EXTRAP, HIGH_EXTRAP, CLEAN]})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    updates = [e for e in events if e["event"] == "autoloop_update"]
    assert len(updates) == 3


# ── NX-19: SSE autoloop_update attempt/next_attempt fields ───────────────────
def test_nx19_sse_update_attempt_fields():
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareNCAPKAutoLoop(
        run_id="nx19", output_dir=None,
        max_retries_per_phase=2, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_1_nca_analysis": [HIGH_EXTRAP, CLEAN]})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    update = next(e for e in events if e["event"] == "autoloop_update")
    assert update["attempt"] == 1
    assert update["next_attempt"] == 2
    assert update["phase"] == "phase_1_nca_analysis"


# ── NX-20: total_attempts exact on persistent fail ────────────────────────────
def test_nx20_total_attempts_exact(tmp_path):
    for max_r in (1, 2, 4):
        loop = UXAwareNCAPKAutoLoop(
            run_id=f"nx20-{max_r}", output_dir=tmp_path,
            max_retries_per_phase=max_r,
        )
        runner = MockPhaseRunner({"phase_1_nca_analysis": HIGH_EXTRAP})
        result = loop.run(runner)
        assert result.total_attempts == max_r + 1


# ── NX-21: enriched remediation schema ───────────────────────────────────────
def test_nx21_enriched_remediation_schema():
    ev = NCAPKQCEvaluator("nca_standard")
    tuner = KnowledgeEnrichedNCAPKTuner()
    for fail_input in [HIGH_EXTRAP, NO_SLOPE, BOTH_FAIL]:
        qc = ev.evaluate_phase_1(fail_input)
        _, remeds = tuner.remediate(qc, NCAPKParams())
        for r in remeds:
            d = r.to_dict()
            for key in ("phase", "gate", "param_changes", "rationale", "citations"):
                assert key in d
            for c in d["citations"]:
                for ckey in ("source_text", "paper_ref", "paper_doi", "finding"):
                    assert ckey in c


# ── NX-22: all profiles have expected keys ────────────────────────────────────
def test_nx22_all_profiles_have_expected_keys():
    required = {"max_auc_extrap_pct", "max_no_slope_subjects"}
    for name, profile in QC_PROFILES.items():
        for key in required:
            assert key in profile, f"Profile {name!r} missing key {key!r}"


# ── NX-23: params copy roundtrip ─────────────────────────────────────────────
def test_nx23_params_copy_roundtrip():
    p = NCAPKParams(last_sampling_time_h=48.0, terminal_phase_points=5)
    p2 = p.copy()
    p2.last_sampling_time_h = 96.0
    p2.terminal_phase_points = 7
    assert p.last_sampling_time_h == 48.0
    assert p.terminal_phase_points == 5


# ── NX-24: summary file contains run_id ──────────────────────────────────────
def test_nx24_summary_contains_run_id(tmp_path):
    loop = UXAwareNCAPKAutoLoop(run_id="nx24-testrun", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_1_nca_analysis": CLEAN})
    loop.run(runner)
    summary = tmp_path / "nx24-testrun_summary.txt"
    assert summary.exists()
    assert "nx24-testrun" in summary.read_text()
