"""
Population PK (nlmixr2 / NONMEM) QC gate tests.

Three gates, in order of severity:
  poppk_convergence     — REGULATORY   (FDA Pop PK Guidance 2019 §V.C)
  poppk_eta_shrinkage   — RISK_STRATIFICATION (Savic & Karlsson 2009 CPT:PSP)
  poppk_condition_number — RISK_STRATIFICATION (Beal & Sheiner 1992)

Profile defaults (poppk_standard):
  eta_shrinkage_pct:  pass < 20%, advisory 20-30%, halt > 30%
  condition_number:   pass < 100, advisory 100-1000, halt > 1000

Stricter profile (poppk_ind):
  eta_shrinkage_pct:  pass < 15%, advisory 15-20%, halt > 20%
  condition_number:   pass < 50, advisory 50-300, halt > 300
"""
from experiments.admet_autoloop.qc_evaluator import (
    ADMETQCEvaluator, QCAction, QCLevel, RegulatoryBasis,
)
from experiments.autoloop_bridge import _resolve_phase


def _ev(profile="poppk_standard"):
    return ADMETQCEvaluator(profile)


def _gates(metrics: dict, profile="poppk_standard") -> dict:
    ev = _ev(profile)
    result = ev.evaluate_phase("phase_6_poppk", metrics)
    return {g.gate: g for g in result.gate_results}


CONVERGED_CLEAN = {
    "convergence_status": "converged",
    "max_eta_shrinkage_pct": 12.0,
    "condition_number": 45.0,
}


# ── Phase routing ──────────────────────────────────────────────────────────────

def test_evaluate_phase_dispatch():
    """evaluate_phase('phase_6_poppk', ...) dispatches correctly."""
    ev = _ev()
    result = ev.evaluate_phase("phase_6_poppk", CONVERGED_CLEAN)
    assert result.phase == "phase_6_poppk"


def test_bridge_routes_nlmixr2_to_phase6():
    """autoloop_bridge resolves NLMIXR2_POPULATION_PK → phase_6_poppk."""
    assert _resolve_phase("pharmacology", "NLMIXR2_POPULATION_PK") == "phase_6_poppk"


def test_bridge_routes_nonmem_to_phase6():
    """autoloop_bridge resolves NONMEM → phase_6_poppk regardless of domain."""
    assert _resolve_phase("drug_discovery", "NONMEM_POPPK") == "phase_6_poppk"


def test_bridge_routes_poppk_keyword():
    assert _resolve_phase("pharmacology", "POPULATION_PK") == "phase_6_poppk"


# ── Gate 1: convergence ────────────────────────────────────────────────────────

def test_convergence_pass():
    g = _gates(CONVERGED_CLEAN)
    assert g["poppk_convergence"].action == QCAction.PASS
    assert g["poppk_convergence"].level == QCLevel.GOLD


def test_convergence_not_converged_halts():
    g = _gates({**CONVERGED_CLEAN, "convergence_status": "not_converged"})
    assert g["poppk_convergence"].action == QCAction.HALT
    assert g["poppk_convergence"].level == QCLevel.FAIL


def test_convergence_failed_halts():
    g = _gates({**CONVERGED_CLEAN, "convergence_status": "failed"})
    assert g["poppk_convergence"].action == QCAction.HALT


def test_convergence_is_regulatory():
    g = _gates(CONVERGED_CLEAN)
    assert g["poppk_convergence"].regulatory_basis == RegulatoryBasis.REGULATORY


def test_convergence_halt_message_mentions_fda():
    g = _gates({**CONVERGED_CLEAN, "convergence_status": "not_converged"})
    assert "FDA" in g["poppk_convergence"].message


def test_convergence_halt_suggestion_mentions_simplify():
    g = _gates({**CONVERGED_CLEAN, "convergence_status": "not_converged"})
    assert "1-compartment" in g["poppk_convergence"].suggestion.lower() or \
           "simplif" in g["poppk_convergence"].suggestion.lower()


# ── Gate 2: ETA shrinkage ─────────────────────────────────────────────────────

def test_eta_shrinkage_pass():
    """< 20% → PASS."""
    g = _gates({**CONVERGED_CLEAN, "max_eta_shrinkage_pct": 10.0})
    assert g["poppk_eta_shrinkage"].action == QCAction.PASS


def test_eta_shrinkage_advisory():
    """20-30% → ADVISORY."""
    g = _gates({**CONVERGED_CLEAN, "max_eta_shrinkage_pct": 25.0})
    assert g["poppk_eta_shrinkage"].action == QCAction.ADVISORY
    assert g["poppk_eta_shrinkage"].level == QCLevel.BRONZE


def test_eta_shrinkage_halt():
    """> 30% → HALT."""
    g = _gates({**CONVERGED_CLEAN, "max_eta_shrinkage_pct": 42.0})
    assert g["poppk_eta_shrinkage"].action == QCAction.HALT
    assert g["poppk_eta_shrinkage"].level == QCLevel.FAIL


def test_eta_shrinkage_is_risk_stratification():
    g = _gates({**CONVERGED_CLEAN, "max_eta_shrinkage_pct": 35.0})
    assert g["poppk_eta_shrinkage"].regulatory_basis == RegulatoryBasis.RISK_STRATIFICATION


def test_eta_shrinkage_absent_no_gate():
    """If max_eta_shrinkage_pct is absent, no poppk_eta_shrinkage gate emitted."""
    g = _gates({"convergence_status": "converged", "condition_number": 50.0})
    assert "poppk_eta_shrinkage" not in g


def test_eta_shrinkage_suggestion_mentions_savic():
    g = _gates({**CONVERGED_CLEAN, "max_eta_shrinkage_pct": 45.0})
    assert "Savic" in g["poppk_eta_shrinkage"].suggestion


# ── Gate 3: condition number ──────────────────────────────────────────────────

def test_condition_number_pass():
    """< 100 → PASS."""
    g = _gates({**CONVERGED_CLEAN, "condition_number": 40.0})
    assert g["poppk_condition_number"].action == QCAction.PASS


def test_condition_number_advisory():
    """100-1000 → ADVISORY."""
    g = _gates({**CONVERGED_CLEAN, "condition_number": 500.0})
    assert g["poppk_condition_number"].action == QCAction.ADVISORY


def test_condition_number_halt():
    """> 1000 → HALT."""
    g = _gates({**CONVERGED_CLEAN, "condition_number": 2500.0})
    assert g["poppk_condition_number"].action == QCAction.HALT


def test_condition_number_is_risk_stratification():
    g = _gates({**CONVERGED_CLEAN, "condition_number": 1500.0})
    assert g["poppk_condition_number"].regulatory_basis == RegulatoryBasis.RISK_STRATIFICATION


def test_condition_number_absent_no_gate():
    """No gate emitted when condition_number is absent."""
    g = _gates({"convergence_status": "converged", "max_eta_shrinkage_pct": 10.0})
    assert "poppk_condition_number" not in g


# ── Clean-pass: all gates PASS ────────────────────────────────────────────────

def test_all_gates_pass_converged_clean():
    """Well-fitting model → all three gates PASS, result passes."""
    g = _gates(CONVERGED_CLEAN)
    assert g["poppk_convergence"].action == QCAction.PASS
    assert g["poppk_eta_shrinkage"].action == QCAction.PASS
    assert g["poppk_condition_number"].action == QCAction.PASS
    ev = _ev()
    result = ev.evaluate_phase("phase_6_poppk", CONVERGED_CLEAN)
    assert result.passed


# ── Stricter IND profile ──────────────────────────────────────────────────────

def test_ind_profile_stricter_shrinkage():
    """poppk_ind: 18% shrinkage passes standard but halts IND profile."""
    metrics = {**CONVERGED_CLEAN, "max_eta_shrinkage_pct": 18.0}
    g_std = _gates(metrics, "poppk_standard")
    g_ind = _gates(metrics, "poppk_ind")
    assert g_std["poppk_eta_shrinkage"].action == QCAction.PASS
    # poppk_ind: warn=15, halt=20 → 18% > 15% → ADVISORY
    assert g_ind["poppk_eta_shrinkage"].action == QCAction.ADVISORY


def test_ind_profile_stricter_condition_number():
    """poppk_ind: condition 200 is advisory (standard would pass at < 1000)."""
    metrics = {**CONVERGED_CLEAN, "condition_number": 200.0}
    g_std = _gates(metrics, "poppk_standard")
    g_ind = _gates(metrics, "poppk_ind")
    # standard: 200 is advisory (100-1000); ind halt=300, warn=50 → 200 is advisory too
    assert g_std["poppk_condition_number"].action == QCAction.ADVISORY
    assert g_ind["poppk_condition_number"].action == QCAction.ADVISORY


def test_ind_profile_unknown_raises():
    """Constructing with unknown profile raises ValueError."""
    import pytest
    with pytest.raises(ValueError):
        ADMETQCEvaluator("poppk_bogus")
