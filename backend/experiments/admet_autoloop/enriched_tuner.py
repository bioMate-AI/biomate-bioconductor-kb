"""
Knowledge-enriched parameter tuner for ADMET auto-loop.

Wraps `ADMETParamTuner` to attach literature citations to every remediation.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .param_tuner import ADMETParamTuner, Remediation
from .params import ADMETParams
from .qc_evaluator import PhaseQCResult
from .knowledge_base import KnowledgeEntry, get_knowledge


@dataclass
class EnrichedRemediation:
    """
    A `Remediation` augmented with knowledge entries from ADMET literature.

    Every automated parameter change is backed by traceable, verbatim sources
    from Aronov 2008 (hERG), Lammert 2010 (DILI), and Kazius 2005 (Ames).
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


class KnowledgeEnrichedADMETTuner:
    """
    Drop-in replacement for `ADMETParamTuner` returning `EnrichedRemediation`.
    """

    def __init__(self) -> None:
        self._inner = ADMETParamTuner()

    def remediate(
        self,
        qc_result: PhaseQCResult,
        params: ADMETParams,
    ) -> tuple[ADMETParams, list[EnrichedRemediation]]:
        new_params, remediations = self._inner.remediate(qc_result, params)
        enriched = [EnrichedRemediation.from_remediation(r) for r in remediations]
        return new_params, enriched
