"""Nominate -> validate bridge: turn ranked targets into launchable BioMate validation workflows.

This is the EXECUTION/INTEGRATION value (the honest product, not a baseline-beating model): a user goes
disease -> provenance-backed OpenTargets-ranked targets (orchestrator) -> for each top target, the
concrete BioMate workflows that would VALIDATE it (druggability/tractability, differential expression,
structure+docking, perturbation phenotype) -> launch them on the real engine.

Design (matches the module's standalone-importable contract): ``search_fn`` is INJECTABLE (like the
channels' ``http``), defaulting lazily to galaxy's UnifiedWorkflowSearch when available — so this is unit-
testable offline with a mock catalog and never hard-couples target_id to the rest of galaxy. 3.9-safe.
"""
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

# (intent_key, query template) — the standard validation battery for a nominated target. Templates are
# gene-parametrised NL queries fed to the workflow catalog search; edit here to tune the battery.
VALIDATION_INTENTS: List[Tuple[str, str]] = [
    ("druggability", "{gene} druggability tractability small-molecule binding pocket assessment"),
    ("expression", "{gene} differential expression RNA-seq disease vs control"),
    ("structure_docking", "{gene} protein structure prediction and ligand docking"),
    ("perturbation", "{gene} CRISPR knockout perturbation phenotype screen"),
]


def _match_to_dict(m: Any) -> Dict[str, Any]:
    """WorkflowMatch (or a dict) -> a compact launchable spec."""
    g = (lambda k, d=None: getattr(m, k, d) if not isinstance(m, dict) else m.get(k, d))
    return {"id": g("id"), "name": g("name"), "domain": g("domain"), "source": g("source"),
            "format": g("format"), "filename": g("filename"), "score": g("score"),
            "match_type": g("match_type")}


def _default_search() -> Callable[[str, int], List[Dict[str, Any]]]:
    """Lazy galaxy UnifiedWorkflowSearch wrapper -> search_fn(query, limit)->[launchable spec]."""
    from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch
    u = UnifiedWorkflowSearch()

    def search_fn(query: str, limit: int = 3) -> List[Dict[str, Any]]:
        return [_match_to_dict(m) for m in u.search(query, limit=limit)]

    return search_fn


def _sym(ts: Any) -> Optional[str]:
    if hasattr(ts, "target"):
        return ts.target
    if isinstance(ts, dict):
        return ts.get("target")
    return str(ts) if ts is not None else None


def _tier(ts: Any) -> Optional[str]:
    if hasattr(ts, "tier"):
        return ts.tier
    if isinstance(ts, dict):
        return ts.get("tier")
    return None


def validation_plan(targets: Sequence[Any], top_n: int = 5, per_intent: int = 2,
                    search_fn: Optional[Callable[[str, int], List[Dict[str, Any]]]] = None,
                    intents: Optional[Sequence[Tuple[str, str]]] = None) -> Dict[str, Any]:
    """For the top-N nominated targets, return the BioMate workflows that would validate each.

    targets: ranked TargetScore list (or dicts/symbols). search_fn(query, limit)->[workflow spec] is
    injectable (defaults to UnifiedWorkflowSearch). Returns {target: {rank, tier, validation:{intent:[wf]}}}.
    Fail-soft per query (a catalog miss yields [], never raises)."""
    intents = list(intents or VALIDATION_INTENTS)
    if search_fn is None:
        search_fn = _default_search()
    plan: Dict[str, Any] = {}
    for i, ts in enumerate(list(targets)[:top_n]):
        sym = _sym(ts)
        if not sym:
            continue
        per: Dict[str, Any] = {}
        for key, tmpl in intents:
            try:
                per[key] = search_fn(tmpl.format(gene=sym), per_intent) or []
            except Exception as e:  # defence in depth; search_fn should fail soft
                per[key] = {"error": "%s: %s" % (type(e).__name__, e)}
        plan[sym] = {"rank": i + 1, "tier": _tier(ts), "validation": per}
    return plan


def nominate_and_validate(orchestrator: Any, query: str, context: Optional[Dict[str, Any]] = None,
                          top_n: int = 5, per_intent: int = 2,
                          search_fn: Optional[Callable[[str, int], List[Dict[str, Any]]]] = None) -> Dict[str, Any]:
    """End-to-end: orchestrator.identify(query) -> validation_plan for the top targets.

    Returns {query, targets: OrchestratorResult, validation_plan: {...}}. This is the product loop:
    nominate (OpenTargets-primary, provenance-backed) THEN validate (launchable workflows per target)."""
    res = orchestrator.identify(query, context)
    plan = validation_plan(res.targets, top_n=top_n, per_intent=per_intent, search_fn=search_fn)
    return {"query": query, "targets": res, "validation_plan": plan,
            "note": "OpenTargets-primary nomination + per-target BioMate validation workflows (launchable)."}
