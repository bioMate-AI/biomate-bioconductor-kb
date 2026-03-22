"""
Sequential Workflow Chain API

Executes N Nextflow workflows in order, auto-wiring each step's output
as the next step's input parameters.

Auto-discovered by FastAPI via include_all_package_routers().

Routes:
  POST /api/workflows/chain                          — submit chain
  GET  /api/workflows/chain/{chain_run_id}           — poll status
  POST /api/workflows/runs/{run_id}/resolve-outputs  — output-as-input resolver
"""

import json
import logging
import os
import sqlite3
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from fastapi import HTTPException
from pydantic import BaseModel

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["workflow-chain"])

# ---------------------------------------------------------------------------
# Persistent storage helpers
# ---------------------------------------------------------------------------

_CHAINS_DIR = Path(os.environ.get(
    "BIOMATE_CHAINS_DIR",
    "/home/yzhang/biomate/backend/database/ai_workflow_ops/chains"
))


def _chains_dir() -> Path:
    _CHAINS_DIR.mkdir(parents=True, exist_ok=True)
    return _CHAINS_DIR


def _chain_path(chain_run_id: str) -> Path:
    return _chains_dir() / f"{chain_run_id}.json"


def _load_chain(chain_run_id: str) -> Optional[Dict[str, Any]]:
    p = _chain_path(chain_run_id)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except Exception as exc:
        log.warning("workflow_chain: failed to read %s: %s", p, exc)
        return None


def _save_chain(state: Dict[str, Any]) -> None:
    p = _chain_path(state["chain_run_id"])
    try:
        p.write_text(json.dumps(state, indent=2, default=str))
    except Exception as exc:
        log.warning("workflow_chain: failed to persist %s: %s", p, exc)


# ---------------------------------------------------------------------------
# In-memory registry (authoritative while process is alive; disk is durable)
# ---------------------------------------------------------------------------

_chains: Dict[str, Dict[str, Any]] = {}
_chains_lock = threading.Lock()


def _get_chain(chain_run_id: str) -> Optional[Dict[str, Any]]:
    with _chains_lock:
        if chain_run_id in _chains:
            return dict(_chains[chain_run_id])
    return _load_chain(chain_run_id)


def _update_chain(state: Dict[str, Any]) -> None:
    with _chains_lock:
        _chains[state["chain_run_id"]] = state
    _save_chain(state)


# ---------------------------------------------------------------------------
# Output-as-input resolver
# ---------------------------------------------------------------------------

# Extension → common parameter names for Nextflow workflows
_EXT_TO_PARAM: Dict[str, List[str]] = {
    "fastq": ["reads", "input", "fastq", "fastq_input"],
    "fq": ["reads", "input", "fastq"],
    "gz": ["reads", "input"],
    "fa": ["genome", "fasta", "reference", "input"],
    "fasta": ["genome", "fasta", "reference", "input"],
    "bam": ["bam", "input_bam", "alignments", "input"],
    "bai": ["bai", "bam_index"],
    "vcf": ["vcf", "variants", "input_vcf"],
    "tsv": ["tsv", "samplesheet", "input"],
    "csv": ["csv", "samplesheet", "input"],
    "txt": ["input"],
    "json": ["params_json", "input"],
}


def _resolve_outputs_for_run(run_id: str, next_workflow_input_types: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """
    Given a completed run_id, attempt to match its output files to the next
    workflow's expected input parameter names.

    next_workflow_input_types: optional {param_name: expected_type_hint}
    Returns {resolved_params: {...}, warnings: [...]}
    """
    from galaxy.webapps.galaxy.api.nextflow_executor import _runs, _runs_lock  # noqa: PLC0415

    resolved: Dict[str, Any] = {}
    warnings: List[str] = []

    with _runs_lock:
        run_info = dict(_runs.get(run_id, {}))

    if not run_info:
        # Fallback: try disk
        run_dir = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs")) / run_id
        if not run_dir.exists():
            warnings.append(f"Run {run_id} not found in memory or on disk")
            return {"resolved_params": resolved, "warnings": warnings}
        # Build minimal run_info from disk
        run_info = {"outdir": str(run_dir), "status": "unknown"}

    outdir = run_info.get("outdir", "")
    s3_files = run_info.get("s3_output_files", [])

    # Prefer S3 files if available
    if s3_files:
        for file_info in s3_files:
            ext = file_info.get("extension", "").lower()
            s3_uri = file_info.get("s3_uri", "")
            param_candidates = _EXT_TO_PARAM.get(ext, [])
            for param in param_candidates:
                if param not in resolved:
                    if next_workflow_input_types:
                        if param in next_workflow_input_types:
                            resolved[param] = s3_uri
                            break
                    else:
                        resolved[param] = s3_uri
                        break
    elif outdir and Path(outdir).exists():
        # Walk local output directory
        out_path = Path(outdir)
        for fpath in sorted(out_path.rglob("*")):
            if not fpath.is_file():
                continue
            # Skip Nextflow internals
            parts_str = str(fpath)
            if any(skip in parts_str for skip in ["/work/", "/.nextflow/", "/trace.", "/timeline.", "/dag.", "/report."]):
                continue
            ext = fpath.suffix.lstrip(".").lower()
            param_candidates = _EXT_TO_PARAM.get(ext, [])
            for param in param_candidates:
                if param not in resolved:
                    if next_workflow_input_types:
                        if param in next_workflow_input_types:
                            resolved[param] = str(fpath)
                            break
                    else:
                        resolved[param] = str(fpath)
                        break
    else:
        warnings.append(f"No output files found for run {run_id}")

    if not resolved:
        warnings.append("Could not auto-resolve any outputs to input parameters")

    return {"resolved_params": resolved, "warnings": warnings}


# ---------------------------------------------------------------------------
# Chain executor (background thread)
# ---------------------------------------------------------------------------

def _run_chain(chain_run_id: str) -> None:
    """Execute chain steps sequentially in a background thread."""
    state = _get_chain(chain_run_id)
    if state is None:
        log.error("workflow_chain: chain %s not found", chain_run_id)
        return

    steps = state["steps"]
    log.info("workflow_chain: starting chain %s with %d steps", chain_run_id, len(steps))

    for idx, step in enumerate(steps):
        # Re-load state (may have been updated externally)
        current = _get_chain(chain_run_id) or state

        if current.get("status") == "cancelled":
            log.info("workflow_chain: chain %s cancelled before step %d", chain_run_id, idx)
            return

        # Mark step as running
        current["steps"][idx]["status"] = "running"
        current["steps"][idx]["started_at"] = datetime.now(timezone.utc).isoformat()
        current["status"] = "running"
        _update_chain(current)

        nextflow_path = step["nextflow_path"]
        params = dict(step.get("params", {}))

        # Auto-wire previous step's outputs as inputs (skip for first step)
        if idx > 0:
            prev_step = current["steps"][idx - 1]
            prev_run_id = prev_step.get("run_id")

            # Pre-flight type compatibility check using DB types
            prev_name = prev_step.get("nextflow_path", "")
            next_name = step.get("nextflow_path", "")
            prev_out_types = prev_step.get("output_types", [])
            next_in_types, next_out_types = _get_workflow_types(next_name)
            step["input_types"] = next_in_types
            step["output_types"] = next_out_types

            if not prev_out_types:
                _, prev_out_types = _get_workflow_types(prev_name)
                prev_step["output_types"] = prev_out_types

            compat = check_step_compatibility(prev_out_types, next_in_types, prev_name, next_name)
            if not compat["compatible"]:
                log.warning(
                    "workflow_chain: type incompatibility at step %d→%d: %s",
                    idx - 1, idx, compat["warnings"]
                )
                current["steps"][idx]["compatibility_warnings"] = compat["warnings"]
                current["steps"][idx]["compatibility_suggestions"] = compat["suggestions"]
                _update_chain(current)

            if prev_run_id:
                try:
                    # Use DB input_types to guide file resolution
                    next_input_type_map = {t: t for t in next_in_types} if next_in_types else None
                    resolution = _resolve_outputs_for_run(prev_run_id, next_input_type_map)
                    auto_params = resolution.get("resolved_params", {})
                    # Only fill params that aren't already explicitly set
                    for k, v in auto_params.items():
                        if k not in params:
                            params[k] = v
                    if auto_params:
                        log.info(
                            "workflow_chain: step %d auto-wired params from run %s: %s",
                            idx, prev_run_id, list(auto_params.keys())
                        )
                except Exception as exc:
                    log.warning("workflow_chain: output resolution failed for step %d: %s", idx, exc)
        else:
            # First step: populate type info from DB
            next_in_types, next_out_types = _get_workflow_types(step.get("nextflow_path", ""))
            current["steps"][idx]["input_types"] = next_in_types
            current["steps"][idx]["output_types"] = next_out_types
            _update_chain(current)

        # Launch Nextflow via the existing executor
        try:
            from galaxy.webapps.galaxy.api.nextflow_executor import (  # noqa: PLC0415
                NextflowExecuteRequest,
                execute_nextflow,
            )
            req = NextflowExecuteRequest(
                nextflow_path=nextflow_path,
                parameters=params,
            )
            result = execute_nextflow(req)
            run_id = result.get("run_id")
        except Exception as exc:
            log.error("workflow_chain: step %d failed to launch: %s", idx, exc)
            current = _get_chain(chain_run_id) or state
            current["steps"][idx]["status"] = "failed"
            current["steps"][idx]["error"] = str(exc)
            current["steps"][idx]["completed_at"] = datetime.now(timezone.utc).isoformat()
            current["status"] = "failed"
            _update_chain(current)
            return

        # Store run_id in state
        current = _get_chain(chain_run_id) or state
        current["steps"][idx]["run_id"] = run_id
        _update_chain(current)

        # Poll until complete
        log.info("workflow_chain: step %d launched as run_id=%s, polling...", idx, run_id)
        _poll_run_until_done(chain_run_id, idx, run_id)

        # Check if this step failed
        current = _get_chain(chain_run_id) or state
        step_status = current["steps"][idx].get("status", "unknown")
        if step_status != "succeeded":
            current["status"] = "failed"
            _update_chain(current)
            log.error("workflow_chain: chain %s failed at step %d (run_id=%s)", chain_run_id, idx, run_id)
            return

    # All steps succeeded
    current = _get_chain(chain_run_id) or state
    current["status"] = "succeeded"
    current["completed_at"] = datetime.now(timezone.utc).isoformat()
    _update_chain(current)
    log.info("workflow_chain: chain %s completed successfully", chain_run_id)


def _poll_run_until_done(chain_run_id: str, step_idx: int, run_id: str, poll_interval: float = 5.0, timeout: float = 3600.0) -> None:
    """Poll a Nextflow run until it finishes, updating chain state accordingly."""
    from galaxy.webapps.galaxy.api.nextflow_executor import _runs, _runs_lock  # noqa: PLC0415

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        with _runs_lock:
            run_info = dict(_runs.get(run_id, {}))

        status = run_info.get("status", "running")
        if status in ("succeeded", "failed", "cancelled"):
            current = _get_chain(chain_run_id)
            if current:
                current["steps"][step_idx]["status"] = status
                current["steps"][step_idx]["completed_at"] = datetime.now(timezone.utc).isoformat()
                _update_chain(current)
            log.info("workflow_chain: run %s finished with status=%s", run_id, status)
            return

        time.sleep(poll_interval)

    # Timeout
    current = _get_chain(chain_run_id)
    if current:
        current["steps"][step_idx]["status"] = "failed"
        current["steps"][step_idx]["error"] = "Polling timeout exceeded"
        current["steps"][step_idx]["completed_at"] = datetime.now(timezone.utc).isoformat()
        _update_chain(current)
    log.warning("workflow_chain: run %s timed out after %.0fs", run_id, timeout)


# ---------------------------------------------------------------------------
# DB type lookup helpers
# ---------------------------------------------------------------------------

_DB_PATH = Path(os.environ.get("GALAXY_AI_DB", "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"))

# Semantic aliases: output type → list of input type strings it satisfies
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


def _type_satisfies(out_type: str, in_type: str) -> bool:
    if out_type == in_type:
        return True
    aliases = _TYPE_ALIASES.get(out_type, [out_type])
    return any(a == in_type or in_type in a or a in in_type for a in aliases)


def _get_workflow_types(workflow_name_or_path: str) -> Tuple[List[str], List[str]]:
    """Look up input_types and output_types for a workflow by name or filename."""
    try:
        conn = sqlite3.connect(str(_DB_PATH))
        row = conn.execute(
            "SELECT input_types, output_types FROM workflows "
            "WHERE name=? OR filename LIKE ? LIMIT 1",
            (workflow_name_or_path, f"%{workflow_name_or_path.split('/')[-1]}%"),
        ).fetchone()
        conn.close()
        if row:
            inp = json.loads(row[0] or "[]")
            out = json.loads(row[1] or "[]")
            return inp, out
    except Exception as exc:
        log.debug("workflow_chain: DB type lookup failed for %s: %s", workflow_name_or_path, exc)
    return [], []


def check_step_compatibility(
    prev_output_types: List[str],
    next_input_types: List[str],
    prev_name: str = "",
    next_name: str = "",
) -> Dict[str, Any]:
    """
    Return {compatible, warnings, suggestions} for a step transition.
    Uses semantic type matching so "bam" satisfies "input_bam", etc.
    """
    if not next_input_types or not prev_output_types:
        return {"compatible": True, "warnings": [], "suggestions": []}

    unmatched = [
        in_t for in_t in next_input_types
        if not any(_type_satisfies(out_t, in_t) for out_t in prev_output_types)
    ]
    if not unmatched:
        return {"compatible": True, "warnings": [], "suggestions": []}

    warnings = [
        f"{prev_name or 'Previous step'} produces [{', '.join(prev_output_types)}] "
        f"but {next_name or 'next step'} requires [{', '.join(unmatched)}]."
    ]
    suggestions = [
        "Consider adding an intermediate format-conversion step, or confirm that "
        f"the output directory from {prev_name} contains the required files."
    ]
    return {"compatible": False, "warnings": warnings, "suggestions": suggestions}


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class ChainStep(BaseModel):
    nextflow_path: str
    params: Optional[Dict[str, Any]] = None


class ChainSubmitRequest(BaseModel):
    chain_run_id: Optional[str] = None
    steps: List[ChainStep]


class ResolveOutputsRequest(BaseModel):
    next_workflow_path: Optional[str] = None
    next_workflow_input_types: Optional[Dict[str, str]] = None


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/api/workflows/chain", summary="Submit a sequential Nextflow workflow chain")
async def submit_chain(request: ChainSubmitRequest) -> Dict[str, Any]:
    """
    Accept a list of Nextflow workflow steps and execute them sequentially.
    Each step's outputs are automatically wired as the next step's inputs.
    Returns immediately with chain_run_id and status="running".
    """
    import math  # noqa: PLC0415

    if not request.steps:
        raise HTTPException(status_code=400, detail="steps array required")

    chain_run_id = request.chain_run_id or f"chain_{int(time.time())}_{os.urandom(3).hex()}"

    steps_state = [
        {
            "index": i,
            "nextflow_path": step.nextflow_path,
            "params": step.params or {},
            "status": "pending",
            "run_id": None,
            "started_at": None,
            "completed_at": None,
        }
        for i, step in enumerate(request.steps)
    ]

    state: Dict[str, Any] = {
        "chain_run_id": chain_run_id,
        "status": "running",
        "steps": steps_state,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "completed_at": None,
    }
    _update_chain(state)

    # Launch background thread
    t = threading.Thread(target=_run_chain, args=(chain_run_id,), daemon=True, name=f"chain-{chain_run_id[:12]}")
    t.start()

    return {"chain_run_id": chain_run_id, "status": "running", "steps": steps_state}


@router.get("/api/workflows/chain/{chain_run_id}", summary="Poll chain execution status")
async def get_chain_status(chain_run_id: str) -> Dict[str, Any]:
    """Return the current status of a sequential workflow chain."""
    state = _get_chain(chain_run_id)
    if state is None:
        raise HTTPException(status_code=404, detail=f"Chain {chain_run_id!r} not found")
    return state


@router.post("/api/workflows/runs/{run_id}/resolve-outputs", summary="Resolve run outputs as next-step inputs")
async def resolve_outputs(run_id: str, request: ResolveOutputsRequest) -> Dict[str, Any]:
    """
    Given a completed Nextflow run_id, scan its output directory (local or S3)
    and map output files to suggested input parameter names for the next workflow.
    """
    result = _resolve_outputs_for_run(run_id, request.next_workflow_input_types)
    return result


class TypeCompatibilityRequest(BaseModel):
    steps: List[str]  # list of workflow names or nextflow paths in order


@router.post("/api/workflows/type-compatibility", summary="Pre-flight type compatibility check for a pipeline chain")
async def check_chain_type_compatibility(request: TypeCompatibilityRequest) -> Dict[str, Any]:
    """
    Given an ordered list of workflow names/paths, check whether each step's
    output types are compatible with the next step's input types.

    Returns per-step type info and any compatibility warnings, so the UI can
    surface issues before the chain is launched.
    """
    if len(request.steps) < 2:
        return {"compatible": True, "steps": [], "warnings": []}

    step_info = []
    all_warnings: List[str] = []
    all_suggestions: List[str] = []

    for i, wf_name in enumerate(request.steps):
        in_types, out_types = _get_workflow_types(wf_name)
        step_info.append({
            "index": i,
            "workflow": wf_name,
            "input_types": in_types,
            "output_types": out_types,
            "compatibility_warnings": [],
        })

        if i > 0:
            prev = step_info[i - 1]
            compat = check_step_compatibility(
                prev["output_types"], in_types,
                prev["workflow"], wf_name,
            )
            if not compat["compatible"]:
                step_info[i]["compatibility_warnings"] = compat["warnings"]
                all_warnings.extend(compat["warnings"])
                all_suggestions.extend(compat["suggestions"])

    return {
        "compatible": len(all_warnings) == 0,
        "steps": step_info,
        "warnings": all_warnings,
        "suggestions": all_suggestions,
    }


@router.get("/api/workflows/{workflow_name:path}/types", summary="Get input/output types for a workflow")
async def get_workflow_types(workflow_name: str) -> Dict[str, Any]:
    """Look up input_types and output_types for a workflow by name or path."""
    in_types, out_types = _get_workflow_types(workflow_name)
    return {
        "workflow": workflow_name,
        "input_types": in_types,
        "output_types": out_types,
        "has_type_info": bool(in_types or out_types),
    }


# ── Workflow chain catalog ─────────────────────────────────────────────────

def _load_chain_row(row: tuple) -> Dict[str, Any]:
    """Convert a workflow_chains DB row to a dict."""
    cols = [
        "id", "name", "display_name", "domain", "description",
        "steps", "connections", "required_inputs", "expected_outputs",
        "example_queries", "tags", "source", "usage_count", "success_rate",
        "created_at", "updated_at",
    ]
    d = dict(zip(cols, row))
    for field in ("steps", "connections", "required_inputs", "expected_outputs", "example_queries", "tags"):
        try:
            d[field] = json.loads(d[field] or "[]")
        except (json.JSONDecodeError, TypeError):
            d[field] = []
    return d


@router.get("/api/workflows/chains", summary="List curated workflow chains")
async def list_workflow_chains(domain: Optional[str] = None) -> Dict[str, Any]:
    """Return all curated workflow chains, optionally filtered by domain."""
    try:
        conn = sqlite3.connect(str(_DB_PATH))
        try:
            if domain:
                rows = conn.execute(
                    "SELECT * FROM workflow_chains WHERE domain=? ORDER BY usage_count DESC",
                    (domain,),
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM workflow_chains ORDER BY usage_count DESC"
                ).fetchall()
        finally:
            conn.close()
        return {"chains": [_load_chain_row(r) for r in rows], "total": len(rows)}
    except Exception as exc:
        log.warning("list_workflow_chains failed: %s", exc)
        return {"chains": [], "total": 0, "error": str(exc)}


class RecordChainRunRequest(BaseModel):
    chain_name: str
    success: bool


@router.post("/api/workflows/chains/record-run", summary="Record outcome of a chain run")
async def record_chain_run(request: RecordChainRunRequest) -> Dict[str, Any]:
    """Update usage_count and rolling success_rate for a named chain."""
    try:
        conn = sqlite3.connect(str(_DB_PATH))
        try:
            row = conn.execute(
                "SELECT usage_count, success_rate FROM workflow_chains WHERE name=?",
                (request.chain_name,),
            ).fetchone()
            if not row:
                raise HTTPException(status_code=404, detail=f"Chain '{request.chain_name}' not found")
            usage, rate = row
            new_usage = usage + 1
            new_rate = round((rate * usage + (1.0 if request.success else 0.0)) / new_usage, 4)
            conn.execute(
                "UPDATE workflow_chains SET usage_count=?, success_rate=?, updated_at=? WHERE name=?",
                (new_usage, new_rate, datetime.now(timezone.utc).isoformat(), request.chain_name),
            )
            conn.commit()
        finally:
            conn.close()
        return {"chain_name": request.chain_name, "usage_count": new_usage, "success_rate": new_rate}
    except HTTPException:
        raise
    except Exception as exc:
        log.warning("record_chain_run failed: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))
