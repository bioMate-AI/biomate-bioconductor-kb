"""Survival (Cox PH) parameter schema for the auto-loop.

Thresholds anchored to:
  - Grambsch PM, Therneau TM. Biometrika 1994;81:515 (Schoenfeld-residual
    test for proportional hazards; cox.zph). Global test p < 0.05 => PH
    violated for the model.
  - Standard confounding criterion: a covariate that is prognostic
    (significant in the model) AND associated with the exposure, omitted
    from the naive model, biases the exposure effect. Operationally we
    flag an omitted covariate that is significant at p < 0.05.
"""

from dataclasses import dataclass, field, asdict
from typing import List


@dataclass
class SurvivalParams:
    """Tunable parameters for a Cox proportional-hazards survival run."""

    # Columns the model currently adjusts for. The first is the exposure /
    # biomarker of interest (e.g. the CD8 T-effector signature).
    covariates: List[str] = field(default_factory=lambda: ["biomarker"])

    # Prognostic covariates available in the data but NOT yet in the model.
    # The evaluator flags them when they are significant; the tuner moves
    # them into `covariates` (the confounder -> re-fit correction).
    candidate_confounders: List[str] = field(default_factory=list)

    # Covariates to stratify on (used when they violate proportional hazards
    # instead of being modelled as a linear term).
    strata: List[str] = field(default_factory=list)

    # Gate thresholds.
    ph_pvalue_threshold: float = 0.05          # Schoenfeld global p < this => PH FAIL
    confounder_pvalue_threshold: float = 0.05  # omitted covariate p < this => confounding FAIL

    def as_dict(self) -> dict:
        return asdict(self)
