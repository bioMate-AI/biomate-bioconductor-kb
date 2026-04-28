"""
Extended tests for CYP DDI auto-loop (CX-1 to CX-24).

Covers: gate boundary values, min/max guards, multi-gate combos,
profile edge cases, knowledge base integrity, reporter behaviors,
audit completeness, and adversarial inputs.
"""
import json
from io import StringIO

import pytest
from rich.console import Console

from ..params import CYPDDIParams
from ..qc_evaluator import CYPDDIQCEvaluator, QCAction, QCLevel, QC_PROFILES
from ..param_tuner import CYPDDIParamTuner, MIN_CMAX_uM
from ..knowledge_base import get_knowledge, KnowledgeEntry, _KNOWLEDGE
from ..forum_knowledge import get_forum_entries, FORUM_ENTRIES
from ..enriched_tuner import KnowledgeEnrichedCYPTuner
from ..ux_loop import UXAwareCYPDDIAutoLoop, ProgressReporter
from ..orchestrator import MockPhaseRunner

CLEAN = {"summary": {"n_clinical": 0, "n_investigate": 0, "n_tdi": 0,
                     "overall_recommendation": "NOT_EXPECTED"}}
CLINICAL_1 = {"summary": {"n_clinical": 1, "n_investigate": 2, "n_tdi": 0,
                           "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}}
INVESTIGATE_3 = {"summary": {"n_clinical": 0, "n_investigate": 3, "n_tdi": 1,
                              "overall_recommendation": "INVESTIGATE"}}


# ── CX-1: boundary — n_investigate exactly at max (advisory, not HALT) ───────
def test_cx1_investigate_exact_max_advisory():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")  # max_investigate = 2
    metrics = {"summary": {"n_clinical": 0, "n_investigate": 2, "n_tdi": 0,
                            "overall_recommendation": "INVESTIGATE"}}
    result = ev.evaluate_phase_2(metrics)
    assert result.passed, "n_investigate == max should not HALT"
    inv_gate = next(g for g in result.gate_results if g.gate == "investigate_isoforms")
    assert inv_gate.action in (QCAction.PASS, QCAction.ADVISORY)


# ── CX-2: boundary — n_investigate one above max → HALT ─────────────────────
def test_cx2_investigate_one_over_max_halts():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")  # max_investigate = 2
    metrics = {"summary": {"n_clinical": 0, "n_investigate": 3, "n_tdi": 0,
                            "overall_recommendation": "INVESTIGATE"}}
    result = ev.evaluate_phase_2(metrics)
    assert not result.passed
    assert "investigate_isoforms" in [g.gate for g in result.halts]


# ── CX-3: multi-gate — both clinical AND investigate HALT simultaneously ──────
def test_cx3_dual_halt_both_gates_remediated():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = CYPDDIParamTuner()
    params = CYPDDIParams(cmax_ss_uM=4.0)
    # n_clinical=2 > max_clinical=0; n_investigate=4 > max_investigate=2
    both_fail = {"summary": {"n_clinical": 2, "n_investigate": 4, "n_tdi": 0,
                              "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}}
    qc = ev.evaluate_phase_2(both_fail)
    assert not qc.passed
    assert len(qc.halts) == 2
    new_params, rems = tuner.remediate(qc, params)
    # One remediation per HALT gate
    assert len(rems) == 2
    gate_names = {r.gate for r in rems}
    assert "clinical_study_isoforms" in gate_names
    assert "investigate_isoforms" in gate_names
    # cmax was reduced by both handlers stacking: 4.0 * 0.5 = 2.0 (clinical), then * 0.7 = 1.4
    assert new_params.cmax_ss_uM < params.cmax_ss_uM


# ── CX-4: MIN_CMAX guard — cmax never goes below MIN_CMAX_uM ────────────────
def test_cx4_cmax_never_below_minimum():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = CYPDDIParamTuner()
    # Start at a very small cmax — should clamp at MIN_CMAX_uM
    params = CYPDDIParams(cmax_ss_uM=0.08)
    qc = ev.evaluate_phase_2(CLINICAL_1)
    new_params, _ = tuner.remediate(qc, params)
    assert new_params.cmax_ss_uM >= MIN_CMAX_uM


# ── CX-5: repeated remediations never go below MIN_CMAX ─────────────────────
def test_cx5_repeated_remediations_clamped(tmp_path):
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cx5",
        params=CYPDDIParams(cmax_ss_uM=0.10),
        output_dir=tmp_path,
        max_retries_per_phase=5,
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLINICAL_1})
    loop.run(runner)
    assert loop.params.cmax_ss_uM >= MIN_CMAX_uM


# ── CX-6: oncology profile — n_clinical=1 at max=1 → advisory, not HALT ─────
def test_cx6_oncology_max_clinical_boundary():
    ev = CYPDDIQCEvaluator("cyp_ddi_oncology")  # max_clinical = 1
    metrics = {"summary": {"n_clinical": 1, "n_investigate": 0, "n_tdi": 0,
                            "overall_recommendation": "CLINICAL_STUDY_RECOMMENDED"}}
    result = ev.evaluate_phase_2(metrics)
    assert result.passed, "Oncology allows 1 CLINICAL (at max) — should pass"
    clin_gate = next(g for g in result.gate_results if g.gate == "clinical_study_isoforms")
    # advisory-level at max_clinical > 0
    assert clin_gate.action in (QCAction.PASS, QCAction.ADVISORY)


# ── CX-7: TDI advisory doesn't block phase pass ──────────────────────────────
def test_cx7_tdi_only_doesnt_block():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    metrics = {"summary": {"n_clinical": 0, "n_investigate": 0, "n_tdi": 3,
                            "overall_recommendation": "NOT_EXPECTED"}}
    result = ev.evaluate_phase_2(metrics)
    assert result.passed
    # TDI gate is advisory
    tdi = next(g for g in result.gate_results if g.gate == "tdi_concern")
    assert tdi.action == QCAction.ADVISORY


# ── CX-8: knowledge base integrity — all entries have required fields ────────
def test_cx8_knowledge_entries_have_required_fields():
    for gate, entries in _KNOWLEDGE.items():
        for entry in entries:
            assert entry.source_text, f"gate={gate}: source_text is empty"
            assert entry.paper_ref,   f"gate={gate}: paper_ref is empty"
            assert entry.paper_doi,   f"gate={gate}: paper_doi is empty"
            assert entry.finding,     f"gate={gate}: finding is empty"


# ── CX-9: get_knowledge never returns None ────────────────────────────────────
def test_cx9_get_knowledge_never_none():
    for gate in ["clinical_study_isoforms", "investigate_isoforms", "tdi_concern",
                 "nonexistent_gate", "", "phase_2_ddi_risk"]:
        result = get_knowledge(gate)
        assert result is not None
        assert isinstance(result, list)


# ── CX-10: forum entries — all gates are valid QC gate names ─────────────────
def test_cx10_forum_entry_gates_valid():
    valid_gates = {"clinical_study_isoforms", "investigate_isoforms", "tdi_concern"}
    for entry in FORUM_ENTRIES:
        assert entry.gate in valid_gates, (
            f"ForumEntry has unknown gate: {entry.gate!r}"
        )


# ── CX-11: forum entries all have non-empty verbatim ─────────────────────────
def test_cx11_forum_entries_have_verbatim():
    for entry in FORUM_ENTRIES:
        assert entry.verbatim.strip(), f"ForumEntry {entry.thread_title!r} has empty verbatim"


# ── CX-12: get_forum_entries returns only matching gate ──────────────────────
def test_cx12_get_forum_entries_filters_correctly():
    clinical_entries = get_forum_entries("clinical_study_isoforms")
    assert all(e.gate == "clinical_study_isoforms" for e in clinical_entries)
    tdi_entries = get_forum_entries("tdi_concern")
    assert all(e.gate == "tdi_concern" for e in tdi_entries)
    none_entries = get_forum_entries("nonexistent_gate")
    assert none_entries == []


# ── CX-13: verbose=False suppresses citations in terminal ────────────────────
def test_cx13_verbose_false_no_citation_text(tmp_path):
    buf = StringIO()
    reporter = ProgressReporter(
        console=Console(file=buf, highlight=False),
        json_sink=None,
        verbose=False,
    )
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cx13", output_dir=tmp_path,
        max_retries_per_phase=1, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": [CLINICAL_1, CLEAN]})
    loop.run(runner)
    output = buf.getvalue()
    # "Evidence:" section only appears when verbose=True
    assert "Evidence:" not in output


# ── CX-14: json_sink=None — no AttributeError crash ──────────────────────────
def test_cx14_no_sink_no_crash(tmp_path):
    reporter = ProgressReporter(
        console=Console(file=StringIO()),
        json_sink=None,
    )
    loop = UXAwareCYPDDIAutoLoop(run_id="cx14", output_dir=tmp_path, reporter=reporter)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    result = loop.run(runner)
    assert result.phases_passed == ["phase_2_ddi_risk"]


# ── CX-15: SSE autoloop_phase_start contains params_summary ──────────────────
def test_cx15_sse_phase_start_has_params():
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareCYPDDIAutoLoop(run_id="cx15", output_dir=None, reporter=reporter)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    start = next(e for e in events if e["event"] == "autoloop_phase_start")
    assert "params_summary" in start
    assert isinstance(start["params_summary"], dict)


# ── CX-16: SSE gate_results contains all three gate names ────────────────────
def test_cx16_sse_gate_results_all_gates():
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareCYPDDIAutoLoop(run_id="cx16", output_dir=None, reporter=reporter)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    gate_event = next(e for e in events if e["event"] == "autoloop_gate_results")
    gate_names = {g["gate"] for g in gate_event["gates"]}
    assert "clinical_study_isoforms" in gate_names
    assert "investigate_isoforms" in gate_names
    assert "tdi_concern" in gate_names


# ── CX-17: multiple retries produce multiple autoloop_update events ───────────
def test_cx17_multiple_updates_on_retries():
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cx17", output_dir=None,
        max_retries_per_phase=2, reporter=reporter,
    )
    # Fail twice, then pass
    runner = MockPhaseRunner({"phase_2_ddi_risk": [CLINICAL_1, CLINICAL_1, CLEAN]})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    updates = [e for e in events if e["event"] == "autoloop_update"]
    assert len(updates) == 2  # two retries triggered


# ── CX-18: total_attempts == max_retries+1 on persistent fail ────────────────
def test_cx18_total_attempts_exact_on_fail(tmp_path):
    max_retries = 3
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cx18", output_dir=tmp_path,
        max_retries_per_phase=max_retries,
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLINICAL_1})
    result = loop.run(runner)
    assert result.total_attempts == max_retries + 1


# ── CX-19: params snapshot in SSE update records pre-change values ────────────
def test_cx19_sse_update_has_phase_and_attempt():
    sink = StringIO()
    reporter = ProgressReporter(console=Console(file=StringIO()), json_sink=sink)
    loop = UXAwareCYPDDIAutoLoop(
        run_id="cx19", output_dir=None,
        max_retries_per_phase=1, reporter=reporter,
    )
    runner = MockPhaseRunner({"phase_2_ddi_risk": [CLINICAL_1, CLEAN]})
    loop.run(runner)
    events = [json.loads(l) for l in sink.getvalue().strip().split("\n") if l]
    update = next(e for e in events if e["event"] == "autoloop_update")
    assert update["phase"] == "phase_2_ddi_risk"
    assert update["attempt"] == 1
    assert update["next_attempt"] == 2


# ── CX-20: strict profile — 0 investigate allowed → any INVESTIGATE HALTS ────
def test_cx20_strict_zero_investigate():
    ev = CYPDDIQCEvaluator("cyp_ddi_strict")
    for n in range(1, 5):
        metrics = {"summary": {"n_clinical": 0, "n_investigate": n, "n_tdi": 0,
                                "overall_recommendation": "INVESTIGATE"}}
        result = ev.evaluate_phase_2(metrics)
        assert not result.passed, f"strict: n_investigate={n} should HALT"


# ── CX-21: all profiles have expected keys ────────────────────────────────────
def test_cx21_all_profiles_have_expected_keys():
    required = {"max_clinical_isoforms", "max_investigate_isoforms", "min_ic50_flagged_uM"}
    for name, profile in QC_PROFILES.items():
        for key in required:
            assert key in profile, f"Profile {name!r} missing key {key!r}"


# ── CX-22: params to_dict / copy roundtrip ────────────────────────────────────
def test_cx22_params_roundtrip():
    p = CYPDDIParams(cmax_ss_uM=3.5, r1_clinical_threshold=1.15)
    d = p.to_dict()
    p2 = CYPDDIParams(**d)
    assert p2.cmax_ss_uM == 3.5
    assert p2.r1_clinical_threshold == 1.15


# ── CX-23: enriched remediation to_dict schema ───────────────────────────────
def test_cx23_enriched_remediation_schema():
    ev = CYPDDIQCEvaluator("cyp_ddi_standard")
    tuner = KnowledgeEnrichedCYPTuner()
    qc = ev.evaluate_phase_2(CLINICAL_1)
    _, remeds = tuner.remediate(qc, CYPDDIParams())
    for r in remeds:
        d = r.to_dict()
        for key in ("phase", "gate", "param_changes", "rationale", "citations"):
            assert key in d, f"Missing key {key!r} in to_dict()"
        for c in d["citations"]:
            for ckey in ("source_text", "paper_ref", "paper_doi", "finding"):
                assert ckey in c, f"Missing citation key {ckey!r}"


# ── CX-24: summary file contains run_id ───────────────────────────────────────
def test_cx24_summary_contains_run_id(tmp_path):
    loop = UXAwareCYPDDIAutoLoop(run_id="cx24-myrun", output_dir=tmp_path)
    runner = MockPhaseRunner({"phase_2_ddi_risk": CLEAN})
    loop.run(runner)
    summary = tmp_path / "cx24-myrun_summary.txt"
    assert summary.exists()
    assert "cx24-myrun" in summary.read_text()
