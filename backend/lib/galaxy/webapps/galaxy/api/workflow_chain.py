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
import re
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Context-param propagation helpers
# ---------------------------------------------------------------------------

# Transform registry: maps transform-name → {raw_value_lower → transformed_value}.
# Used by resolve_context_params() to convert a param value from step N into
# the appropriate form for step N+1.
_PARAM_TRANSFORMS: Dict[str, Dict[str, str]] = {
    "genome_to_organism": {
        "grch38": "hsa", "grch37": "hsa", "hg38": "hsa", "hg19": "hsa",
        "grcm39": "mmu", "grcm38": "mmu", "mm10": "mmu", "mm39": "mmu",
        "rnor_6.0": "rno", "rnor6": "rno",
        "bdgp6": "dme", "danrer11": "dre",
    }
}


def resolve_context_params(
    connection: Dict[str, Any],
    prev_run_params: Dict[str, Any],
) -> Dict[str, Any]:
    """Return a dict of params inherited from the previous step's run params.

    Given a connection dict (with optional ``context_params`` field) and the
    params dict from the previous step's run, return a dict of resolved params
    to merge into the next step's params_template.

    Example connection::

        {
            "from_step": 1, "from_output": "results",
            "to_step": 2, "to_input": "de_results",
            "context_params": {
                "organism": {
                    "from_run_param": "genome",
                    "transform": "genome_to_organism"
                }
            }
        }

    Rules:
    - ``from_run_param``: key to look up in *prev_run_params*.
    - ``transform`` (optional): name of a transform table in ``_PARAM_TRANSFORMS``.
      If the looked-up value is not in the table, the raw value is passed through.
    - Missing source param → the dest param is silently omitted (no error).
    """
    ctx = connection.get("context_params", {})
    resolved: Dict[str, Any] = {}
    for dest_param, rule in ctx.items():
        src_key = rule.get("from_run_param")
        transform = rule.get("transform")
        raw_val = prev_run_params.get(src_key)
        if raw_val is None:
            continue
        if transform:
            table = _PARAM_TRANSFORMS.get(transform, {})
            raw_val = table.get(str(raw_val).lower(), raw_val)
        resolved[dest_param] = raw_val
    return resolved

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
    str(Path(__file__).parent.parent.parent.parent.parent.parent / "database" / "ai_workflow_ops" / "chains")
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
    "sdf": ["ligand_sdf", "compounds", "ligand_file", "input"],
    "smi": ["smiles", "ligand_smiles", "compound_smiles"],
}


def _list_run_output_files(run_id: str) -> List[Dict[str, Any]]:
    """Collect output files for a Nextflow run (S3 + local outdir)."""
    from galaxy.webapps.galaxy.api.nextflow_executor import (  # noqa: PLC0415
        _runs,
        _runs_lock,
        get_nextflow_status,
    )

    files: List[Dict[str, Any]] = []
    seen: set = set()

    def _add(f: Dict[str, Any]) -> None:
        key = f.get("s3_uri") or f.get("path") or f.get("filename")
        if key and key not in seen:
            seen.add(key)
            files.append(f)

    with _runs_lock:
        run_info = dict(_runs.get(run_id, {}))
    for f in run_info.get("s3_output_files") or []:
        _add({**f, "filename": f.get("filename", "")})

    try:
        status = get_nextflow_status(run_id)
        for f in status.get("s3_output_files") or []:
            _add({**f, "filename": f.get("filename", "")})
        outdir = status.get("outdir")
        if outdir and Path(outdir).exists():
            for fpath in sorted(Path(outdir).rglob("*")):
                if not fpath.is_file():
                    continue
                parts_str = str(fpath)
                if any(skip in parts_str for skip in ["/work/", "/.nextflow/", "/trace.", "/timeline."]):
                    continue
                _add({
                    "filename": fpath.name,
                    "path": str(fpath),
                    "extension": fpath.suffix.lstrip(".").lower(),
                })
    except Exception as exc:
        log.debug("workflow_chain: list outputs for %s failed: %s", run_id, exc)

    return files


def _apply_connection_handoffs(
    chain_state: Dict[str, Any],
    step_index: int,
    params: Dict[str, Any],
) -> Tuple[Dict[str, Any], List[str]]:
    """Wire chain connections into next-step params (Phase 2 artifact contracts)."""
    from galaxy.chain.artifact_contracts import artifact_value, pick_artifact_file  # noqa: PLC0415

    connections = chain_state.get("connections") or []
    steps = chain_state.get("steps") or []
    wired: Dict[str, Any] = {}
    warnings: List[str] = []
    target_step = step_index + 1  # catalog connections are 1-based

    for conn in connections:
        if int(conn.get("to_step", -1)) != target_step:
            continue
        from_step = int(conn.get("from_step", 0)) - 1
        from_output = str(conn.get("from_output", ""))
        to_input = str(conn.get("to_input", ""))
        if not from_output or not to_input:
            continue
        if from_step < 0 or from_step >= len(steps):
            warnings.append(f"Invalid from_step {from_step + 1} for → step {target_step}")
            continue
        prev_run_id = steps[from_step].get("run_id")
        if not prev_run_id:
            warnings.append(f"Step {from_step + 1} missing run_id for {from_output}→{to_input}")
            continue
        picked = pick_artifact_file(_list_run_output_files(prev_run_id), from_output)
        if not picked:
            warnings.append(f"No artifact '{from_output}' found from step {from_step + 1}")
            continue
        value = artifact_value(picked)
        if value and to_input not in params:
            wired[to_input] = value
            log.info(
                "workflow_chain: connection step %d→%d: %s → %s = %s",
                from_step + 1, target_step, from_output, to_input, value[:120],
            )

    merged = dict(params)
    for k, v in wired.items():
        if k not in merged:
            merged[k] = v
    return merged, warnings


def _extract_step_artifacts(
    run_id: str,
    connections: List[Dict[str, Any]],
    from_step_number: int,
) -> Dict[str, Any]:
    """Snapshot logical outputs produced by a completed step."""
    from galaxy.chain.artifact_contracts import artifact_value, pick_artifact_file  # noqa: PLC0415

    files = _list_run_output_files(run_id)
    artifacts: Dict[str, Any] = {}
    for conn in connections:
        if int(conn.get("from_step", -1)) != from_step_number:
            continue
        from_output = str(conn.get("from_output", ""))
        if not from_output or from_output in artifacts:
            continue
        picked = pick_artifact_file(files, from_output)
        if picked:
            artifacts[from_output] = {
                "path": artifact_value(picked),
                "filename": picked.get("filename"),
            }
    return artifacts


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

def _compute_chain_meta(
    chain_name: Optional[str],
    step_index: int,
    nextflow_path: Optional[str],
) -> Optional[Dict[str, Any]]:
    """Parse a Nextflow main.nf for `// [Phase X]` markers and emit the
    chain_meta.json shape `_resolve_rationale_id` expects.

    For multi-step chains, the rationale_id encodes step+letter as
    `<step+1>.<letter>` (matching the T05 atlas+triage convention).
    For single-step chains, just `<letter>`.

    Safe-fail: returns None if the file is unreadable or has no markers.
    """
    if not chain_name or not nextflow_path:
        return None
    try:
        from pathlib import Path
        # nextflow_path is typically relative to the workflows root; the
        # nextflow_executor resolver handles both. For the meta sidecar we
        # only need the source text, so search common roots.
        candidates = [
            Path(nextflow_path),
            Path("backend") / nextflow_path,
            Path("backend") / "nf-core-workflows" / Path(nextflow_path).relative_to(
                "nf-core-workflows"
            ) if str(nextflow_path).startswith("nf-core-workflows/") else Path(nextflow_path),
        ]
        src = None
        for c in candidates:
            if c.exists():
                src = c.read_text(errors="ignore")
                break
        if src is None:
            return None
        import re
        # Match: // [Phase A] ... \n[whitespace]process PROCESS_NAME
        phases = []
        for m in re.finditer(
            r"//\s*\[Phase\s+([A-Z])\][^\n]*\n[^\n]*?process\s+([A-Z0-9_]+)",
            src,
        ):
            letter, proc = m.group(1), m.group(2)
            # For multi-step chains, prefix with step index (1-based).
            phase_id = f"{step_index + 1}.{letter}" if step_index > 0 else letter
            # If we're step 0 of a multi-step chain (T05-style), keep 1.X form
            # too. We don't know the total step count here; the resolver tries
            # both `<letter>` and `<step+1>.<letter>` callers, so either is safe.
            phases.append({
                "process_name_pattern": f"^{re.escape(proc)}$",
                "phase_letter": phase_id,
            })
        if not phases:
            return None
        return {"chain_name": chain_name, "phases": phases}
    except Exception as exc:
        log.debug("[chain_meta] compute failed for %s: %s", nextflow_path, exc)
        return None


def _run_chain(chain_run_id: str, start_from_step: int = 0) -> None:
    """Execute chain steps sequentially in a background thread."""
    state = _get_chain(chain_run_id)
    if state is None:
        log.error("workflow_chain: chain %s not found", chain_run_id)
        return

    steps = state["steps"]
    connections = state.get("connections") or []
    log.info(
        "workflow_chain: starting chain %s from step %d (%d steps total)",
        chain_run_id, start_from_step, len(steps),
    )

    for idx in range(start_from_step, len(steps)):
        step = steps[idx]
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

        nextflow_path = step.get("nextflow_path") or ""
        params = dict(step.get("params", {}))

        # Skip unresolved steps (no workflow path) — mark as failed and continue
        if not nextflow_path:
            log.warning("workflow_chain: step %d has no nextflow_path — marking failed", idx)
            current["steps"][idx]["status"] = "failed"
            current["steps"][idx]["error"] = "nextflow_path not resolved"
            current["status"] = "failed"
            _update_chain(current)
            return

        # Auto-wire outputs → inputs via chain connections (Phase 2) or extension heuristics
        if connections:
            params, conn_warnings = _apply_connection_handoffs(current, idx, params)
            if conn_warnings:
                current["steps"][idx]["handoff_warnings"] = conn_warnings
                _update_chain(current)
            # Propagate context params from the previous step's run params
            # (e.g. genome → organism transform for DESeq2 / clusterProfiler).
            # This runs whenever connections are defined, regardless of whether
            # artifact handoff resolved any files.
            if idx > 0:
                prev_step_state = current["steps"][idx - 1]
                prev_run_params = prev_step_state.get("params") or {}
                target_step_num = idx + 1  # connections use 1-based step numbers
                for conn in connections:
                    if int(conn.get("to_step", -1)) != target_step_num:
                        continue
                    if conn.get("context_params"):
                        inherited = resolve_context_params(conn, prev_run_params)
                        if inherited:
                            params.update(inherited)
                            log.info(
                                "workflow_chain: step %d inherited context params from step %d: %s",
                                idx, idx - 1, list(inherited.keys()),
                            )
        elif idx > 0:
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
            # Build chain_meta sidecar so the (why?) anchor can resolve
            # rationale_id on each phase. Derived from the .nf header's
            # `// [Phase X]` markers + the following `process <NAME>` line.
            _chain_meta = _compute_chain_meta(
                current.get("chain_name"),
                step_index=idx,
                nextflow_path=nextflow_path,
            )
            req = NextflowExecuteRequest(
                nextflow_path=nextflow_path,
                parameters=params,
                chain_meta=_chain_meta,
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

        # Record logical artifacts for downstream steps / aggregate outputs API
        if connections:
            current = _get_chain(chain_run_id) or state
            current["steps"][idx]["artifacts"] = _extract_step_artifacts(
                run_id, connections, idx + 1,
            )
            _update_chain(current)

        current = _get_chain(chain_run_id) or state
        _write_pipeline_manifest(current)

        end_at = current.get("end_at_step")
        if end_at is not None and idx >= int(end_at):
            remaining = any(
                s.get("status") == "pending"
                for s in (current.get("steps") or [])[idx + 1:]
            )
            if remaining:
                current["status"] = "awaiting_approval"
                log.info(
                    "workflow_chain: chain %s paused after step %d (awaiting approval)",
                    chain_run_id, idx,
                )
            else:
                current["status"] = "succeeded"
                current["completed_at"] = datetime.now(timezone.utc).isoformat()
                log.info("workflow_chain: chain %s completed successfully", chain_run_id)
            _update_chain(current)
            return

    # All steps succeeded
    current = _get_chain(chain_run_id) or state
    current["status"] = "succeeded"
    current["completed_at"] = datetime.now(timezone.utc).isoformat()
    _update_chain(current)
    _write_pipeline_manifest(current)
    log.info("workflow_chain: chain %s completed successfully", chain_run_id)


def _normalize_run_status(raw_status: str) -> str:
    """Map Nextflow executor status strings to chain step terminal states."""
    s = (raw_status or "running").lower()
    if s in ("succeeded", "completed", "ok", "success"):
        return "succeeded"
    if s in ("failed", "error", "errored"):
        return "failed"
    if s in ("cancelled", "aborted", "stopped"):
        return "cancelled"
    return "running"


def _poll_run_until_done(chain_run_id: str, step_idx: int, run_id: str, poll_interval: float = 5.0, timeout: float = 3600.0) -> None:
    """Poll a Nextflow run until it finishes, updating chain state accordingly."""
    from galaxy.webapps.galaxy.api.nextflow_executor import (  # noqa: PLC0415
        _looks_like_false_success,
        get_nextflow_status,
    )

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status_payload: Dict[str, Any] = {}
        try:
            status_payload = get_nextflow_status(run_id)
        except Exception as exc:
            log.debug("workflow_chain: get_nextflow_status failed for %s: %s", run_id, exc)

        status = _normalize_run_status(status_payload.get("status", "running"))

        # Batch/driver mismatch: failed in memory but S3 outputs exist and pass QC heuristics.
        if status == "failed":
            s3_files = status_payload.get("s3_output_files") or []
            if s3_files and not _looks_like_false_success(
                log_tail=status_payload.get("log_tail"),
                total_steps=status_payload.get("totalSteps") or 0,
                duration_s=status_payload.get("duration_s") or 0,
                s3_output_files=s3_files,
                workflow_domain=status_payload.get("workflow_domain", ""),
                nextflow_path=status_payload.get("nextflow_path", ""),
            ):
                log.info(
                    "workflow_chain: run %s reported failed but has valid outputs — treating as succeeded",
                    run_id,
                )
                status = "succeeded"

        if status in ("succeeded", "failed", "cancelled"):
            current = _get_chain(chain_run_id)
            if current:
                current["steps"][step_idx]["status"] = status
                current["steps"][step_idx]["completed_at"] = datetime.now(timezone.utc).isoformat()
                if status_payload.get("outdir"):
                    current["steps"][step_idx]["outdir"] = status_payload.get("outdir")
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

# Resolve to the canonical database path: $GALAXY_AI_DB env > app-relative default.
# Uses the same logic as unified_workflow_search.py so all code that opens this DB
# resolves to the same file. The hardcoded /home/yzhang/ fallback only worked on one
# developer's laptop — it never worked in Docker.
_DB_PATH = Path(os.environ.get(
    "GALAXY_AI_DB",
    str(Path(__file__).parent.parent.parent.parent.parent.parent / "database" / "galaxy_ai_tools.db")
))


def resolve_workflow_name_to_path(workflow_name: str, workflow_id: Optional[int] = None) -> Optional[str]:
    """Resolve a curated chain step to an indexed nextflow_path (filename).

    Determinism order:
      0) If workflow_id is supplied (chain step pinned to a specific row),
         look up that row's filename directly. This is the only path that
         survives re-indexing without surprise — the cascade below picks
         by SQLite rowid order, which is stable per DB but not across
         re-runs of index_all_workflows.py.
      1-6) Name-based cascade (legacy behaviour for unpinned chain steps).
    """
    if workflow_id is not None:
        try:
            conn = sqlite3.connect(str(_DB_PATH))
            row = conn.execute(
                "SELECT filename FROM workflows WHERE id=? AND executable=1 LIMIT 1",
                (int(workflow_id),),
            ).fetchone()
            conn.close()
            if row and row[0]:
                return str(row[0])
        except Exception as exc:
            log.debug("workflow_chain: workflow_id resolve failed for %s: %s", workflow_id, exc)
        # workflow_id missed (row deleted / non-executable) — fall through
        # to the name cascade rather than returning None outright.
    if not workflow_name or not str(workflow_name).strip():
        return None
    name = str(workflow_name).strip()
    # Curated chain templates reference steps as BIOC_<PKG> (the original atomic-wrapper
    # convention), but the regenerated bioc workflows are indexed under their bare package
    # name (e.g. 'minfi', 'dss', 'missmethyl'). Strip a leading BIOC_ so the chain resolves
    # to the indexed row instead of returning 0 rows.
    bare = re.sub(r'^bioc[_-]', '', name, flags=re.IGNORECASE).strip()
    slug = name.lower().replace(" ", "_").replace("-", "_")
    bare_slug = bare.lower().replace(" ", "_").replace("-", "_")
    try:
        conn = sqlite3.connect(str(_DB_PATH))
        queries = [
            ("SELECT filename FROM workflows WHERE lower(name)=lower(?) AND executable=1 LIMIT 1", (name,)),
            # BIOC_<PKG> -> bare package-name row (the dominant chain-resolution gap)
            ("SELECT filename FROM workflows WHERE lower(name)=lower(?) AND executable=1 LIMIT 1", (bare,)),
            ("SELECT filename FROM workflows WHERE name LIKE ? AND executable=1 LIMIT 1", (f"%{name}%",)),
            (
                "SELECT filename FROM workflows WHERE replace(lower(name),' ','') "
                "= replace(lower(?),' ','') AND executable=1 LIMIT 1",
                (name,),
            ),
            ("SELECT filename FROM workflows WHERE lower(filename) LIKE ? AND executable=1 LIMIT 1", (f"%/{bare_slug}/%",)),
            ("SELECT filename FROM workflows WHERE lower(filename) LIKE ? AND executable=1 LIMIT 1", (f"%{slug}%",)),
            ("SELECT filename FROM workflows WHERE lower(filename) LIKE ? AND executable=1 LIMIT 1", (f"%{name.lower()}%",)),
        ]
        for sql, params in queries:
            row = conn.execute(sql, params).fetchone()
            if row and row[0]:
                conn.close()
                return str(row[0])
        conn.close()
    except Exception as exc:
        log.debug("workflow_chain: path resolve failed for %s: %s", workflow_name, exc)
    return None


def enrich_chain_steps(steps: List[Any]) -> List[Dict[str, Any]]:
    """Attach nextflow_path to chain step dicts when only workflow_name is present."""
    enriched: List[Dict[str, Any]] = []
    for step in steps or []:
        s = dict(step) if isinstance(step, dict) else {}
        if not s.get("nextflow_path"):
            wn = s.get("workflow_name") or ""
            path = resolve_workflow_name_to_path(wn)
            if path:
                s["nextflow_path"] = path
        enriched.append(s)
    return enriched


def _slug_step_key(workflow_name: Optional[str], role: Optional[str] = None) -> str:
    if role:
        return str(role).strip().lower().replace(" ", "_")
    if not workflow_name:
        return "step"
    name = str(workflow_name).lower()
    for short, key in (
        ("pocket_detection", "pocket"),
        ("pharmacophore", "pharmacophore"),
        ("predict_admet", "admet"),
        ("docking_autodock_vina", "docking_vina"),
        ("structure_prediction_docking", "docking"),
        ("gromacs", "gromacs_mmgbsa"),
        ("reinvent4", "reinvent4"),
        ("epitopeprediction", "epitope"),
    ):
        if short in name:
            return key
    return name.split("/")[-1].replace(" ", "_")[:48]


def _build_pipeline_manifest(state: Dict[str, Any]) -> Dict[str, Any]:
    """ANDV-compatible manifest for chain runs (parity with CLI pipeline_manifest.json)."""
    steps_out: List[Dict[str, Any]] = []
    for step in state.get("steps") or []:
        key = step.get("step_key") or _slug_step_key(
            step.get("workflow_name"), step.get("role"),
        )
        entry: Dict[str, Any] = {
            "key": key,
            "title": step.get("workflow_name") or key,
            "nextflow_path": step.get("nextflow_path"),
            "run_id": step.get("run_id"),
            "status": step.get("status"),
            "artifacts": step.get("artifacts") or {},
        }
        if step.get("outdir"):
            entry["outdir"] = step.get("outdir")
        if step.get("artifacts"):
            entry["artifact_paths"] = {
                k: v.get("path") for k, v in step["artifacts"].items() if isinstance(v, dict)
            }
        steps_out.append(entry)
    succeeded = sum(1 for s in state.get("steps") or [] if s.get("status") == "succeeded")
    return {
        "chain_run_id": state.get("chain_run_id"),
        "chain_name": state.get("chain_name"),
        "created_at": state.get("created_at"),
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "status": state.get("status"),
        "through_step": succeeded,
        "steps": steps_out,
    }


def _write_pipeline_manifest(state: Dict[str, Any]) -> None:
    manifest = _build_pipeline_manifest(state)
    chain_id = state.get("chain_run_id", "")
    if not chain_id:
        return
    run_dir = _chains_dir() / chain_id
    run_dir.mkdir(parents=True, exist_ok=True)
    mf_path = run_dir / "pipeline_manifest.json"
    try:
        mf_path.write_text(json.dumps(manifest, indent=2, default=str))
    except Exception as exc:
        log.warning("workflow_chain: failed to write manifest %s: %s", mf_path, exc)


def _resolve_submit_steps(steps: List["ChainStep"]) -> List[Dict[str, Any]]:
    """Normalize ChainStep models to executor dicts with resolved nextflow_path."""
    resolved: List[Dict[str, Any]] = []
    for step in steps:
        data = step.model_dump() if hasattr(step, "model_dump") else dict(step)
        nf_path = data.get("nextflow_path")
        wn = data.get("workflow_name")
        role = data.get("role")
        if not nf_path and wn:
            nf_path = resolve_workflow_name_to_path(str(wn))
        resolved.append({
            "nextflow_path": nf_path,
            "params": data.get("params") or {},
            "workflow_name": wn,
            "role": role,
            "step_key": data.get("step_key") or _slug_step_key(wn, role),
        })
    return resolved


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
    nextflow_path: Optional[str] = None  # Optional: may be unresolved for AI-generated pipelines
    workflow_name: Optional[str] = None
    role: Optional[str] = None
    step_key: Optional[str] = None
    params: Optional[Dict[str, Any]] = None


class ChainSubmitRequest(BaseModel):
    chain_run_id: Optional[str] = None
    chain_name: Optional[str] = None
    chat_session_id: Optional[str] = None
    connections: Optional[List[Dict[str, Any]]] = None
    start_from_step: Optional[int] = None  # 0-based; resume from this step
    end_at_step: Optional[int] = None  # 0-based inclusive; pause for approval after this step
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

    start_from = max(0, int(request.start_from_step or 0))
    end_at = request.end_at_step
    resume = bool(request.chain_run_id and (start_from > 0 or end_at is not None))

    if resume and request.chain_run_id:
        existing = _get_chain(request.chain_run_id)
        if existing is None:
            raise HTTPException(status_code=404, detail=f"Chain {request.chain_run_id!r} not found for resume")
        chain_run_id = request.chain_run_id
        if start_from > 0:
            for i in range(start_from, len(existing["steps"])):
                existing["steps"][i].update({
                    "status": "pending",
                    "run_id": None,
                    "started_at": None,
                    "completed_at": None,
                    "error": None,
                    "artifacts": {},
                    "handoff_warnings": [],
                })
        existing["status"] = "running"
        existing["completed_at"] = None
        if request.connections is not None:
            existing["connections"] = request.connections
        if request.chain_name:
            existing["chain_name"] = request.chain_name
        if end_at is not None:
            existing["end_at_step"] = int(end_at)
        _update_chain(existing)
        steps_state = existing["steps"]
    else:
        chain_run_id = request.chain_run_id or f"chain_{int(time.time())}_{os.urandom(3).hex()}"
        resolved_steps = _resolve_submit_steps(request.steps)

        steps_state = [
            {
                "index": i,
                "nextflow_path": step.get("nextflow_path"),
                "workflow_name": step.get("workflow_name"),
                "role": step.get("role"),
                "step_key": step.get("step_key"),
                "params": step.get("params") or {},
                "status": "pending",
                "run_id": None,
                "started_at": None,
                "completed_at": None,
                "artifacts": {},
            }
            for i, step in enumerate(resolved_steps)
        ]

        state: Dict[str, Any] = {
            "chain_run_id": chain_run_id,
            "chain_name": request.chain_name,
            "chat_session_id": request.chat_session_id,
            "connections": request.connections or [],
            "end_at_step": int(end_at) if end_at is not None else None,
            "status": "running",
            "steps": steps_state,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "completed_at": None,
        }
        _update_chain(state)

    t = threading.Thread(
        target=_run_chain,
        args=(chain_run_id, start_from),
        daemon=True,
        name=f"chain-{str(chain_run_id)[:12]}",
    )
    t.start()

    return {
        "chain_run_id": chain_run_id,
        "status": "running",
        "steps": steps_state,
        "resumed_from_step": start_from if resume else None,
    }


@router.get("/api/workflows/chain/{chain_run_id}", summary="Poll chain execution status")
async def get_chain_status(chain_run_id: str) -> Dict[str, Any]:
    """Return the current status of a sequential workflow chain."""
    state = _get_chain(chain_run_id)
    if state is None:
        raise HTTPException(status_code=404, detail=f"Chain {chain_run_id!r} not found")
    steps = state.get("steps") or []
    completed = sum(1 for s in steps if s.get("status") == "succeeded")
    failed = sum(1 for s in steps if s.get("status") == "failed")
    running = sum(1 for s in steps if s.get("status") == "running")
    return {
        **state,
        "steps_completed": completed,
        "steps_total": len(steps),
        "steps_failed": failed,
        "steps_running": running,
        "progress": {
            "completedSteps": completed,
            "totalSteps": len(steps),
            "failedSteps": failed,
            "runningSteps": running,
            "percentComplete": int(100 * completed / len(steps)) if steps else 0,
        },
    }


@router.get("/api/workflows/chain/{chain_run_id}/outputs", summary="Aggregate outputs across chain steps")
async def get_chain_outputs(chain_run_id: str) -> Dict[str, Any]:
    """Return per-step artifacts and file listings for a workflow chain."""
    state = _get_chain(chain_run_id)
    if state is None:
        raise HTTPException(status_code=404, detail=f"Chain {chain_run_id!r} not found")

    step_outputs: List[Dict[str, Any]] = []
    all_files: List[Dict[str, Any]] = []

    for step in state.get("steps") or []:
        run_id = step.get("run_id")
        entry: Dict[str, Any] = {
            "step_index": step.get("index"),
            "workflow_name": step.get("workflow_name"),
            "nextflow_path": step.get("nextflow_path"),
            "status": step.get("status"),
            "run_id": run_id,
            "artifacts": step.get("artifacts") or {},
            "files": [],
        }
        if run_id:
            files = _list_run_output_files(run_id)
            entry["files"] = files
            for f in files:
                all_files.append({**f, "step_index": step.get("index"), "run_id": run_id})
        step_outputs.append(entry)

    return {
        "chain_run_id": chain_run_id,
        "chain_name": state.get("chain_name"),
        "status": state.get("status"),
        "steps": step_outputs,
        "output_files": all_files,
        "count": len(all_files),
    }


@router.get("/api/workflows/chain/{chain_run_id}/manifest", summary="Export ANDV-compatible pipeline manifest")
async def get_chain_manifest(chain_run_id: str) -> Dict[str, Any]:
    """Return pipeline_manifest.json shape for chain runs (CLI parity)."""
    state = _get_chain(chain_run_id)
    if state is None:
        raise HTTPException(status_code=404, detail=f"Chain {chain_run_id!r} not found")
    manifest = _build_pipeline_manifest(state)
    run_dir = _chains_dir() / chain_run_id
    disk_path = str(run_dir / "pipeline_manifest.json") if run_dir.exists() else None
    return {**manifest, "manifest_path": disk_path}


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


@router.get("/api/workflow-chains", summary="List curated workflow chains")
async def list_workflow_chains(
    domain: Optional[str] = None,
    intent_hint: bool = False,
) -> Dict[str, Any]:
    """Return curated workflow chains, optionally filtered by domain.

    intent_hint=true excludes 'bioc_reactive' chains (post-completion suggestions only).
    These are bioc_*_v2 chains meant to be surfaced after a run finishes, not by the
    upfront intent classifier — excluding them prevents mis-routes where a single-step
    request gets escalated to a full multi-step pipeline.
    """
    try:
        conn = sqlite3.connect(str(_DB_PATH))
        try:
            clauses: list[str] = []
            params: list[str] = []
            if intent_hint:
                clauses.append("source != 'bioc_reactive'")
            if domain:
                clauses.append("domain=?")
                params.append(domain)
            where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
            rows = conn.execute(
                f"SELECT * FROM workflow_chains {where} ORDER BY usage_count DESC",
                params,
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


@router.post("/api/workflow-chains/record-run", summary="Record outcome of a chain run")
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


# ── v2: Bioconductor chain suggestion ─────────────────────────────────────────

class ChainSuggestRequest(BaseModel):
    workflow_name: str          # name of the completed workflow
    output_extensions: List[str] = []   # file extensions of its outputs
    domain: Optional[str] = None        # optional domain hint


@router.post("/api/v2/bioc/chain-suggest", summary="[v2] Suggest Bioconductor downstream chains for a completed run")
async def suggest_bioc_chain(request: ChainSuggestRequest) -> Dict[str, Any]:
    """
    Given a completed workflow name and its output file extensions, return
    ranked Bioconductor pipeline chain suggestions from BIOC_CHAIN_TEMPLATES.

    Used by the AI assistant to propose a follow-up chain after a run finishes.
    """
    try:
        from galaxy.ai.bioc_chain_templates import suggest_chains_for_run
        chains = suggest_chains_for_run(request.workflow_name, request.output_extensions)

        # If domain hint provided, boost matching domain chains
        if request.domain and chains:
            chains.sort(key=lambda c: (0 if c["domain"] == request.domain else 1))

        return {
            "workflow_name": request.workflow_name,
            "suggestions": [
                {
                    "name": c["name"],
                    "display_name": c["display_name"],
                    "domain": c["domain"],
                    "description": c["description"],
                    "steps": c["steps"],
                    "connections": c["connections"],
                    "required_inputs": c.get("required_inputs", []),
                    "example_queries": c.get("example_queries", []),
                }
                for c in chains[:3]  # top 3
            ],
            "total": len(chains),
        }
    except Exception as exc:
        log.warning("suggest_bioc_chain failed: %s", exc)
        return {"workflow_name": request.workflow_name, "suggestions": [], "total": 0, "error": str(exc)}


@router.get("/api/v2/bioc/chain-templates", summary="[v2] List all Bioconductor pipeline chain templates")
async def list_bioc_chain_templates(domain: Optional[str] = None) -> Dict[str, Any]:
    """Return all BIOC_CHAIN_TEMPLATES, optionally filtered by domain."""
    try:
        from galaxy.ai.bioc_chain_templates import BIOC_CHAIN_TEMPLATES
        templates = BIOC_CHAIN_TEMPLATES
        if domain:
            templates = [t for t in templates if t["domain"] == domain]
        return {
            "templates": [
                {
                    "name": t["name"],
                    "display_name": t["display_name"],
                    "domain": t["domain"],
                    "description": t["description"],
                    "steps": t["steps"],
                    "tags": t.get("tags", []),
                }
                for t in templates
            ],
            "total": len(templates),
        }
    except Exception as exc:
        log.warning("list_bioc_chain_templates failed: %s", exc)
        return {"templates": [], "total": 0, "error": str(exc)}
