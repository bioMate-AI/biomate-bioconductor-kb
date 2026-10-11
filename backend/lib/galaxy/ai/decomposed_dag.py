"""Assemble a decomposed task list into an executable DAG plan.

Reconciliation #3 (first slice): stop *discarding* the TaskDecomposer's output
(`ai_assistant.py` used to fall back to single-task generation after decomposing
a request into N tasks — see docs/20261008_DECOMPOSITION_EXECUTION_FLEXIBILITY_AUDIT.md).
This converts those tasks into the DAG plan shape the chain executor already
validates (`galaxy.chain.dag.validate_plan`): a list of steps, each with a
resolved ``nextflow_path`` and 1-based ``depends_on`` (``[]`` for roots), plus a
``max_parallel`` bound.

Design (safe-by-construction):
  * Per-task workflow resolution is INJECTED (``resolver(task) -> {nextflow_path,
    parameters} | None``) so this module is pure + hermetically testable, and so
    the caller controls how a task maps to a real workflow.
  * If ANY task cannot be resolved, the whole function returns ``None`` — the
    caller then falls back to the existing single-task path (never a half-built,
    unexecutable DAG).
  * ``depends_on`` is kept strictly BACKWARD (a step may only depend on earlier
    steps) so the assembled plan is always acyclic and passes validate_plan.

Python 3.9 compatible — no PEP 604 unions.
"""

from __future__ import annotations

from typing import Any, Callable, Dict, List, Optional


def _field(task: Any, key: str, default: Any = None) -> Any:
    if isinstance(task, dict):
        return task.get(key, default)
    return getattr(task, key, default)


# Medium-confidence bar from unified_workflow_search (high >= 12, medium >= 6).
# Below this we refuse to resolve a task so the DAG never dispatches a weak,
# likely-wrong workflow match — it falls back to single-task generation instead.
DAG_RESOLVE_MIN_SCORE = 6.0


def pick_workflow_match(matches: Any, min_score: float = DAG_RESOLVE_MIN_SCORE) -> Optional[Dict[str, Any]]:
    """Choose a CONFIDENT workflow for a task from ranked search matches, or None.

    Pure + testable (accepts WorkflowMatch-like objects or dicts). Returns the top
    match only when it clears ``min_score`` and has a filename; otherwise ``None``
    so build_dag_plan falls back rather than wiring an uncertain workflow.
    """
    if not matches:
        return None
    top = matches[0]
    filename = top.get("filename") if isinstance(top, dict) else getattr(top, "filename", None)
    score = top.get("score", 0) if isinstance(top, dict) else getattr(top, "score", 0)
    if filename and (score or 0) >= min_score:
        return {"nextflow_path": filename, "parameters": {}}
    return None


def build_dag_plan(
    tasks: List[Any],
    resolver: Callable[[Any], Optional[Dict[str, Any]]],
    max_parallel: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    """Convert decomposed ``tasks`` into a DAG plan, or ``None`` if any task is
    unresolvable (caller must then fall back to single-task generation).

    ``resolver(task)`` must return ``{"nextflow_path": str, "parameters": dict}``
    or ``None``. ``depends_on``/``parallel_with`` on a task (if present) are used
    to shape the graph; otherwise steps are sequential.
    """
    if not tasks:
        return None
    n = len(tasks)
    steps: List[Dict[str, Any]] = []
    for i, task in enumerate(tasks):  # i is 0-based; the step is 1-based (i+1)
        resolved = resolver(task)
        if not resolved or not resolved.get("nextflow_path"):
            return None  # unresolvable → no executable DAG → caller falls back

        explicit = _field(task, "depends_on")
        if isinstance(explicit, list) and explicit:
            # keep only valid BACKWARD deps (1-based, strictly earlier) → acyclic
            deps = sorted({d for d in explicit if isinstance(d, int) and 1 <= d <= i})
        elif _field(task, "parallel_with"):
            deps = []  # declared parallel → a root (runs in the first wave)
        else:
            deps = [i] if i > 0 else []  # sequential: depend on the previous step (1-based i)

        steps.append({
            "step_key": str(_field(task, "id") or "step_%d" % (i + 1)),
            "description": _field(task, "description", "") or "",
            "nextflow_path": resolved["nextflow_path"],
            "parameters": resolved.get("parameters") or {},
            "depends_on": deps,
        })

    if max_parallel is None:
        max_parallel = sum(1 for s in steps if not s["depends_on"]) or 1
    # dag.validate_plan requires an int in [1, 16] — always clamp.
    max_parallel = max(1, min(16, int(max_parallel)))

    return {"execution_mode": "dag", "steps": steps, "max_parallel": max_parallel}
