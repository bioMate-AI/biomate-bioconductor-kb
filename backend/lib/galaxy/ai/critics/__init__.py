"""
BioMate Critic layer — generic, scalable self-correction.

A decoupled post-run "judgment" layer that replaces per-workflow, hand-coded ``.nf``
statistics with small, independently-tested, evidence-grounded plugins (*critics*).
Each critic reads only the standardized run contract (``design.json`` +
``results_manifest.json`` + the run's published output artifacts) and answers:

    detect(run_context)       -> Issue[]        "is anything wrong with this analysis?"
    remediate(issue, run_ctx) -> Remediation     "what's the correct analysis, and why?"

Public surface::

    from galaxy.ai.critics import (
        Critic, Issue, Remediation, RunContext, Severity, RemediationKind, Evidence,
        get_registry, run_critics, run_critics_from_run_meta,
    )

The post-run hook (:func:`run_critics_from_run_meta`) attaches to the executor's
AWS-Batch/cloud completion path, builds the RunContext from the run_meta the executor
already computes, and publishes gates + naive-vs-corrected + rationale through the
existing autoloop SSE channel + suggestion store. See the design doc:
``docs/biomate_critic_framework_design.md`` (business dir copy linked from there).
"""
from .base import (
    Critic,
    Issue,
    Remediation,
    Evidence,
    Severity,
    Provenance,
    RemediationKind,
)
from .run_context import RunContext, OutputFile
from .registry import CriticRegistry, get_registry, register_builtin_critics, default_registry
from .hook import (
    run_critics,
    run_critics_from_run_meta,
    CriticReport,
    CriticFinding,
)

__all__ = [
    "Critic",
    "Issue",
    "Remediation",
    "Evidence",
    "Severity",
    "Provenance",
    "RemediationKind",
    "RunContext",
    "OutputFile",
    "CriticRegistry",
    "get_registry",
    "register_builtin_critics",
    "default_registry",
    "run_critics",
    "run_critics_from_run_meta",
    "CriticReport",
    "CriticFinding",
]
