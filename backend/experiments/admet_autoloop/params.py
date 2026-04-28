"""
ADMET parameter schema and phase ownership map.

Gate thresholds mirror those in:
  - backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py
  - backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf

Parameters are partitioned by phase so the tuner knows which subset to adjust
when a given gate fails.
"""

from dataclasses import dataclass, field, asdict
from typing import Optional


@dataclass
class ADMETParams:
    """
    All tunable parameters for an ADMET-driven compound screening run.

    Two categories:
      - Safety gate thresholds: define what counts as a pass/fail
      - Screening scope: control which compounds enter / exit the funnel
    """

    # ── hERG cardiotoxicity gate ──────────────────────────────────────────────
    # ICH S7B: concern when hERG IC50 < 30× therapeutic Cmax; BioMate empirical
    # threshold from assay_ingestion.py: _HERG_SAFETY_THRESHOLD_uM = 10.0
    herg_ic50_threshold_uM: float = 10.0       # µM — HALT if min IC50 below this
    herg_safety_margin: float = 1.0            # multiplier: 1.0 = strict, 0.5 = relaxed

    # ── DILI (drug-induced liver injury) gate ─────────────────────────────────
    # Lammert 2010 Toxicol Sci model: logP > 4.0 AND MW > 400 → "high" risk
    dili_probability_max: float = 0.5          # HALT if worst-case DILI prob exceeds this
    dili_risk_level_max: str = "medium"        # "low" | "medium" | "high" — strings allowed

    # ── Ames mutagenicity gate ────────────────────────────────────────────────
    # Kazius structural alerts — binary flag in toxicity_report.json
    ames_probability_max: float = 0.5          # HALT if Ames probability exceeds this
    ames_strict: bool = False                  # True → HALT even on advisory (prob > 0.3)

    # ── Lipinski / physicochemical filter ────────────────────────────────────
    logp_max: float = 5.0                      # Lipinski Rule of 5
    mw_max_da: float = 500.0                   # Da — Rule of 5 upper bound
    hbd_max: int = 5                           # H-bond donors
    hba_max: int = 10                          # H-bond acceptors
    tpsa_max_A2: float = 140.0                 # topological polar surface area Å²

    # ── Screening funnel parameters ───────────────────────────────────────────
    num_candidates: int = 50                   # compounds submitted per iteration
    top_n_to_advance: int = 10                 # compounds advancing to next phase
    scaffold_diversity_min: float = 0.3        # Tanimoto dissimilarity between top hits

    # ── Iteration controls ────────────────────────────────────────────────────
    max_retries: int = 3                       # replicate of cryo_em_autoloop default
    strict_all_gates: bool = True              # True = all gates must pass; False = majority

    def to_dict(self) -> dict:
        return asdict(self)

    def copy(self) -> "ADMETParams":
        return ADMETParams(**asdict(self))


# Which parameters belong to each phase of the ADMET screening pipeline.
# Used by ADMETParamTuner to scope adjustments to the right phase.
PHASE_PARAM_OWNERS: dict[str, list[str]] = {
    "phase_1_virtual_screen": [
        "num_candidates",
        "top_n_to_advance",
        "scaffold_diversity_min",
        "logp_max",
        "mw_max_da",
        "hbd_max",
        "hba_max",
        "tpsa_max_A2",
    ],
    "phase_2_admet_prediction": [
        "herg_ic50_threshold_uM",
        "herg_safety_margin",
        "dili_probability_max",
        "dili_risk_level_max",
        "ames_probability_max",
        "ames_strict",
    ],
    "phase_3_herg_screen": [
        "herg_ic50_threshold_uM",
        "herg_safety_margin",
    ],
    "phase_4_dili_ames": [
        "dili_probability_max",
        "dili_risk_level_max",
        "ames_probability_max",
        "ames_strict",
    ],
    "phase_5_pk_properties": [
        # PK phase is advisory-only; no automated adjustment defined yet
    ],
}

# Human-readable names for reporting
PHASE_LABELS: dict[str, str] = {
    "phase_1_virtual_screen":  "Phase 1 — Virtual Screening",
    "phase_2_admet_prediction": "Phase 2 — ADMET Prediction",
    "phase_3_herg_screen":     "Phase 3 — hERG Safety Screen",
    "phase_4_dili_ames":       "Phase 4 — DILI / Ames Screen",
    "phase_5_pk_properties":   "Phase 5 — PK Properties",
}
