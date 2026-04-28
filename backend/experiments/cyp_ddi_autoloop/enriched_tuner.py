"""
Knowledge-enriched parameter tuner for CYP DDI auto-loop.

Wraps `CYPDDIParamTuner` to attach literature citations to every remediation.
The `EnrichedRemediation` objects are what get emitted to the frontend
(via SSE `autoloop_update` events) and to the audit trail.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .param_tuner import CYPDDIParamTuner, Remediation
from .params import CYPDDIParams
from .qc_evaluator import PhaseQCResult
from .knowledge_base import KnowledgeEntry, get_knowledge


# ── Extended Remediation ──────────────────────────────────────────────────────

@dataclass
class EnrichedRemediation:
    """
    A `Remediation` augmented with knowledge entries from FDA DDI guidance
    and peer-reviewed literature.

    Every automated parameter change is backed by a traceable, verbatim source.
    """
    phase: str
    gate: str
    param_changes: dict
    rationale: str
    citations: list[KnowledgeEntry] = field(default_factory=list)

    @classmethod
    def from_remediation(cls, rem: Remediation) -> "EnrichedRemediation":
        return cls(
            phase=rem.phase,
            gate=rem.gate,
            param_changes=rem.param_changes,
            rationale=rem.rationale,
            citations=get_knowledge(rem.gate),
        )

    def to_dict(self) -> dict:
        return {
            "phase": self.phase,
            "gate": self.gate,
            "param_changes": self.param_changes,
            "rationale": self.rationale,
            "citations": [c.to_dict() for c in self.citations],
        }

    def has_citations(self) -> bool:
        return len(self.citations) > 0


# ── Enriched tuner ────────────────────────────────────────────────────────────

class KnowledgeEnrichedCYPTuner:
    """
    Drop-in replacement for `CYPDDIParamTuner` that returns `EnrichedRemediation`
    objects instead of plain `Remediation` objects.

    Usage::

        tuner = KnowledgeEnrichedCYPTuner()
        new_params, enriched_rems = tuner.remediate(qc_result, params)
        for r in enriched_rems:
            print(r.citations[0].short_ref())
    """

    def __init__(self) -> None:
        self._inner = CYPDDIParamTuner()

    def remediate(
        self,
        qc_result: PhaseQCResult,
        params: CYPDDIParams,
    ) -> tuple[CYPDDIParams, list[EnrichedRemediation]]:
        new_params, remediations = self._inner.remediate(qc_result, params)
        enriched = [EnrichedRemediation.from_remediation(r) for r in remediations]
        return new_params, enriched
