"""
Instruction-panel feedback -> reward -> gated harness improvement (B2).

BioMate captures user corrections (the Python `workflow_user_corrections` table +
the TS `correction_log`) but nothing turns them into durable improvement — the
one real learn-from-feedback loop (regulatory-document DPO) is disabled. This
module is the missing bridge: a user correction IS ground truth, so it becomes an
ANSWER-BASED reward signal that feeds the gated Harness2 improver (the corrected
value is what the harness should have produced).

It reuses the P0 verifier bridge (`research/verifiers.py`) and plugs a Correction
into the same `score(ground_truth, response)` contract BioMate's eval harness
uses, so the gated Propose-Probe-Compose loop (research/harness_improver.py +
h2_biomate.py) can improve a rule/skill against real feedback — proposed only,
never auto-applied.

A correction also maps cleanly to a DPO pair (chosen=corrected, rejected=
original), generalising BioMate's regulatory-DPO recorder to every correction
channel.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List

# correction types mirror BioMate's workflow_audit_service.record_correction
CORRECTION_TYPES = ("domain", "tool_selection", "parameters", "answer")


@dataclass
class Correction:
    """One user correction from the instruction panel / workflow card.

    `context` is the goal/query that produced the output; `original_value` is what
    the harness produced (the mistake); `corrected_value` is the user's fix (the
    ground truth).
    """
    correction_type: str
    context: str
    original_value: str
    corrected_value: str
    reason: str = ""
    meta: Dict = field(default_factory=dict)

    def __post_init__(self):
        if self.correction_type not in CORRECTION_TYPES:
            raise ValueError(
                f"unknown correction_type {self.correction_type!r}; "
                f"expected one of {CORRECTION_TYPES}"
            )

    def to_task(self) -> Dict:
        """A Harness2-shaped task: the context is the prompt, ground truth encodes
        the correction so the gated improver can probe an edit against it."""
        key = abs(hash((self.correction_type, self.context, self.corrected_value))) % 100000
        return {
            "id": f"corr:{self.correction_type}:{key}",
            "prompt": self.context,
            "ground_truth": {
                "expected": self.corrected_value,
                "avoid": self.original_value,
                "correction_type": self.correction_type,
            },
        }

    def to_dpo_pair(self) -> Dict:
        """chosen = corrected, rejected = original — the regulatory-DPO shape,
        generalised to any correction channel."""
        return {
            "chosen": self.corrected_value,
            "rejected": self.original_value,
            "prompt": self.context,
            "meta": {"correction_type": self.correction_type, "reason": self.reason, **self.meta},
        }


class CorrectionVerifier:
    """Answer-BASED reward from a user correction: the corrected value is ground
    truth. Rewards producing the corrected value and NOT repeating the original
    mistake. Same signature as BioMate's eval scorers / the P0 verifiers."""

    name = "correction_match"
    answer_free = False

    def score(self, ground_truth, response: str) -> float:
        gt = ground_truth or {}
        expected = str(gt.get("expected", "")).strip().lower()
        avoid = str(gt.get("avoid", "")).strip().lower()
        if not expected:
            return 0.0
        r = (response or "").lower()
        produced_fix = 1.0 if expected in r else 0.0
        repeated_mistake = 1.0 if (avoid and avoid != expected and avoid in r) else 0.0
        # full credit for the fix; halve for repeating the mistake alongside it.
        return max(0.0, produced_fix - 0.5 * repeated_mistake)


def corrections_to_dpo_pairs(corrections: List[Correction]) -> List[Dict]:
    """Turn a batch of corrections into DPO pairs (chosen/rejected), skipping
    no-op corrections where the fix equals the original."""
    out = []
    for c in corrections:
        if c.corrected_value.strip() and c.corrected_value.strip() != c.original_value.strip():
            out.append(c.to_dpo_pair())
    return out
