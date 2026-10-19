"""
Harness2-style self-improvement for the deep-research harness — adapted for
BioMate, GOVERNED.

Google's Harness2 (arXiv:2610.14224, Apache-2.0) improves an agent's *harness*
(not its weights) with a verifier-free **Propose-Probe-Compose** loop. We adopt
the technique — NOT the benchmark CLI (which runs sandbox-disabled with
unrestricted network and is "not an officially supported Google product").

NOTE: this module is the LIGHTWEIGHT local variant (a hand-rolled single PPC step,
useful for quick in-process scoring). The FAITHFUL integration REUSES Google's
actual vendored method code (recursion/selection/library/proposer) via the
`BenchmarkAdapter` seam — see `research/h2_biomate.py` + `research/vendor/harness2/`.
Prefer that for real harness adaptation; keep this for cheap inline checks.

Two BioMate-specific adaptations that make it safe and better here:

  1. VERIFIER-FREE PROBE = the Grounded TRUST LATTICE. Harness2 compares raw
     "behavioral contrasts"; we have a cheap, deterministic quality signal
     already: did an edit yield more AUTHORITATIVE grounded claims, broader tier
     coverage, and fewer unresolved boundaries — at acceptable retrieval cost?
     That is a far better verifier-free probe than a generic behavior diff.

  2. HARD GOVERNANCE GATE. A self-rewriting harness must never silently mutate a
     production pipeline. `propose_probe_compose` only PROPOSES an improvement;
     the winning edit is adopted only after an explicit human `.approve()`.
     Approved lessons accumulate in an `ImprovementHarness` (the second "²"
     recursion), still gated.

The "harness" we edit here is the research controller's knobs (budget + the
router's intent->source-kind table) — a slice of Harness2's 8 components
(tool-guidance + routines), the ones that are safe to vary offline.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from typing import Callable, Dict, List, Optional

from . import router
from .controller import Budget, ResearchResult, research
from .registry import CLINICAL, PATENT, PUBLICATION, WEB


@dataclass
class HarnessConfig:
    """The editable harness slice: retrieval budget + router source-kind table."""
    budget: Budget = field(default_factory=Budget)
    kinds_override: Dict[str, List[str]] = field(default_factory=dict)
    label: str = "base"


@dataclass
class CandidateEdit:
    kind: str                 # "general" | "task_specific"
    description: str
    config: HarnessConfig


@dataclass
class ProbeResult:
    edit: CandidateEdit
    score: float
    metrics: Dict[str, float]


@dataclass
class ProposedImprovement:
    task: str
    base_score: float
    winner: ProbeResult
    probes: List[ProbeResult]
    lesson: str
    improved: bool
    approved: bool = False

    def approve(self) -> HarnessConfig:
        """GOVERNANCE GATE: a human must call this before the edit is adopted."""
        self.approved = True
        return self.winner.edit.config


def harness_score(result: ResearchResult):
    """Verifier-free quality proxy from the trust lattice (+ cost).

    Higher is better. Rewards authoritative grounded evidence and tier breadth;
    penalises unresolved boundaries and retrieval cost. No ground truth needed.
    """
    grounded = [c for c in result.answer.claims if c.is_grounded]
    authoritative = sum(
        1 for c in grounded for s in c.supporting if s.tier.is_authoritative
    )
    tiers = {s.tier for c in grounded for s in c.supporting}
    boundaries = len(result.answer.boundaries)
    cost = sum(t.retrievals for t in result.trace)
    score = 2.0 * authoritative + 1.0 * len(tiers) - 1.5 * boundaries - 0.05 * cost
    return score, {
        "authoritative_claims": float(authoritative),
        "tier_breadth": float(len(tiers)),
        "unresolved_boundaries": float(boundaries),
        "retrieval_cost": float(cost),
    }


# task-intent -> an extra source KIND worth trying for that intent (task-specific edit)
_INTENT_EXTRA_KIND = {
    "admet": CLINICAL, "regulatory": PUBLICATION, "clinical": PATENT,
    "variant": PUBLICATION, "mechanism": CLINICAL, "general": WEB,
}


def _default_propose(task: str, base: HarnessConfig) -> List[CandidateEdit]:
    """Rule stand-in for the LLM proposer: one general + one task-specific edit."""
    intent = router.detect_intent(task)

    # general: broaden breadth + depth
    g_cfg = HarnessConfig(
        budget=replace(base.budget,
                       max_sources_per_subq=base.budget.max_sources_per_subq + 2,
                       max_rounds=base.budget.max_rounds + 1),
        kinds_override=dict(base.kinds_override),
        label="general:broaden",
    )
    general = CandidateEdit("general", "broaden breadth (+2 sources) and depth (+1 round)", g_cfg)

    # task-specific: add a relevant source KIND to this intent's routing table
    base_kinds = (base.kinds_override.get(intent)
                  or router._INTENT_KINDS.get(intent, router._INTENT_KINDS["general"]))
    extra = _INTENT_EXTRA_KIND.get(intent, WEB)
    new_kinds = list(base_kinds) + ([extra] if extra not in base_kinds else [])
    ts_cfg = HarnessConfig(
        budget=base.budget,
        kinds_override={**base.kinds_override, intent: new_kinds},
        label=f"task:add_{extra}_to_{intent}",
    )
    task_specific = CandidateEdit("task_specific", f"add '{extra}' sources to intent '{intent}'", ts_cfg)
    return [general, task_specific]


def propose_probe_compose(
    task: str,
    base: HarnessConfig,
    *,
    retrieve_fn: Callable,
    decompose_fn: Optional[Callable] = None,
    assess_fn: Optional[Callable] = None,
    propose_fn: Optional[Callable[[str, HarnessConfig], List[CandidateEdit]]] = None,
) -> ProposedImprovement:
    """One Harness2 task-level step: PROPOSE edits, PROBE them on `task` via the
    trust-lattice score, COMPOSE the winner — PROPOSED only (needs .approve())."""

    def _run(cfg: HarnessConfig) -> ResearchResult:
        return research(task, "harness-eval", retrieve_fn=retrieve_fn,
                        decompose_fn=decompose_fn, assess_fn=assess_fn,
                        budget=cfg.budget, kinds_override=cfg.kinds_override)

    base_score, _ = harness_score(_run(base))
    candidates = (propose_fn or _default_propose)(task, base)

    probes: List[ProbeResult] = []
    for ed in candidates:
        sc, m = harness_score(_run(ed.config))
        probes.append(ProbeResult(ed, sc, m))

    winner = max(probes, key=lambda p: p.score)
    improved = winner.score > base_score
    lesson = (
        f"intent '{router.detect_intent(task)}': '{winner.edit.description}' "
        f"improved the trust-lattice score {base_score:.1f} -> {winner.score:.1f}"
        if improved else
        f"no proposed edit beat the base harness (base {base_score:.1f})"
    )
    return ProposedImprovement(task, base_score, winner, probes, lesson, improved)


@dataclass
class ImprovementHarness:
    """Harnessing-level ("²") recursion: accumulate APPROVED lessons across tasks.

    Still gated — only approved improvements enter. This is the continual
    improvement harness that makes the agent better on FUTURE tasks.
    """
    lessons: List[str] = field(default_factory=list)
    config: HarnessConfig = field(default_factory=HarnessConfig)

    def adopt(self, proposal: ProposedImprovement) -> bool:
        if not proposal.approved:
            return False      # gate: refuse un-approved edits
        self.config = proposal.winner.edit.config
        self.lessons.append(proposal.lesson)
        return True
