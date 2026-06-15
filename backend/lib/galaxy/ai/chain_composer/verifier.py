"""Deterministic verification of composed chains.

The composer (especially the LLM path) can emit chains that look correct
but reference nonexistent workflows, contain cycles, or have orphan edges.
The verifier catches these without LLM judgment.

Two verifier outputs:
  - errors  — block submission ("workflow X does not exist", "cycle A→B→A")
  - warnings — surface to user but don't block ("typed-port mismatch")

Errors are structured (`VerifierIssue` dataclass) so they can be fed back
to the LLM for revision rather than the raw chain being thrown away.

Scope deliberately narrow: this checks STRUCTURE, not semantics. "Is DESeq2
the right downstream of RNA-seq?" is not a verifier question — that's a
matter of taste/method, decided upstream by the LLM with pattern guidance.
"""

from __future__ import annotations

import os
import sqlite3
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

from .types import ChainEdge, ChainStep, ComposedChain


_DEFAULT_DB = Path(
    os.environ.get(
        "BIOMATE_AI_TOOLS_DB",
        Path(__file__).resolve().parents[4] / "database" / "galaxy_ai_tools.db",
    )
)


@dataclass
class VerifierIssue:
    code: str            # short machine-readable code, e.g. "unknown_workflow"
    message: str         # human-readable
    step_order: Optional[int] = None
    edge: Optional[Dict[str, int]] = None  # {from_step, to_step} for edge issues

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class VerifierReport:
    ok: bool = True
    errors: List[VerifierIssue] = field(default_factory=list)
    warnings: List[VerifierIssue] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "ok": self.ok,
            "errors": [e.to_dict() for e in self.errors],
            "warnings": [w.to_dict() for w in self.warnings],
        }

    def to_llm_feedback(self) -> str:
        """Render for re-feeding to the LLM during revision."""
        if not self.errors and not self.warnings:
            return "Chain verified clean."
        lines = []
        if self.errors:
            lines.append("ERRORS (must fix):")
            for e in self.errors:
                ref = ""
                if e.step_order is not None:
                    ref = f" [step {e.step_order}]"
                elif e.edge is not None:
                    ref = f" [edge {e.edge['from_step']}→{e.edge['to_step']}]"
                lines.append(f"  - {e.code}{ref}: {e.message}")
        if self.warnings:
            lines.append("WARNINGS (consider):")
            for w in self.warnings:
                lines.append(f"  - {w.code}: {w.message}")
        return "\n".join(lines)


def _load_known_workflow_names(db_path: Path) -> Set[str]:
    """All workflow names in the catalog. Used to flag unknown step references."""
    if not db_path.exists():
        return set()
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute("SELECT name FROM workflows WHERE executable=1").fetchall()
    finally:
        conn.close()
    return {r[0] for r in rows if r[0]}


def _load_known_curated_chain_step_names(db_path: Path) -> Set[str]:
    """Step names referenced by curated chains — some are placeholder names
    (e.g. `pharmacophore_filtering`) that don't appear in `workflows` but
    are still valid because the curated chain owns them. Treat these as known.
    """
    if not db_path.exists():
        return set()
    import json
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute("SELECT steps FROM workflow_chains").fetchall()
    finally:
        conn.close()
    names: Set[str] = set()
    for (raw,) in rows:
        try:
            steps = json.loads(raw or "[]")
        except Exception:
            continue
        for s in steps if isinstance(steps, list) else []:
            wn = s.get("workflow_name") if isinstance(s, dict) else None
            if wn:
                names.add(wn)
    return names


def _has_cycle(steps: List[ChainStep], edges: List[ChainEdge]) -> bool:
    """Detect a cycle in the DAG defined by edges over step orders."""
    if not steps or not edges:
        return False
    by_order = {s.order: s for s in steps}
    adj: Dict[int, List[int]] = {o: [] for o in by_order}
    for e in edges:
        if e.from_step in adj:
            adj[e.from_step].append(e.to_step)
    # Iterative DFS with white/gray/black coloring.
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {o: WHITE for o in by_order}
    for start in by_order:
        if color[start] != WHITE:
            continue
        stack: List[Tuple[int, int]] = [(start, 0)]
        color[start] = GRAY
        while stack:
            node, idx = stack[-1]
            nexts = adj.get(node, [])
            if idx >= len(nexts):
                color[node] = BLACK
                stack.pop()
                continue
            stack[-1] = (node, idx + 1)
            nb = nexts[idx]
            if nb not in color:
                continue  # edge to nonexistent step — different error
            if color[nb] == GRAY:
                return True
            if color[nb] == WHITE:
                color[nb] = GRAY
                stack.append((nb, 0))
    return False


def verify_chain(
    composed: ComposedChain,
    *,
    db_path: Optional[Path] = None,
    known_names: Optional[Set[str]] = None,
) -> VerifierReport:
    """Run structural checks on a composed chain.

    Args:
        composed: the chain to check.
        db_path: catalog DB (default `BIOMATE_AI_TOOLS_DB` or repo path).
        known_names: pre-loaded workflow name set. Useful in tests to avoid
            touching the real DB.
    """
    report = VerifierReport()

    db_path = db_path or _DEFAULT_DB
    if known_names is None:
        known_names = _load_known_workflow_names(db_path)
        known_names |= _load_known_curated_chain_step_names(db_path)

    # Empty chain is acceptable (stub path) — caller handled the "no plan" case.
    if not composed.steps:
        return report

    # 1. Step `order` values must be unique and sequential starting at 1.
    orders = [s.order for s in composed.steps]
    if len(set(orders)) != len(orders):
        report.errors.append(VerifierIssue(
            code="duplicate_step_orders",
            message=f"step `order` values must be unique; got {orders}",
        ))
    expected = list(range(1, len(composed.steps) + 1))
    if sorted(orders) != expected:
        report.warnings.append(VerifierIssue(
            code="non_sequential_orders",
            message=f"step orders should be 1..N; got sorted={sorted(orders)} expected={expected}",
        ))

    # 2. Workflow names must exist in catalog (or curated-chain step name pool).
    valid_orders = set(orders)
    if known_names:
        for s in composed.steps:
            if not s.workflow_name or s.workflow_name == "?":
                report.errors.append(VerifierIssue(
                    code="missing_workflow_name",
                    step_order=s.order,
                    message="step has no workflow_name",
                ))
                continue
            if s.workflow_name not in known_names:
                report.errors.append(VerifierIssue(
                    code="unknown_workflow",
                    step_order=s.order,
                    message=f"workflow `{s.workflow_name}` not found in catalog",
                ))
    else:
        # No catalog loaded — degrade to a warning so tests still surface signal.
        report.warnings.append(VerifierIssue(
            code="catalog_unavailable",
            message="workflow catalog not loaded; step-existence check skipped",
        ))

    # 3. Edges reference valid step orders.
    for e in composed.edges:
        if e.from_step not in valid_orders:
            report.errors.append(VerifierIssue(
                code="edge_source_unknown",
                edge={"from_step": e.from_step, "to_step": e.to_step},
                message=f"edge from_step={e.from_step} is not a step order",
            ))
        if e.to_step not in valid_orders:
            report.errors.append(VerifierIssue(
                code="edge_target_unknown",
                edge={"from_step": e.from_step, "to_step": e.to_step},
                message=f"edge to_step={e.to_step} is not a step order",
            ))
        if e.from_step == e.to_step:
            report.errors.append(VerifierIssue(
                code="self_loop_edge",
                edge={"from_step": e.from_step, "to_step": e.to_step},
                message=f"step {e.from_step} cannot edge to itself",
            ))

    # 4. No cycles.
    if _has_cycle(composed.steps, composed.edges):
        report.errors.append(VerifierIssue(
            code="cycle_detected",
            message="chain contains a directed cycle",
        ))

    # 5. Orphan steps (>1 step but no edge touches them).
    if len(composed.steps) > 1 and composed.edges:
        touched: Set[int] = set()
        for e in composed.edges:
            touched.add(e.from_step)
            touched.add(e.to_step)
        for s in composed.steps:
            if s.order not in touched:
                report.warnings.append(VerifierIssue(
                    code="orphan_step",
                    step_order=s.order,
                    message=f"step {s.order} is not connected by any edge",
                ))

    report.ok = not report.errors
    return report
