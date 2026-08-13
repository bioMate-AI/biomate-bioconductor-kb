"""Turn a multi-omics method recommendation into a RUNNABLE BioMate workflow plan.

This is the bridge that makes flexible integration end-to-end: the data-shape-aware
selector (`method_selector.recommend`) chooses *which* integrator suits the user's
arbitrary modality mix; this module maps that choice to the actual Bioconductor
integration subworkflow, builds the universal `omics` parameter list from the user's
modality files, and emits an `/api/nextflow/execute`-ready request.

Deterministic + unit-testable here; the run itself happens on AWS Batch via the
existing `nextflow_executor`. Replaces the old hardcoded-MOFA2 `bioconductor_multiomics`
entry point — the method is now chosen from the data, not fixed.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Union

from .method_selector import Modality, recommend as _recommend

# Subworkflow root — the logical `nextflow_nfcore/…` prefix that the executor's
# `_resolve_nextflow_path` explicitly strips + resolves against the workflow roots
# (this is the exact form the E2E benchmark orchestrator submits and that runs on
# AWS Batch; a `biomni_workflows/…`-prefixed form only resolves when CWD==backend/).
_BIOC = "nextflow_nfcore/subworkflows/bioconductor"

# Canonical method name (exactly as recommend() emits) → runnable subworkflow main.nf.
# These six share the universal `// Input: omics` contract (a list, one matrix/modality).
METHOD_WORKFLOW: Dict[str, str] = {
    "MOFA2":        f"{_BIOC}/mofa2/main.nf",
    "SNF":          f"{_BIOC}/snf_multiomics/main.nf",
    "MCIA":         f"{_BIOC}/mcia_multiomics/main.nf",
    "intNMF":       f"{_BIOC}/intnmf_multiomics/main.nf",
    "iClusterPlus": f"{_BIOC}/iclusterplus_multiomics/main.nf",
    "JIVE":         f"{_BIOC}/jive_multiomics/main.nf",
    # MFA is runnable via the rGCCA base-R subworkflow (the form the orchestrator runs
    # E2E); it uses a DIFFERENT contract (a single concatenated matrix) — flagged below
    # so the caller concatenates first.
    "MFA":          f"{_BIOC}/rgcca_multiomics/main.nf",
}

# Recommended by the selector for some data shapes but not yet packaged as a workflow.
_NOT_YET_RUNNABLE = {"StabMap"}

# Latent-factor methods take `n_factors`; the rest cluster directly with `n_clusters`.
_FACTOR_METHODS = {"MOFA2", "MCIA", "JIVE", "MFA"}
# Method whose input is a single concatenated matrix, not the `omics` list.
_CONCAT_INPUT = {"MFA"}


def plan_integration(
    modalities: List[Union[Modality, Dict[str, Any]]],
    paths: Dict[str, str],
    *,
    goal: Optional[str] = None,
    n_clusters: Optional[int] = None,
    n_factors: int = 10,
    labels_uri: Optional[str] = None,
    outdir: str = "results",
    constraints: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Recommend an integrator for `modalities` and return a runnable plan.

    Args:
      modalities: Modality descriptors (or dicts) — name/data_type/sample_ids/...
      paths:      map of modality name -> file URI (S3/local) for its features×samples matrix.
      goal:       optional 'factors' | 'clustering' | 'subtypes' | 'feature_selection'.
      n_clusters: k for clustering methods (default 2 when the method clusters).
      n_factors:  latent factors for factor methods (default 10).
      labels_uri: optional ground-truth labels file (for evaluation runs).
      outdir:     workflow output directory.

    Returns a dict:
      {method, workflow_path, params, normalization_plan, overlap_type,
       aligned_samples, rationale, alternatives, warnings, runnable, reason}
    """
    mods = [m if isinstance(m, Modality) else Modality(**m) for m in modalities]
    rec = _recommend(mods, goal=goal, constraints=constraints)
    method = rec.get("recommended_method")
    warnings: List[str] = list(rec.get("warnings") or [])

    plan: Dict[str, Any] = {
        "method": method,
        "workflow_path": None,
        "params": {},
        "normalization_plan": rec.get("normalization_plan"),
        "overlap_type": rec.get("overlap_type"),
        "aligned_samples": rec.get("aligned_samples"),
        "rationale": rec.get("rationale"),
        "alternatives": rec.get("alternatives"),
        "warnings": warnings,
        "runnable": False,
        "reason": None,
    }

    # Degenerate: nothing to integrate.
    if method is None:
        plan["reason"] = "no integration method (single or degenerate modality set)"
        return plan

    # Recommended but not yet packaged as a runnable workflow → point at the nearest runnable.
    if method in _NOT_YET_RUNNABLE or method not in METHOD_WORKFLOW:
        runnable_alts = [a for a in (rec.get("alternatives") or []) if a in METHOD_WORKFLOW]
        plan["reason"] = (
            f"{method} best fits this data shape but is not yet packaged as a runnable "
            f"workflow. Nearest runnable alternatives: {runnable_alts or 'none'}."
        )
        plan["warnings"].append(plan["reason"])
        return plan

    # File URIs for every modality are required to build the `omics` list.
    missing = [m.name for m in mods if m.name not in paths]
    if missing:
        raise ValueError(f"no file path provided for modalities: {missing}")
    omics = [paths[m.name] for m in mods]

    params: Dict[str, Any] = {"outdir": outdir}
    if method in _CONCAT_INPUT:
        # MFA expects a single pre-concatenated matrix; surface that to the caller.
        params["omics"] = omics
        plan["warnings"].append(
            "MFA expects a single concatenated features×samples matrix — concatenate the "
            "modalities (or run omics_normalize with concat) before execution."
        )
    else:
        params["omics"] = omics  # universal list contract

    if method in _FACTOR_METHODS:
        params["n_factors"] = int(n_factors)
        if n_clusters is not None:
            params["n_clusters"] = int(n_clusters)  # optional downstream clustering of factors
    else:
        params["n_clusters"] = int(n_clusters) if n_clusters is not None else 2

    if labels_uri:
        params["labels"] = labels_uri

    plan.update(workflow_path=METHOD_WORKFLOW[method], params=params, runnable=True)
    return plan


def to_execute_request(plan: Dict[str, Any]) -> Dict[str, Any]:
    """Shape a runnable plan into the `/api/nextflow/execute` payload
    (`nextflow_executor.NextflowExecuteRequest`)."""
    if not plan.get("runnable"):
        raise ValueError(f"plan is not runnable: {plan.get('reason')}")
    return {"nextflow_path": plan["workflow_path"], "params": dict(plan["params"])}


# The self-contained per-modality normalizer (auto-detects RNA→log2-CPM, methylation→M-value,
# scATAC→TF-IDF, …) that feeds the integration methods. MOFA2 in particular does NOT normalize
# internally, so a correct flexible pipeline normalizes first, then integrates.
OMICS_NORMALIZE_WORKFLOW = f"{_BIOC}/omics_normalize/main.nf"


def plan_pipeline(
    modalities: List[Union[Modality, Dict[str, Any]]],
    paths: Dict[str, str],
    **kwargs: Any,
) -> Dict[str, Any]:
    """The full flexible-integration PIPELINE: normalize each modality, then run the
    data-shape-selected integrator on the normalized matrices.

    Returns:
      {method, runnable, reason, normalization_plan, overlap_type, warnings,
       steps: [ {step, workflow_path, params}, ... ]}
    where the integrate step's `omics` is a placeholder `{"from_step": 0, "output":
    "normalized"}` — the orchestrator runs step 0, collects its `normalized_*.csv`
    outputs, and substitutes them as the integrate step's `omics` list. Falls back to
    a single (integrate-only) step when the chosen method is not runnable.
    """
    base = plan_integration(modalities, paths, **kwargs)
    pipeline: Dict[str, Any] = {
        "method": base.get("method"),
        "runnable": base.get("runnable", False),
        "reason": base.get("reason"),
        "normalization_plan": base.get("normalization_plan"),
        "overlap_type": base.get("overlap_type"),
        "warnings": list(base.get("warnings") or []),
        "steps": [],
    }
    if not base.get("runnable"):
        return pipeline

    raw_omics = base["params"]["omics"]
    outdir = base["params"].get("outdir", "results")

    # omics_normalize names each output `normalized_<view>.csv`, where <view> is the
    # input file's basename stem (main.nf: `.view <- sub("[.][^.]+$", "", basename(.f))`).
    # So step 1's input filenames are DETERMINISTIC now — only step 0's output S3 prefix
    # is a genuine runtime value. Carry the basenames so the orchestrator just prepends it.
    views = [f"normalized_{_stem(p)}.csv" for p in raw_omics]
    dup = {v for v in views if views.count(v) > 1}
    if dup:  # basename collision → normalized_*.csv would overwrite; caller must rename inputs
        pipeline["warnings"].append(
            f"modality files share a basename ({sorted(dup)}); rename them so each "
            "normalized_<name>.csv is unique before running the pipeline."
        )

    normalize_step = {
        "step": "normalize",
        "workflow_path": OMICS_NORMALIZE_WORKFLOW,
        "params": {"omics": list(raw_omics), "outdir": outdir},
    }
    # The integrate step reuses the base params but swaps raw omics → step-0 normalized outputs.
    integrate_params = dict(base["params"])
    integrate_params["omics"] = {"from_step": 0, "output": "normalized", "views": views}
    integrate_step = {
        "step": "integrate",
        "workflow_path": base["workflow_path"],
        "params": integrate_params,
    }
    pipeline["steps"] = [normalize_step, integrate_step]
    return pipeline


def _stem(path: str) -> str:
    """Basename without extension — matches omics_normalize's view-naming rule."""
    base = path.rstrip("/").rsplit("/", 1)[-1]
    return base.rsplit(".", 1)[0] if "." in base else base


def _resolve_step_params(step: Dict[str, Any], step_output_prefixes: List[Any]) -> Dict[str, Any]:
    """Resolve one step's params, substituting any `{from_step, output, views}` omics
    placeholder with concrete `[<prefix>/<view>, ...]` paths from an upstream step."""
    params = dict(step["params"])
    omics = params.get("omics")
    if isinstance(omics, dict) and "from_step" in omics:
        src = omics["from_step"]
        if src >= len(step_output_prefixes) or not step_output_prefixes[src]:
            raise ValueError(f"missing output prefix for upstream step {src}")
        prefix = str(step_output_prefixes[src]).rstrip("/")
        params["omics"] = [f"{prefix}/{v}" for v in omics["views"]]
    return params


def resolve_pipeline(plan: Dict[str, Any], step_output_prefixes: List[str]) -> List[Dict[str, Any]]:
    """Turn a `plan_pipeline` result into concrete `/api/nextflow/execute` payloads.

    `step_output_prefixes[i]` is the S3/local output prefix produced by running step i
    (the executor returns it). Any `{from_step, output, views}` placeholder is resolved to
    `[<prefix>/<view>, ...]`. Step 0 (which has no upstream) is emitted as-is. Call this
    incrementally: run step 0, capture its prefix, then resolve+run step 1.
    """
    if not plan.get("runnable"):
        raise ValueError(f"pipeline is not runnable: {plan.get('reason')}")
    return [
        {"nextflow_path": step["workflow_path"],
         "params": _resolve_step_params(step, step_output_prefixes)}
        for step in plan["steps"]
    ]


def run_pipeline(plan: Dict[str, Any], execute_and_wait) -> List[Dict[str, Any]]:
    """Run a `plan_pipeline` end-to-end, resolving each step's inputs from prior outputs.

    `execute_and_wait(nextflow_path, params) -> output_prefix` is injected by the caller —
    in production it submits to `nextflow_executor`, waits for SUCCEEDED, and returns the
    run's S3 output prefix; in tests it's a fake. This keeps the sequencing logic (resolve
    step i's placeholder from step i-1's real output prefix) fully unit-testable without
    touching AWS Batch. Runs steps strictly in order; raises if any step yields no prefix.

    Returns one record per step: {step, nextflow_path, params, output_prefix}.
    """
    if not plan.get("runnable"):
        raise ValueError(f"pipeline is not runnable: {plan.get('reason')}")
    prefixes: List[Any] = []
    results: List[Dict[str, Any]] = []
    for step in plan["steps"]:
        params = _resolve_step_params(step, prefixes)
        prefix = execute_and_wait(step["workflow_path"], params)
        if not prefix:
            raise ValueError(f"step '{step.get('step')}' produced no output prefix")
        prefixes.append(prefix)
        results.append({
            "step": step.get("step"),
            "nextflow_path": step["workflow_path"],
            "params": params,
            "output_prefix": prefix,
        })
    return results
