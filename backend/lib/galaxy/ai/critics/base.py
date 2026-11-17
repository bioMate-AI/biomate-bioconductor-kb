"""
Critic framework — core interface and data model.

A *Critic* is a small, independently-testable plugin that reads a completed run's
*contract* (``design.json`` + ``results_manifest.json`` + the run's published output
artifacts) and answers two questions about the SCIENCE of the run:

    detect(run_context)        -> Issue[]          "is anything wrong with this analysis?"
    remediate(issue, run_ctx)  -> Remediation       "what is the correct analysis, and why?"

The critic never reads a workflow's internals (no ``.nf`` parsing). It reads only the
standardized run contract. This is the substrate that moves the domain statistics OUT
of the workflow ``.nf`` and into reusable, versioned, unit-tested Python modules.

Design intent (see docs/… critic_framework_design):
  * The *framework* (this module + registry + hook + run_context) is generic.
  * The *statistics* live in concrete ``Critic`` subclasses (survival, rna-seq, …).
  * Guardrails are structural, not optional: an Issue with no cited evidence is
    down-ranked to advisory/silent by the hook (cite-evidence-or-stay-silent), and
    a Remediation is advisory unless auto-apply is explicitly opted into and audited.

This file intentionally has ZERO heavy dependencies (stdlib only) so it imports
cheaply on the executor completion path and is trivially unit-testable.
"""
from __future__ import annotations

import enum
from abc import ABC, abstractmethod
from dataclasses import dataclass, field, asdict
from typing import Any, Callable, Dict, List, Optional


# ─────────────────────────────────────────────────────────────────────────────
# Severity / remediation vocabulary
# ─────────────────────────────────────────────────────────────────────────────

class Severity(enum.Enum):
    """How strongly a detected Issue should be surfaced.

    Ordering (INFO < ADVISORY < WARNING < CRITICAL) lets the hook sort and
    threshold. Nothing here *blocks* a run — critics are post-run and advisory by
    default; severity drives presentation and (optionally) auto-apply eligibility.
    """
    INFO = "info"
    ADVISORY = "advisory"
    WARNING = "warning"
    CRITICAL = "critical"

    @property
    def rank(self) -> int:
        return {"info": 0, "advisory": 1, "warning": 2, "critical": 3}[self.value]


class Provenance(enum.Enum):
    """Evidence provenance grade — mirrors qc_evidence.yaml's GOLD/SILVER/BRONZE."""
    GOLD = "GOLD"       # peer-reviewed / regulatory guideline with a DOI
    SILVER = "SILVER"   # textbook / widely-accepted methodological norm
    BRONZE = "BRONZE"   # heuristic / community practice
    NONE = "NONE"       # uncited — the hook will NOT publish an issue resting only on this


class RemediationKind(enum.Enum):
    """The bounded, deterministic operation a Remediation proposes.

    Keeping this a CLOSED enum is a guardrail: a critic (and, later, the LLM critic)
    may only ever propose one of these well-understood, reviewable operations —
    never free-form "change the analysis".
    """
    REFIT = "refit"                 # re-fit the same model with a corrected spec
    ADD_COVARIATE = "add_covariate" # add omitted covariate(s) to the design formula
    STRATIFY = "stratify"           # stratify by a covariate (e.g. PH violation)
    TIME_TRANSFORM = "time_transform"  # add a time-varying term (tt()) for a covariate
    DROP_SAMPLE = "drop_sample"     # exclude outlier / degenerate group
    RENORMALIZE = "renormalize"     # change normalization method
    FLAG = "flag"                   # advisory-only: surface, propose no mechanical change


# ─────────────────────────────────────────────────────────────────────────────
# Evidence (grounding) — the cite-or-stay-silent substrate
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class Evidence:
    """One grounded claim backing an Issue or Remediation.

    ``provenance == Provenance.NONE`` or an empty ``source``/``doi`` means the claim
    is uncited; the hook treats an Issue whose evidence is entirely uncited as
    advisory-only (or drops it), per the guardrail. A DOI is strongly preferred and
    should ultimately resolve against ``config/qc_evidence.yaml`` design-rule entries.
    """
    claim: str
    source: str = ""                       # human-readable citation or qc_evidence key
    doi: Optional[str] = None
    provenance: Provenance = Provenance.NONE

    @property
    def is_cited(self) -> bool:
        return self.provenance is not Provenance.NONE and bool(self.source or self.doi)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "claim": self.claim,
            "source": self.source,
            "doi": self.doi,
            "provenance": self.provenance.value,
        }


# ─────────────────────────────────────────────────────────────────────────────
# Issue — a detected problem with a run's analysis
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class Issue:
    """A single scientific problem a critic detected in a completed run.

    Unlike the legacy ``GateResult(gate, value, threshold, action)`` (a scalar-vs-
    threshold comparison), an Issue expresses a *judgment about the design/analysis*:
    confounding, PH violation, batch-in-formula, underpowered, etc.
    """
    critic_id: str
    code: str                               # stable machine code, e.g. "omitted_confounder"
    title: str                              # one-line human summary
    severity: Severity = Severity.ADVISORY
    detail: str = ""                        # longer explanation (shown to the scientist)
    subjects: List[str] = field(default_factory=list)   # e.g. covariate names
    metrics: Dict[str, Any] = field(default_factory=dict)  # e.g. {"naive_hr":.817,"adjusted_hr":.806}
    evidence: List[Evidence] = field(default_factory=list)

    @property
    def is_cited(self) -> bool:
        """True iff at least one piece of backing evidence is cited."""
        return any(e.is_cited for e in self.evidence)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "critic_id": self.critic_id,
            "code": self.code,
            "title": self.title,
            "severity": self.severity.value,
            "detail": self.detail,
            "subjects": list(self.subjects),
            "metrics": dict(self.metrics),
            "evidence": [e.to_dict() for e in self.evidence],
            "is_cited": self.is_cited,
        }


# ─────────────────────────────────────────────────────────────────────────────
# Remediation — the proposed correct analysis
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class Remediation:
    """The corrected analysis a critic proposes for an Issue.

    Always carries the naive-vs-corrected comparison and the rationale so the
    scientist can judge it. ``applied`` is False by default (advisory-by-default);
    the hook flips it to True only under an explicit, audited auto-apply opt-in.
    """
    issue_code: str
    kind: RemediationKind
    summary: str                            # one-line "what to do"
    rationale: str = ""                     # why — grounded in evidence
    # naive-vs-corrected: the headline the scientist reads (e.g. HR 0.817 -> 0.806)
    naive: Dict[str, Any] = field(default_factory=dict)
    corrected: Dict[str, Any] = field(default_factory=dict)
    # the bounded mechanical change (a formula edit / param delta / stratify key)
    params_delta: Dict[str, Any] = field(default_factory=dict)
    evidence: List[Evidence] = field(default_factory=list)
    applied: bool = False                   # advisory-by-default
    audit: Dict[str, Any] = field(default_factory=dict)  # populated iff applied

    def to_dict(self) -> Dict[str, Any]:
        return {
            "issue_code": self.issue_code,
            "kind": self.kind.value,
            "summary": self.summary,
            "rationale": self.rationale,
            "naive": dict(self.naive),
            "corrected": dict(self.corrected),
            "params_delta": dict(self.params_delta),
            "evidence": [e.to_dict() for e in self.evidence],
            "applied": self.applied,
            "audit": dict(self.audit),
        }


# ─────────────────────────────────────────────────────────────────────────────
# Critic — the plugin interface
# ─────────────────────────────────────────────────────────────────────────────

class Critic(ABC):
    """Base class for a single, domain-specific self-correction plugin.

    Subclasses set ``domain`` and ``critic_id`` and implement ``detect`` + ``remediate``.
    ``applies_to`` gates dispatch cheaply BEFORE any output is read, so a run that a
    critic does not concern pays nothing. The default checks the run's declared
    ``workflow_domain`` and that the critic's required artifacts are present.
    """

    #: Coarse domain this critic serves (matched against RunContext.workflow_domain).
    domain: str = ""
    #: Stable identifier (used in Issue.critic_id, registry keys, audit logs).
    critic_id: str = ""
    #: Output artifact filenames this critic needs present to run (e.g. survival_qc.json).
    #: Empty means "no specific artifact required".
    required_artifacts: List[str] = []

    def applies_to(self, ctx: "RunContext") -> bool:
        """Cheap pre-check: does this critic concern this run?

        Default: domain matches (or critic is domain-agnostic) AND every required
        artifact is listed in the results manifest. Override for finer control.
        """
        if self.domain and ctx.workflow_domain and self.domain != ctx.workflow_domain:
            # Allow a soft match on nextflow_path / workflow name for runs that did
            # not stamp a domain (common for bioc subworkflows).
            if self.domain not in (ctx.workflow or "").lower() and \
               self.domain not in (ctx.nextflow_path or "").lower():
                return False
        for art in self.required_artifacts:
            if ctx.find_artifact(art) is None:
                return False
        return True

    @abstractmethod
    def detect(self, ctx: "RunContext") -> List[Issue]:
        """Read the run contract/artifacts and return zero or more Issues."""
        raise NotImplementedError

    @abstractmethod
    def remediate(self, issue: Issue, ctx: "RunContext") -> Remediation:
        """Given one of this critic's own Issues, return the corrected-analysis proposal."""
        raise NotImplementedError


# RunContext is defined in run_context.py to keep that (slightly heavier, I/O-aware)
# logic separate; re-exported here for the type references above at runtime.
from .run_context import RunContext  # noqa: E402  (circular-safe: run_context imports nothing from here)

__all__ = [
    "Severity",
    "Provenance",
    "RemediationKind",
    "Evidence",
    "Issue",
    "Remediation",
    "Critic",
    "RunContext",
]
