"""Tests for the generic Power / EPV / sample-size critic (PowerEPVCritic).

The flagship SAFE-first critic: advisory-only (FLAG), zero causal-inference risk.
Covers the three underpowered-design conditions, the graceful-degradation / silence
path, grounding, and end-to-end dispatch through the hook + registry.

Run:
    cd backend && PYTHONPATH=lib python3.9 -m pytest tests/test_power_critic.py -q
"""
import sys
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_LIB = ROOT / "backend" / "lib"
sys.path.insert(0, str(_LIB))

# Real import first; lightweight galaxy.ai namespace stub only if the heavy parent-init
# is broken locally (same pattern as test_survival_critic.py).
try:  # noqa: SIM105
    import galaxy.ai.critics  # noqa: F401
except Exception:
    _stub = types.ModuleType("galaxy.ai")
    _stub.__path__ = [str(_LIB / "galaxy" / "ai")]
    sys.modules["galaxy.ai"] = _stub

from galaxy.ai.critics import (  # noqa: E402
    RunContext, RemediationKind, Severity, run_critics_from_run_meta, get_registry,
)
from galaxy.ai.critics.critics.power import PowerEPVCritic  # noqa: E402


# ── validation fixtures ───────────────────────────────────────────────────────

# FIRES: Cox model, 24 events / 6 covariates -> EPV 4.0 (< 5, severe); AND a DE arm
# with a 2-replicate smallest group; AND 30 obs / 6 params = 5.0 (not over-param).
DESIGN_FIRES = {
    "kind": "design", "run_id": "run-underpowered",
    "workflow": "cox_proportional_hazards_regression.nf",
    "workflow_domain": "survival",
    "inputs": {"input_data": "s3://b/clinical.csv"},
    "parameters": {},
    "design": {
        "formula": "Surv(time, status) ~ a + b + c + d + e + f",
        "covariates": ["a", "b", "c", "d", "e", "f"],
        "events": 24,
        "n_samples": 30,
        "group_sizes": {"treated": 2, "control": 8},
        "model_type": "cox",
    },
}

# DOES NOT FIRE: well-powered design. 200 events / 5 covariates = EPV 40; 6 reps/group;
# 200 obs / 5 params = 40 obs/param.
DESIGN_SILENT = {
    "kind": "design", "run_id": "run-powered",
    "workflow": "cox_proportional_hazards_regression.nf",
    "workflow_domain": "survival",
    "inputs": {"input_data": "s3://b/clinical.csv"},
    "parameters": {},
    "design": {
        "formula": "Surv(time, status) ~ a + b + c + d + e",
        "covariates": ["a", "b", "c", "d", "e"],
        "events": 200,
        "n_samples": 200,
        "group_sizes": {"treated": 6, "control": 6},
        "model_type": "cox",
    },
}

MANIFEST = {
    "kind": "results_manifest", "run_id": "run-x",
    "workflow_domain": "survival", "files": [],
}


def _ctx(design):
    return RunContext.from_contract(design, MANIFEST)


# ── 1. EPV ────────────────────────────────────────────────────────────────────

def test_power_epv_fires_below_floor_and_is_severe():
    issues = PowerEPVCritic().detect(_ctx(DESIGN_FIRES))
    epv = next(i for i in issues if i.code == "low_epv")
    assert epv.metrics["events"] == 24.0
    assert epv.metrics["n_covariates"] == 6.0
    assert epv.metrics["epv"] == 4.0
    assert epv.severity == Severity.CRITICAL  # EPV < 5
    assert epv.is_cited                        # grounded in power.epv_floor (GOLD, DOI)


def test_power_epv_covariates_list_counted_when_n_covariates_absent():
    d = {**DESIGN_FIRES, "design": {**DESIGN_FIRES["design"]}}
    d["design"].pop("n_covariates", None)  # rely on len(covariates)
    d["design"]["events"] = 60             # 60 / 6 = EPV 10 → NOT below floor
    issues = PowerEPVCritic().detect(_ctx(d))
    assert not any(i.code == "low_epv" for i in issues)


# ── 2. replicates ─────────────────────────────────────────────────────────────

def test_power_low_replicates_fires_and_flags_group():
    issues = PowerEPVCritic().detect(_ctx(DESIGN_FIRES))
    rep = next(i for i in issues if i.code == "low_replicates")
    assert "treated" in rep.subjects
    assert rep.metrics["min_replicates"] == 2.0
    assert rep.severity == Severity.WARNING  # 2 is underpowered but dispersion estimable
    assert rep.is_cited


def test_power_replicates_boundary_two_is_warning_not_critical():
    # smallest group == 2 → underpowered (WARNING) but dispersion still estimable.
    d = {**DESIGN_FIRES, "design": {**DESIGN_FIRES["design"], "group_sizes": {"t": 2, "c": 5}}}
    rep = next(i for i in PowerEPVCritic().detect(_ctx(d)) if i.code == "low_replicates")
    assert rep.severity == Severity.WARNING


def test_power_replicates_one_is_critical():
    d = {**DESIGN_FIRES, "design": {**DESIGN_FIRES["design"], "group_sizes": {"t": 1, "c": 5}}}
    rep = next(i for i in PowerEPVCritic().detect(_ctx(d)) if i.code == "low_replicates")
    assert rep.severity == Severity.CRITICAL


# ── 3. over-parameterisation ──────────────────────────────────────────────────

def test_power_overparameterized_non_identifiable():
    d = {**DESIGN_FIRES, "design": {
        "covariates": ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"],
        "n_samples": 8, "events": 200,  # events high so EPV does not fire here
    }}
    over = next(i for i in PowerEPVCritic().detect(_ctx(d)) if i.code == "overparameterized")
    assert over.metrics["non_identifiable"] is True
    assert over.severity == Severity.CRITICAL
    assert over.is_cited


# ── remediation ───────────────────────────────────────────────────────────────

def test_power_remediation_is_advisory_flag_that_changes_nothing():
    critic = PowerEPVCritic()
    for iss in critic.detect(_ctx(DESIGN_FIRES)):
        rem = critic.remediate(iss, _ctx(DESIGN_FIRES))
        assert rem.kind == RemediationKind.FLAG
        assert rem.params_delta == {}       # never edits the analysis
        assert rem.corrected == {}
        assert rem.applied is False          # advisory by default


# ── silence / graceful degradation ────────────────────────────────────────────

def test_power_silent_when_well_powered():
    assert PowerEPVCritic().detect(_ctx(DESIGN_SILENT)) == []


def test_power_silent_when_no_design_facts():
    # empty design + no QC → nothing to judge; must not guess.
    ctx = RunContext.from_contract({"design": {}}, MANIFEST)
    assert PowerEPVCritic().detect(ctx) == []


def test_power_reads_events_from_qc_fallback_when_absent_from_design():
    # events not in design; pulled from survival_qc.json like survival.py does.
    design = {**DESIGN_SILENT, "design": {
        "covariates": ["a", "b", "c", "d", "e", "f"],  # 6 covariates
        "model_type": "cox",
    }}
    ctx = RunContext.from_contract(
        design, MANIFEST,
        inline_artifacts={"survival_qc.json": {"n_events": 12}},  # 12 / 6 = EPV 2
    )
    epv = next(i for i in PowerEPVCritic().detect(ctx) if i.code == "low_epv")
    assert epv.metrics["epv"] == 2.0


# ── end-to-end through hook + registry ────────────────────────────────────────

def test_power_critic_registered_in_default_registry():
    ids = {c.critic_id for c in get_registry().all()}
    assert "power.epv" in ids


def test_power_full_hook_publishes_underpowered_findings():
    run_meta = {"run_id": "run-underpowered", "design": DESIGN_FIRES, "results_manifest": MANIFEST}
    report = run_critics_from_run_meta(run_meta)
    published = [f for f in report.findings if f.published]
    codes = {f.issue.code for f in published}
    assert {"low_epv", "low_replicates"} <= codes
    # every power finding carries an advisory FLAG remediation
    for f in published:
        if f.issue.critic_id == "power.epv":
            assert f.remediation.kind == RemediationKind.FLAG
            assert f.remediation.applied is False
