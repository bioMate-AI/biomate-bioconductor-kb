"""
Post-run critic hook — the one place critics run, with the guardrails baked in.

This is the generic replacement for per-workflow ``.nf`` self-correction. It attaches
to the executor's completion path (the AWS Batch / cloud path, near where ``run_meta``
is assembled after ``_build_results_manifest`` / ``_build_design_json``), builds a
:class:`RunContext` from the already-computed contract, dispatches to every applicable
critic, and publishes gates + naive-vs-corrected + rationale through the EXISTING
transport (the autoloop SSE channel + suggestion store, and the bioc-harness gate
tuples). It never imports a workflow file and never runs statistics itself.

Guardrails (structural, non-negotiable — hardened per committee Blocker B):
  G1. CITE-BY-KB-KEY-OR-STAY-SILENT (validity, not presence). An Issue is published
      only if at least one Evidence carries a ``kb_key`` that RESOLVES in the design-
      rule KB (``config/qc_evidence.yaml design_rules:``). The DOI/provenance are read
      FROM that KB entry; author- (or LLM-) supplied DOI/grade are ignored for the
      decision. A fabricated DOI stamped GOLD with no/unknown key is *uncited* → NOT
      published (capped to advisory, ``published=False``, kept for audit).
  G2. DETERMINISTIC PRECONDITION VERIFIER between detect() and publish. A critic may
      attach a :class:`Precondition` predicate to an Issue; the hook verifies it over
      the RunContext. Unverified / unverifiable precondition → advisory-only, never
      WARNING/CRITICAL, never auto-apply.
  G3. HOOK-COMPUTED SEVERITY. The published severity is computed by the hook from
      (grounded?, precondition-verified?, KB provenance grade, confidence, clinical-
      context) — never the author-set ``Issue.severity``. A critic can NOT self-assert
      CRITICAL.
  G4. ADVISORY-BY-DEFAULT + audited, tightened auto-apply. A Remediation is advisory
      (``applied=False``) unless the caller opts into ``auto_apply`` AND the kind is in
      ``auto_apply_kinds`` AND the issue is grounded AND its precondition is verified
      AND context is non-clinical AND provenance==GOLD AND confidence ≥ 0.99; every
      applied remediation is audited. The default ``auto_apply_kinds`` is empty.

The hook is fail-open: any critic error is logged and skipped so the completion path
is never blocked by the judgment layer (same contract as ``autoloop_bridge``).
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

from .base import Critic, Evidence, Issue, Remediation, RemediationKind, Severity, Provenance
from .run_context import RunContext
from .registry import CriticRegistry, get_registry
from .evidence import design_rule as _default_grounding_resolver

log = logging.getLogger(__name__)

# A grounding resolver maps a KB key -> its authoritative Evidence (or None if unknown).
GroundingResolver = Callable[[str], Optional[Evidence]]

#: Confidence floor at which a GOLD + verified, non-clinical issue may reach CRITICAL.
_CRITICAL_CONFIDENCE = 0.99
#: Confidence floor for a WARNING (vs a soft advisory).
_WARNING_CONFIDENCE = 0.90

# Transport seams (all optional). The executor wires these to the existing channels.
EmitFn = Callable[[str, Dict[str, Any]], None]          # SSE: (event_type, payload)
PublishGatesFn = Callable[[List[tuple]], None]          # bioc-harness gate tuples
StoreSuggestionsFn = Callable[[str, Dict[str, Any]], None]  # (invocation_id, suggestion_doc)

# Kinds we would ever allow to auto-apply (bounded, reversible, cheap). FLAG never
# applies anything; REFIT/ADD_COVARIATE/STRATIFY/TIME_TRANSFORM change the analysis and
# so default to advisory even when auto_apply is on, unless explicitly allowlisted.
_DEFAULT_AUTO_APPLY_KINDS: tuple = ()  # empty: advisory-only by default


@dataclass
class CriticFinding:
    """One critic's Issue paired with its Remediation, plus the hook's audit trail of
    WHY it was published at the computed severity (grounding / precondition / grade)."""
    issue: Issue
    remediation: Optional[Remediation]
    published: bool = True          # False when suppressed by the grounding guardrail
    grounded: bool = False          # a KB key resolved (G1)
    precondition_verified: bool = False   # the deterministic predicate held (G2)
    kb_provenance: str = Provenance.NONE.value   # authoritative grade read from the KB
    requested_severity: str = ""    # what the critic ASKED for (audit only; not trusted)
    computed_severity: str = ""     # what the hook COMPUTED and published (G3)
    confidence: float = 1.0
    clinical: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "issue": self.issue.to_dict(),
            "remediation": self.remediation.to_dict() if self.remediation else None,
            "published": self.published,
            "grounded": self.grounded,
            "precondition_verified": self.precondition_verified,
            "kb_provenance": self.kb_provenance,
            "requested_severity": self.requested_severity,
            "computed_severity": self.computed_severity,
            "confidence": self.confidence,
            "clinical": self.clinical,
        }


@dataclass
class CriticReport:
    """The result of running the critic layer on one run. Written into run_meta
    (``run_meta['critic_report']``) and/or published to the run's outdir."""
    run_id: str
    findings: List[CriticFinding] = field(default_factory=list)
    gates: List[tuple] = field(default_factory=list)      # bioc-harness-compatible tuples
    critics_run: List[str] = field(default_factory=list)
    generated_at: str = ""

    @property
    def has_issues(self) -> bool:
        return any(f.published for f in self.findings)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "kind": "critic_report",
            "schema_version": "1.0",
            "run_id": self.run_id,
            "generated_at": self.generated_at,
            "critics_run": list(self.critics_run),
            "findings": [f.to_dict() for f in self.findings],
            "gate_count": len([f for f in self.findings if f.published]),
        }


def _issue_to_gate_tuple(issue: Issue, rem: Optional[Remediation]) -> tuple:
    """Render an Issue as a bioc-harness gate tuple so it flows through the SAME
    audit/transport path as existing QC gates:
        (gate_row, metric_value, threshold, passes, level, message)
    A detected issue is a FAIL (passes=False). We surface the headline metric
    (corrected vs naive when present) as the metric value for the UI's two-number view.
    """
    gate_row = f"critic_{issue.code}"
    # Pick a representative numeric metric. Prefer the Issue's own declared headline
    # metric (generic); fall back to a small known-key list only if none is declared.
    metric_value = 0.0
    threshold = 0.0
    keys = []
    if issue.headline_metric:
        keys.append(issue.headline_metric)
    keys += ["schoenfeld_global_p", "adjusted_hr", "naive_hr", "p_value"]
    for k in keys:
        if isinstance(issue.metrics.get(k), (int, float)):
            metric_value = float(issue.metrics[k])
            break
    level = "FAIL" if issue.severity.rank >= Severity.WARNING.rank else "ADVISORY"
    msg = issue.title
    if rem is not None and (rem.naive or rem.corrected):
        msg = f"{issue.title} — {rem.summary}"
    return (gate_row, metric_value, threshold, False, level, msg)


def run_critics(
    ctx: RunContext,
    *,
    registry: Optional[CriticRegistry] = None,
    require_citation: bool = True,
    auto_apply: bool = False,
    auto_apply_kinds: tuple = _DEFAULT_AUTO_APPLY_KINDS,
    grounding_resolver: Optional[GroundingResolver] = None,
    clinical: Optional[bool] = None,
    emit: Optional[EmitFn] = None,
    publish_gates: Optional[PublishGatesFn] = None,
    store_suggestions: Optional[StoreSuggestionsFn] = None,
) -> CriticReport:
    """Run every applicable critic against ``ctx`` and publish the result.

    Parameters mirror the guardrails described in the module docstring.

    ``require_citation`` (G1): when True (default), only KB-GROUNDED issues publish.
    ``grounding_resolver`` resolves a KB key -> authoritative Evidence; defaults to the
    design-rule KB loaded from ``qc_evidence.yaml``. ``clinical`` forces the clinical-
    context demotion (never auto-apply, severity demoted one tier); when None it is
    auto-detected from the RunContext. The three transport callables are optional so
    the hook is fully unit-testable with none wired.
    """
    registry = registry or get_registry()
    resolver = grounding_resolver or _default_grounding_resolver
    is_clinical = _detect_clinical(ctx) if clinical is None else bool(clinical)
    report = CriticReport(
        run_id=ctx.run_id,
        generated_at=datetime.now(timezone.utc).isoformat(),
    )

    try:
        critics = registry.for_context(ctx)
    except Exception as exc:
        log.warning("[critics] registry dispatch failed for run %s: %s", ctx.run_id, exc)
        return report

    for critic in critics:
        report.critics_run.append(critic.critic_id)
        try:
            issues = critic.detect(ctx) or []
        except Exception as exc:  # fail-open per-critic
            log.warning("[critics] %s.detect failed for run %s: %s", critic.critic_id, ctx.run_id, exc)
            continue

        for issue in issues:
            finding = _handle_issue(
                critic, issue, ctx,
                require_citation=require_citation,
                auto_apply=auto_apply,
                auto_apply_kinds=auto_apply_kinds,
                resolver=resolver,
                clinical=is_clinical,
            )
            report.findings.append(finding)
            if finding.published:
                report.gates.append(_issue_to_gate_tuple(finding.issue, finding.remediation))

    _publish(report, ctx, emit=emit, publish_gates=publish_gates, store_suggestions=store_suggestions)
    return report


def _resolve_grounding(evidence: List[Evidence], resolver: GroundingResolver) -> tuple:
    """G1 core: validate citations against the KB. Returns (grounded, best_provenance).

    An Evidence grounds ONLY if its ``kb_key`` resolves to a real KB entry. The
    provenance used is the KB entry's authoritative grade — NOT the author-set grade on
    the Evidence object (so a fabricated DOI stamped GOLD with no/unknown key cannot
    escalate). ``best_provenance`` is the highest grade among grounded items.
    """
    grounded = False
    best = Provenance.NONE
    for e in evidence or []:
        key = getattr(e, "kb_key", None)
        if not key:
            continue
        try:
            kb_ev = resolver(key)
        except Exception:
            kb_ev = None
        if kb_ev is None:
            continue
        grounded = True
        if kb_ev.provenance.rank > best.rank:
            best = kb_ev.provenance
    return grounded, best


def _compute_severity(
    *, grounded: bool, verified: bool, provenance: Provenance, confidence: float, clinical: bool
) -> Severity:
    """G3: the published severity, computed by the hook (never author-set).

    Policy (committee §4 precision→tier, grounded in KB provenance + confidence):
      * not grounded                      → ADVISORY (and the issue is not published)
      * grounded but precondition UNverified → ADVISORY (retrieve-and-explain FYI only)
      * grounded + verified:
          GOLD   + confidence ≥ 0.99 + non-clinical → CRITICAL
          GOLD/SILVER + confidence ≥ 0.90           → WARNING
          confidence ≥ 0.70                         → ADVISORY (soft)
          else                                      → ADVISORY
      * clinical context demotes the result one tier and forbids CRITICAL.
    A critic that stamped CRITICAL therefore cannot force it: only this function decides.
    """
    if not grounded or not verified:
        return Severity.ADVISORY

    conf = max(0.0, min(1.0, float(confidence)))
    if provenance is Provenance.GOLD and conf >= _CRITICAL_CONFIDENCE and not clinical:
        sev = Severity.CRITICAL
    elif provenance.rank >= Provenance.SILVER.rank and conf >= _WARNING_CONFIDENCE:
        sev = Severity.WARNING
    else:
        sev = Severity.ADVISORY

    if clinical:
        sev = _demote(sev)
    return sev


def _demote(sev: Severity) -> Severity:
    order = [Severity.INFO, Severity.ADVISORY, Severity.WARNING, Severity.CRITICAL]
    i = order.index(sev)
    return order[max(0, i - 1)]


def _detect_clinical(ctx: RunContext) -> bool:
    """Treat 'clinical' as a first-class context flag. Honor an explicit flag on the
    RunContext / design.json / parameters; fall back to a domain heuristic."""
    for src in (
        getattr(ctx, "clinical", None),
        (ctx.raw_design or {}).get("clinical"),
        (ctx.parameters or {}).get("clinical"),
        (ctx.inputs or {}).get("clinical"),
    ):
        if isinstance(src, bool):
            if src:
                return True
        elif isinstance(src, str) and src.strip().lower() in ("1", "true", "yes", "clinical"):
            return True
    domain = (ctx.workflow_domain or "").lower()
    return domain in ("clinical", "clinical_trial", "ind", "patient")


def _handle_issue(
    critic: Critic,
    issue: Issue,
    ctx: RunContext,
    *,
    require_citation: bool,
    auto_apply: bool,
    auto_apply_kinds: tuple,
    resolver: GroundingResolver,
    clinical: bool,
) -> CriticFinding:
    """Apply G1–G4 to one issue and build its remediation.

    Order matters: ground (G1) → verify precondition (G2) → compute severity (G3) →
    decide publication → gate auto-apply (G4). The author-set ``issue.severity`` is
    recorded for audit only and then overwritten by the computed value.
    """
    requested_severity = issue.severity

    # G1: grounding by KB key (validity, not presence). author DOI/grade ignored.
    grounded, kb_provenance = _resolve_grounding(issue.evidence, resolver)

    # G2: deterministic precondition verifier between detect() and publish.
    if issue.precondition is not None:
        verified = issue.precondition.verify(ctx)
    else:
        # No declared, machine-checkable precondition → treat as UNverifiable.
        verified = False

    confidence = max(0.0, min(1.0, float(getattr(issue, "confidence", 1.0) or 0.0)))

    # G3: hook-computed severity (overwrites whatever the critic asked for).
    computed = _compute_severity(
        grounded=grounded, verified=verified,
        provenance=kb_provenance, confidence=confidence, clinical=clinical,
    )
    issue.severity = computed

    # Publication: a grounded issue publishes; an ungrounded one is kept for audit
    # only (published=False), unless the caller explicitly disabled the guardrail.
    published = grounded or (not require_citation)
    if not grounded:
        log.info("[critics] %s issue %r suppressed (uncited: no KB-key grounding) for run %s",
                 critic.critic_id, issue.code, ctx.run_id)
    elif not verified:
        log.info("[critics] %s issue %r capped to advisory (precondition unverified) for run %s",
                 critic.critic_id, issue.code, ctx.run_id)

    remediation: Optional[Remediation] = None
    try:
        remediation = critic.remediate(issue, ctx)
    except Exception as exc:
        log.warning("[critics] %s.remediate failed for run %s: %s",
                    critic.critic_id, ctx.run_id, exc)

    # G4: advisory-by-default + tightened, audited auto-apply. Auto-apply requires a
    # grounded, precondition-verified, non-clinical, GOLD, high-confidence issue whose
    # remediation kind is allowlisted and whose remediation evidence is itself grounded.
    if remediation is not None:
        rem_grounded, _ = _resolve_grounding(remediation.evidence, resolver)
        can_apply = (
            auto_apply
            and remediation.kind in auto_apply_kinds
            and published
            and grounded
            and verified
            and rem_grounded
            and not clinical
            and kb_provenance is Provenance.GOLD
            and confidence >= _CRITICAL_CONFIDENCE
        )
        if can_apply:
            remediation.applied = True
            remediation.audit = {
                "applied_at": datetime.now(timezone.utc).isoformat(),
                "critic_id": critic.critic_id,
                "issue_code": issue.code,
                "run_id": ctx.run_id,
                "params_delta": dict(remediation.params_delta),
                "evidence": [e.to_dict() for e in remediation.evidence
                             if getattr(e, "kb_key", None) and resolver(e.kb_key) is not None],
                "grounded": True,
                "precondition_verified": True,
                "provenance": kb_provenance.value,
            }
        else:
            remediation.applied = False

    return CriticFinding(
        issue=issue,
        remediation=remediation,
        published=published,
        grounded=grounded,
        precondition_verified=verified,
        kb_provenance=kb_provenance.value,
        requested_severity=requested_severity.value,
        computed_severity=computed.value,
        confidence=confidence,
        clinical=clinical,
    )


def _publish(
    report: CriticReport,
    ctx: RunContext,
    *,
    emit: Optional[EmitFn],
    publish_gates: Optional[PublishGatesFn],
    store_suggestions: Optional[StoreSuggestionsFn],
) -> None:
    """Push the report through the existing transport channels, best-effort."""
    published_findings = [f for f in report.findings if f.published]
    if not published_findings:
        return

    # 1. bioc-harness gate tuples (same audit path as existing QC gates).
    if publish_gates is not None and report.gates:
        try:
            publish_gates(report.gates)
        except Exception as exc:
            log.warning("[critics] publish_gates failed: %s", exc)

    # 2. autoloop SSE channel — reuse the event names the AutoLoopPanel already renders.
    if emit is not None:
        try:
            emit("autoloop_gate_results", {
                "domain": ctx.workflow_domain or "critic",
                "source": "critic_layer",
                "gates": [
                    {
                        "gate": f.issue.code,
                        "level": f.issue.severity.value.upper(),
                        "message": f.issue.title,
                        "detail": f.issue.detail,
                        "subjects": f.issue.subjects,
                        "metrics": f.issue.metrics,
                        "evidence": [e.to_dict() for e in f.issue.evidence],
                    }
                    for f in published_findings
                ],
            })
            emit("autoloop_update", {
                "domain": ctx.workflow_domain or "critic",
                "source": "critic_layer",
                "remediations": [
                    f.remediation.to_dict() for f in published_findings if f.remediation
                ],
            })
        except Exception as exc:
            log.warning("[critics] SSE emit failed: %s", exc)

    # 3. suggestion store — so GET /api/invocations/{id}/autoloop-suggestions serves it.
    if store_suggestions is not None and ctx.run_id:
        try:
            store_suggestions(ctx.run_id, {
                "source": "critic_layer",
                "domain": ctx.workflow_domain or "critic",
                "remediations": [
                    f.remediation.to_dict() for f in published_findings if f.remediation
                ],
                "failed_gates": [f.issue.code for f in published_findings],
            })
        except Exception as exc:
            log.warning("[critics] store_suggestions failed: %s", exc)


def run_critics_from_run_meta(
    run_meta: Dict[str, Any],
    *,
    artifact_loader=None,
    inline_artifacts: Optional[Dict[str, Any]] = None,
    **kwargs,
) -> CriticReport:
    """Convenience entry point for the executor completion path.

    ``run_meta`` is the dict the executor assembles on completion; it already carries
    ``results_manifest`` and ``design`` (written at lines ~4589–4592 of
    nextflow_executor.py). This builds the RunContext and calls :func:`run_critics`.
    """
    ctx = RunContext.from_contract(
        design=run_meta.get("design"),
        manifest=run_meta.get("results_manifest"),
        run_id=str(run_meta.get("run_id") or run_meta.get("id") or ""),
        artifact_loader=artifact_loader,
        inline_artifacts=inline_artifacts,
    )
    return run_critics(ctx, **kwargs)
