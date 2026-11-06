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
    n_eval_tasks: int = 1
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


def _signature(cfg: HarnessConfig) -> tuple:
    """Dedup key for a candidate config (budget knobs + routing table)."""
    b = cfg.budget
    return (b.max_rounds, b.max_breadth, b.max_parallel, b.max_evidence,
            b.max_sources_per_subq,
            tuple(sorted((k, tuple(v)) for k, v in cfg.kinds_override.items())))


def _evaluate(cfg: HarnessConfig, tasks: List[str], run_one: Callable):
    """Score a config across a task set. Returns (mean, per_task, errors).
    An 'error' = the run raised OR produced no grounded claims (degenerate) — the
    continuous-score analogue of ScienceBuddy selection.py's runtime-error count."""
    per_task: Dict[str, Optional[float]] = {}
    scores: List[float] = []
    errors = 0
    for t in tasks:
        try:
            res = run_one(t, cfg)
            grounded = [c for c in res.answer.claims if c.is_grounded]
            sc, _ = harness_score(res)
            if not grounded:
                errors += 1
        except Exception:
            errors += 1
            sc = None
        per_task[t] = sc
        if sc is not None:
            scores.append(sc)
    mean = sum(scores) / len(scores) if scores else float("-inf")
    return mean, per_task, errors


def propose_probe_compose(
    task: str,
    base: HarnessConfig,
    *,
    retrieve_fn: Callable,
    decompose_fn: Optional[Callable] = None,
    assess_fn: Optional[Callable] = None,
    propose_fn: Optional[Callable[[str, HarnessConfig], List[CandidateEdit]]] = None,
    val_tasks: Optional[List[str]] = None,
    require_no_regression: bool = True,
    regression_tol: float = 1e-9,
) -> ProposedImprovement:
    """One Harness2 task-level step with ScienceBuddy-style selection discipline:
    PROPOSE edits, PROBE them on a HELD-OUT task set, COMPOSE the winner only if it has
    ZERO errors, STRICTLY beats the parent's mean, and (by default) regresses on NO
    held-out task. PROPOSED only — needs .approve().

    `val_tasks` is the held-out evaluation set (ScienceBuddy's D_val); omitted, the
    triggering `task` is used (cheap single-task check, backward compatible). Candidates
    are deduped and all scored before selection; nothing is adopted unless it is a
    strict, regression-free, error-free improvement — otherwise the PARENT is kept.
    """
    eval_tasks = list(val_tasks) if val_tasks else [task]

    def run_one(t: str, cfg: HarnessConfig) -> ResearchResult:
        return research(t, "harness-eval", retrieve_fn=retrieve_fn,
                        decompose_fn=decompose_fn, assess_fn=assess_fn,
                        budget=cfg.budget, kinds_override=cfg.kinds_override)

    base_mean, base_per, _ = _evaluate(base, eval_tasks, run_one)
    candidates = (propose_fn or _default_propose)(task, base)

    # Generate + score every candidate (deduped) BEFORE revealing a selection.
    probes: List[ProbeResult] = []
    seen = {_signature(base)}
    for ed in candidates:
        sig = _signature(ed.config)
        if sig in seen:
            continue
        seen.add(sig)
        mean, per, errors = _evaluate(ed.config, eval_tasks, run_one)
        min_delta = min((per[t] - base_per[t] for t in eval_tasks
                         if per[t] is not None and base_per[t] is not None), default=0.0)
        probes.append(ProbeResult(ed, mean, {
            "mean_score": mean, "errors": float(errors), "min_delta_vs_base": min_delta,
        }))

    def _eligible(p: ProbeResult) -> bool:
        return (p.metrics["errors"] == 0
                and p.score > base_mean + regression_tol
                and not (require_no_regression and p.metrics["min_delta_vs_base"] < -regression_tol))

    winners = [p for p in probes if _eligible(p)]
    if winners:
        winner = max(winners, key=lambda p: p.score)
        improved = True
        lesson = (f"intent '{router.detect_intent(task)}': '{winner.edit.description}' "
                  f"strictly improved the held-out mean {base_mean:.1f} -> {winner.score:.1f} "
                  f"over {len(eval_tasks)} task(s), no regression")
    else:
        # No strict, regression-free improvement — KEEP THE PARENT (selection.py rule).
        base_edit = CandidateEdit("base", "keep parent harness", base)
        winner = ProbeResult(base_edit, base_mean, {"mean_score": base_mean, "errors": 0.0})
        improved = False
        lesson = (f"no proposed edit strictly improved the held-out mean without regression "
                  f"(parent {base_mean:.1f} over {len(eval_tasks)} task(s)) — kept parent")

    return ProposedImprovement(task, base_mean, winner, probes, lesson, improved,
                               n_eval_tasks=len(eval_tasks))


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
