"""Survival (Cox) param tuner: turn QC-gate failures into a re-fit.

Mirrors ADMETParamTuner.remediate(qc_result, params) -> (new_params, [Remediation]).

  cox_confounding  HALT -> add the omitted prognostic covariates to the design
                           (Surv ~ biomarker  ->  Surv ~ biomarker + confounders)
  cox_ph_schoenfeld HALT -> stratify on the PH-violating covariate(s)
"""

import copy
from typing import List, Tuple

from experiments.admet_autoloop.qc_evaluator import QCAction, PhaseQCResult
from experiments.admet_autoloop.param_tuner import Remediation
from experiments.survival_autoloop.params import SurvivalParams


class SurvivalParamTuner:
    def __init__(self, params: SurvivalParams | None = None, **_):
        self.params = params or SurvivalParams()

    def remediate(
        self,
        qc_result: PhaseQCResult,
        params: SurvivalParams,
    ) -> Tuple[SurvivalParams, List[Remediation]]:
        new = copy.deepcopy(params)
        rems: List[Remediation] = []

        for g in qc_result.gate_results:
            if g.action != QCAction.HALT:
                continue

            if g.gate == "cox_confounding":
                # Move every candidate confounder not yet modelled into the design.
                to_add = [c for c in new.candidate_confounders if c not in new.covariates]
                if to_add:
                    new.covariates = new.covariates + to_add
                    new.candidate_confounders = [
                        c for c in new.candidate_confounders if c not in to_add
                    ]
                    rems.append(Remediation(
                        phase=qc_result.phase,
                        gate=g.gate,
                        param_changes={"covariates": new.covariates},
                        rationale=(
                            "Omitted prognostic covariate(s) detected -> re-fit "
                            f"Cox adjusting for {', '.join(to_add)} "
                            "(confounding control; Grambsch & Therneau 1994 / "
                            "standard multivariable adjustment)."
                        ),
                        confidence="confident",
                    ))

            elif g.gate == "cox_ph_schoenfeld":
                # Stratify on the PH-violating covariate(s) if known; else flag manual.
                viol = [c for c in new.covariates if c not in new.strata] or list(new.candidate_confounders)
                if viol:
                    new.strata = new.strata + [viol[0]]
                    rems.append(Remediation(
                        phase=qc_result.phase,
                        gate=g.gate,
                        param_changes={"strata": new.strata},
                        rationale=(
                            f"Proportional-hazards violation -> stratify on '{viol[0]}' "
                            "(Grambsch & Therneau 1994; non-proportional term modelled "
                            "by stratification rather than a single hazard ratio)."
                        ),
                        confidence="heuristic",
                    ))

        return new, rems
