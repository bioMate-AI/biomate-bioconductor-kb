"""
Knowledge-enriched parameter tuner.

Wraps `ParamTuner` to attach literature citations to every remediation.
The `EnrichedRemediation` objects are what get emitted to the frontend
(via SSE `autoloop_update` events) and to the audit trail.
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from cryo_em_autoloop.param_tuner import ParamTuner, Remediation
from cryo_em_autoloop.params import CryoEMParams
from cryo_em_autoloop.qc_evaluator import PhaseQCResult

from .knowledge_base import KnowledgeEntry, get_knowledge


# ── Extended Remediation ──────────────────────────────────────────────────────

@dataclass
class EnrichedRemediation:
    """
    A `Remediation` augmented with knowledge entries from BioMate skill docs.

    This is what reaches the frontend — every automated parameter change
    is backed by traceable, verbatim sources from published structural biology
    studies (docs/cryo_em_skills/).
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

class KnowledgeEnrichedTuner:
    """
    Drop-in replacement for `ParamTuner` that returns `EnrichedRemediation`
    objects instead of plain `Remediation` objects.

    Usage::

        tuner = KnowledgeEnrichedTuner()
        new_params, enriched_rems = tuner.remediate(qc_result, params)
        for r in enriched_rems:
            print(r.citations[0].short_ref())
    """

    def __init__(self) -> None:
        self._inner = ParamTuner()

    def remediate(
        self,
        qc_result: PhaseQCResult,
        params: CryoEMParams,
    ) -> tuple[CryoEMParams, list[EnrichedRemediation]]:
        new_params, remediations = self._inner.remediate(qc_result, params)
        enriched = [EnrichedRemediation.from_remediation(r) for r in remediations]
        return new_params, enriched
