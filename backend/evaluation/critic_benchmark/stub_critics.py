"""
Stub critics for the critic benchmark — the FIRST scored entries.

The benchmark must score *any registered critic*. The real ``survival.confounding``
and ``survival.proportional_hazards`` critics already exist in the critics package and
are scored as-is. The Workstream-2 critics the committee prioritized first — the
generic **Power / events-per-variable** critic and the **output-presence / low-N
floor** — are not merged on this branch yet, so we *stub* them here (plus the
RNA-seq **imbalanced-confounding CRITICAL** flag and a generic **QC-threshold floor**).

These stubs implement the exact same ``Critic`` interface the hook dispatches to, read
ONLY the run contract, and cite curated Evidence so they publish through the real
guardrails. They are deliberately *correctly designed* (they fire on their injected
positive and stay silent on their hard negative) — in contrast to the real
``survival.confounding`` critic, whose Table-2-fallacy weakness on mediators the
benchmark is meant to *measure*, not hide.

When the real WS2 critics land, delete the corresponding stub and register the real
one in :func:`build_registry`; the benchmark is unchanged.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from . import _bootstrap  # noqa: F401  (side effect: backend/lib on sys.path)

from galaxy.ai.critics.base import (
    Critic,
    Evidence,
    Issue,
    Provenance,
    Remediation,
    RemediationKind,
    Severity,
)
from galaxy.ai.critics.run_context import RunContext
from galaxy.ai.critics.registry import CriticRegistry


# ─────────────────────────────────────────────────────────────────────────────
# Curated evidence for the stub critics (stand-in for qc_evidence.yaml design_rules).
# GOLD provenance + a real DOI so Issue.is_cited passes and the hook publishes them.
# ─────────────────────────────────────────────────────────────────────────────

_EV_EPV = Evidence(
    claim=(
        "A regression model needs an adequate number of events per predictor variable "
        "(EPV); below ~10 the coefficient estimates are unstable and biased."
    ),
    source="Peduzzi et al., 'A simulation study of the number of events per variable "
           "in logistic regression analysis', J Clin Epidemiol 49(12):1373-1379 (1996)",
    doi="10.1016/s0895-4356(96)00236-3",
    provenance=Provenance.GOLD,
)

_EV_BATCH = Evidence(
    claim=(
        "A technical covariate (batch) that is collinear with the biological condition "
        "confounds the condition effect and cannot be separated from it; this is a "
        "validity threat, not a precision one."
    ),
    source="Leek et al., 'Tackling the widespread and critical impact of batch effects "
           "in high-throughput data', Nat Rev Genet 11:733-739 (2010)",
    doi="10.1038/nrg2825",
    provenance=Provenance.GOLD,
)

_EV_QC = Evidence(
    claim=(
        "A quantitative QC metric below its accepted floor (e.g. mapping rate, RIN, "
        "assignment rate) indicates the inputs/outputs are not trustworthy for the "
        "downstream analysis."
    ),
    source="nf-core/rnaseq QC guidance; Conesa et al., 'A survey of best practices for "
           "RNA-seq data analysis', Genome Biol 17:13 (2016)",
    doi="10.1186/s13059-016-0881-8",
    provenance=Provenance.SILVER,
)

_EV_OUTPUT = Evidence(
    claim=(
        "A run that completes successfully but produces none of its expected primary "
        "result artifacts (a result table / fitted model) is a silent failure: exit "
        "code 0 does not imply a usable result."
    ),
    source="FAIR / provenance best practice; a succeeded run with no primary output is "
           "a result-presence violation",
    doi=None,
    provenance=Provenance.SILVER,
)


# ─────────────────────────────────────────────────────────────────────────────
# Stub critics
# ─────────────────────────────────────────────────────────────────────────────

class PowerEPVCritic(Critic):
    """WS2 generic Power / events-per-variable critic (stub).

    Reads ``power_qc.json`` = {"n_events": int, "n_covariates": int}. Fires WARNING
    when EPV = n_events / n_covariates < 10. Remediation is advisory FLAG only — you
    cannot manufacture events, so the fix (collect more events / drop covariates) is a
    human decision, never an auto-apply.
    """

    domain = ""  # generic
    critic_id = "power.events_per_variable"
    required_artifacts = ["power_qc.json"]
    EPV_FLOOR = 10.0

    def detect(self, ctx: RunContext) -> List[Issue]:
        qc = ctx.load_json("power_qc.json")
        if not isinstance(qc, dict):
            return []
        n_events = qc.get("n_events")
        n_cov = qc.get("n_covariates")
        if not isinstance(n_events, (int, float)) or not isinstance(n_cov, (int, float)) or n_cov <= 0:
            return []
        epv = float(n_events) / float(n_cov)
        if epv >= self.EPV_FLOOR:
            return []
        return [Issue(
            critic_id=self.critic_id,
            code="underpowered_epv",
            title=f"Underpowered model: {epv:.1f} events per variable (floor {self.EPV_FLOOR:.0f})",
            severity=Severity.WARNING,
            detail=(
                f"The model fits {int(n_cov)} covariates on only {int(n_events)} events "
                f"(EPV {epv:.2f}). Below ~10 EPV, coefficient estimates and their "
                f"standard errors are unreliable."
            ),
            subjects=[],
            metrics={"n_events": n_events, "n_covariates": n_cov, "epv": round(epv, 3),
                     "epv_floor": self.EPV_FLOOR},
            evidence=[_EV_EPV],
        )]

    def remediate(self, issue: Issue, ctx: RunContext) -> Remediation:
        return Remediation(
            issue_code=issue.code,
            kind=RemediationKind.FLAG,  # cannot manufacture data — advisory only
            summary="Reduce the number of covariates or increase events; do not over-interpret the current fit.",
            rationale=(
                "Events-per-variable is a data-sufficiency floor. The only valid "
                "responses are a more parsimonious model or more data; neither can be "
                "auto-applied."
            ),
            naive={"epv": issue.metrics.get("epv")},
            corrected={"epv_target": self.EPV_FLOOR},
            evidence=[_EV_EPV],
        )


class RNASeqImbalancedConfoundingCritic(Critic):
    """WS2 RNA-seq imbalanced-confounding CRITICAL flag (stub).

    The committee's point (00 §2 Blocker C): the live Stream-6 loop flags a *balanced*
    covariate (balanced ≠ confounder; omitting costs precision, not validity) while
    ignoring the real validity threat — a covariate *imbalanced / collinear with the
    condition*. This critic flags exactly that, and ONLY that.

    Reads ``batch_qc.json`` = {"covariates": [{"name", "association_with_condition",
    "in_formula"}]}. Fires CRITICAL when a covariate's association with the condition is
    >= 0.8 and it is NOT already in the design formula. Remediation is FLAG: a
    condition-confounded batch is *detectable but uncorrectable* (removing it removes
    the biological signal) — the committee's hard ceiling.
    """

    domain = "rnaseq"
    critic_id = "rnaseq.imbalanced_confounding"
    required_artifacts = ["batch_qc.json"]
    ASSOC_FLOOR = 0.8

    def _culprits(self, ctx: RunContext) -> List[Dict[str, Any]]:
        qc = ctx.load_json("batch_qc.json")
        if not isinstance(qc, dict):
            return []
        out = []
        for c in qc.get("covariates") or []:
            if not isinstance(c, dict):
                continue
            assoc = c.get("association_with_condition")
            if isinstance(assoc, (int, float)) and assoc >= self.ASSOC_FLOOR and not c.get("in_formula"):
                out.append(c)
        return out

    def detect(self, ctx: RunContext) -> List[Issue]:
        culprits = self._culprits(ctx)
        if not culprits:
            return []
        names = [c.get("name") for c in culprits if c.get("name")]
        return [Issue(
            critic_id=self.critic_id,
            code="batch_confounded_with_condition",
            title=f"Batch confounded with condition: {', '.join(names)}",
            severity=Severity.CRITICAL,
            detail=(
                f"Covariate(s) {', '.join(names)} are collinear with the biological "
                f"condition (association >= {self.ASSOC_FLOOR}) and are not in the design "
                f"formula. Their effect cannot be separated from the condition effect; "
                f"the differential-expression result is not interpretable as biology."
            ),
            subjects=names,
            metrics={"culprits": culprits, "assoc_floor": self.ASSOC_FLOOR},
            evidence=[_EV_BATCH],
        )]

    def remediate(self, issue: Issue, ctx: RunContext) -> Remediation:
        return Remediation(
            issue_code=issue.code,
            kind=RemediationKind.FLAG,  # uncorrectable: removing batch removes signal
            summary="Flag the design: batch is confounded with condition; re-design the experiment (balanced batches).",
            rationale=(
                "This is a validity threat that cannot be fixed post-hoc by adding the "
                "covariate (it is collinear with the condition) nor by removing it "
                "(that removes the biological signal). The honest action is to flag it "
                "and advise a balanced re-design."
            ),
            naive={"interpretation": "condition effect"},
            corrected={"interpretation": "confounded — not estimable from this design"},
            evidence=[_EV_BATCH],
        )


class QCThresholdFloorCritic(Critic):
    """Generic QC-threshold floor critic (stub) — archetype 'result/input QC gate'.

    Reads ``qc_metrics.json`` = {"metrics": [{"name", "value", "floor", "direction":
    "min"|"max"}]}. Fires WARNING when any metric violates its floor (value < floor for
    direction 'min', value > floor for 'max'). Remediation is FLAG (re-run / filter is a
    human call). This catches the 'corrupt-a-QC-threshold' archetype: a run that
    SUCCEEDED but whose QC metric is actually below the accepted threshold.
    """

    domain = ""
    critic_id = "qc.metric_floor"
    required_artifacts = ["qc_metrics.json"]

    def _violations(self, ctx: RunContext) -> List[Dict[str, Any]]:
        qc = ctx.load_json("qc_metrics.json")
        if not isinstance(qc, dict):
            return []
        bad = []
        for m in qc.get("metrics") or []:
            if not isinstance(m, dict):
                continue
            v, floor = m.get("value"), m.get("floor")
            direction = m.get("direction", "min")
            if not isinstance(v, (int, float)) or not isinstance(floor, (int, float)):
                continue
            violated = (v < floor) if direction == "min" else (v > floor)
            if violated:
                bad.append(m)
        return bad

    def detect(self, ctx: RunContext) -> List[Issue]:
        bad = self._violations(ctx)
        if not bad:
            return []
        names = [m.get("name") for m in bad if m.get("name")]
        return [Issue(
            critic_id=self.critic_id,
            code="qc_below_floor",
            title=f"QC metric(s) below accepted floor: {', '.join(names)}",
            severity=Severity.WARNING,
            detail=(
                f"Metric(s) {', '.join(names)} violate their acceptance floor on a run "
                f"that completed successfully — a silent input/output quality failure."
            ),
            subjects=names,
            metrics={"violations": bad},
            evidence=[_EV_QC],
        )]

    def remediate(self, issue: Issue, ctx: RunContext) -> Remediation:
        return Remediation(
            issue_code=issue.code,
            kind=RemediationKind.FLAG,
            summary="Treat results as provisional; re-run or filter inputs failing QC before interpreting.",
            rationale="A QC-floor violation means the inputs/outputs are below the trust threshold.",
            naive={"violations": issue.metrics.get("violations")},
            corrected={},
            evidence=[_EV_QC],
        )


class OutputPresenceFloorCritic(Critic):
    """WS2 output-presence / low-N floor critic (stub).

    Reads ``expected_outputs.json`` = {"expected_roles": ["table", "model", ...]} and
    the results manifest. Fires WARNING when a succeeded run is missing an expected
    primary output *role* (exit 0 but no result). Remediation FLAG.
    """

    domain = ""
    critic_id = "output.presence_floor"
    required_artifacts = ["expected_outputs.json"]

    def detect(self, ctx: RunContext) -> List[Issue]:
        spec = ctx.load_json("expected_outputs.json")
        if not isinstance(spec, dict):
            return []
        expected = [r for r in (spec.get("expected_roles") or []) if isinstance(r, str)]
        if not expected:
            return []
        present_roles = {f.role for f in ctx.outputs}
        missing = [r for r in expected if r not in present_roles]
        if not missing:
            return []
        return [Issue(
            critic_id=self.critic_id,
            code="missing_expected_output",
            title=f"Run succeeded but produced no {', '.join(missing)} output",
            severity=Severity.WARNING,
            detail=(
                f"The run completed (exit 0) but its manifest contains no output with "
                f"role(s) {', '.join(missing)}. A successful run with no primary result "
                f"is a silent failure the exit code hides."
            ),
            subjects=missing,
            metrics={"expected_roles": expected, "missing_roles": missing,
                     "present_roles": sorted(present_roles)},
            evidence=[_EV_OUTPUT],
        )]

    def remediate(self, issue: Issue, ctx: RunContext) -> Remediation:
        return Remediation(
            issue_code=issue.code,
            kind=RemediationKind.FLAG,
            summary="Investigate: the expected primary result is missing despite a successful exit.",
            rationale="Exit code 0 does not imply the primary result artifact was produced.",
            naive={"present_roles": issue.metrics.get("present_roles")},
            corrected={"expected_roles": issue.metrics.get("expected_roles")},
            evidence=[_EV_OUTPUT],
        )


# ─────────────────────────────────────────────────────────────────────────────
# Registry assembly — real critics + stubs
# ─────────────────────────────────────────────────────────────────────────────

#: Stub critics scored as the first benchmark entries (WS2 Power/EPV + output-presence
#: first, plus the RNA-seq imbalanced-confounding and QC-floor critics).
STUB_CRITIC_CLASSES = (
    PowerEPVCritic,
    OutputPresenceFloorCritic,
    RNASeqImbalancedConfoundingCritic,
    QCThresholdFloorCritic,
)


def build_registry(include_real: bool = True, include_stubs: bool = True) -> CriticRegistry:
    """Assemble a fresh registry with the real survival critics + the WS2 stubs.

    The benchmark accepts *any* registered critic, so this is the only place that
    decides which critics are under test. Swap a stub for the real WS2 critic here
    when that branch merges — nothing else changes.
    """
    reg = CriticRegistry()
    if include_real:
        from galaxy.ai.critics.critics.survival import (
            SurvivalConfoundingCritic,
            SurvivalPHCritic,
        )
        for cls in (SurvivalConfoundingCritic, SurvivalPHCritic):
            reg.register(cls())
    if include_stubs:
        for cls in STUB_CRITIC_CLASSES:
            reg.register(cls())
    return reg
