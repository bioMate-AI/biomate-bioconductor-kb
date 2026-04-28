"""
CYP DDI parameter schema.

Thresholds derived from FDA DDI guidance (2020) as implemented in
drug_discovery/cyp_ddi_panel/main.nf:

  R1  = 1 + (Imax / Ki)   — reversible inhibition ratio
  R1gut = 1 + (fa * Dose / (250 * Ki))  — intestinal inhibition
  R2  = 1 / (1 + kinact * [I]gut / (kdeg * (KI + [I]gut)))  — TDI proxy

  R1  ≥ 1.02  → INVESTIGATE
  R1  ≥ 1.1   → CLINICAL_STUDY_RECOMMENDED
  R1gut ≥ 11  → CLINICAL_STUDY_RECOMMENDED
  R2  ≤ 0.79  → INVESTIGATE
  R2  ≤ 0.71  → CLINICAL_STUDY_RECOMMENDED
"""

from dataclasses import dataclass, field, asdict


@dataclass
class CYPDDIParams:
    """Tunable parameters for a CYP DDI panel run."""

    # ── DDI perpetrator threshold adjustments ─────────────────────────────────
    # FDA 2020: R1 ≥ 1.02 = INVESTIGATE; ≥ 1.1 = CLINICAL_STUDY
    r1_investigate_threshold: float = 1.02     # raise to relax gate
    r1_clinical_threshold: float = 1.10
    r1gut_clinical_threshold: float = 11.0
    r2_investigate_threshold: float = 0.79     # lower means stricter (R2 ≤ thresh → flag)
    r2_clinical_threshold: float = 0.71

    # ── Risk flag tolerances ──────────────────────────────────────────────────
    max_clinical_isoforms: int = 0    # HALT if any isoform triggers CLINICAL_STUDY
    max_investigate_isoforms: int = 2  # HALT if >2 isoforms flag INVESTIGATE

    # ── Compound/assay parameters ─────────────────────────────────────────────
    fu_mic: float = 1.0              # fraction unbound in microsomal assay
    fu_plasma: float = 1.0           # fraction unbound in plasma
    max_clinical_dose_mg: float = 100.0
    cmax_ss_uM: float = 1.0          # steady-state Cmax (µM) for R1 calculation

    # ── Screening scope ───────────────────────────────────────────────────────
    isoforms_tested: list = field(default_factory=lambda: [
        "CYP1A2", "CYP2B6", "CYP2C8", "CYP2C9", "CYP2C19", "CYP2D6", "CYP3A4"
    ])
    run_tdi_screen: bool = True      # include time-dependent inhibition check

    def to_dict(self) -> dict:
        return asdict(self)

    def copy(self) -> "CYPDDIParams":
        return CYPDDIParams(**{k: v for k, v in asdict(self).items()})


PHASE_PARAM_OWNERS: dict[str, list[str]] = {
    "phase_1_cyp_inhibition": [
        "fu_mic", "cmax_ss_uM", "isoforms_tested",
    ],
    "phase_2_ddi_risk": [
        "r1_investigate_threshold", "r1_clinical_threshold",
        "r1gut_clinical_threshold", "r2_investigate_threshold",
        "r2_clinical_threshold", "max_clinical_isoforms",
        "max_investigate_isoforms", "max_clinical_dose_mg",
    ],
    "phase_3_clearance_correction": [
        "fu_plasma",
    ],
}
