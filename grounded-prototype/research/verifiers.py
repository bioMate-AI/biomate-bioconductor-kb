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


def _blend_decomp(node_f1: float, structure_hit: float, edge_f1: float) -> float:
    """Scalar decomposition reward: nodes + structure are the primary signal, edges
    conditioned on matched nodes. Shared by the mirror StructureVerifier AND the real
    scorer bridge so the two produce identical rewards on identical component scores."""
    return max(0.0, min(1.0, 0.45 * node_f1 + 0.30 * structure_hit + 0.25 * edge_f1))


class StructureVerifier:
    """Decomposition-plan reward, mirroring evaluation/datasets/decomposition_v2/
    score.py :: score_one — a blend of node_f1 (did we recover the right
    sub-tasks, token-matched), edge_f1 (right dependency edges on matched nodes),
    and structure match (parallel/sequential/mixed). This is the Part A signal:
    reward decomposing CORRECTLY (parallel when parallel), not merely more.

    ground_truth = {"gold_subtasks": [{"sub_task","order","depends_on",
    "domain"?,"tool_id"?}, ...]}. `response` is the predicted plan as a JSON list
    (or its JSON string). Weighting follows the benchmark's emphasis: nodes and
    structure first, edges conditioned on matched nodes.
    """

    name = "decomp_structure"
    answer_free = False

    _WORD = re.compile(r"[a-z0-9]+")

    def _toks(self, s: Any) -> set:
        return set(self._WORD.findall(str(s).lower()))

    def _tok_f1(self, a: set, b: set) -> float:
        if not a or not b:
            return 0.0
        inter = len(a & b)
        if not inter:
            return 0.0
        p, r = inter / len(a), inter / len(b)
        return 2 * p * r / (p + r)

    def _gold_match_tokens(self, gn: dict) -> set:
        t = self._toks(gn.get("sub_task", ""))
        t |= self._toks(str(gn.get("domain", "")).replace("_", " "))
        t |= self._toks(gn.get("tool_id", ""))
        return t

    def _match_nodes(self, pred: list, gold: list, thresh: float = 0.3) -> Dict[int, int]:
        gtoks = [self._gold_match_tokens(g) for g in gold]
        ptoks = [self._toks(p.get("sub_task", "")) for p in pred]
        cand = []
        for pi, pt in enumerate(ptoks):
            for gi, gt in enumerate(gtoks):
                s = self._tok_f1(pt, gt)
                if s >= thresh:
                    cand.append((s, pi, gi))
        cand.sort(reverse=True)
        pused, gused, m = set(), set(), {}
        for s, pi, gi in cand:
            if pi in pused or gi in gused:
                continue
            pused.add(pi); gused.add(gi); m[pi] = gi
        return m

    def _edges(self, plan: list) -> set:
        idx = {}
        for i, s in enumerate(plan):
            idx[s.get("order", i + 1)] = i
        E = set()
        for i, s in enumerate(plan):
            for d in (s.get("depends_on", []) or []):
                if d in idx:
                    E.add((idx[d], i))
        return E

    def _structure_of(self, plan: list) -> str:
        deps = [len(s.get("depends_on", []) or []) for s in plan if isinstance(s, dict)]
        if not deps:
            return "empty"
        if all(d == 0 for d in deps):
            return "parallel"
        if all(d > 0 for d in deps[1:]):
            return "sequential"
        return "mixed"

    def score(self, ground_truth: Any, response: str) -> float:
        import json
        gold = (ground_truth or {}).get("gold_subtasks", []) or []
        pred = response
        if isinstance(pred, str):
            try:
                pred = json.loads(pred)
            except Exception:
                pred = []
        if not isinstance(pred, list):
            pred = []
        if not gold:
            return 0.0

        m = self._match_nodes(pred, gold)
        tp = len(m)
        node_p = tp / len(pred) if pred else 0.0
        node_r = tp / len(gold) if gold else 0.0
        node_f1 = 2 * node_p * node_r / (node_p + node_r) if (node_p + node_r) else 0.0

        ge = self._edges(gold)
        pe = {(m[u], m[v]) for (u, v) in self._edges(pred) if u in m and v in m}
        etp = len(pe & ge)
        edge_p = etp / len(pe) if pe else (1.0 if not ge else 0.0)
        edge_r = etp / len(ge) if ge else (1.0 if not pe else 0.0)
        edge_f1 = (2 * edge_p * edge_r / (edge_p + edge_r)) if (edge_p + edge_r) else (
            1.0 if (not ge and not pe) else 0.0)

        structure_hit = 1.0 if self._structure_of(pred) == self._structure_of(gold) else 0.0
        return _blend_decomp(node_f1, structure_hit, edge_f1)


class RealDecompVerifier:
    """Decomposition reward computed by BioMate's REAL production scorer
    (evaluation/datasets/decomposition_v2/score.py::score_one), not the mirror. This is
    the "production wiring" the module docstring calls for: the self-improvement loop
    optimizes against the exact node_f1/edge_f1/structure metric the benchmark reports,
    so a harness edit that scores well here scores well on the real benchmark. Blended
    with _blend_decomp — identical to StructureVerifier on identical component scores."""

    name = "decomp_structure_real"
    answer_free = False

    def __init__(self, scorer_module):
        self._score_one = scorer_module.score_one

    def score(self, ground_truth: Any, response: str) -> float:
        import json
        gold = (ground_truth or {}).get("gold_subtasks", []) or []
        pred = response
        if isinstance(pred, str):
            try:
                pred = json.loads(pred)
            except Exception:
                pred = []
        if not isinstance(pred, list):
            pred = []
        if not gold:
            return 0.0
        r = self._score_one(gold, pred)
        return _blend_decomp(float(r.get("node_f1", 0.0)),
                             float(r.get("structure_hit", 0.0)),
                             float(r.get("edge_f1", 0.0)))


_REAL_DECOMP = "unset"


def real_decomp_verifier():
    """Load BioMate's real decomposition scorer once; return a RealDecompVerifier, or
    None when evaluation/ is unavailable (then the caller uses the mirror). Resilient:
    any import failure falls back to None rather than breaking the loop."""
    global _REAL_DECOMP
    if _REAL_DECOMP == "unset":
        _REAL_DECOMP = None
        try:
            import importlib.util
            import os
            here = os.path.dirname(os.path.abspath(__file__))
            path = os.path.abspath(os.path.join(
                here, "..", "..", "evaluation", "datasets", "decomposition_v2", "score.py"))
            if os.path.exists(path):
                spec = importlib.util.spec_from_file_location("biomate_decomp_score", path)
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                if hasattr(mod, "score_one"):
                    _REAL_DECOMP = RealDecompVerifier(mod)
        except Exception:
            _REAL_DECOMP = None
    return _REAL_DECOMP


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
_STRUCT = StructureVerifier()


def select_verifier(ground_truth: Optional[Any]) -> Verifier:
    """Answer-BASED where the task carries ground truth (by shape), else the
    answer-FREE trust lattice. This is the P0 bridge decision."""
    if isinstance(ground_truth, dict):
        if ground_truth.get("expected_params") is not None:
            return _PARAMS
        if ground_truth.get("classes") is not None:
            return _CLASS
        if ground_truth.get("gold_subtasks") is not None:
            # a decomposition-plan task (research/decompose.py): the gold plan is ground
            # truth, scored graph-aware (node/edge/structure). Prefer BioMate's REAL
            # production scorer; fall back to the mirror when evaluation/ is unavailable.
            return real_decomp_verifier() or _STRUCT
        if ground_truth.get("expected") is not None:
            # a user-correction task (research/feedback.py): the corrected value
            # is ground truth. Lazy import avoids a cycle.
            from .feedback import CorrectionVerifier
            return CorrectionVerifier()
    return _TRUST
