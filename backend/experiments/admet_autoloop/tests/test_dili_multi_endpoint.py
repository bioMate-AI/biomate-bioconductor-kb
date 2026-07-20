"""
DILI multi-endpoint gate tests.

Three gates, all RISK_STRATIFICATION, all optional (only emitted when field present):
  bsep_inhibition     — BSEP (ABCB11) inhibition probability (Dawson 2012 Drug Metab Dispos)
  mito_toxicity       — Mitochondrial toxicity probability (Xu 2008 Toxicol Sci)
  reactive_metabolites — Structural alert flag (Thompson 2006 Drug Metab Rev)

Profile thresholds (admet_standard):
  bsep: warn=0.5, halt=0.75
  mito: warn=0.5, halt=0.75

Oncology profile is more permissive (halt=0.85).
CNS profile is stricter (halt=0.6).

Absence behaviour: all three gates are SKIPPED (not emitted) when the corresponding
metrics key is absent — so legacy runs (no BSEP model output) don't get false halts.
"""
from experiments.admet_autoloop.qc_evaluator import ADMETQCEvaluator, QCAction, QCLevel, RegulatoryBasis


BASE = {
    "herg_ic50_uM": 20.0,
    "dili_probability": 0.2,
    "dili_risk": "low",
    "ames_positive": False,
    "ames_probability": 0.1,
    "ames_statistical_positive": False,
    "ames_statistical_probability": 0.1,
    "logP": 2.5,
    "mw": 350.0,
}


def _gates(metrics: dict, profile: str = "admet_standard") -> dict:
    ev = ADMETQCEvaluator(profile)
    result = ev.evaluate_phase_2(metrics)
    return {g.gate: g for g in result.gate_results}


# ── Absence: gates not emitted when fields absent ─────────────────────────────

def test_bsep_absent_no_gate():
    """No bsep_inhibition gate when field not in metrics."""
    g = _gates(BASE)
    assert "bsep_inhibition" not in g


def test_mito_absent_no_gate():
    g = _gates(BASE)
    assert "mito_toxicity" not in g


def test_reactive_met_absent_no_gate():
    """No reactive_metabolites gate when neither flag nor alerts list is present."""
    g = _gates(BASE)
    assert "reactive_metabolites" not in g


# ── BSEP gate ─────────────────────────────────────────────────────────────────

def test_bsep_pass():
    g = _gates({**BASE, "bsep_inhibition_probability": 0.3})
    assert g["bsep_inhibition"].action == QCAction.PASS
    assert g["bsep_inhibition"].level == QCLevel.GOLD


def test_bsep_advisory():
    """0.5–0.75 → ADVISORY."""
    g = _gates({**BASE, "bsep_inhibition_probability": 0.62})
    assert g["bsep_inhibition"].action == QCAction.ADVISORY
    assert g["bsep_inhibition"].level == QCLevel.BRONZE


def test_bsep_halt():
    """> 0.75 → HALT."""
    g = _gates({**BASE, "bsep_inhibition_probability": 0.85})
    assert g["bsep_inhibition"].action == QCAction.HALT
    assert g["bsep_inhibition"].level == QCLevel.FAIL


def test_bsep_is_risk_stratification():
    g = _gates({**BASE, "bsep_inhibition_probability": 0.8})
    assert g["bsep_inhibition"].regulatory_basis == RegulatoryBasis.RISK_STRATIFICATION


def test_bsep_halt_suggestion_mentions_dawson():
    g = _gates({**BASE, "bsep_inhibition_probability": 0.9})
    assert "Dawson" in g["bsep_inhibition"].suggestion or "BSEP" in g["bsep_inhibition"].suggestion


def test_bsep_pass_no_suggestion():
    g = _gates({**BASE, "bsep_inhibition_probability": 0.2})
    assert g["bsep_inhibition"].suggestion == ""


# ── Mitochondrial toxicity gate ───────────────────────────────────────────────

def test_mito_pass():
    g = _gates({**BASE, "mito_tox_probability": 0.2})
    assert g["mito_toxicity"].action == QCAction.PASS


def test_mito_advisory():
    g = _gates({**BASE, "mito_tox_probability": 0.6})
    assert g["mito_toxicity"].action == QCAction.ADVISORY


def test_mito_halt():
    g = _gates({**BASE, "mito_tox_probability": 0.9})
    assert g["mito_toxicity"].action == QCAction.HALT


def test_mito_is_risk_stratification():
    g = _gates({**BASE, "mito_tox_probability": 0.8})
    assert g["mito_toxicity"].regulatory_basis == RegulatoryBasis.RISK_STRATIFICATION


def test_mito_halt_suggestion_mentions_xu():
    g = _gates({**BASE, "mito_tox_probability": 0.85})
    assert "Xu" in g["mito_toxicity"].suggestion or "mito" in g["mito_toxicity"].suggestion.lower()


# ── Reactive metabolite gate ─────────────────────────────────────────────────

def test_rm_flag_false_passes():
    g = _gates({**BASE, "reactive_metabolite_flag": False})
    assert g["reactive_metabolites"].action == QCAction.PASS


def test_rm_flag_true_advisory():
    """Boolean flag True → ADVISORY (not HALT — needs confirmatory trapping assay)."""
    g = _gates({**BASE, "reactive_metabolite_flag": True})
    assert g["reactive_metabolites"].action == QCAction.ADVISORY
    assert g["reactive_metabolites"].level == QCLevel.BRONZE


def test_rm_alerts_list_advisory():
    """Named alert list → ADVISORY, alert names visible in message."""
    g = _gates({**BASE, "reactive_metabolite_alerts": ["furan", "aniline"]})
    assert g["reactive_metabolites"].action == QCAction.ADVISORY
    assert "furan" in g["reactive_metabolites"].message or "aniline" in g["reactive_metabolites"].message


def test_rm_empty_alerts_no_gate():
    """Empty list → no gate (treated as absent)."""
    g = _gates({**BASE, "reactive_metabolite_alerts": []})
    assert "reactive_metabolites" not in g


def test_rm_never_halts():
    """Reactive metabolite flag never escalates to HALT — advisory only."""
    g = _gates({**BASE, "reactive_metabolite_flag": True, "reactive_metabolite_alerts": ["furan", "nitro", "aniline", "Michael acceptor"]})
    assert g["reactive_metabolites"].action == QCAction.ADVISORY


def test_rm_is_risk_stratification():
    g = _gates({**BASE, "reactive_metabolite_flag": True})
    assert g["reactive_metabolites"].regulatory_basis == RegulatoryBasis.RISK_STRATIFICATION


def test_rm_suggestion_mentions_thompson():
    g = _gates({**BASE, "reactive_metabolite_flag": True})
    assert "Thompson" in g["reactive_metabolites"].suggestion


# ── Profile variations ────────────────────────────────────────────────────────

def test_oncology_more_permissive_bsep():
    """Oncology: bsep_halt=0.85 so probability 0.78 is only ADVISORY."""
    g_std = _gates({**BASE, "bsep_inhibition_probability": 0.78})
    g_onc = _gates({**BASE, "bsep_inhibition_probability": 0.78}, "admet_oncology")
    assert g_std["bsep_inhibition"].action == QCAction.HALT
    assert g_onc["bsep_inhibition"].action == QCAction.ADVISORY


def test_cns_stricter_mito():
    """CNS: mito_halt=0.6 so probability 0.65 halts CNS but is only ADVISORY in standard."""
    g_std = _gates({**BASE, "mito_tox_probability": 0.65})
    g_cns = _gates({**BASE, "mito_tox_probability": 0.65}, "admet_cns")
    assert g_std["mito_toxicity"].action == QCAction.ADVISORY
    assert g_cns["mito_toxicity"].action == QCAction.HALT


# ── All three new gates together ──────────────────────────────────────────────

def test_all_three_gates_clean_pass():
    """All three gates present and below thresholds → all PASS."""
    metrics = {
        **BASE,
        "bsep_inhibition_probability": 0.2,
        "mito_tox_probability":        0.15,
        "reactive_metabolite_flag":    False,
    }
    g = _gates(metrics)
    assert g["bsep_inhibition"].action == QCAction.PASS
    assert g["mito_toxicity"].action == QCAction.PASS
    assert g["reactive_metabolites"].action == QCAction.PASS


def test_all_three_gates_present_and_flagged():
    """All three flagged simultaneously — BSEP+mito HALT, RM ADVISORY."""
    metrics = {
        **BASE,
        "bsep_inhibition_probability": 0.85,
        "mito_tox_probability":        0.9,
        "reactive_metabolite_flag":    True,
    }
    g = _gates(metrics)
    assert g["bsep_inhibition"].action == QCAction.HALT
    assert g["mito_toxicity"].action == QCAction.HALT
    assert g["reactive_metabolites"].action == QCAction.ADVISORY
