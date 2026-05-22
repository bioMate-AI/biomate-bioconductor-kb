"""
Knowledge-enriched PBPK tuner.

Wraps PBPKTuner.remediate() — attaches knowledge_base citations to each
remediation so SSE payloads include the supporting FDA/EMA/peer-reviewed
evidence for the parameter change.

Mirrors KnowledgeEnrichedADMETTuner / KnowledgeEnrichedDockingTuner etc.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Tuple

from .knowledge_base import KnowledgeEntry, get_knowledge_for_gate
from .param_tuner import PBPKTuner, Remediation
from .params import PBPKParams
from .qc_evaluator import PhaseQCResult


@dataclass
class EnrichedRemediation:
    """A Remediation + the KnowledgeEntries supporting it."""
    remediation: Remediation
    knowledge: list[KnowledgeEntry] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            **self.remediation.to_dict(),
            "knowledge": [k.to_dict() for k in self.knowledge],
        }


class KnowledgeEnrichedPBPKTuner:
    """Wraps PBPKTuner.remediate; adds per-gate knowledge citations."""

    def __init__(self):
        self._base = PBPKTuner()

    def remediate(
        self,
        qc_result: PhaseQCResult,
        params: PBPKParams,
    ) -> Tuple[PBPKParams, list[EnrichedRemediation]]:
        new_params, base_remeds = self._base.remediate(qc_result, params)
        enriched: list[EnrichedRemediation] = []
        for r in base_remeds:
            enriched.append(EnrichedRemediation(
                remediation=r,
                knowledge=get_knowledge_for_gate(r.gate),
            ))
        return new_params, enriched
