"""
Survival critics — the first migration of a bespoke ``.nf`` self-correction loop into
the generic Critic framework (Stream 3).

Historically, the Cox workflow's self-correction was hand-written R embedded in
``cox_proportional_hazards_regression.nf``: it emitted ``survival_qc.json`` and the
(per-domain) survival logic decided confounding/PH remediation. That couples the
statistics to the workflow file and is not reusable.

Here the SAME science is expressed as two framework critics that read ONLY the run
contract (``survival_qc.json`` + ``design.json`` + ``results_manifest.json``):

  * :class:`SurvivalConfoundingCritic` — detects significant omitted confounders and
    proposes the confounder-adjusted re-fit (naive HR 0.817 → adjusted HR 0.806 for
    the live Stream-3 case: ECOG + liver-metastasis confounders).
  * :class:`SurvivalPHCritic` — detects a proportional-hazards violation (Schoenfeld)
    and proposes stratification / a time-transform.

The DETECTION reads the contract. The optional RE-FIT is delegated to a reusable R
stats script (``r/survival_refit.R``) via :mod:`.r_refit`, decoupled from ``cox.nf``.
The script is only invoked when the clinical CSV is locally available AND ``Rscript``
is present AND ``allow_compute`` is set; otherwise the critic reports the naive-vs-
corrected numbers already present in ``survival_qc.json`` (which the emitter computes).
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from ..base import Critic, Issue, Remediation, RemediationKind, Severity
from ..run_context import RunContext
from ..evidence import design_rule

log = logging.getLogger(__name__)

_QC_ARTIFACT = "survival_qc.json"
_P_THRESHOLD = 0.05


def _load_qc(ctx: RunContext) -> Optional[Dict[str, Any]]:
    qc = ctx.load_json(_QC_ARTIFACT)
    return qc if isinstance(qc, dict) else None


class SurvivalConfoundingCritic(Critic):
    """Detect omitted prognostic confounders in a Cox model and propose the adjusted
    re-fit, surfacing the naive-vs-adjusted primary hazard ratio."""

    domain = "survival"
    critic_id = "survival.confounding"
    required_artifacts = [_QC_ARTIFACT]

    def detect(self, ctx: RunContext) -> List[Issue]:
        qc = _load_qc(ctx)
        if not qc:
            return []
        omitted = qc.get("omitted_confounders") or []
        significant = [
            c for c in omitted
            if isinstance(c, dict) and isinstance(c.get("p"), (int, float)) and c["p"] < _P_THRESHOLD
        ]
        if not significant:
            return []

        primary = qc.get("primary_covariate")
        naive_hr = qc.get("naive_primary_hr")
        adjusted_hr = qc.get("adjusted_primary_hr")
        names = [c.get("name") for c in significant if c.get("name")]

        hr_shift = None
        if isinstance(naive_hr, (int, float)) and isinstance(adjusted_hr, (int, float)):
            hr_shift = round(adjusted_hr - naive_hr, 4)

        detail = (
            f"The Cox model's primary covariate '{primary}' has significant omitted "
            f"confounder(s): {', '.join(names)} (each p < {_P_THRESHOLD}). An unadjusted "
            f"hazard ratio for '{primary}' is confounded."
        )
        if hr_shift is not None:
            detail += (
                f" Adjusting moves the primary HR from {naive_hr} (naive) to "
                f"{adjusted_hr} (adjusted), a shift of {hr_shift}."
            )

        ev = design_rule("survival.adjust_confounders")
        return [Issue(
            critic_id=self.critic_id,
            code="omitted_confounder",
            title=f"Confounded hazard ratio: adjust for {', '.join(names)}",
            severity=Severity.WARNING,
            detail=detail,
            subjects=names,
            metrics={
                "primary_covariate": primary,
                "naive_hr": naive_hr,
                "adjusted_hr": adjusted_hr,
                "hr_shift": hr_shift,
                "confounders": significant,
            },
            evidence=[ev] if ev else [],
        )]

    def remediate(self, issue: Issue, ctx: RunContext) -> Remediation:
        m = issue.metrics
        primary = m.get("primary_covariate")
        names = issue.subjects
        naive_hr = m.get("naive_hr")
        adjusted_hr = m.get("adjusted_hr")

        # Optionally recompute via the reusable R script (decoupled from cox.nf).
        # Only when the data is locally available and compute is allowed; otherwise
        # fall back to the contract's already-emitted adjusted HR.
        computed = _maybe_refit(ctx, primary, names)
        if computed and isinstance(computed.get("adjusted_primary_hr"), (int, float)):
            adjusted_hr = computed["adjusted_primary_hr"]

        formula = f"Surv(time, status) ~ {' + '.join([primary] + list(names))}" if primary else None
        ev_rule = design_rule("survival.adjust_confounders")
        return Remediation(
            issue_code=issue.code,
            kind=RemediationKind.ADD_COVARIATE,
            summary=(
                f"Re-fit the Cox model adjusting for {', '.join(names)}"
                + (f": primary HR {naive_hr} → {adjusted_hr}" if naive_hr is not None else "")
            ),
            rationale=(
                "The naive model attributes effect to the primary covariate that is "
                "partly explained by the omitted prognostic covariate(s); the adjusted "
                "model gives the de-confounded hazard ratio."
            ),
            naive={"covariate": primary, "hazard_ratio": naive_hr, "formula": f"Surv(time, status) ~ {primary}"},
            corrected={"covariate": primary, "hazard_ratio": adjusted_hr,
                       "covariates_added": list(names), "formula": formula},
            params_delta={"formula": formula, "covariates_added": list(names)},
            evidence=[ev_rule] if ev_rule else [],
        )


class SurvivalPHCritic(Critic):
    """Detect a proportional-hazards assumption violation (scaled Schoenfeld residuals)
    and propose stratification or a time-transform for the offending covariate(s)."""

    domain = "survival"
    critic_id = "survival.proportional_hazards"
    required_artifacts = [_QC_ARTIFACT]

    def detect(self, ctx: RunContext) -> List[Issue]:
        qc = _load_qc(ctx)
        if not qc:
            return []
        global_p = qc.get("schoenfeld_global_p")
        violators = [v for v in (qc.get("ph_violating_covariates") or []) if v]
        global_violation = isinstance(global_p, (int, float)) and global_p < _P_THRESHOLD
        if not (global_violation or violators):
            return []

        subjects = violators or (["<global>"] if global_violation else [])
        detail = (
            "The proportional-hazards assumption is violated"
            + (f" for: {', '.join(violators)}" if violators else "")
            + (f" (global Schoenfeld p = {global_p})" if isinstance(global_p, (int, float)) else "")
            + ". A single hazard ratio misrepresents a time-varying effect."
        )
        ev = design_rule("survival.ph_assumption")
        return [Issue(
            critic_id=self.critic_id,
            code="ph_violation",
            title="Proportional-hazards assumption violated",
            severity=Severity.WARNING,
            detail=detail,
            subjects=subjects,
            metrics={
                "schoenfeld_global_p": global_p,
                "ph_violating_covariates": violators,
            },
            evidence=[ev] if ev else [],
        )]

    def remediate(self, issue: Issue, ctx: RunContext) -> Remediation:
        violators = [s for s in issue.subjects if s and s != "<global>"]
        target = violators or ["the violating covariate"]
        ev_rule = design_rule("survival.ph_time_transform")
        return Remediation(
            issue_code=issue.code,
            kind=RemediationKind.TIME_TRANSFORM,
            summary=f"Stratify on, or add a time-transform term for, {', '.join(target)}",
            rationale=(
                "Because the effect of these covariate(s) changes over time, the model "
                "should either stratify by them (baseline-hazard per stratum) or include "
                "a time-varying term (e.g. tt()), rather than report one constant HR."
            ),
            naive={"model": "constant hazard ratio", "schoenfeld_global_p": issue.metrics.get("schoenfeld_global_p")},
            corrected={"model": "stratified or time-transformed", "covariates": violators},
            params_delta={"strata": violators, "time_transform": violators},
            evidence=[ev_rule] if ev_rule else [],
        )


def _maybe_refit(ctx: RunContext, primary: Optional[str], confounders: List[str]) -> Optional[Dict[str, Any]]:
    """Best-effort: recompute the adjusted model via the reusable R script when the
    clinical CSV is locally available and compute is enabled. Returns the parsed
    refit JSON or None (the critic then uses the contract's emitted numbers)."""
    if not getattr(ctx, "_allow_compute", False) or not primary:
        return None
    try:
        from .r_refit import run_survival_refit
    except Exception:
        return None
    # Resolve the clinical input path from design.json inputs (first dataset input).
    data_path = None
    for v in (ctx.inputs or {}).values():
        if isinstance(v, str) and (v.endswith(".csv") or "clinical" in v.lower()):
            data_path = v
            break
    if not data_path:
        return None
    return run_survival_refit(data_path, primary, confounders)
