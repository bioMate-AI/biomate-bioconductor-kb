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


# Semantic type-compatibility for inter-step handoffs. MIRRORS
# workflow_chain._type_satisfies / _TYPE_ALIASES (the sanctioned matcher used by
# check_step_compatibility) — copied here because workflow_chain is a heavy module
# (FastAPI/beaker) that does not import in the pure/offline contexts this module +
# its test run in. Using EXACT string match here instead was the composer's real
# firing bottleneck: it rejected ~95% of real dependent chains whose resolved
# workflows have equivalent-but-not-identical type tokens (counts_matrix vs counts).
# See docs/20261021_DAG_RESOLUTION_COVERAGE_RESULT.md.
# TODO(dedup): extract to a shared pure module (e.g. galaxy.chain.type_match) and
# point workflow_chain at it, once that edit can be verified in a full Galaxy env.
_TYPE_ALIASES: Dict[str, List[str]] = {
    "bam":             ["bam", "input_bam", "alignments", "reads_bam", "input"],
    "vcf":             ["vcf", "input_vcf", "variants", "variant_file"],
    "fastq":           ["fastq", "reads", "input", "samplesheet"],
    "counts_matrix":   ["counts_matrix", "counts", "matrix", "input", "samplesheet"],
    "tpm_matrix":      ["tpm_matrix", "tpm", "expression_matrix", "counts_matrix"],
    "bed_peaks":       ["bed_peaks", "peaks", "bed", "input"],
    "fasta":           ["fasta", "genome", "reference", "input"],
    "fasta_assembly":  ["fasta_assembly", "fasta", "assembly", "input"],
    "tsv_taxonomy":    ["tsv_taxonomy", "taxonomy", "tsv", "input"],
    "h5ad":            ["h5ad", "anndata", "input"],
    "csv":             ["csv", "samplesheet", "input"],
    "tsv_proteins":    ["tsv_proteins", "protein_groups", "input"],
    "bigwig":          ["bigwig", "signal", "coverage"],
    "multiqc_report":  ["multiqc_report", "qc_report"],
    "results_dir":     ["results_dir", "outdir", "output_dir"],
}


def type_satisfies(out_type: str, in_type: str) -> bool:
    """True iff a step producing ``out_type`` can feed a step consuming ``in_type``
    (semantic, via the alias table) — e.g. ``bam`` satisfies ``input_bam``."""
    if out_type == in_type:
        return True
    aliases = _TYPE_ALIASES.get(out_type, [out_type])
    return any(a == in_type or in_type in a or a in in_type for a in aliases)


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


def to_pipeline_card(dag_plan: Optional[Dict[str, Any]], name: str = "Decomposed plan") -> Optional[Dict[str, Any]]:
    """Render a DAG plan in the frontend's existing pipeline-card shape.

    The chat UI renders a whole-plan chain card when ``workflow.workflow_type ==
    'pipeline'`` and reads ``pipeline_steps`` + ``connections`` + ``max_parallel``
    (chat-message.tsx / chat-with-artifacts.tsx / chain-execution.ts). This maps the
    executor-shaped plan from ``build_dag_plan`` onto that contract WITHOUT changing
    the frontend — the executor fields (``depends_on``, ``connections``,
    ``max_parallel``, ``execution_mode``) are preserved for whole-plan submission.
    """
    if not dag_plan:
        return None
    pipeline_steps = []
    for i, s in enumerate(dag_plan.get("steps", [])):
        pipeline_steps.append({
            "id": s.get("step_key") or "step_%d" % (i + 1),
            "workflow_name": s.get("description") or s.get("nextflow_path"),
            "nextflow_path": s.get("nextflow_path"),
            "params": s.get("parameters") or {},
            "depends_on": s.get("depends_on") or [],
            "output_types": [],
            "status": "pending",
        })
    return {
        "workflow_type": "pipeline",
        "execution_mode": "dag",
        "name": name,
        "pipeline_steps": pipeline_steps,
        "connections": dag_plan.get("connections") or [],
        "max_parallel": dag_plan.get("max_parallel", 4),
    }


# Extension → the most common primary input param name for a Nextflow workflow.
# Used for BEST-EFFORT prefill of a fan-out's shared input onto each root step;
# the whole-plan-approval card lets the user correct it, so this is not
# safety-critical (unlike the typed inter-step connections above).
_DEFAULT_EXT_TO_PARAM = {
    "fastq": "reads", "fq": "reads", "gz": "reads",
    "fa": "genome", "fasta": "genome",
    "bam": "bam", "vcf": "vcf", "bed": "input",
    "csv": "samplesheet", "tsv": "samplesheet", "txt": "input",
    "h5ad": "input", "h5": "input", "rds": "input",
    "sdf": "ligand_file", "smi": "smiles", "pdb": "receptor",
}


def _ref_path(ref: Any) -> str:
    if isinstance(ref, str):
        return ref
    if isinstance(ref, dict):
        return ref.get("path") or ref.get("s3_uri") or ref.get("filename") or ref.get("url") or ""
    return ""


def _ext_of(ref: Any) -> str:
    name = _ref_path(ref)
    return name.rsplit(".", 1)[-1].lower() if "." in name else ""


def bind_shared_inputs(
    plan: Optional[Dict[str, Any]],
    input_refs: Optional[List[Any]],
    ext_to_param: Optional[Dict[str, str]] = None,
) -> Optional[Dict[str, Any]]:
    """Best-effort: bind the user's primary input file onto each ROOT step's primary
    input param (chosen by file extension). This is the fan-out case — N tools over
    the same user input (the motivating screenshot). Never overwrites a param the
    resolver already set, and binds nothing when the extension is unknown (the user
    then fills it in the whole-plan-approval card). Returns the plan unchanged if
    there is no plan or no input. Does not touch dependent steps (they are wired by
    typed connections)."""
    if not plan or not input_refs:
        return plan
    ext_to_param = ext_to_param or _DEFAULT_EXT_TO_PARAM
    primary = input_refs[0]
    path = _ref_path(primary)
    param = ext_to_param.get(_ext_of(primary))
    if not path or not param:
        return plan
    for step in plan.get("steps", []):
        if not step.get("depends_on") and param not in (step.get("parameters") or {}):
            step.setdefault("parameters", {})[param] = path
    return plan


def build_dag_plan(
    tasks: List[Any],
    resolver: Callable[[Any], Optional[Dict[str, Any]]],
    type_provider: Optional[Callable[[str], Any]] = None,
    max_parallel: Optional[int] = None,
) -> Optional[Dict[str, Any]]:
    """Convert decomposed ``tasks`` into a DAG plan, or ``None`` if it cannot be
    assembled executably (caller then falls back to single-task generation).

    ``resolver(task)`` -> ``{"nextflow_path": str, "parameters": dict}`` or None.
    ``type_provider(nextflow_path)`` -> ``(input_types, output_types)`` is used to
    wire the handoff between DEPENDENT steps by type compatibility. Root steps
    (``depends_on == []``, e.g. a fan-out of tools over the same input) need no
    inter-step connection. A dependent step that cannot be type-matched to any of
    its dependencies -- or a dependent plan with no ``type_provider`` -- makes the
    whole function return ``None`` (never a fabricated, fragile handoff).
    """
    if not tasks:
        return None
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

    # Wire dependent-step handoffs by declared-type compatibility (non-fragile:
    # only a real type match produces a connection; otherwise we refuse).
    connections: List[Dict[str, Any]] = []
    bound = set()  # (to_step, to_input) — validate_plan requires one binding per input
    for i, step in enumerate(steps):
        if not step["depends_on"]:
            continue  # root: consumes the user's input, no inter-step connection
        if type_provider is None:
            return None  # dependent plan but no way to verify the handoff → fallback
        dst = i + 1
        dst_in = (type_provider(step["nextflow_path"]) or ([], []))[0] or []
        wired = False
        for src in step["depends_on"]:
            src_out = (type_provider(steps[src - 1]["nextflow_path"]) or ([], []))[1] or []
            # SEMANTIC handoff (type_satisfies), not exact string match: a source output
            # type may be an equivalent-but-different token from the dest input type
            # (counts_matrix→counts). Still refuses a genuinely incompatible handoff.
            for out_t in src_out:
                for in_t in dst_in:
                    if type_satisfies(out_t, in_t) and (dst, in_t) not in bound:
                        connections.append({"from_step": src, "from_output": out_t,
                                             "to_step": dst, "to_input": in_t})
                        bound.add((dst, in_t))
                        wired = True
                        break
                if wired:
                    break
            if wired:
                break
        if not wired:
            return None  # no type-compatible handoff for a dependent step → fallback

    if max_parallel is None:
        max_parallel = sum(1 for s in steps if not s["depends_on"]) or 1
    # dag.validate_plan requires an int in [1, 16] — always clamp.
    max_parallel = max(1, min(16, int(max_parallel)))

    return {"execution_mode": "dag", "steps": steps, "connections": connections, "max_parallel": max_parallel}


def plan_dag_from_tasks(sa: Any, tasks: List[Dict[str, Any]], name: Optional[str] = None,
                        max_parallel: Optional[int] = None) -> Dict[str, Any]:
    """Pure core of /plan_dag (``sa`` supplies _resolve_task_to_workflow / _workflow_io_types)."""
    tasks = [dict(t) for t in tasks]
    # build_dag_plan reads an EMPTY depends_on as "sequential after the previous step" unless
    # the task is marked parallel_with; here [] means an independent branch (a root).
    for t in tasks:
        if not t.get("depends_on"):
            t["parallel_with"] = True
    if len(tasks) < 2:
        return {"success": False, "reason": "fewer_than_two_tasks"}
    resolved, per_task = {}, []
    for i, t in enumerate(tasks):
        r = ({"nextflow_path": t["nextflow_path"], "parameters": {}} if t.get("nextflow_path")
             else sa._resolve_task_to_workflow(t))
        resolved[i] = r
        per_task.append({"task": t.get("id") or f"task_{i + 1}", "description": t.get("description", ""),
                         "nextflow_path": (r or {}).get("nextflow_path"), "resolved": bool(r)})
    if not all(resolved.values()):
        return {"success": False, "reason": "unresolved_task", "tasks": per_task}
    _idx = {id(t): i for i, t in enumerate(tasks)}
    plan = build_dag_plan(tasks, lambda t: resolved.get(_idx.get(id(t))),
                          type_provider=sa._workflow_io_types, max_parallel=max_parallel)
    order_only = False
    if not plan:
        # No typed handoff (catalog type metadata is often generic). The dependency ORDER is still
        # known and chain.dag.validate_plan accepts a dependent step without connections, so keep the
        # plan order-only — no fabricated wiring; every dependency is reported for the user to map.
        plan = _order_only_plan(tasks, resolved, max_parallel)
        order_only = plan is not None
    if not plan:
        return {"success": False, "reason": "no_type_compatible_handoff", "tasks": per_task}
    card = to_pipeline_card(plan, name=(name or "Multi-step analysis plan"))
    for step, t in zip(card.get("pipeline_steps", []), per_task):
        step["description"] = t["description"]
    # A fan-in step depends on several branches but build_dag_plan wires one typed connection per
    # destination input: dependencies with no data connection run in the right order but do not
    # hand their outputs over. Say so (the plan card asks the user to map them) — never imply they do.
    wired = {(c["from_step"], c["to_step"]) for c in plan.get("connections", [])}
    unwired = [{"from_step": d, "to_step": i + 1}
               for i, st in enumerate(plan["steps"]) for d in st.get("depends_on", []) if (d, i + 1) not in wired]
    if unwired:
        card["unwired_dependencies"] = unwired
    if order_only:
        card["order_only"] = True
    return {"success": True, "workflow": card, "tasks": per_task, "unwired_dependencies": unwired,
            "order_only": order_only}


def _order_only_plan(tasks: List[Dict[str, Any]], resolved: Dict[int, Any],
                     max_parallel: Optional[int]) -> Optional[Dict[str, Any]]:
    """Plan with the declared dependency order and no inter-step connections (see caller)."""
    steps = []
    for i, t in enumerate(tasks):
        r = resolved.get(i) or {}
        if not r.get("nextflow_path"):
            return None
        deps = sorted({d for d in (t.get("depends_on") or []) if isinstance(d, int) and 1 <= d <= i})
        steps.append({"step_key": str(t.get("id") or "step_%d" % (i + 1)), "description": t.get("description", ""),
                      "nextflow_path": r["nextflow_path"], "parameters": r.get("parameters") or {},
                      "depends_on": deps})
    if max_parallel is None:
        max_parallel = sum(1 for s in steps if not s["depends_on"]) or 1
    return {"execution_mode": "dag", "steps": steps, "connections": [],
            "max_parallel": max(1, min(16, int(max_parallel)))}
