"""
Verifier bridge (P0) — let the Harness2 loop score a harness against BioMate's
REAL ground-truth verifiers where they exist, and the answer-free Grounded trust
lattice where they do not.

Contract matches BioMate's eval harness exactly, so the real scorers drop in:
    evaluation/core/base_adapter.py :: BenchmarkAdapter.score(task, response)->float
Here a Verifier is `score(ground_truth, response) -> float in [0,1]` + a `name` +
`answer_free` flag. `select_verifier(ground_truth)` picks answer-BASED when the
task carries ground truth, else the answer-FREE trust lattice.

Two reference verifiers are implemented with the SAME logic as BioMate's:
  * ExpectedParamsVerifier   — F1 over expected_params with a must_not_fill penalty,
                               mirroring evaluation/adapters/param_prefill_adapter.py
  * ExactClassVerifier       — exact class-match accuracy, mirroring
                               evaluation/scorers/admet_scorer.py
  * TrustLatticeVerifier     — answer-free: tiered-citation density + a boundary-
                               honesty bonus (the Grounded signal).

Production wiring: replace these with the real adapters' `score()` — same
signature — keyed by the task's benchmark. Nothing else in the loop changes.
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Protocol, runtime_checkable


@runtime_checkable
class Verifier(Protocol):
    name: str
    answer_free: bool

    def score(self, ground_truth: Any, response: str) -> float:
        """Return a reward in [0,1] for `response` given `ground_truth`."""


# ── answer-free: the Grounded trust lattice ──────────────────────────────────

class TrustLatticeVerifier:
    """Answer-free reward from the Grounded deliverable: authoritative-citation
    density + a bonus for honest boundaries (preferring the gap-admitter, per
    Harness2's FIDELITY rule). Does not use ground truth."""

    name = "trust_lattice"
    answer_free = True

    def score(self, ground_truth: Any, response: str) -> float:
        a = response.count("[A·")
        b = response.count("[B·")
        authoritative = a + b
        # honesty bonus: the answer names where the record stops rather than
        # confidently filling the gap.
        honest = 1 if ("not answered from memory" in response.lower()
                       or "where the record stops" in response.lower()) else 0
        # squashing to [0,1]: saturate around ~6 authoritative citations.
        base = min(1.0, authoritative / 6.0)
        return min(1.0, 0.85 * base + 0.15 * honest)


# ── answer-based: mirrors BioMate's real scorers ─────────────────────────────

class ExpectedParamsVerifier:
    """F1 over expected params present in the response, penalised by must_not_fill
    violations — the logic of evaluation/adapters/param_prefill_adapter.py.

    ground_truth = {"expected_params": {k: v, ...}, "must_not_fill": [k, ...]}.
    A param counts as filled if its key AND value both appear in the response.
    """

    name = "expected_params_f1"
    answer_free = False

    def score(self, ground_truth: Any, response: str) -> float:
        gt = ground_truth or {}
        expected: Dict[str, Any] = gt.get("expected_params", {}) or {}
        must_not: List[str] = gt.get("must_not_fill", []) or []
        r = response.lower()

        def _filled(k: str, v: Any) -> bool:
            return k.lower() in r and str(v).lower() in r

        tp = sum(1 for k, v in expected.items() if _filled(k, v))
        # predicted-filled among expected keys (we only observe expected keys here)
        predicted = sum(1 for k in expected if k.lower() in r)
        precision = tp / predicted if predicted else (1.0 if not expected else 0.0)
        recall = tp / len(expected) if expected else 1.0
        f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0

        violations = sum(1 for k in must_not if k.lower() in r)
        penalty = violations / max(len(must_not), 1) if must_not else 0.0
        return max(0.0, f1 * (1.0 - 0.5 * penalty))


class ExactClassVerifier:
    """Exact class-match accuracy over labelled properties — the logic of
    evaluation/scorers/admet_scorer.py.

    ground_truth = {"classes": {prop: expected_label, ...}}; a property is correct
    if `prop` and its expected label co-occur in the response.
    """

    name = "exact_class_accuracy"
    answer_free = False

    def score(self, ground_truth: Any, response: str) -> float:
        classes: Dict[str, str] = (ground_truth or {}).get("classes", {}) or {}
        if not classes:
            return 0.0
        r = response.lower()
        correct = sum(1 for prop, lbl in classes.items()
                      if prop.lower() in r and str(lbl).lower() in r)
        return correct / len(classes)


_TRUST = TrustLatticeVerifier()
_PARAMS = ExpectedParamsVerifier()
_CLASS = ExactClassVerifier()


def select_verifier(ground_truth: Optional[Any]) -> Verifier:
    """Answer-BASED where the task carries ground truth (by shape), else the
    answer-FREE trust lattice. This is the P0 bridge decision."""
    if isinstance(ground_truth, dict):
        if ground_truth.get("expected_params") is not None:
            return _PARAMS
        if ground_truth.get("classes") is not None:
            return _CLASS
    return _TRUST
