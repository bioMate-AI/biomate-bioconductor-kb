"""
OutputPresence / low-N result-floor critic — the generic "did this run actually
produce usable science?" gate (Phase-2 build order, committee item #2).

This is the domain-agnostic floor every workflow should clear: it reads the run's
*manifest* (and, when present, a result-summary JSON) and surfaces three ways a run
can finish "successfully" while producing nothing a scientist can use:

  1. **Missing expected outputs** — the run declared ``expected_outputs`` but some are
     absent, OR the manifest lists files yet none are a primary scientific artifact
     (table / model / figure / result — only logs & QC were produced), OR the manifest
     is present but declares zero files at all.
  2. **Empty / near-empty result tables** — a primary table artifact is 0 bytes (or a
     summary declares 0 rows).
  3. **Zero significant features** — a result summary reports 0 significant
     features/genes/hits. This is a *legitimate null result*, surfaced (ADVISORY) so it
     is reported honestly and not mistaken for a pipeline bug — not alarmed over.

It is advisory-only (every remediation is a ``FLAG``) and reads ONLY the contract
(``results_manifest.json`` via ``RunContext.outputs`` + optional summary JSON). It
degrades gracefully: with no manifest at all (e.g. a bare context) it stays silent
rather than guessing a run "failed".
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Tuple

from ..base import Critic, Issue, Remediation, RemediationKind, Severity
from ..run_context import RunContext, OutputFile
from ..evidence import design_rule

log = logging.getLogger(__name__)

# Manifest roles that count as primary, user-facing scientific output.
_PRIMARY_ROLES = {"table", "model", "figure", "result"}
# Roles that are tabular results whose emptiness is meaningful.
_TABLE_ROLES = {"table", "result"}
# Summary-JSON keys that carry a significant-feature count.
_SIG_KEYS = (
    "n_significant", "num_significant", "n_sig", "significant",
    "n_degs", "n_deg", "n_significant_features", "significant_features",
    "n_significant_genes", "significant_genes",
)
# Summary-JSON keys that carry a result row count.
_ROWCOUNT_KEYS = ("n_rows", "num_rows", "row_count", "n_records")
# Fixed candidate summary artifacts (plus manifest/inline *.json discovered at runtime).
_SUMMARY_CANDIDATES = (
    "results_summary.json", "de_summary.json", "de_results_summary.json",
    "summary.json", "qc_metrics.json", "analysis_summary.json",
)


def _num(v: Any) -> Optional[float]:
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    return None


def _summary_jsons(ctx: RunContext) -> List[Tuple[str, Dict[str, Any]]]:
    """Load candidate result-summary JSONs: a fixed list plus any manifest/inline file
    whose name looks like a summary/stats document. Never raises."""
    names = set(_SUMMARY_CANDIDATES)
    for o in ctx.outputs or []:
        n = (o.name or "").lower()
        if n.endswith(("summary.json", "stats.json", "_qc.json", "metrics.json")):
            names.add(o.name)
    for n in list((ctx.inline_artifacts or {}).keys()):
        if str(n).lower().endswith(".json"):
            names.add(n)
    out: List[Tuple[str, Dict[str, Any]]] = []
    for n in names:
        try:
            j = ctx.load_json(n)
        except Exception:
            j = None
        if isinstance(j, dict):
            out.append((n, j))
    return out


def _basename_set(outputs: List[OutputFile]) -> set:
    return {(o.name or "").lower() for o in outputs}


class OutputPresenceCritic(Critic):
    """Generic result-presence / null-result floor. Domain-agnostic, advisory-only."""

    domain = "*"
    critic_id = "output.presence"
    required_artifacts: List[str] = []  # universal: gate on the manifest inside detect()

    def applies_to(self, ctx: RunContext) -> bool:
        """Universal critic: concerns EVERY run (the base ``applies_to`` would reject a
        literal ``"*"`` domain against a concrete one). Self-selection happens inside
        ``detect`` (it stays silent when no manifest is declared)."""
        for art in self.required_artifacts:
            if ctx.find_artifact(art) is None:
                return False
        return True

    def detect(self, ctx: RunContext) -> List[Issue]:
        issues: List[Issue] = []
        design = ctx.design or {}
        outputs = list(ctx.outputs or [])
        manifest_declared = isinstance(ctx.raw_manifest, dict) and "files" in ctx.raw_manifest
        ev_present = design_rule("output.expected_outputs_present")
        ev_null = design_rule("output.null_result_reporting")

        # 1a. Explicitly declared expected outputs that are missing.
        expected = design.get("expected_outputs")
        if isinstance(expected, list) and expected:
            present = _basename_set(outputs)
            missing = [
                str(e) for e in expected
                if not any(p == str(e).lower() or p.endswith("/" + str(e).lower())
                           for p in present)
            ]
            if missing:
                issues.append(Issue(
                    critic_id=self.critic_id,
                    code="missing_expected_outputs",
                    title=f"Missing expected output(s): {', '.join(missing)}",
                    severity=Severity.WARNING,
                    detail=(
                        "The run declared these primary outputs but the manifest does "
                        f"not contain them: {', '.join(missing)}. The analysis did not "
                        "produce the artifacts it was expected to."
                    ),
                    subjects=missing,
                    metrics={"expected": [str(e) for e in expected], "missing": missing},
                    evidence=[ev_present] if ev_present else [],
                ))
        # 1b. No explicit expectation: generic "did it emit any primary output?" floor.
        elif manifest_declared:
            if not outputs:
                issues.append(Issue(
                    critic_id=self.critic_id,
                    code="no_outputs",
                    title="Run produced no output files",
                    severity=Severity.WARNING,
                    detail=("The results manifest declares zero output files — the run "
                            "finished without producing any artifacts."),
                    subjects=[],
                    metrics={"n_outputs": 0},
                    evidence=[ev_present] if ev_present else [],
                ))
            elif not any(o.role in _PRIMARY_ROLES for o in outputs):
                roles = sorted({o.role for o in outputs})
                issues.append(Issue(
                    critic_id=self.critic_id,
                    code="no_primary_output",
                    title="Run produced no primary scientific output",
                    severity=Severity.WARNING,
                    detail=(
                        "The manifest lists only non-primary artifacts "
                        f"(roles: {', '.join(roles)}) — no result table, model or figure. "
                        "The run emitted logs/QC but no usable scientific result."
                    ),
                    subjects=[],
                    metrics={"n_outputs": len(outputs), "roles": roles},
                    evidence=[ev_present] if ev_present else [],
                ))

        # 2. Empty / near-empty result tables (0-byte primary tables, or summary n_rows=0).
        empty_tables = [
            o.name for o in outputs
            if o.role in _TABLE_ROLES and isinstance(o.size, int) and o.size == 0
        ]
        summaries = _summary_jsons(ctx)
        zero_row_sources = [
            name for name, j in summaries
            if any(_num(j.get(k)) == 0.0 for k in _ROWCOUNT_KEYS)
        ]
        if empty_tables or zero_row_sources:
            subjects = sorted(set(empty_tables) | set(zero_row_sources))
            issues.append(Issue(
                critic_id=self.critic_id,
                code="empty_results",
                title=f"Empty result table(s): {', '.join(subjects)}",
                severity=Severity.WARNING,
                detail=(
                    "These result artifacts are empty (0 bytes / 0 rows): "
                    f"{', '.join(subjects)}. A declared result table with no content is "
                    "a null result, not a successful finding — verify inputs and "
                    "thresholds, and report it as such."
                ),
                subjects=subjects,
                metrics={"empty_tables": empty_tables, "zero_row_sources": zero_row_sources},
                evidence=[ev_null] if ev_null else [],
            ))

        # 3. Zero significant features (legitimate null result → ADVISORY, surface only).
        zero_sig: List[str] = []
        for name, j in summaries:
            for k in _SIG_KEYS:
                if k in j and _num(j.get(k)) == 0.0:
                    zero_sig.append(f"{name}:{k}")
                    break
        if zero_sig:
            issues.append(Issue(
                critic_id=self.critic_id,
                code="zero_significant_features",
                title="Analysis found zero significant features",
                severity=Severity.ADVISORY,
                detail=(
                    "A result summary reports zero significant features/genes/hits "
                    f"({', '.join(zero_sig)}). This may be a true null result — report "
                    "it honestly as 'no significant findings', and check it is not a "
                    "threshold or power problem rather than a pipeline failure."
                ),
                subjects=zero_sig,
                metrics={"zero_significant_sources": zero_sig},
                evidence=[ev_null] if ev_null else [],
            ))

        return issues

    def remediate(self, issue: Issue, ctx: RunContext) -> Remediation:
        """Advisory-only ``FLAG`` — the layer cannot manufacture a result; it can only
        tell the scientist the run did not produce usable science and why to re-check."""
        code = issue.code
        if code in ("missing_expected_outputs", "no_outputs", "no_primary_output"):
            key = "output.expected_outputs_present"
            summary = (
                "Verify the run completed every step and wrote its primary outputs; "
                "re-check inputs and logs before treating this run as a usable result."
            )
            rationale = (
                "A run that emits no primary artifact has produced nothing to interpret; "
                "the layer flags it rather than presenting an empty run as a success."
            )
        elif code == "empty_results":
            key = "output.null_result_reporting"
            summary = (
                "Treat the empty table as a null result: confirm inputs/filters are "
                "correct, and report 'no results' explicitly rather than as success."
            )
            rationale = (
                "An empty result table is either a true null or an upstream problem; "
                "either way it must be surfaced, not silently passed as a finding."
            )
        else:  # zero_significant_features
            key = "output.null_result_reporting"
            summary = (
                "Report zero significant features honestly as a null finding; sanity-"
                "check the significance threshold, effect direction and power first."
            )
            rationale = (
                "Absence of significant results is itself a result; it should be "
                "reported, but it is not a pipeline success and not auto-fixable."
            )
        ev = design_rule(key)
        return Remediation(
            issue_code=issue.code,
            kind=RemediationKind.FLAG,
            summary=summary,
            rationale=rationale,
            naive=dict(issue.metrics),
            corrected={},
            params_delta={},   # NEVER changes anything
            evidence=[ev] if ev else [],
        )
