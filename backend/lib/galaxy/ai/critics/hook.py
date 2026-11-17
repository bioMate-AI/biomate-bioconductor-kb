"""
Post-run critic hook — the one place critics run, with the guardrails baked in.

This is the generic replacement for per-workflow ``.nf`` self-correction. It attaches
to the executor's completion path (the AWS Batch / cloud path, near where ``run_meta``
is assembled after ``_build_results_manifest`` / ``_build_design_json``), builds a
:class:`RunContext` from the already-computed contract, dispatches to every applicable
critic, and publishes gates + naive-vs-corrected + rationale through the EXISTING
transport (the autoloop SSE channel + suggestion store, and the bioc-harness gate
tuples). It never imports a workflow file and never runs statistics itself.

Guardrails (structural, non-negotiable):
  1. cite-evidence-or-stay-silent — an Issue whose evidence is entirely uncited is
     forced to advisory and is NOT published as a gate (``require_citation=True``).
  2. advisory-by-default — a Remediation is advisory (``applied=False``) unless the
     caller opts into ``auto_apply`` AND the remediation kind is in ``auto_apply_kinds``
     AND the backing evidence is cited; every applied remediation is audited.

The hook is fail-open: any critic error is logged and skipped so the completion path
is never blocked by the judgment layer (same contract as ``autoloop_bridge``).
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional

from .base import Critic, Issue, Remediation, RemediationKind, Severity
from .run_context import RunContext
from .registry import CriticRegistry, get_registry

log = logging.getLogger(__name__)

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
    """One critic's Issue paired with its Remediation."""
    issue: Issue
    remediation: Optional[Remediation]
    published: bool = True          # False when suppressed by the citation guardrail

    def to_dict(self) -> Dict[str, Any]:
        return {
            "issue": self.issue.to_dict(),
            "remediation": self.remediation.to_dict() if self.remediation else None,
            "published": self.published,
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
    # Pick a representative numeric metric if the critic provided one.
    metric_value = 0.0
    threshold = 0.0
    for k in ("schoenfeld_global_p", "adjusted_hr", "naive_hr", "p_value"):
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
    emit: Optional[EmitFn] = None,
    publish_gates: Optional[PublishGatesFn] = None,
    store_suggestions: Optional[StoreSuggestionsFn] = None,
) -> CriticReport:
    """Run every applicable critic against ``ctx`` and publish the result.

    Parameters mirror the guardrails described in the module docstring. The three
    transport callables (``emit``/``publish_gates``/``store_suggestions``) are optional
    so the hook is fully unit-testable with none of them wired.
    """
    registry = registry or get_registry()
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
            )
            report.findings.append(finding)
            if finding.published:
                report.gates.append(_issue_to_gate_tuple(finding.issue, finding.remediation))

    _publish(report, ctx, emit=emit, publish_gates=publish_gates, store_suggestions=store_suggestions)
    return report


def _handle_issue(
    critic: Critic,
    issue: Issue,
    ctx: RunContext,
    *,
    require_citation: bool,
    auto_apply: bool,
    auto_apply_kinds: tuple,
) -> CriticFinding:
    """Apply the citation + advisory guardrails to one issue, build its remediation."""
    published = True

    # Guardrail 1: cite-evidence-or-stay-silent.
    if require_citation and not issue.is_cited:
        # Keep the finding for the audit trail but do not surface it as a gate, and
        # cap its severity at advisory — an uncited judgment must never present as
        # WARNING/CRITICAL.
        if issue.severity.rank > Severity.ADVISORY.rank:
            issue.severity = Severity.ADVISORY
        published = False
        log.info("[critics] %s issue %r suppressed (uncited) for run %s",
                 critic.critic_id, issue.code, ctx.run_id)

    remediation: Optional[Remediation] = None
    try:
        remediation = critic.remediate(issue, ctx)
    except Exception as exc:
        log.warning("[critics] %s.remediate failed for run %s: %s",
                    critic.critic_id, ctx.run_id, exc)

    # Guardrail 2: advisory-by-default + audited auto-apply.
    if remediation is not None:
        can_apply = (
            auto_apply
            and remediation.kind in auto_apply_kinds
            and any(e.is_cited for e in remediation.evidence)
            and published
        )
        if can_apply:
            remediation.applied = True
            remediation.audit = {
                "applied_at": datetime.now(timezone.utc).isoformat(),
                "critic_id": critic.critic_id,
                "issue_code": issue.code,
                "run_id": ctx.run_id,
                "params_delta": dict(remediation.params_delta),
                "evidence": [e.to_dict() for e in remediation.evidence if e.is_cited],
            }
        else:
            remediation.applied = False

    return CriticFinding(issue=issue, remediation=remediation, published=published)


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
