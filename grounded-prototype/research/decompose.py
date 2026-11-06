"""
Decomposition + flow-pattern selection — the HARNESS-owned half of orchestration (Part A).

The live composer's verified failure mode is over-collapsing: an LLM classifier
(`galaxy-assistant.ts::analyzeIntent`) emits single/sequential flags + a LINEAR
`pipeline_steps` list, and regex collapse-overrides push multi-step asks back to
one workflow. The production-grade parallel/DAG engine (`_run_dag_chain` +
`galaxy.chain.dag.run_plan`) is built and API-reachable but never fired from chat,
because chat never emits a `depends_on` plan. So the gap is NOT a missing engine —
it is that nothing decides "these sub-tasks are independent, run them in parallel"
and emits the branching plan the engine already consumes.

This module is that missing decider, as a deterministic harness step:
  * the LLM (injected) PROPOSES sub-tasks (+ optional produces/consumes I/O tokens);
  * the HARNESS infers dependency EDGES deterministically (a node depends on an
    earlier node whose outputs it consumes) — defaulting to PARALLEL when no data
    handoff is evident, which is the exact correction the live over-collapse needs;
  * the HARNESS validates the plan (acyclic, orders resolvable, no dangling edge)
    before the DAG engine ever runs.

The emitted plan is EXACTLY the benchmark's shape — a list of
`{"sub_task", "order", "depends_on": [orders]}` — so it scores directly against
`evaluation/datasets/decomposition_v2/score.py` (mirrored as
`research.verifiers.StructureVerifier`) and drops into `galaxy.chain.dag.run_plan`.

Division of labour mirrors the deep-research controller (research/controller.py):
LLM judgment proposes, harness owns the deterministic structure + invariants.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Sequence

# Flow patterns across which orchestration must choose. The first three map onto
# the decomposition benchmark's structure classes (parallel/sequential/mixed);
# SINGLE and ITERATIVE_QC are live-composer decisions outside that benchmark's
# label set (a single workflow; a QC remediation loop) but share this selector.
SINGLE = "single"
PARALLEL = "parallel"
SEQUENTIAL = "sequential"
MIXED = "mixed"
ITERATIVE_QC = "iterative_qc"

# Cues that a goal wants a QC/remediation LOOP rather than a straight-line DAG.
_QC_CUES = ("qc gate", "remediate", "auto-loop", "until it passes", "iterate until",
            "re-run until", "threshold", "pass the gate")


@dataclass
class SubTask:
    """One proposed sub-task. `produces`/`consumes` are I/O tokens (e.g. file
    kinds or artefact names) the LLM may attach; when present the harness infers
    edges from them. `order` is a stable 1-based id used for depends_on."""
    sub_task: str
    order: int
    produces: List[str] = field(default_factory=list)
    consumes: List[str] = field(default_factory=list)


def _norm(tokens: Sequence[str]) -> set:
    return {str(t).strip().lower() for t in tokens if str(t).strip()}


def infer_edges(subtasks: List[SubTask]) -> Dict[int, List[int]]:
    """Deterministic dependency inference: a node depends on EVERY earlier node
    whose `produces` intersects this node's `consumes`. No handoff -> no edge
    (parallel). Only earlier orders can be depended on, so the result is acyclic
    by construction. Returns {order: [dep orders]}."""
    deps: Dict[int, List[int]] = {}
    ordered = sorted(subtasks, key=lambda s: s.order)
    for i, node in enumerate(ordered):
        consumes = _norm(node.consumes)
        node_deps: List[int] = []
        if consumes:
            for earlier in ordered[:i]:
                if consumes & _norm(earlier.produces):
                    node_deps.append(earlier.order)
        deps[node.order] = node_deps
    return deps


def build_plan(
    subtasks: List[SubTask],
    *,
    depends_fn: Optional[Callable[[List[SubTask]], Dict[int, List[int]]]] = None,
) -> List[Dict]:
    """Assemble the benchmark/engine plan shape from proposed sub-tasks.

    `depends_fn` is the injectable override (an LLM that judges handoff from prose
    when I/O tokens are absent); it must also return only backward edges. The
    default is the deterministic I/O-token inference. The plan is validated before
    return — a cyclic or dangling plan raises rather than reaching the DAG engine.
    """
    edges = (depends_fn or infer_edges)(subtasks)
    plan = [
        {"sub_task": s.sub_task, "order": s.order,
         "depends_on": sorted(edges.get(s.order, []))}
        for s in sorted(subtasks, key=lambda s: s.order)
    ]
    validate_plan(plan)
    return plan


def validate_plan(plan: List[Dict]) -> None:
    """Deterministic guardrails the DAG engine assumes: every depends_on refers to
    a real order, and the graph is acyclic. Raises ValueError on violation."""
    orders = {s["order"] for s in plan}
    for s in plan:
        for d in s.get("depends_on", []) or []:
            if d not in orders:
                raise ValueError(f"node {s['order']} depends on unknown order {d}")
            if d == s["order"]:
                raise ValueError(f"node {s['order']} depends on itself")
    # cycle check via DFS over the order graph
    graph = {s["order"]: list(s.get("depends_on", []) or []) for s in plan}
    WHITE, GREY, BLACK = 0, 1, 2
    color = {o: WHITE for o in graph}

    def visit(o: int) -> None:
        color[o] = GREY
        for d in graph[o]:
            if color[d] == GREY:
                raise ValueError(f"dependency cycle through order {o} -> {d}")
            if color[d] == WHITE:
                visit(d)
        color[o] = BLACK

    for o in graph:
        if color[o] == WHITE:
            visit(o)


def structure_of(plan: List[Dict]) -> str:
    """The benchmark's structure classes (mirrors decomposition_v2/score.py
    `_structure_of`): empty / parallel (no deps) / sequential (every non-first
    node has a dep) / mixed."""
    deps = [len(s.get("depends_on", []) or []) for s in plan if isinstance(s, dict)]
    if not deps:
        return "empty"
    if all(d == 0 for d in deps):
        return "parallel"
    if all(d > 0 for d in deps[1:]):
        return "sequential"
    return "mixed"


def select_pattern(goal: str, plan: List[Dict]) -> str:
    """Pick the flow pattern for the whole goal. A QC/remediation loop in the goal
    text wins (ITERATIVE_QC); a single-node plan is SINGLE; otherwise the plan's
    own topology decides (this is where the harness recovers PARALLEL that the
    live composer collapses away). Deterministic and LLM-independent — the LLM
    proposed the sub-tasks; the pattern is a property of the resulting graph."""
    g = (goal or "").lower()
    if any(cue in g for cue in _QC_CUES):
        return ITERATIVE_QC
    if len(plan) <= 1:
        return SINGLE
    return structure_of(plan)  # parallel / sequential / mixed
