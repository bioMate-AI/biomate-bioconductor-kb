"""
Knowledge-enriched parameter tuner for ADMET auto-loop.

Wraps `ADMETParamTuner` to attach literature citations to every remediation.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .param_tuner import ADMETParamTuner, Remediation
from typing import Optional
from .params import ADMETParams
from .qc_evaluator import PhaseQCResult
from .knowledge_base import KnowledgeEntry, get_knowledge


@dataclass
class EnrichedRemediation:
    """
    A `Remediation` augmented with knowledge entries from ADMET literature.

    Every automated parameter change is backed by traceable, verbatim sources
    from Kazius 2005 (Ames), Lammert 2010 (DILI), Waring & Johnstone 2007 (hERG).

    `confidence` mirrors Remediation.confidence:
      "confident"  — categorical fix with GOLD/SILVER evidence, no step-size uncertainty
      "heuristic"  — directionally supported, magnitude estimated from gap ratio
      "manual"     — system cannot determine the correct value; user input required
    """
    phase: str
    gate: str
    param_changes: dict
    rationale: str
    confidence: str = "confident"
    citations: list[KnowledgeEntry] = field(default_factory=list)

    @classmethod
    def from_remediation(cls, rem: Remediation) -> "EnrichedRemediation":
        return cls(
            phase=rem.phase,
            gate=rem.gate,
            param_changes=rem.param_changes,
            rationale=rem.rationale,
            confidence=rem.confidence,
            citations=get_knowledge(rem.gate),
        )

    def to_dict(self) -> dict:
        return {
            "phase": self.phase,
            "gate": self.gate,
            "param_changes": self.param_changes,
            "rationale": self.rationale,
            "confidence": self.confidence,
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
        herg_compound_descriptors: Optional[dict] = None,
    ) -> tuple[ADMETParams, list[EnrichedRemediation]]:
        new_params, remediations = self._inner.remediate(
            qc_result, params, herg_compound_descriptors=herg_compound_descriptors
        )
        enriched = [EnrichedRemediation.from_remediation(r) for r in remediations]
        return new_params, enriched
