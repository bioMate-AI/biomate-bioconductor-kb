"""Cox proportional-hazards QC evaluator for the survival auto-loop.

Consumes a metrics dict adapted from the workflow's `survival_qc.json`:

    {
      "schoenfeld_global_p": 0.41,          # cox.zph global test p-value
      "ph_violating_covariates": ["age"],   # per-term zph p < 0.05 (optional)
      "omitted_confounders": [              # prognostic covariates left OUT of
        {"name": "ecog_ge1", "hr": 2.15, "p": 1.6e-5},   #   the naive model
        {"name": "liver_mets", "hr": 1.49, "p": 0.017}
      ],
      "naive_primary_hr": 0.818,            # exposure HR, naive model (optional)
      "adjusted_primary_hr": 0.819          # exposure HR, adjusted model (optional)
    }

Reuses the shared gate dataclasses so the autoloop_bridge serialises the
results identically to the other domains.
"""

from experiments.admet_autoloop.qc_evaluator import (
    QCAction, QCLevel, RegulatoryBasis, GateResult, PhaseQCResult,
)

PH_PVALUE_THRESHOLD = 0.05
CONFOUNDER_PVALUE_THRESHOLD = 0.05


class SurvivalQCEvaluator:
    """One phase: phase_1_cox. Two gates: PH assumption + omitted confounding."""

    def __init__(self, profile: str = "survival_standard"):
        self.profile = profile

    def evaluate_phase(self, phase: str, metrics: dict) -> PhaseQCResult:
        if phase != "phase_1_cox":
            # single-phase domain; be permissive about the label
            phase = "phase_1_cox"
        gates: list[GateResult] = []

        # ── Gate 1: proportional-hazards (Schoenfeld) ────────────────────────
        zph_p = metrics.get("schoenfeld_global_p")
        if zph_p is not None:
            violated = zph_p < PH_PVALUE_THRESHOLD
            viol_terms = metrics.get("ph_violating_covariates") or []
            gates.append(GateResult(
                gate="cox_ph_schoenfeld",
                action=QCAction.HALT if violated else QCAction.PASS,
                level=QCLevel.FAIL if violated else QCLevel.GOLD,
                value=float(zph_p),
                threshold=PH_PVALUE_THRESHOLD,
                message=(
                    f"Proportional-hazards assumption violated (Schoenfeld global p={zph_p:.3g}"
                    + (f"; terms: {', '.join(viol_terms)}" if viol_terms else "") + ")"
                    if violated else
                    f"Proportional-hazards assumption holds (Schoenfeld global p={zph_p:.3g})"
                ),
                suggestion=(
                    "Stratify on the violating covariate(s) or add a time-transform"
                    if violated else ""
                ),
                regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
            ))

        # ── Gate 2: omitted-confounder detection ─────────────────────────────
        omitted = metrics.get("omitted_confounders") or []
        sig = [c for c in omitted
               if c.get("p") is not None and c["p"] < CONFOUNDER_PVALUE_THRESHOLD]
        if omitted:
            worst_p = min((c["p"] for c in sig), default=1.0)
            confounded = len(sig) > 0
            names = ", ".join(f"{c['name']} (HR {c.get('hr','?')}, p={c['p']:.2g})" for c in sig)
            gates.append(GateResult(
                gate="cox_confounding",
                action=QCAction.HALT if confounded else QCAction.PASS,
                level=QCLevel.FAIL if confounded else QCLevel.GOLD,
                value=float(worst_p),
                threshold=CONFOUNDER_PVALUE_THRESHOLD,
                message=(
                    f"Naive model omits significant prognostic covariate(s): {names}"
                    if confounded else
                    "No significant omitted prognostic covariate detected"
                ),
                suggestion=(
                    "Re-fit adjusting for the omitted covariate(s): "
                    + ", ".join(c["name"] for c in sig)
                    if confounded else ""
                ),
                regulatory_basis=RegulatoryBasis.RISK_STRATIFICATION,
            ))

        return PhaseQCResult(phase=phase, gate_results=gates)
