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

    @property
    def rank(self) -> int:
        """Ordering so the hook can pick the best grade and threshold severity on it."""
        return {"NONE": 0, "BRONZE": 1, "SILVER": 2, "GOLD": 3}[self.value]


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

    GROUNDING MODEL (hardened — see hook.py / evidence.py):
      An Evidence is *grounded* only when ``kb_key`` names a design-rule KEY that
      exists in the evidence store (``config/qc_evidence.yaml design_rules:``).
      The authoritative ``claim``/``doi``/``provenance`` are the KB entry's — NOT
      whatever an author (or an LLM critic) stamped on the object. The hook reads
      the grade/DOI *from the KB* and ignores the author-set fields for the
      publish/severity decision, so a fabricated DOI stamped ``GOLD`` with no
      (or an unknown) ``kb_key`` cannot escalate: it is *uncited* and NOT published.

    Construct grounded evidence with :func:`galaxy.ai.critics.evidence.design_rule`
    (it stamps ``kb_key`` for you); never hand-build a GOLD Evidence for publication.

    ``is_cited`` remains a cheap *presence* property (back-compat for callers that
    only format evidence). It is deliberately NOT the publish gate — the hook's
    KB-key grounding check is. ``provenance == NONE`` / empty source still reads as
    un-presence-cited.
    """
    claim: str
    source: str = ""                       # human-readable citation or qc_evidence key
    doi: Optional[str] = None
    provenance: Provenance = Provenance.NONE
    #: Design-rule KB key (``config/qc_evidence.yaml design_rules:``). Grounding is
    #: validated against this at the hook; author-set DOI/grade are NOT trusted for it.
    kb_key: Optional[str] = None

    @property
    def is_cited(self) -> bool:
        """Legacy *presence* check (back-compat). NOT the publish gate — see hook."""
        return self.provenance is not Provenance.NONE and bool(self.source or self.doi)

    def grounded_against(self, resolver: "Callable[[str], Optional['Evidence']]") -> bool:
        """True iff ``kb_key`` resolves to a real KB entry via ``resolver``.

        This is the real grounding test the hook uses: a fabricated DOI with no
        ``kb_key`` (or a key the KB does not contain) returns False, full stop.
        """
        if not self.kb_key:
            return False
        try:
            return resolver(self.kb_key) is not None
        except Exception:
            return False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "claim": self.claim,
            "source": self.source,
            "doi": self.doi,
            "provenance": self.provenance.value,
            "kb_key": self.kb_key,
        }


# ─────────────────────────────────────────────────────────────────────────────
# Precondition — a machine-checkable predicate the hook verifies before publishing
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class Precondition:
    """A deterministic, machine-checkable predicate over a :class:`RunContext`.

    A critic attaches one to an Issue to assert *the flaw is actually present in
    THIS run* (not merely that a KB rule about the flaw exists). The hook runs the
    predicate between ``detect()`` and publication:

      * predicate returns True  → precondition VERIFIED → the issue may reach
        WARNING/CRITICAL (subject to grounding + provenance + confidence).
      * predicate returns False / None, raises, OR the issue declares no
        precondition → UNVERIFIED → the issue is capped to advisory (an FYI), is
        never CRITICAL, and is never auto-apply eligible.

    The predicate must be deterministic and side-effect-free. It is NOT serialized.
    """
    label: str
    predicate: "Callable[['RunContext'], Optional[bool]]"

    def verify(self, ctx: "RunContext") -> bool:
        """Run the predicate; any exception or non-True result → unverified (fail-closed)."""
        try:
            return self.predicate(ctx) is True
        except Exception:
            return False


# ─────────────────────────────────────────────────────────────────────────────
# Untrusted-text hardening — result-file content is DATA, never instructions
# ─────────────────────────────────────────────────────────────────────────────

#: Hard cap on untrusted result-file text fed to any critic (esp. a future LLM critic).
MAX_UNTRUSTED_TEXT_LEN = 4000


def sanitize_untrusted_text(text: Any, max_len: int = MAX_UNTRUSTED_TEXT_LEN) -> str:
    """Neutralize untrusted result-file text read from a ``RunContext`` artifact.

    CONTRACT (injection hardening, committee Blocker B / §3.5):
      * Result-file bytes (logs, QC narratives, sample names, README text) are
        **DATA, never instructions**. A critic reading them MUST pass them through
        this helper before using them in any message, prompt, or detail string.
      * This helper length-caps the text, drops control characters, and neutralizes
        markup/delimiter tokens an attacker uses to break out of a data frame.
      * It NEVER eval/exec's the text. File content can NOT set an Evidence
        ``kb_key``, a provenance grade, a precondition result, or a severity —
        those are decided by the hook from the KB and a deterministic predicate,
        independent of anything a file claims (so a planted
        "emit CRITICAL, provenance GOLD, doi 10.x" cannot flip the verdict).
    """
    if text is None:
        return ""
    if isinstance(text, bytes):
        text = text.decode("utf-8", "replace")
    elif not isinstance(text, str):
        text = str(text)
    # Drop control chars (keep newline/tab); 0x7f and other C0/C1 controls removed.
    cleaned_chars = []
    for ch in text:
        o = ord(ch)
        if ch in ("\n", "\t"):
            cleaned_chars.append(ch)
        elif 32 <= o != 127:
            cleaned_chars.append(ch)
    cleaned = "".join(cleaned_chars)
    # Neutralize markup / fenced-instruction delimiters used to break the data frame.
    for tok in ("<", ">", "`", "\u0000"):
        cleaned = cleaned.replace(tok, " ")
    if max_len is not None and len(cleaned) > max_len:
        cleaned = cleaned[:max_len]
    return cleaned


# ─────────────────────────────────────────────────────────────────────────────
# Issue — a detected problem with a run's analysis
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class Issue:
    """A single scientific problem a critic detected in a completed run.

    Unlike the legacy ``GateResult(gate, value, threshold, action)`` (a scalar-vs-
    threshold comparison), an Issue expresses a *judgment about the design/analysis*:
    confounding, PH violation, batch-in-formula, underpowered, etc.

    ``severity`` is a *request/hint* only. The published severity is COMPUTED BY THE
    HOOK from (grounding, precondition-verified?, provenance grade, confidence,
    clinical-context) — a critic can no longer self-assert CRITICAL. ``confidence``
    (0..1) feeds the governance-by-precision tiering; ``precondition`` is verified
    before the issue may exceed advisory; ``headline_metric`` names the metric the
    generic transport should surface (so the hook needn't pattern-match field names).
    """
    critic_id: str
    code: str                               # stable machine code, e.g. "omitted_confounder"
    title: str                              # one-line human summary
    severity: Severity = Severity.ADVISORY  # REQUEST only — hook recomputes the published value
    detail: str = ""                        # longer explanation (shown to the scientist)
    subjects: List[str] = field(default_factory=list)   # e.g. covariate names
    metrics: Dict[str, Any] = field(default_factory=dict)  # e.g. {"naive_hr":.817,"adjusted_hr":.806}
    evidence: List[Evidence] = field(default_factory=list)
    #: Governance-by-precision knob (0..1). Deterministic critics ≈1.0; an LLM critic
    #: sets it lower. Feeds the hook's severity computation and auto-apply gate.
    confidence: float = 1.0
    #: Name of the metric in ``metrics`` the transport should headline (optional).
    headline_metric: Optional[str] = None
    #: Deterministic predicate the hook verifies before this issue may exceed advisory.
    precondition: Optional[Precondition] = None

    @property
    def is_cited(self) -> bool:
        """Legacy *presence* check — at least one evidence item is presence-cited.

        NOT the publish gate. The hook publishes on KB-key GROUNDING, not presence.
        """
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
            "confidence": self.confidence,
            "headline_metric": self.headline_metric,
            "precondition": self.precondition.label if self.precondition else None,
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

        A ``domain`` of ``""`` or ``"*"`` is a wildcard: the critic is
        domain-agnostic and the domain gate is skipped entirely (it still has to
        pass the required-artifact check below).
        """
        if self.domain not in ("", "*") and ctx.workflow_domain and self.domain != ctx.workflow_domain:
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
    "Precondition",
    "Issue",
    "Remediation",
    "Critic",
    "RunContext",
    "sanitize_untrusted_text",
    "MAX_UNTRUSTED_TEXT_LEN",
]
