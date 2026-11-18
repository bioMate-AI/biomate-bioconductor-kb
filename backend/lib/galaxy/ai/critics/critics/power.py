"""
Power / events-per-variable (EPV) / sample-size critic — the flagship SAFE-first
proof of the Critic framework (Phase-2 build order, committee item #1).

This is *archetype D* from the biostatistics review (§5): design is underpowered or
unstable. It is the single safest critic to ship first because:

  * the math is uniform across domains (events-per-variable, replicates-per-group,
    observations-per-parameter) — the same calculation everywhere;
  * it never changes the estimand and never edits the analysis — it only *warns*;
  * it is therefore impossible for it to be "wrong" in a harmful way (zero causal-
    inference risk). The remediation is always an advisory ``FLAG``.

It detects three underpowered-design conditions, each gated on data availability and
degrading gracefully (returns nothing it cannot ground in numbers it actually read):

  1. **Low EPV** — for Cox / logistic risk models: EPV = events / n_coefficients < 10
     (Peduzzi 1995/1996). EPV < 5 is flagged as severe.
  2. **Low replicate count** — for differential-expression designs: the smallest group
     has < 3 biological replicates (Schurch 2016); < 2 means dispersion is inestimable.
  3. **Over-parameterised design** — the model estimates >= 1 parameter per observation
     (non-identifiable), or < 5 observations per parameter (unstable / over-fit).

Inputs are read from ``RunContext`` using the design fields WS1 is populating
(``design.events``, ``design.n_covariates`` / ``design.covariates``,
``design.group_sizes``, ``design.n_samples``, ``design.model_type``). Where a field is
absent, it falls back to the per-class QC JSON exactly as ``survival.py`` does, and if
nothing usable is found it simply stays silent.
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

from ..base import Critic, Issue, Remediation, RemediationKind, Severity
from ..run_context import RunContext
from ..evidence import design_rule

log = logging.getLogger(__name__)

# ── thresholds (grounded; see evidence keys) ─────────────────────────────────
_EPV_FLOOR = 10.0          # events-per-variable rule (Peduzzi)
_EPV_SEVERE = 5.0          # below this EPV is severe (unstable)
_MIN_REPLICATES = 3        # min biological replicates / group for DE (Schurch)
_NO_VARIANCE_REPLICATES = 2  # < 2 → within-group variance inestimable
_MIN_OBS_PER_PARAM = 5.0   # observations per estimated parameter floor

# Per-class QC artifacts the critic may fall back to for design facts (same spirit as
# survival.py reading survival_qc.json). None are *required* — load_json fails closed.
_QC_FALLBACK = ("survival_qc.json", "qc_metrics.json", "qc_report.json", "design_qc.json")


def _num(v: Any) -> Optional[float]:
    """Coerce a scalar to float, rejecting bools/non-numerics. None if not numeric."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            return float(v.strip())
        except (ValueError, AttributeError):
            return None
    return None


def _first_num(d: Dict[str, Any], keys: List[str]) -> Optional[float]:
    if not isinstance(d, dict):
        return None
    for k in keys:
        n = _num(d.get(k))
        if n is not None:
            return n
    return None


def _qc_fallbacks(ctx: RunContext) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for name in _QC_FALLBACK:
        try:
            j = ctx.load_json(name)
        except Exception:  # loader must never crash a critic
            j = None
        if isinstance(j, dict):
            out.append(j)
    return out


def _design_facts(ctx: RunContext) -> Tuple[
    Optional[float], Optional[float], Optional[float], Dict[str, float], str
]:
    """Gather (events, n_covariates, n_samples, group_sizes, model_type) from the run
    contract, preferring design.json fields (WS1), then parameters, then QC JSON."""
    d = ctx.design or {}
    params = ctx.parameters or {}
    qc = _qc_fallbacks(ctx)
    sources = [d, params] + qc

    def pick(keys: List[str]) -> Optional[float]:
        for src in sources:
            n = _first_num(src, keys)
            if n is not None:
                return n
        return None

    events = pick(["events", "n_events", "num_events", "nevent", "n_event"])
    n_cov = pick(["n_covariates", "n_coefficients", "n_coef", "n_params",
                  "n_predictors", "n_parameters"])
    covariates = d.get("covariates")
    if n_cov is None and isinstance(covariates, list) and covariates:
        n_cov = float(len(covariates))
    n_samples = pick(["n_samples", "n_obs", "total_n", "n", "n_subjects"])
    model_type = str(d.get("model_type") or d.get("family") or d.get("model") or "").lower()

    # group_sizes: design.json dict first, else parameters/QC.
    group_sizes: Dict[str, float] = {}
    for src in sources:
        cand = src.get("group_sizes") if isinstance(src, dict) else None
        if isinstance(cand, dict) and cand:
            parsed = {str(g): _num(v) for g, v in cand.items()}
            parsed = {g: v for g, v in parsed.items() if v is not None}
            if parsed:
                group_sizes = parsed
                break

    return events, n_cov, n_samples, group_sizes, model_type


class PowerEPVCritic(Critic):
    """Generic underpowered-design detector (EPV / replicates / over-parameterisation).

    Domain-agnostic (``*``): applies to every run and self-selects inside ``detect`` by
    whether the design facts it needs are actually present. Advisory-only — every
    remediation is a ``FLAG`` that changes nothing.
    """

    domain = "*"
    critic_id = "power.epv"
    required_artifacts: List[str] = []  # universal: gate on data inside detect()

    def applies_to(self, ctx: RunContext) -> bool:
        """Universal critic: concerns EVERY run (the base ``applies_to`` would reject a
        literal ``"*"`` domain against a concrete one). Self-selection happens inside
        ``detect`` by whether the design facts are actually present."""
        for art in self.required_artifacts:
            if ctx.find_artifact(art) is None:
                return False
        return True

    def detect(self, ctx: RunContext) -> List[Issue]:
        events, n_cov, n_samples, group_sizes, model_type = _design_facts(ctx)
        issues: List[Issue] = []

        # 1. Events-per-variable (Cox / logistic).
        if events is not None and n_cov and n_cov > 0:
            epv = events / n_cov
            if epv < _EPV_FLOOR:
                severe = epv < _EPV_SEVERE
                ev = design_rule("power.epv_floor")
                issues.append(Issue(
                    critic_id=self.critic_id,
                    code="low_epv",
                    title=(f"Underpowered risk model: {epv:.1f} events per variable "
                           f"(EPV < {int(_EPV_FLOOR)})"),
                    severity=Severity.CRITICAL if severe else Severity.WARNING,
                    detail=(
                        f"The model estimates {int(n_cov)} coefficient(s) from "
                        f"{int(events)} event(s) -> EPV = {epv:.2f}. Below the EPV >= 10 "
                        f"rule the hazard/odds ratios and their confidence intervals are "
                        f"unstable, biased and over-fit"
                        + (" (EPV < 5 is severe)." if severe else ".")
                    ),
                    subjects=[],
                    metrics={
                        "events": events, "n_covariates": n_cov,
                        "epv": round(epv, 3), "epv_floor": _EPV_FLOOR,
                        "model_type": model_type or None,
                    },
                    evidence=[ev] if ev else [],
                ))

        # 2. Replicates per group (differential expression).
        if group_sizes:
            min_n = min(group_sizes.values())
            if min_n < _MIN_REPLICATES:
                underpowered = {g: n for g, n in group_sizes.items() if n < _MIN_REPLICATES}
                inestimable = min_n < _NO_VARIANCE_REPLICATES
                ev = design_rule("power.min_replicates")
                issues.append(Issue(
                    critic_id=self.critic_id,
                    code="low_replicates",
                    title=(f"Underpowered design: {int(min_n)} replicate(s) in the "
                           f"smallest group (< {_MIN_REPLICATES})"),
                    severity=Severity.CRITICAL if inestimable else Severity.WARNING,
                    detail=(
                        f"Smallest group has {int(min_n)} replicate(s); groups below "
                        f"{_MIN_REPLICATES}: "
                        + ", ".join(f"{g}={int(n)}" for g, n in sorted(underpowered.items()))
                        + ". At least 3 biological replicates per group are needed to "
                          "estimate within-group dispersion"
                        + (" — with < 2 the dispersion is not estimable at all and no "
                           "software can recover it." if inestimable else "; >= 6 are "
                           "recommended to recover most true changes.")
                    ),
                    subjects=sorted(underpowered.keys()),
                    metrics={
                        "group_sizes": group_sizes,
                        "min_replicates": min_n,
                        "replicate_floor": _MIN_REPLICATES,
                        "underpowered_groups": underpowered,
                    },
                    evidence=[ev] if ev else [],
                ))

        # 3. Over-parameterised design (observations per parameter).
        if n_samples is not None and n_samples > 0 and n_cov and n_cov > 0:
            ratio = n_samples / n_cov
            non_identifiable = n_cov >= n_samples
            if non_identifiable or ratio < _MIN_OBS_PER_PARAM:
                ev = design_rule("power.overparameterized")
                issues.append(Issue(
                    critic_id=self.critic_id,
                    code="overparameterized",
                    title=(f"Over-parameterised design: {ratio:.1f} observations per "
                           f"estimated parameter"),
                    severity=Severity.CRITICAL if non_identifiable else Severity.WARNING,
                    detail=(
                        f"The design estimates {int(n_cov)} parameter(s) from "
                        f"{int(n_samples)} observation(s) -> {ratio:.2f} obs/parameter. "
                        + ("With >= 1 parameter per observation the model is "
                           "non-identifiable (rank-deficient)."
                           if non_identifiable else
                           f"Below ~{int(_MIN_OBS_PER_PARAM)} obs/parameter the fit is "
                           "unstable and over-fit.")
                    ),
                    subjects=[],
                    metrics={
                        "n_samples": n_samples, "n_covariates": n_cov,
                        "obs_per_parameter": round(ratio, 3),
                        "obs_per_parameter_floor": _MIN_OBS_PER_PARAM,
                        "non_identifiable": non_identifiable,
                    },
                    evidence=[ev] if ev else [],
                ))

        return issues

    def remediate(self, issue: Issue, ctx: RunContext) -> Remediation:
        """Advisory-only. Power is a *design* property that cannot be fixed post-hoc by
        editing the analysis, so the remediation is always a ``FLAG`` that changes
        nothing (``params_delta`` empty, ``applied`` stays False)."""
        code = issue.code
        if code == "low_epv":
            key = "power.epv_floor"
            summary = (
                "Reduce the number of covariates, use a penalised fit (ridge / LASSO / "
                "Firth), or report the coefficients with explicitly wide confidence "
                "intervals — do not interpret unstable estimates at face value."
            )
            rationale = (
                "Events-per-variable below 10 over-fits the risk model; the correct "
                "response is a design/analysis choice the scientist must make, not an "
                "automatic edit, so this is advisory-only."
            )
        elif code == "low_replicates":
            key = "power.min_replicates"
            summary = (
                "Add biological replicates (>= 3 per group, >= 6 preferred); with < 2 "
                "the dispersion is not estimable and no amount of modelling recovers it."
            )
            rationale = (
                "Replication is a property of data collection; it cannot be "
                "manufactured post-hoc, so the layer can only warn, never auto-fix."
            )
        else:  # overparameterized
            key = "power.overparameterized"
            summary = (
                "Reduce model complexity (drop terms, combine levels) or collect more "
                "observations; a model with >= 1 parameter per observation is "
                "non-identifiable."
            )
            rationale = (
                "The estimand cannot be recovered from an over-parameterised fit by "
                "editing the analysis; the fix is a design change, hence advisory-only."
            )
        ev = design_rule(key)
        return Remediation(
            issue_code=issue.code,
            kind=RemediationKind.FLAG,
            summary=summary,
            rationale=rationale,
            naive=dict(issue.metrics),   # the measured, underpowered state
            corrected={},                # advisory: no corrected analysis is produced
            params_delta={},             # NEVER changes anything
            evidence=[ev] if ev else [],
        )
