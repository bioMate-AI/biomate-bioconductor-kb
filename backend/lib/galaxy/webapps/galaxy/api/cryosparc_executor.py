"""
CryoSPARC Executor — BioMate integration with live CryoSPARC v5

Connects to the CryoSPARC instance defined by environment variables:
    CRYOSPARC_HOST       — hostname or IP (default: localhost)
    CRYOSPARC_PORT       — base port (default: 30000)
    CRYOSPARC_EMAIL      — admin email
    CRYOSPARC_PASSWORD   — admin password
    CRYOSPARC_PROJECT_DIR — path on the CryoSPARC host for project storage

This executor replaces the Nextflow mock pipeline for cryo-EM SPA workflows.
Each SPA step maps directly to a CryoSPARC job type submitted via cryosparc-tools.

Job submission flow:
    1. Create/reuse project + workspace for this BioMate run
    2. Import movies
    3. Patch motion correction
    4. Patch CTF estimation
    5. (additional steps in future iterations)

Progress is reported via SSE using the same qc_trace_monitor SSE path.
"""

from __future__ import annotations

import logging
import os
import time
import traceback
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

CRYOSPARC_HOST = os.environ.get("CRYOSPARC_HOST", "localhost")
CRYOSPARC_PORT = int(os.environ.get("CRYOSPARC_PORT", "30000"))
CRYOSPARC_EMAIL = os.environ.get("CRYOSPARC_EMAIL", "admin@biomate.ai")
CRYOSPARC_PASSWORD = os.environ.get("CRYOSPARC_PASSWORD", "")
CRYOSPARC_LICENSE = os.environ.get("CRYOSPARC_LICENSE", "")
CRYOSPARC_PROJECT_DIR = os.environ.get("CRYOSPARC_PROJECT_DIR", "/tmp/cryosparc_projects")

# EC2 instance lifecycle (on-demand start/stop to avoid idle GPU cost)
CRYOSPARC_INSTANCE_ID = os.environ.get("CRYOSPARC_INSTANCE_ID", "")
CRYOSPARC_INSTANCE_REGION = os.environ.get("CRYOSPARC_INSTANCE_REGION", "us-east-1")
CRYOSPARC_AMI_ID = os.environ.get("CRYOSPARC_AMI_ID", "")
CRYOSPARC_INSTANCE_TYPE = os.environ.get("CRYOSPARC_INSTANCE_TYPE", "g6.2xlarge")
CRYOSPARC_SSH_KEY = os.environ.get("CRYOSPARC_SSH_KEY", "")
CRYOSPARC_SSH_USER = os.environ.get("CRYOSPARC_SSH_USER", "ubuntu")

# Tracks the instance launched for the current/last job (set by start_instance)
_active_instance_id: str = ""

# CryoSPARC job types for SPA pipeline
_IMPORT_JOB = "import_movies"
_MOTION_JOB = "patch_motion_correction_multi"
_CTF_JOB = "patch_ctf_estimation_multi"

# ---------------------------------------------------------------------------
# CryoSPARC connection helper
# ---------------------------------------------------------------------------

def _connect() -> "CryoSPARC":
    """Return an authenticated CryoSPARC connection. Raises if unavailable."""
    try:
        from cryosparc.tools import CryoSPARC  # type: ignore
    except ImportError as exc:
        raise RuntimeError(
            "cryosparc-tools is not installed. Run: pip install cryosparc-tools"
        ) from exc

    cs = CryoSPARC(
        host=CRYOSPARC_HOST,
        base_port=CRYOSPARC_PORT,
        email=CRYOSPARC_EMAIL,
        password=CRYOSPARC_PASSWORD,
    )
    if not cs.test_connection():
        raise RuntimeError(
            f"Cannot connect to CryoSPARC at {CRYOSPARC_HOST}:{CRYOSPARC_PORT}"
        )
    return cs


def is_cryosparc_available() -> bool:
    """Non-blocking health check for startup logging."""
    try:
        _connect()
        return True
    except Exception as exc:
        log.warning("[CryoSPARC] Not available: %s", exc)
        return False


# ---------------------------------------------------------------------------
# EC2 instance lifecycle management
# ---------------------------------------------------------------------------

def _ec2_client():
    import boto3  # type: ignore
    return boto3.client("ec2", region_name=CRYOSPARC_INSTANCE_REGION)


def get_instance_state() -> str:
    """Return 'running' | 'stopped' | 'pending' | 'stopping' | 'unknown'."""
    if not CRYOSPARC_INSTANCE_ID:
        return "unknown"
    try:
        ec2 = _ec2_client()
        resp = ec2.describe_instances(InstanceIds=[CRYOSPARC_INSTANCE_ID])
        state = resp["Reservations"][0]["Instances"][0]["State"]["Name"]
        return state
    except Exception as exc:
        log.warning("[CryoSPARC] Cannot get instance state: %s", exc)
        return "unknown"


def start_instance(wait: bool = True) -> str:
    """
    Start the stopped CryoSPARC EC2 instance and return its public IP.
    If CRYOSPARC_INSTANCE_ID is not set but CRYOSPARC_AMI_ID is, launch a new instance.
    """
    ec2 = _ec2_client()

    if CRYOSPARC_INSTANCE_ID:
        state = get_instance_state()
        if state == "running":
            log.info("[CryoSPARC] Instance already running")
        elif state in ("stopped", "pending", "stopping"):
            log.info("[CryoSPARC] Starting instance %s ...", CRYOSPARC_INSTANCE_ID)
            ec2.start_instances(InstanceIds=[CRYOSPARC_INSTANCE_ID])
        else:
            log.warning("[CryoSPARC] Unexpected instance state: %s", state)

        if wait:
            _wait_for_instance_running(ec2, CRYOSPARC_INSTANCE_ID)

        resp = ec2.describe_instances(InstanceIds=[CRYOSPARC_INSTANCE_ID])
        ip = resp["Reservations"][0]["Instances"][0].get("PublicIpAddress", "")
        return ip

    elif CRYOSPARC_AMI_ID:
        # Launch fresh instance from AMI (terminate-on-completion pattern — no idle EBS cost)
        log.info("[CryoSPARC] Launching new instance from AMI %s ...", CRYOSPARC_AMI_ID)
        user_data = """#!/bin/bash
cd /home/ubuntu
export PATH=/home/ubuntu/cryosparc_master/bin:$PATH
cryosparcm start
"""
        resp = ec2.run_instances(
            ImageId=CRYOSPARC_AMI_ID,
            InstanceType=CRYOSPARC_INSTANCE_TYPE,
            KeyName="cryosparc-benchmark",
            SecurityGroupIds=["sg-015137721b5fabddb"],
            MinCount=1, MaxCount=1,
            UserData=user_data,
            # EBS: DeleteOnTermination=True so terminate() cleans up storage automatically
            BlockDeviceMappings=[{
                "DeviceName": "/dev/sda1",
                "Ebs": {"VolumeSize": 200, "VolumeType": "gp3", "DeleteOnTermination": True}
            }],
            TagSpecifications=[{"ResourceType": "instance", "Tags": [
                {"Key": "Name", "Value": "cryosparc-biomate-job"},
                {"Key": "Project", "Value": "biomate"},
                {"Key": "AutoTerminate", "Value": "true"},
            ]}],
        )
        new_id = resp["Instances"][0]["InstanceId"]
        log.info("[CryoSPARC] New instance: %s", new_id)
        # Track so stop_instance() can terminate it
        global _active_instance_id
        _active_instance_id = new_id
        if wait:
            _wait_for_instance_running(ec2, new_id)
        resp2 = ec2.describe_instances(InstanceIds=[new_id])
        ip = resp2["Reservations"][0]["Instances"][0].get("PublicIpAddress", "")
        return ip

    raise RuntimeError("No CRYOSPARC_INSTANCE_ID or CRYOSPARC_AMI_ID set")


def stop_instance() -> None:
    """
    Terminate (not merely stop) the CryoSPARC EC2 instance to save cost.

    We use TERMINATE rather than STOP because:
    - Stopped instances still pay EBS storage (~$40/month for 500 GB)
    - The AMI (ami-008607f719aaac1b0) preserves the full CryoSPARC setup
    - A fresh instance launches from AMI in ~5-8 min when next needed
    - Terminate = $0 until next job; Stop = $40/month for nothing

    The instance ID is read from the module-level _active_instance_id which is
    set by start_instance() when a new instance is launched.
    """
    global _active_instance_id
    instance_id = _active_instance_id or CRYOSPARC_INSTANCE_ID
    if not instance_id:
        log.warning("[CryoSPARC] No active instance ID — nothing to terminate")
        return
    try:
        ec2 = _ec2_client()
        ec2.terminate_instances(InstanceIds=[instance_id])
        log.info("[CryoSPARC] Instance %s terminated (EBS auto-deleted)", instance_id)
        _active_instance_id = ""
    except Exception as exc:
        log.warning("[CryoSPARC] Failed to terminate instance: %s", exc)


def _wait_for_instance_running(ec2, instance_id: str, timeout: int = 300) -> None:
    """Wait until instance is running and SSH is ready."""
    log.info("[CryoSPARC] Waiting for instance %s to be running ...", instance_id)
    deadline = time.time() + timeout
    while time.time() < deadline:
        resp = ec2.describe_instances(InstanceIds=[instance_id])
        state = resp["Reservations"][0]["Instances"][0]["State"]["Name"]
        if state == "running":
            log.info("[CryoSPARC] Instance running. Waiting 30s for SSH/CryoSPARC startup...")
            time.sleep(30)
            return
        time.sleep(10)
    raise TimeoutError(f"Instance {instance_id} did not reach running state in {timeout}s")


def ensure_cryosparc_running(
    progress_callback: Optional[Callable[[int, str], None]] = None
) -> None:
    """
    Ensure the CryoSPARC instance is running before job submission.
    Called at the start of execute_spa_pipeline; shows a 'provisioning' progress event.
    """
    state = get_instance_state()
    if state == "running":
        return  # Already up

    log.info("[CryoSPARC] Instance state=%s — starting...", state)
    if progress_callback:
        progress_callback(0, "Provisioning CryoSPARC compute instance (GPU cold-start ~3-5 min)...")

    new_ip = start_instance(wait=True)

    # Update the global HOST so _connect() uses the current IP
    global CRYOSPARC_HOST
    if new_ip:
        CRYOSPARC_HOST = new_ip
        log.info("[CryoSPARC] Instance IP: %s", CRYOSPARC_HOST)

    # Wait for CryoSPARC API to be ready
    deadline = time.time() + 300
    while time.time() < deadline:
        try:
            _connect()
            log.info("[CryoSPARC] API ready")
            return
        except Exception:
            time.sleep(15)
    raise TimeoutError("CryoSPARC API did not become ready after instance start")


# ---------------------------------------------------------------------------
# Run registry (in-process, mirrors nextflow_executor._runs)
# ---------------------------------------------------------------------------

@dataclass
class CryoSPARCRun:
    run_id: str
    status: str = "queued"          # queued | running | completed | failed
    project_uid: str = ""
    workspace_uid: str = ""
    job_uids: List[str] = field(default_factory=list)
    progress_percent: int = 0
    completed_jobs: int = 0
    total_jobs: int = 0
    error_message: str = ""
    started_at: float = field(default_factory=time.time)
    finished_at: Optional[float] = None
    user_id: str = ""
    params: Dict[str, Any] = field(default_factory=dict)


_cs_runs: Dict[str, CryoSPARCRun] = {}


# ---------------------------------------------------------------------------
# SPA pipeline executor
# ---------------------------------------------------------------------------

def execute_spa_pipeline(
    run_id: str,
    params: Dict[str, Any],
    user_id: str = "",
    progress_callback: Optional[Callable[[int, str], None]] = None,
) -> str:
    """
    Submit a CryoSPARC SPA pipeline for the given parameters.

    Returns the run_id immediately; execution continues in a background thread.

    params expected keys (all optional with defaults):
        movie_dir     — path to EER/TIFF/MRC movies on the CryoSPARC host
        pixel_size    — Å/pixel (default 1.0)
        voltage       — kV (default 300)
        cs            — Cs in mm (default 2.7)
        amplitude_contrast — (default 0.1)
        particle_diameter — Å (default 180)
        symmetry      — point group (default C1)
        num_movies    — expected count (informational only)
    """
    import threading

    run = CryoSPARCRun(run_id=run_id, status="queued", user_id=user_id, params=params)
    _cs_runs[run_id] = run

    def _run():
        try:
            _execute_spa_pipeline_sync(run, progress_callback)
        except Exception as exc:
            log.error("[CryoSPARC] Run %s failed: %s", run_id, traceback.format_exc())
            run.status = "failed"
            run.error_message = str(exc)
            run.finished_at = time.time()
            # Auto-stop on failure too — don't leave GPU running on error
            auto_stop_mins = int(os.environ.get("AUTO_STOP_AFTER_MINUTES", "5"))
            if auto_stop_mins > 0:
                log.info("[CryoSPARC] Auto-stopping instance after failure in %d min...", auto_stop_mins)
                time.sleep(auto_stop_mins * 60)
                stop_instance()

    thread = threading.Thread(target=_run, daemon=True, name=f"cryosparc-{run_id[:8]}")
    thread.start()
    return run_id


def _progress(run: CryoSPARCRun, pct: int, msg: str,
               cb: Optional[Callable[[int, str], None]]) -> None:
    run.progress_percent = pct
    log.info("[CryoSPARC:%s] %d%% — %s", run.run_id[:8], pct, msg)
    if cb:
        try:
            cb(pct, msg)
        except Exception:
            pass


def _execute_spa_pipeline_sync(
    run: CryoSPARCRun,
    cb: Optional[Callable[[int, str], None]],
) -> None:
    params = run.params
    run.status = "running"

    # Step 0: Ensure instance is running (starts it if stopped), then connect
    ensure_cryosparc_running(cb)
    _progress(run, 1, "Connecting to CryoSPARC...", cb)
    cs = _connect()

    # Step 1: Create project + workspace
    _progress(run, 2, "Creating project workspace...", cb)
    proj = cs.api.projects.create(
        title=f"biomate-{run.run_id[:8]}",
        parent_dir=CRYOSPARC_PROJECT_DIR,
    )
    run.project_uid = proj.uid
    log.info("[CryoSPARC] Project: %s at %s", proj.uid, proj.project_dir)

    ws = cs.create_workspace(project_uid=proj.uid, title="W1-spa")
    run.workspace_uid = ws.uid
    log.info("[CryoSPARC] Workspace: %s", ws.uid)

    # Determine movie directory
    movie_dir = params.get("movie_dir") or params.get("data_dir")
    if not movie_dir:
        raise ValueError(
            "No movie_dir provided. Set params.movie_dir to the path of EER/TIFF/MRC movies "
            "on the CryoSPARC host."
        )

    # Step 2: Import movies
    _progress(run, 5, "Importing movies...", cb)
    import_params = {
        "blob_paths": str(Path(movie_dir) / "*.eer"),
        "psize_A": float(params.get("pixel_size", 1.0)),
        "accel_kv": float(params.get("voltage", 300)),
        "cs_mm": float(params.get("cs", 2.7)),
        "amp_contrast": float(params.get("amplitude_contrast", 0.1)),
        "total_dose_e_per_A2": float(params.get("total_dose", 40.0)),
    }
    import_job = cs.create_job(
        project_uid=proj.uid,
        workspace_uid=ws.uid,
        type=_IMPORT_JOB,
        params=import_params,
        title="Import Movies",
    )
    run.job_uids.append(import_job.uid)
    log.info("[CryoSPARC] Import job: %s", import_job.uid)
    import_job.queue(lane="default")

    _wait_for_job(import_job, run, cb, target_pct=20, step_name="Import Movies")

    # Reload job to get output datasets
    import_job = cs.find_job(proj.uid, import_job.uid)
    movies_dataset = import_job.load_output("imported_movies")
    log.info("[CryoSPARC] Imported %d movies", len(movies_dataset))

    # Step 3: Patch motion correction
    _progress(run, 22, "Starting motion correction...", cb)
    motion_job = cs.create_job(
        project_uid=proj.uid,
        workspace_uid=ws.uid,
        type=_MOTION_JOB,
        connections={"movies": (import_job.uid, "imported_movies")},
        params={},
        title="Patch Motion Correction",
    )
    run.job_uids.append(motion_job.uid)
    motion_job.queue(lane="default")

    _wait_for_job(motion_job, run, cb, target_pct=50, step_name="Motion Correction")

    motion_job = cs.find_job(proj.uid, motion_job.uid)
    micrographs_dataset = motion_job.load_output("micrographs")
    log.info("[CryoSPARC] Motion corrected %d micrographs", len(micrographs_dataset))

    # Step 4: Patch CTF estimation
    _progress(run, 52, "Starting CTF estimation...", cb)
    ctf_job = cs.create_job(
        project_uid=proj.uid,
        workspace_uid=ws.uid,
        type=_CTF_JOB,
        connections={"micrographs": (motion_job.uid, "micrographs")},
        params={},
        title="Patch CTF Estimation",
    )
    run.job_uids.append(ctf_job.uid)
    ctf_job.queue(lane="default")

    _wait_for_job(ctf_job, run, cb, target_pct=70, step_name="CTF Estimation")

    # Done (future: particle picking, 2D/3D classification, refinement)
    _progress(run, 100, "Pipeline complete (import → motion → CTF)", cb)
    run.status = "completed"
    run.finished_at = time.time()
    log.info("[CryoSPARC] Run %s completed in %.1fs",
             run.run_id, run.finished_at - run.started_at)

    # Auto-stop instance to save cost (GPU costs ~$0.98/hr when idle)
    auto_stop_mins = int(os.environ.get("AUTO_STOP_AFTER_MINUTES", "5"))
    if auto_stop_mins > 0:
        log.info("[CryoSPARC] Auto-stopping instance in %d minutes...", auto_stop_mins)
        time.sleep(auto_stop_mins * 60)
        stop_instance()


def _wait_for_job(
    job,
    run: CryoSPARCRun,
    cb: Optional[Callable],
    target_pct: int,
    step_name: str,
    poll_interval: int = 10,
    timeout: int = 7200,
) -> None:
    """Poll job until completed/failed; update progress linearly toward target_pct."""
    start_pct = run.progress_percent
    deadline = time.time() + timeout
    while time.time() < deadline:
        job.refresh()
        status = job.status
        if status == "completed":
            _progress(run, target_pct, f"{step_name} complete", cb)
            return
        if status in ("failed", "killed"):
            raise RuntimeError(f"CryoSPARC job {job.uid} ({step_name}) {status}")
        # Linear interpolation toward target while running
        elapsed_frac = min(1.0, (time.time() - run.started_at) / 3600.0)
        pct = int(start_pct + (target_pct - start_pct) * elapsed_frac * 0.8)
        _progress(run, pct, f"{step_name}: {status}", cb)
        time.sleep(poll_interval)
    raise TimeoutError(f"CryoSPARC job {job.uid} ({step_name}) timed out after {timeout}s")


# ---------------------------------------------------------------------------
# Status endpoint helpers (mirrors nextflow_executor status format)
# ---------------------------------------------------------------------------

def get_run_status(run_id: str) -> Optional[Dict[str, Any]]:
    run = _cs_runs.get(run_id)
    if not run:
        return None
    return {
        "run_id": run.run_id,
        "status": run.status,
        "progress_percent": run.progress_percent,
        "completed_jobs": run.completed_jobs,
        "total_jobs": run.total_jobs,
        "error_message": run.error_message or None,
        "project_uid": run.project_uid,
        "workspace_uid": run.workspace_uid,
        "job_uids": run.job_uids,
        "executor": "cryosparc",
        "is_batch": False,  # CryoSPARC manages its own compute
    }


def list_runs() -> List[Dict[str, Any]]:
    return [get_run_status(rid) for rid in _cs_runs]
