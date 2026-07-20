"""
ICH M7 dual-model Ames mutagenicity gate tests.

ICH M7 (2014, rev 2023) §5.1: two complementary computational approaches required.
  Model A: expert rule-based (structural alerts — Kazius 2005)
  Model B: statistical QSAR (Hansen 2009 RF / Lhasa Nexus / equivalent)

Concordance rules (ICH M7 Table 1):
  Both negative                    → PASS
  Both positive                    → HALT (ICH S2R1 wet-lab test mandated)
  Discordant (A+/B- or A-/B+)     → ADVISORY + ames_model_concordance ADVISORY gate
  Model B absent                   → ADVISORY on ames_statistical_qsar gate
"""
from experiments.admet_autoloop.qc_evaluator import ADMETQCEvaluator, QCAction, RegulatoryBasis


def _gates(metrics: dict) -> dict:
    ev = ADMETQCEvaluator("admet_standard")
    result = ev.evaluate_phase("phase_2_admet_prediction", metrics)
    return {g.gate: g for g in result.gate_results}


BASE = {
    "herg_ic50_uM": 20.0,
    "dili_probability": 0.2,
    "dili_risk": "low",
    "logP": 2.5,
    "mw": 350.0,
}


# ── Both models negative ───────────────────────────────────────────────────────

def test_both_negative_pass():
    """Both models clear → PASS, no concordance gate emitted."""
    g = _gates({**BASE, "ames_positive": False, "ames_probability": 0.1,
                "ames_statistical_positive": False, "ames_statistical_probability": 0.15})
    assert g["ames_mutagenicity"].action == QCAction.PASS
    assert g["ames_statistical_qsar"].action == QCAction.PASS
    assert "ames_model_concordance" not in g


# ── Both models positive ───────────────────────────────────────────────────────

def test_both_positive_halt():
    """Both models positive → both HALT, no concordance gate (they agree)."""
    g = _gates({**BASE, "ames_positive": True, "ames_probability": 0.8,
                "ames_statistical_positive": True, "ames_statistical_probability": 0.75})
    assert g["ames_mutagenicity"].action == QCAction.HALT
    assert g["ames_statistical_qsar"].action == QCAction.HALT
    assert "ames_model_concordance" not in g, "Concordant result should not emit concordance gate"


def test_both_positive_are_regulatory():
    """Both Ames gates must be REGULATORY basis (ICH S2R1 mandated)."""
    g = _gates({**BASE, "ames_positive": True, "ames_probability": 0.8,
                "ames_statistical_positive": True, "ames_statistical_probability": 0.75})
    assert g["ames_mutagenicity"].regulatory_basis == RegulatoryBasis.REGULATORY
    assert g["ames_statistical_qsar"].regulatory_basis == RegulatoryBasis.REGULATORY


# ── Discordant: alert positive, statistical negative ──────────────────────────

def test_discordant_a_positive_b_negative():
    """Alert-based positive, statistical negative → A halts, B passes, concordance ADVISORY."""
    g = _gates({**BASE, "ames_positive": True, "ames_probability": 0.7,
                "ames_statistical_positive": False, "ames_statistical_probability": 0.2})
    assert g["ames_mutagenicity"].action == QCAction.HALT
    assert g["ames_statistical_qsar"].action == QCAction.PASS
    assert "ames_model_concordance" in g
    conc = g["ames_model_concordance"]
    assert conc.action == QCAction.ADVISORY
    assert conc.regulatory_basis == RegulatoryBasis.REGULATORY
    assert "discordant" in conc.message.lower()
    assert "equivocal" in conc.message.lower()


def test_discordant_a_negative_b_positive():
    """Alert-based negative, statistical positive → A passes, B halts, concordance ADVISORY."""
    g = _gates({**BASE, "ames_positive": False, "ames_probability": 0.1,
                "ames_statistical_positive": True, "ames_statistical_probability": 0.72})
    assert g["ames_mutagenicity"].action == QCAction.PASS
    assert g["ames_statistical_qsar"].action == QCAction.HALT
    assert "ames_model_concordance" in g
    assert g["ames_model_concordance"].action == QCAction.ADVISORY


# ── Model B absent (single-model run — pre-ICH-M7) ───────────────────────────

def test_model_b_absent_advisory():
    """When statistical model output is absent, ames_statistical_qsar is ADVISORY (not HALT/PASS)."""
    g = _gates({**BASE, "ames_positive": False, "ames_probability": 0.1})
    assert "ames_statistical_qsar" in g
    stat = g["ames_statistical_qsar"]
    assert stat.action == QCAction.ADVISORY
    assert "ICH M7" in stat.suggestion
    assert "not run" in stat.message.lower() or "not" in stat.message.lower()


def test_model_b_absent_no_concordance_gate():
    """No concordance gate when model B was not run."""
    g = _gates({**BASE, "ames_positive": False, "ames_probability": 0.2})
    assert "ames_model_concordance" not in g


def test_model_b_absent_a_positive_still_halts():
    """Alert positive with no model B → alert HALT + statistical ADVISORY (not masking the halt)."""
    g = _gates({**BASE, "ames_positive": True, "ames_probability": 0.9})
    assert g["ames_mutagenicity"].action == QCAction.HALT
    assert g["ames_statistical_qsar"].action == QCAction.ADVISORY


# ── Probability-only classification (no explicit _positive bool) ──────────────

def test_statistical_probability_only():
    """ames_statistical_positive inferred from probability > 0.5 if bool not provided."""
    g = _gates({**BASE, "ames_positive": False, "ames_probability": 0.1,
                "ames_statistical_probability": 0.65})
    # 0.65 > 0.5 threshold → statistical model effectively positive
    assert g["ames_statistical_qsar"].action == QCAction.HALT
    assert "ames_model_concordance" in g, "A-/B+ → discordant → concordance gate expected"


# ── Profile variations ────────────────────────────────────────────────────────

def test_cns_profile_stricter_thresholds():
    """CNS profile has ames_probability_max=0.3; same probability that passes standard fails CNS."""
    ev_std = ADMETQCEvaluator("admet_standard")
    ev_cns = ADMETQCEvaluator("admet_cns")
    metrics = {**BASE, "ames_positive": False, "ames_probability": 0.4,
               "ames_statistical_positive": False, "ames_statistical_probability": 0.25}
    std_gates = {g.gate: g for g in ev_std.evaluate_phase("phase_2_admet_prediction", metrics).gate_results}
    cns_gates = {g.gate: g for g in ev_cns.evaluate_phase("phase_2_admet_prediction", metrics).gate_results}
    # Standard: 0.4 < 0.5 threshold → PASS or ADVISORY
    assert std_gates["ames_mutagenicity"].action in (QCAction.PASS, QCAction.ADVISORY)
    # CNS: 0.4 > 0.3 threshold → HALT
    assert cns_gates["ames_mutagenicity"].action == QCAction.HALT


def test_gate_count_with_model_b():
    """Discordant run emits 3 Ames gates: alert-based + statistical + concordance."""
    g = _gates({**BASE, "ames_positive": True, "ames_probability": 0.7,
                "ames_statistical_positive": False, "ames_statistical_probability": 0.2})
    ames_gates = [k for k in g if k.startswith("ames")]
    assert len(ames_gates) == 3, f"Expected 3 Ames gates, got {ames_gates}"


def test_concordance_suggestion_mentions_expert_review():
    """Concordance gate suggestion must mention expert review and wet-lab."""
    g = _gates({**BASE, "ames_positive": True, "ames_probability": 0.7,
                "ames_statistical_positive": False, "ames_statistical_probability": 0.2})
    sug = g["ames_model_concordance"].suggestion.lower()
    assert "expert" in sug
    assert "wet-lab" in sug or "in vitro" in sug
