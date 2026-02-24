"""
Nextflow Executor API

Provides POST /api/nextflow/execute — launches a Nextflow workflow
as a background subprocess and returns tracking IDs.

Does NOT require Galaxy workflow/invocation infrastructure.
"""
import logging
import os
import subprocess
import threading
import uuid
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import HTTPException
from pydantic import BaseModel

from galaxy.webapps.galaxy.api import Router

log = logging.getLogger(__name__)

router = Router(tags=["nextflow"])

# In-process registry: run_id → {status, process, outdir, ...}
_runs: Dict[str, Dict[str, Any]] = {}
_runs_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class NextflowExecuteRequest(BaseModel):
    nextflow_path: str
    parameters: Optional[Dict[str, Any]] = None
    profile: Optional[str] = "standard"
    history_id: Optional[str] = None
    compute_config: Optional[Dict[str, Any]] = None


class NextflowStatusRequest(BaseModel):
    run_id: str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_nextflow_bin() -> str:
    nf = os.environ.get("NEXTFLOW_BIN", "nextflow")
    # Verify it's actually on PATH
    import shutil
    resolved = shutil.which(nf)
    if resolved:
        return resolved
    raise RuntimeError(
        f"Nextflow binary '{nf}' not found on PATH. "
        "Install with: curl -s https://get.nextflow.io | bash"
    )


def _stream_logs(process: subprocess.Popen, run_id: str, log_path: Path):
    """Stream stdout+stderr to a log file and update run status when done."""
    try:
        with open(log_path, "w") as fh:
            for line in process.stdout:            # type: ignore[union-attr]
                fh.write(line)
                fh.flush()
        process.wait()
        returncode = process.returncode
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = "succeeded" if returncode == 0 else "failed"
                _runs[run_id]["returncode"] = returncode
        log.info(f"[Nextflow run {run_id}] finished with exit code {returncode}")
    except Exception as exc:
        log.error(f"[Nextflow run {run_id}] log streaming error: {exc}")
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = "failed"


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/api/nextflow/execute", summary="Launch a Nextflow workflow")
def execute_nextflow(
    request: NextflowExecuteRequest,
) -> Dict[str, Any]:
    """
    Launch a Nextflow workflow by path.  Returns immediately with a run_id.
    The workflow runs as a background subprocess.
    """
    nf_path = Path(request.nextflow_path)
    if not nf_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Nextflow script not found: {request.nextflow_path}"
        )

    # Generate unique IDs
    run_id = str(uuid.uuid4())
    invocation_id = str(uuid.uuid4())

    # Work / output directory
    work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
    outdir = work_base / run_id / "output"
    work_dir = work_base / run_id / "work"
    log_dir = work_base / run_id
    outdir.mkdir(parents=True, exist_ok=True)
    work_dir.mkdir(parents=True, exist_ok=True)

    # Build nextflow command
    try:
        nf_bin = _get_nextflow_bin()
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

    cmd = [nf_bin, "run", str(nf_path)]

    # Profile
    profile = request.profile or "standard"
    cmd += ["-profile", profile]

    # Work directory
    cmd += ["-w", str(work_dir)]

    # Output dir param (most nf-core pipelines use --outdir)
    cmd += ["--outdir", str(outdir)]

    # Additional parameters
    params = request.parameters or {}
    for key, value in params.items():
        if isinstance(value, bool):
            cmd += [f"--{key}", "true" if value else "false"]
        else:
            cmd += [f"--{key}", str(value)]

    log.info(f"[Nextflow run {run_id}] cmd: {' '.join(cmd)}")
    log.info(f"[Nextflow run {run_id}] outdir: {outdir}")

    log_path = log_dir / "nextflow.log"

    # Environment
    env = os.environ.copy()
    env["NXF_HOME"] = str(log_dir / ".nextflow")

    # Compute config overrides
    compute = request.compute_config or {}
    if compute.get("executor") == "slurm":
        env["NXF_EXECUTOR"] = "slurm"
    elif compute.get("executor") == "awsbatch":
        env["NXF_EXECUTOR"] = "awsbatch"
        if compute.get("s3_bucket"):
            env["NXF_WORK"] = f"s3://{compute['s3_bucket']}/nextflow/{run_id}"

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            cwd=str(nf_path.parent),
            env=env,
        )
    except Exception as exc:
        log.error(f"[Nextflow run {run_id}] failed to launch: {exc}")
        raise HTTPException(status_code=500, detail=f"Failed to launch Nextflow: {exc}")

    # Register run
    with _runs_lock:
        _runs[run_id] = {
            "run_id": run_id,
            "invocation_id": invocation_id,
            "status": "running",
            "returncode": None,
            "outdir": str(outdir),
            "log_path": str(log_path),
            "nextflow_path": str(nf_path),
            "profile": profile,
        }

    # Stream logs in background
    t = threading.Thread(
        target=_stream_logs,
        args=(process, run_id, log_path),
        daemon=True,
        name=f"nf-log-{run_id[:8]}",
    )
    t.start()

    return {
        "success": True,
        "run_id": run_id,
        "invocation_id": invocation_id,
        "status": "running",
        "outputs": {
            "outdir": str(outdir),
        },
        "message": f"Nextflow workflow started (run_id: {run_id})",
    }


@router.get("/api/nextflow/status/{run_id}", summary="Get Nextflow run status")
def get_nextflow_status(
    run_id: str,
) -> Dict[str, Any]:
    """Return current status of a Nextflow run."""
    with _runs_lock:
        info = _runs.get(run_id)

    if info is None:
        raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    # Read last few lines of log for progress info
    log_tail: list = []
    log_path = Path(info.get("log_path", ""))
    if log_path.exists():
        try:
            with open(log_path) as fh:
                lines = fh.readlines()
            log_tail = [l.rstrip() for l in lines[-20:]]
        except Exception:
            pass

    return {
        "run_id": run_id,
        "invocation_id": info["invocation_id"],
        "status": info["status"],
        "returncode": info["returncode"],
        "outdir": info["outdir"],
        "log_tail": log_tail,
    }
