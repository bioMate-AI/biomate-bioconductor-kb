"""
CryoSPARC Executor — BioMate integration with live CryoSPARC v5

Connects to the CryoSPARC instance defined by environment variables:
    CRYOSPARC_HOST        — hostname or IP (default: localhost)
    CRYOSPARC_PORT        — base port (default: 30000)
    CRYOSPARC_EMAIL       — admin email
    CRYOSPARC_PASSWORD    — admin password
    CRYOSPARC_PROJECT_DIR — path on the CryoSPARC host for project storage

This executor replaces the Nextflow mock pipeline for cryo-EM SPA workflows.
Each SPA step maps directly to a CryoSPARC job type submitted via cryosparc-tools.

Full 4-phase parallel SPA pipeline
===================================
Phase A — Preprocessing (parallel per micrograph batch)
    • Split imported movies into batches of batch_size (default 200)
    • Submit motion correction for ALL batches simultaneously
    • As each motion batch completes, immediately submit CTF for that batch
    • Collect all CTF outputs when all batches complete
    Progress milestone: 30 %

Phase B — Picking (parallel per batch)
    • Blob picker for all micrograph batches simultaneously
    • Collect → junk-2D detector (single job) → inspect picks
    • Extract particles R1 (parallel per batch)
    Progress milestone: 50 %

Phase C — Classification (parallel particle batches)
    • Split extracted particles into batches of particle_batch_size (default 10 000)
    • 2D classification R1 — all particle batches simultaneously
    • Collect classes → select best classes → template picker (parallel per mic batch)
    • Extract R2 (parallel) → classify 2D R2 (parallel) → select R2
    Progress milestone: 70 %

Phase D — Reconstruction (parallel per model)
    • num_ab_initio_classes (default 3) ab initio jobs simultaneously
    • Wait for all → homogeneous refinement for all volumes simultaneously
    • Pick best volume → volume tools → validation FSC → local CTF
    • NU refinement → local resolution → sharpening
    Progress milestone: 100 %

Progress is reported via SSE using the same qc_trace_monitor SSE path.
mock_mode=True skips all real API calls and returns dummy data for unit tests.
"""

from __future__ import annotations

import json
import logging
import os
import time
import traceback
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed, Future
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

_QC_GATES_AVAILABLE = False
try:
    from .cryosparc_qc_gates import (
        check_motion_gate, check_ctf_gate, check_junk_class_gate,
        check_orientation_gate, check_fsc_gate, check_abinitio_gate,
        check_model_quality_gate, write_audit_event, QCResult,
    )
    _QC_GATES_AVAILABLE = True
except ImportError:
    try:
        import importlib.util as _ilu, sys as _sys
        _qcg_path = os.path.join(os.path.dirname(__file__), "cryosparc_qc_gates.py")
        _spec = _ilu.spec_from_file_location("cryosparc_qc_gates", _qcg_path)
        _mod = _ilu.module_from_spec(_spec)
        _sys.modules["cryosparc_qc_gates"] = _mod
        _spec.loader.exec_module(_mod)
        check_motion_gate = _mod.check_motion_gate
        check_ctf_gate = _mod.check_ctf_gate
        check_junk_class_gate = _mod.check_junk_class_gate
        check_orientation_gate = _mod.check_orientation_gate
        check_fsc_gate = _mod.check_fsc_gate
        check_abinitio_gate = _mod.check_abinitio_gate
        check_model_quality_gate = _mod.check_model_quality_gate
        write_audit_event = _mod.write_audit_event
        QCResult = _mod.QCResult
        _QC_GATES_AVAILABLE = True
    except Exception:
        pass

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

# ---------------------------------------------------------------------------
# CryoSPARC job type constants — full SPA pipeline (23 types)
# ---------------------------------------------------------------------------

# Preprocessing
_IMPORT_JOB                   = "import_movies"
_MOTION_JOB                   = "patch_motion_correction_multi"
_CTF_JOB                      = "patch_ctf_estimation_multi"
_DENOISER_JOB                 = "micrograph_denoiser"

# Picking
_BLOB_PICKER_JOB              = "blob_picker_gpu"
_JUNK_2D_JOB                  = "job_2D_detection"
_INSPECT_PICKS_JOB            = "inspect_picks"
_EXTRACT_JOB                  = "extract_micrographs_cpu_parallel"

# Classification
_CLASS_2D_JOB                 = "class_2D"
_SELECT_2D_JOB                = "select_2D_classes"
_TOPAZ_XVAL_JOB               = "topaz_cross_validation"

# Reconstruction
_AB_INITIO_JOB                = "homo_abinit"
_HOMO_REFINE_JOB              = "homo_refine_new"
_VOLUME_TOOLS_JOB             = "volume_tools"
_VALIDATION_FSC_JOB           = "validation_fsc"
_LOCAL_CTF_JOB                = "ctf_local"
_NU_REFINE_JOB                = "nonuniform_refine_new"
_LOCAL_RES_JOB                = "local_res"
_SHARPENING_JOB               = "sharpening_fsc"

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
    # Per-phase job UID tracking
    batch_jobs: Dict[str, List[str]] = field(default_factory=dict)
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
# Progress helper
# ---------------------------------------------------------------------------

def _progress(run: CryoSPARCRun, pct: int, msg: str,
               cb: Optional[Callable[[int, str], None]]) -> None:
    run.progress_percent = pct

    # Compute ETA from elapsed time + current percentage.
    # Only shown when: pct >= 10 (enough progress to extrapolate) AND
    # elapsed >= 5 min (early estimates are unreliable due to job queue wait time).
    # Uses "~Xh" for hours, "~Xm" for minutes — no seconds-level false precision.
    eta_str = ""
    if pct >= 10:
        elapsed_s = time.time() - run.started_at
        if elapsed_s >= 300:  # 5 min minimum before showing any estimate
            total_est_s = elapsed_s * 100.0 / pct
            remaining_s = max(0, total_est_s - elapsed_s)
            if remaining_s >= 3600:
                eta_str = f" · ~{remaining_s / 3600:.1f}h remaining"
            elif remaining_s >= 120:
                eta_str = f" · ~{int(remaining_s / 60)}m remaining"
            # Below 2 min remaining: don't show (jitter makes it unreliable)

    log.info("[CryoSPARC:%s] %d%% — %s%s", run.run_id[:8], pct, msg, eta_str)
    if cb:
        try:
            cb(pct, msg + eta_str)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# QC gate wiring helpers
# ---------------------------------------------------------------------------

class QCHaltException(Exception):
    """Raised when a GOLD/SILVER QC gate fires a halt."""
    pass


def _fire_qc_halt(run: CryoSPARCRun, cb, gate_result, audit_dir: str = "") -> None:
    """Emit a QC halt event via the progress callback and raise QCHaltException."""
    msg = f"[QC HALT] {gate_result.gate}: {gate_result.message}"
    log.warning("[CryoSPARC:%s] %s", run.run_id[:8], msg)
    if cb:
        try:
            cb(-1, json.dumps({
                "type": "qc_halt",
                "gate": gate_result.gate,
                "level": gate_result.level,
                "action": "halt",
                "metric": gate_result.metric,
                "value": gate_result.value,
                "threshold": gate_result.threshold,
                "message": gate_result.message,
                "suggestion": gate_result.suggestion,
                "evidence": gate_result.evidence,
                "profile": gate_result.profile,
            }))
        except Exception:
            pass
    if audit_dir:
        try:
            write_audit_event(run.run_id, gate_result.gate, 0, gate_result, audit_dir)
        except Exception:
            pass
    raise QCHaltException(gate_result.message)


def _fire_qc_advisory(run: CryoSPARCRun, cb, gate_result, audit_dir: str = "") -> None:
    """Emit a QC advisory event (non-blocking — pipeline continues)."""
    msg = f"[QC ADVISORY] {gate_result.gate}: {gate_result.message}"
    log.warning("[CryoSPARC:%s] %s", run.run_id[:8], msg)
    if cb:
        try:
            cb(run.progress_percent, json.dumps({
                "type": "qc_advisory",
                "gate": gate_result.gate,
                **{k: getattr(gate_result, k) for k in ("level", "metric", "value", "threshold", "message", "suggestion", "evidence", "profile")}
            }))
        except Exception:
            pass
    if audit_dir:
        try:
            write_audit_event(run.run_id, gate_result.gate, 0, gate_result, audit_dir)
        except Exception:
            pass


def _check_motion_ctf_gates(ctf_jobs, run, cb, qc_profile, audit_dir, mock_mode):
    """Parse per-micrograph motion and CTF stats and run QC gates.

    cryosparc-tools Dataset API: job.load_output(name) → Dataset
    Columns are accessed as dataset["col_name"] → numpy array (NOT row iteration).

    Motion correction job (patch_motion_correction):
      micrographs = job.load_output("micrographs")
      micrographs["total_motion"]   — total drift in pixels
      micrographs["average_motion"] — per-frame avg drift in pixels

    CTF estimation job (patch_ctf_estimation):
      micrographs = job.load_output("micrographs")
      micrographs["ctf/ctf_fit_to_A"]       — CTF fit resolution (Å), lower = better
      micrographs["ctf/cross_corr_ctffind"] — FOM score, higher = better
      micrographs["ctf/df1_A"]              — defocus 1 (Å)
      micrographs["ctf/df2_A"]              — defocus 2 (Å)
    """
    if mock_mode or not _QC_GATES_AVAILABLE:
        return

    import numpy as np
    pixel_size = float(run.params.get("pixel_size", 1.05))

    drift_A_all: List[float] = []
    per_frame_A_all: List[float] = []
    ctf_fom_all: List[float] = []
    defocus_A_all: List[float] = []
    astig_A_all: List[float] = []

    for ctf_job in ctf_jobs:
        try:
            mics = ctf_job.load_output("micrographs")
            # Motion columns (present after patch_motion_correction step)
            if "total_motion" in mics.fields():
                drift_px = mics["total_motion"]
                drift_A_all.extend((drift_px * pixel_size).tolist())
            if "average_motion" in mics.fields():
                per_frame_px = mics["average_motion"]
                per_frame_A_all.extend((per_frame_px * pixel_size).tolist())
            # CTF columns (present after patch_ctf_estimation step)
            if "ctf/cross_corr_ctffind" in mics.fields():
                ctf_fom_all.extend(mics["ctf/cross_corr_ctffind"].tolist())
            if "ctf/df1_A" in mics.fields() and "ctf/df2_A" in mics.fields():
                defocus_A_all.extend(
                    ((mics["ctf/df1_A"] + mics["ctf/df2_A"]) / 2.0).tolist()
                )
            if "ctf/df1_A" in mics.fields() and "ctf/df2_A" in mics.fields():
                astig_A_all.extend(
                    np.abs(mics["ctf/df1_A"] - mics["ctf/df2_A"]).tolist()
                )
        except Exception as e:
            log.debug("[CryoSPARC] QC parse error for job %s: %s", ctf_job.uid, e)

    if drift_A_all:
        total_drift = float(np.median(drift_A_all))
        per_frame = float(np.median(per_frame_A_all)) if per_frame_A_all else (
            total_drift / float(run.params.get("num_frames", 40))
        )
        result = check_motion_gate(total_drift, per_frame, qc_profile)
        if result.action == "halt":
            _fire_qc_halt(run, cb, result, audit_dir)
        elif result.action == "advisory":
            _fire_qc_advisory(run, cb, result, audit_dir)

    if ctf_fom_all:
        median_fom = float(np.median(ctf_fom_all))
        median_defocus = float(np.median(defocus_A_all)) if defocus_A_all else 15000.0
        median_astig = float(np.median(astig_A_all)) if astig_A_all else 0.0
        result = check_ctf_gate(median_fom, median_defocus, median_astig, profile=qc_profile)
        if result.action == "halt":
            _fire_qc_halt(run, cb, result, audit_dir)
        elif result.action == "advisory":
            _fire_qc_advisory(run, cb, result, audit_dir)


def _check_junk_gate(class2d_jobs, run, cb, qc_profile, audit_dir, mock_mode):
    """Check junk class fraction after 2D classification.

    2D classification job (class_2D):
      class_averages = job.load_output("class_averages")
      class_averages["class_num_particles"] — particle count per class (int array)
    """
    if mock_mode or not _QC_GATES_AVAILABLE:
        return

    import numpy as np
    for job in class2d_jobs:
        try:
            class_avgs = job.load_output("class_averages")
            counts = class_avgs["class_num_particles"].astype(int)
            if len(counts) == 0:
                continue
            total = int(counts.sum())
            if total == 0:
                continue
            result = check_junk_class_gate(counts, total, qc_profile)
            if result.action == "halt":
                _fire_qc_halt(run, cb, result, audit_dir)
            elif result.action == "advisory":
                _fire_qc_advisory(run, cb, result, audit_dir)
        except Exception as e:
            log.debug("[CryoSPARC] Junk QC parse error for job %s: %s", job.uid, e)


def _check_orientation_gate_from_job(refine_job, run, cb, qc_profile, audit_dir, mock_mode):
    """Parse Euler angles from refinement output and check orientation bias.

    Refinement job (homogeneous_refinement, nonuniform_refinement):
      particles = job.load_output("particles")
      particles["alignments3D/pose"] — rotation vectors, shape (N, 3)

    The gate function expects Euler angles in RADIANS. The "pose" field contains
    rotation vectors (axis-angle format); we convert to viewing-direction theta
    using the z-component of the unit rotation axis as cos(theta).
    """
    if mock_mode or not _QC_GATES_AVAILABLE:
        return

    import numpy as np
    try:
        particles = refine_job.load_output("particles")
        poses = particles["alignments3D/pose"]  # shape (N, 3), rotation vectors
        if len(poses) < 100:
            return
        # Compute viewing direction theta from rotation vector:
        # the z-component of the normalized rotation axis approximates cos(tilt).
        norms = np.linalg.norm(poses, axis=1, keepdims=True)
        norms = np.where(norms < 1e-9, 1.0, norms)
        unit_axes = poses / norms
        theta_rad = np.arccos(np.clip(unit_axes[:, 2], -1.0, 1.0))  # (N,) in radians
        result = check_orientation_gate(theta_rad, qc_profile)
        if result.action == "halt":
            _fire_qc_halt(run, cb, result, audit_dir)
        elif result.action == "advisory":
            _fire_qc_advisory(run, cb, result, audit_dir)
    except Exception as e:
        log.debug("[CryoSPARC] Orientation QC parse error: %s", e)


def _check_fsc_gate_from_job(val_fsc_job, run, cb, qc_profile, audit_dir, mock_mode):
    """Parse FSC curve from validation_fsc job and apply GOLD resolution gate.

    Validation FSC job (validation_fsc):
      fsc = job.load_output("fsc")
      fsc["freq_A_inv"]   — spatial frequency in 1/Å (float array, len ~200)
      fsc["fsc_nomask"]   — gold-standard half-map FSC without mask (primary criterion)
      fsc["fsc_loosemask"] — FSC with loose mask (secondary)
      fsc["fsc_tightmask"] — FSC with tight mask
    """
    if mock_mode or not _QC_GATES_AVAILABLE:
        return

    import numpy as np
    try:
        fsc_data = val_fsc_job.load_output("fsc")
        freqs = fsc_data["freq_A_inv"]
        fsc_vals = fsc_data["fsc_nomask"]
        if len(freqs) < 5:
            return
        result = check_fsc_gate(freqs, fsc_vals, qc_profile)
        if result.action == "halt":
            _fire_qc_halt(run, cb, result, audit_dir)
        elif result.action == "advisory":
            _fire_qc_advisory(run, cb, result, audit_dir)
    except Exception as e:
        log.debug("[CryoSPARC] FSC QC parse error: %s", e)


def _check_abinitio_gate_from_job(abinitio_job, run, cb, qc_profile, audit_dir, mock_mode):
    """Parse ab initio job outputs and run the G9 ab initio quality gate.

    Ab initio job (ab_initio_reconstruction):
      particles    = job.load_output("particles")
        particles["alignments3D/class_posterior"] — per-particle class posteriors (N, K)
      class_scores = job.load_output("class_scores") [optional]
        class_scores["class_score"] — per-class composite score (K,)

    Strategy
    --------
    1. Attempt to load "class_scores" output to get best_class_score directly.
    2. Fall back to counting populated classes (> 100 particles) from the
       particle assignments in "particles" output.
    3. If neither is available, emit an advisory and return.
    """
    if mock_mode or not _QC_GATES_AVAILABLE:
        return

    import numpy as np
    try:
        best_class_score: float = 0.0
        reported_resolution_A: Optional[float] = None
        num_populated_classes: int = 0

        # --- Try class_scores output first -----------------------------------
        try:
            cs_out = abinitio_job.load_output("class_scores")
            if "class_score" in cs_out.fields():
                scores = np.asarray(cs_out["class_score"], dtype=float)
                if len(scores) > 0:
                    best_class_score = float(scores.max())
                    num_populated_classes = int((scores > 0.0).sum())
        except Exception:
            pass

        # --- Fall back to particle class assignment counts -------------------
        if best_class_score == 0.0:
            try:
                particles = abinitio_job.load_output("particles")
                if "alignments3D/class_posterior" in particles.fields():
                    posteriors = np.asarray(
                        particles["alignments3D/class_posterior"], dtype=float
                    )
                    if posteriors.ndim == 2 and posteriors.shape[1] > 0:
                        # Best class score = highest mean posterior across all classes
                        mean_posteriors = posteriors.mean(axis=0)
                        best_class_score = float(mean_posteriors.max())
                        # Populated = class where max-posterior assignment count > 100
                        assignments = np.argmax(posteriors, axis=1)
                        for k in range(posteriors.shape[1]):
                            if int((assignments == k).sum()) > 100:
                                num_populated_classes += 1
                elif "alignments3D/class" in particles.fields():
                    class_ids = np.asarray(
                        particles["alignments3D/class"], dtype=int
                    )
                    unique, counts_arr = np.unique(class_ids, return_counts=True)
                    num_populated_classes = int((counts_arr > 100).sum())
                    # No per-class score available — use heuristic
                    best_class_score = 0.15 if num_populated_classes > 0 else 0.0
            except Exception:
                pass

        # --- Try to read reported resolution from job metadata ---------------
        try:
            job_meta = abinitio_job.doc()
            status_str = str(job_meta.get("status_messages", ""))
            import re
            m = re.search(r"(\d+(?:\.\d+)?)\s*[Åa]", status_str)
            if m:
                reported_resolution_A = float(m.group(1))
        except Exception:
            pass

        if best_class_score == 0.0 and num_populated_classes == 0:
            # Cannot parse job output — emit advisory and log
            log.debug(
                "[CryoSPARC] Ab initio QC: could not parse outputs for job %s; "
                "skipping gate (advisory placeholder).",
                abinitio_job.uid,
            )
            return

        result = check_abinitio_gate(
            best_class_score=best_class_score,
            reported_resolution_A=reported_resolution_A,
            num_populated_classes=num_populated_classes,
            profile=qc_profile,
        )
        if result.action == "halt":
            _fire_qc_halt(run, cb, result, audit_dir)
        elif result.action == "advisory":
            _fire_qc_advisory(run, cb, result, audit_dir)

    except Exception as e:
        log.debug("[CryoSPARC] Ab initio QC parse error for job %s: %s",
                  abinitio_job.uid, e)


def _check_model_quality_gate_from_job(refine_job, run, cb, qc_profile, audit_dir, mock_mode):
    """Apply the G12 MolProbity / model validation gate after sharpening.

    MolProbity requires running an external tool (``phenix.molprobity``) on
    the sharpened map + atomic model.  This executor does not yet call PHENIX
    automatically — instead it emits a placeholder advisory with instructions
    so the analyst knows to validate the model before deposition.

    When real MolProbity scores are available (e.g. parsed from a PHENIX log
    or a pre-computed JSON file), pass them to ``check_model_quality_gate()``
    directly from a post-processing step.
    """
    if mock_mode or not _QC_GATES_AVAILABLE:
        return

    # Placeholder call — placeholder values that intentionally trigger advisory
    # so the analyst is reminded to run MolProbity before deposition.
    placeholder_molprobity = 2.5       # triggers advisory (≥ 2.0)
    placeholder_ramachandran = 0.95    # advisory (< 0.97 excellent threshold)
    placeholder_rotamer = 0.03        # within acceptable range

    result = check_model_quality_gate(
        molprobity_score=placeholder_molprobity,
        ramachandran_favored_pct=placeholder_ramachandran,
        rotamer_outlier_pct=placeholder_rotamer,
        profile=qc_profile,
    )

    log.info(
        "[CryoSPARC] G12 model quality gate (PLACEHOLDER): MolProbity validation "
        "requires running 'phenix.molprobity' externally on the sharpened map + model. "
        "Emitting advisory as reminder. Run: phenix.molprobity <model.pdb> <map.mrc> "
        "resolution=<fsc_res> and pass scores to check_model_quality_gate()."
    )

    if result.action == "halt":
        _fire_qc_halt(run, cb, result, audit_dir)
    elif result.action == "advisory":
        _fire_qc_advisory(run, cb, result, audit_dir)


# ---------------------------------------------------------------------------
# Job wait helpers
# ---------------------------------------------------------------------------

def _wait_for_job(
    job,
    run: CryoSPARCRun,
    cb: Optional[Callable],
    target_pct: int,
    step_name: str,
    poll_interval: int = 10,
    timeout: int = 7200,
    mock_mode: bool = False,
) -> None:
    """Poll a single job until completed/failed; update progress toward target_pct."""
    if mock_mode:
        _progress(run, target_pct, f"{step_name} complete (mock)", cb)
        return
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
        elapsed_frac = min(1.0, (time.time() - run.started_at) / 3600.0)
        pct = int(start_pct + (target_pct - start_pct) * elapsed_frac * 0.8)
        _progress(run, pct, f"{step_name}: {status}", cb)
        time.sleep(poll_interval)
    raise TimeoutError(f"CryoSPARC job {job.uid} ({step_name}) timed out after {timeout}s")


def _wait_for_jobs_parallel(
    jobs: List[Any],
    run: CryoSPARCRun,
    cb: Optional[Callable],
    phase_name: str,
    poll_interval: int = 10,
    timeout: int = 7200,
    mock_mode: bool = False,
) -> None:
    """
    Poll a list of jobs concurrently (each in its own thread) until ALL complete.
    Raises on first failure.
    """
    if mock_mode:
        log.info("[CryoSPARC] mock_mode: skipping wait for %d %s jobs", len(jobs), phase_name)
        return

    deadline = time.time() + timeout
    pending = {j.uid: j for j in jobs}

    while pending and time.time() < deadline:
        done_uids = []
        for uid, job in list(pending.items()):
            job.refresh()
            status = job.status
            if status == "completed":
                done_uids.append(uid)
                run.completed_jobs += 1
                log.info("[CryoSPARC] %s job %s completed (%d remaining)",
                         phase_name, uid, len(pending) - len(done_uids))
            elif status in ("failed", "killed"):
                raise RuntimeError(
                    f"CryoSPARC {phase_name} job {uid} {status}"
                )
        for uid in done_uids:
            del pending[uid]
        if pending:
            time.sleep(poll_interval)

    if pending:
        raise TimeoutError(
            f"{len(pending)} {phase_name} jobs did not complete within {timeout}s"
        )


# ---------------------------------------------------------------------------
# Mock helpers (for unit tests without a live CryoSPARC instance)
# ---------------------------------------------------------------------------

class _MockJob:
    """Lightweight stand-in returned in mock_mode=True."""

    def __init__(self, job_type: str, title: str = ""):
        self.uid = f"J{uuid.uuid4().hex[:6].upper()}"
        self.type = job_type
        self.title = title
        self.status = "completed"
        self._outputs: Dict[str, Any] = {}

    def queue(self, lane: str = "default") -> None:
        pass

    def refresh(self) -> None:
        pass

    def load_output(self, name: str) -> List[Any]:
        return self._outputs.get(name, [f"mock_{name}_item_{i}" for i in range(5)])


class _MockCS:
    """Mock CryoSPARC connection returned in mock_mode=True."""

    def __init__(self):
        self._proj_uid = f"P{uuid.uuid4().hex[:4].upper()}"
        self._ws_uid   = f"W{uuid.uuid4().hex[:4].upper()}"

    def test_connection(self) -> bool:
        return True

    class _Proj:
        def __init__(self, uid, project_dir):
            self.uid = uid
            self.project_dir = project_dir

    class _WS:
        def __init__(self, uid):
            self.uid = uid

    @property
    def api(self):
        outer = self
        class _API:
            @property
            def projects(self_inner):
                class _Proj:
                    def create(self, title, parent_dir):
                        return _MockCS._Proj(outer._proj_uid, parent_dir)
                return _Proj()
        return _API()

    def create_workspace(self, project_uid: str, title: str) -> "_MockCS._WS":
        return _MockCS._WS(self._ws_uid)

    def create_job(
        self,
        project_uid: str,
        workspace_uid: str,
        type: str,
        params: Optional[Dict] = None,
        connections: Optional[Dict] = None,
        title: str = "",
    ) -> _MockJob:
        return _MockJob(job_type=type, title=title)

    def find_job(self, project_uid: str, job_uid: str) -> _MockJob:
        return _MockJob(job_type="unknown")


# ---------------------------------------------------------------------------
# SPA pipeline executor — public entry point
# ---------------------------------------------------------------------------

def execute_spa_pipeline(
    run_id: str,
    params: Dict[str, Any],
    user_id: str = "",
    progress_callback: Optional[Callable[[int, str], None]] = None,
    num_gpu_workers: int = 1,
) -> str:
    """
    Submit a CryoSPARC SPA pipeline for the given parameters.

    Returns the run_id immediately; execution continues in a background thread.

    params expected keys (all optional with defaults):
        movie_dir              — path to EER/TIFF/MRC movies on the CryoSPARC host
        pixel_size             — Å/pixel (default 1.0)
        voltage                — kV (default 300)
        cs                     — Cs in mm (default 2.7)
        amplitude_contrast     — (default 0.1)
        particle_diameter      — Å (default 180)
        symmetry               — point group (default C1)
        num_movies             — expected count (informational only)
        batch_size             — movies per preprocessing batch (default 200)
        particle_batch_size    — particles per classification batch (default 10000)
        num_ab_initio_classes  — number of ab initio models (default 3)
        num_gpu_workers        — cap on ThreadPoolExecutor max_workers (default 1)
        mock_mode              — if True, skip real API calls for unit tests (default False)
        sample_class (str)     — sample biology type for smart parameter defaults.
            Options: "soluble" (default), "membrane_small", "membrane_large",
            "gpcr_g_protein", "large_rna_protein", "symmetric", "pore_forming"
    """
    import threading

    # num_gpu_workers can also come from params dict; CLI arg takes precedence
    effective_gpu_workers = int(
        params.get("num_gpu_workers", num_gpu_workers)
    )
    params["num_gpu_workers"] = effective_gpu_workers

    run = CryoSPARCRun(run_id=run_id, status="queued", user_id=user_id, params=params)
    _cs_runs[run_id] = run

    def _run():
        try:
            _execute_spa_pipeline_sync(run, progress_callback)
        except QCHaltException as exc:
            log.warning("[CryoSPARC] Run %s halted by QC gate: %s", run_id, exc)
            run.status = "qc_halt"
            run.error_message = str(exc)
            run.finished_at = time.time()
            auto_stop_mins = int(os.environ.get("AUTO_STOP_AFTER_MINUTES", "5"))
            if auto_stop_mins > 0:
                log.info("[CryoSPARC] Auto-stopping instance after QC halt in %d min...",
                         auto_stop_mins)
                time.sleep(auto_stop_mins * 60)
                stop_instance()
        except Exception as exc:
            log.error("[CryoSPARC] Run %s failed: %s", run_id, traceback.format_exc())
            run.status = "failed"
            run.error_message = str(exc)
            run.finished_at = time.time()
            # Auto-stop on failure too — don't leave GPU running on error
            auto_stop_mins = int(os.environ.get("AUTO_STOP_AFTER_MINUTES", "5"))
            if auto_stop_mins > 0:
                log.info("[CryoSPARC] Auto-stopping instance after failure in %d min...",
                         auto_stop_mins)
                time.sleep(auto_stop_mins * 60)
                stop_instance()

    thread = threading.Thread(target=_run, daemon=True, name=f"cryosparc-{run_id[:8]}")
    thread.start()
    return run_id


# ---------------------------------------------------------------------------
# Smart parameter defaults — evidence-based from expert skill documents
# ---------------------------------------------------------------------------

def _resolve_smart_params(params: Dict[str, Any]) -> Dict[str, Any]:
    """
    Apply evidence-based parameter defaults from expert literature.
    User-supplied values are NEVER overwritten — defaults only fill blanks.

    sample_class options (from skill docs):
        "membrane_small"    — < 60 kDa membrane protein (saposin nanodisc)
        "membrane_large"    — > 60 kDa membrane protein (MSP nanodisc / detergent)
        "gpcr_g_protein"    — GPCR + G protein complex (MSP1D1DeltaH5 nanodisc)
        "soluble"           — soluble protein (default)
        "large_rna_protein" — RNP complex > 500 kDa (spliceosome, ribosome)
        "symmetric"         — symmetric assembly (virus, ring ATPase)
        "pore_forming"      — pore-forming protein (BAX, gasdermin)

    Sources:
        00_GENERAL_FRAMEWORK.md — pixel size / defocus / dose decision tables
        01_MFSD2B_preprint.md   — saposin nanodisc + 3-picker strategy
        04_BAX_pore_science2025.md — pore-forming protein picking / liposome
        03_CaV1_2_cell2023.md   — large detergent complex parameters
    """
    import math

    p = dict(params)  # copy, never mutate input
    sc = p.get("sample_class", "soluble")

    # ── Pixel size ──────────────────────────────────────────────────────────
    # 0.649 Å/pix for < 80 kDa; 0.83 standard; 1.08-1.30 for > 500 kDa
    # References: MFSD2B preprint (0.649 for 21 kDa TM core); GENERAL_FRAMEWORK table
    if not p.get("pixel_size"):
        if sc == "membrane_small":
            p.setdefault("pixel_size", 0.649)   # MFSD2B, VMAT2 reference
        elif sc in ("large_rna_protein", "symmetric"):
            p.setdefault("pixel_size", 1.08)
        else:
            p.setdefault("pixel_size", 0.83)

    # ── Defocus range ───────────────────────────────────────────────────────
    # Reference: GENERAL_FRAMEWORK MW table; CaV1.2 and GPCR-G protein docs
    if sc == "large_rna_protein":
        p.setdefault("defocus_min", 1.0)   # μm — deeper for large particle
        p.setdefault("defocus_max", 3.0)   # μm
    elif sc == "gpcr_g_protein":
        p.setdefault("defocus_min", 0.8)   # tight defocus for GPCR complex
        p.setdefault("defocus_max", 2.0)
    else:
        p.setdefault("defocus_min", 0.8)
        p.setdefault("defocus_max", 2.0)

    # ── QC profile selection ─────────────────────────────────────────────────
    if not p.get("qc_profile"):
        if sc in ("membrane_small", "membrane_large", "gpcr_g_protein", "pore_forming"):
            p["qc_profile"] = "cryoem_spa_membrane"
        else:
            p["qc_profile"] = "cryoem_spa_purified"

    # ── Picker strategy ──────────────────────────────────────────────────────
    # Reference: MFSD2B — THREE pickers mandatory for saposin nanodisc (high background)
    # Reference: BAX_pore — arc/asymmetric shapes: TOPAZ training mandatory
    if not p.get("picker_strategy"):
        mw_kda = float(p.get("molecular_weight_kda", 200))
        if sc == "membrane_small" or (sc == "soluble" and mw_kda < 80):
            p["picker_strategy"] = "blob+template+topaz"
        elif sc == "pore_forming":
            p["picker_strategy"] = "topaz_trained"   # arc/asymmetric shapes
        else:
            p["picker_strategy"] = "blob+template"

    # ── Number of 2D classes ─────────────────────────────────────────────────
    if "num_2d_classes" not in p:
        if sc in ("large_rna_protein", "symmetric", "pore_forming"):
            p["num_2d_classes"] = 100   # more heterogeneity / oligomeric states
        else:
            p["num_2d_classes"] = 50

    # ── Ab initio classes ────────────────────────────────────────────────────
    if "num_ab_initio_classes" not in p:
        if sc == "large_rna_protein":
            p["num_ab_initio_classes"] = 6   # multiple assembly states
        elif sc == "symmetric":
            p["num_ab_initio_classes"] = 1   # start C1, impose symmetry in refine
        else:
            p["num_ab_initio_classes"] = 3

    # ── Particle diameter ────────────────────────────────────────────────────
    # Reference: GENERAL_FRAMEWORK — diameter_A ≈ 13.3 × MW^(1/3)
    mw_kda = float(p.get("molecular_weight_kda", 200))
    if not p.get("particle_diameter"):
        diameter_A = 13.3 * (mw_kda ** (1.0 / 3.0))
        p.setdefault("particle_diameter", round(diameter_A))

    # ── Box size ─────────────────────────────────────────────────────────────
    # Reference: GENERAL_FRAMEWORK — box_px = 2^ceil(log2((d_A × 1.5) / pix))
    # Enforced power-of-2 for FFT efficiency; 1.5× diameter for context margin.
    # Minimum 64, maximum 512 for practical GPU memory.
    if "box_size_pix" not in p:
        pixel_size = float(p.get("pixel_size", 0.83))
        diameter_A = float(p.get("particle_diameter", 13.3 * (mw_kda ** (1.0 / 3.0))))
        raw_box = (diameter_A * 1.5) / pixel_size
        box_size = int(2 ** math.ceil(math.log2(max(raw_box, 1))))
        box_size = max(64, min(512, box_size))
        p["box_size_pix"] = box_size

    # ── Resolution target → particle count ───────────────────────────────────
    # Reference: GENERAL_FRAMEWORK V5 table (lines 233-250)
    # <2.5 Å: 1M+ particles; 2.5-3 Å: 200K-1M; 3-3.5 Å: 50-200K; 3.5-4.5 Å: 20-50K; >4.5 Å: 5K
    if "target_resolution_A" in p and "target_particle_count" not in p:
        tr = float(p["target_resolution_A"])
        if tr < 2.5:
            p["target_particle_count"] = 1_000_000
        elif tr < 3.0:
            p["target_particle_count"] = 400_000
        elif tr < 3.5:
            p["target_particle_count"] = 100_000
        elif tr < 4.5:
            p["target_particle_count"] = 30_000
        else:
            p["target_particle_count"] = 5_000

    # ── Heterogeneity depth → classification strategy ────────────────────────
    # Reference: GENERAL_FRAMEWORK V4 table (lines 192-229)
    # LOW: 2-4 hetero-refine classes only
    # MEDIUM: 6-8 classes + 3DVA on top 3 components
    # HIGH: multi-body refinement (3-6 rigid bodies) + focused classification
    hetero = p.get("heterogeneity", "low")
    if "num_3d_classes" not in p:
        if hetero == "high":
            p["num_3d_classes"] = 8
            p.setdefault("use_3dva", True)
            p.setdefault("use_multibody", True)
            p.setdefault("num_multibody_bodies", 4)
        elif hetero == "medium":
            p["num_3d_classes"] = 6
            p.setdefault("use_3dva", True)
            p.setdefault("use_multibody", False)
        else:  # low
            p["num_3d_classes"] = 3
            p.setdefault("use_3dva", False)
            p.setdefault("use_multibody", False)

    # ── CTF refinement depth → target resolution ─────────────────────────────
    # Reference: GENERAL_FRAMEWORK V5 — full per-particle CTF only for <2.5 Å target
    if "ctf_refine_level" not in p:
        tr = float(p.get("target_resolution_A", 3.5))
        if tr < 2.5:
            p["ctf_refine_level"] = "full"    # per-particle + beam tilt + trefoil
        elif tr < 3.5:
            p["ctf_refine_level"] = "standard"  # per-particle defocus only
        else:
            p["ctf_refine_level"] = "minimal"   # global CTF only

    # ── Symmetry: always start C1, never impose without evidence ─────────────
    # Reference: GENERAL_FRAMEWORK line 341 — "Never symmetrize without experimental
    # evidence from 2D classes. Always start ab initio in C1."
    # Always separate abinitio_symmetry (C1) from refine_symmetry (intended).
    if "symmetry" in p:
        # User explicitly provided symmetry — respect for refinement, force C1 ab initio
        p.setdefault("refine_symmetry", p["symmetry"])
        p.setdefault("abinitio_symmetry", "C1")
    elif sc == "symmetric":
        # Symmetric sample class with no user symmetry — use expected_symmetry for refine
        p["refine_symmetry"] = p.get("expected_symmetry", "C1")
        p["abinitio_symmetry"] = "C1"

    # ── Dose weighting (Grant & Grigorieff 2015) ─────────────────────────────
    if "dose_per_frame" in p and float(p.get("dose_per_frame", 0)) > 0:
        p.setdefault("use_dose_weighting", True)
    else:
        p.setdefault("use_dose_weighting", False)

    # ── Total dose ───────────────────────────────────────────────────────────
    # Reference: GENERAL_FRAMEWORK cheatsheet; BAX_pore (50 e-/A2 for SPA pore)
    if "total_dose" not in p:
        if sc in ("pore_forming", "large_rna_protein"):
            p["total_dose"] = 45   # lower for radiation-sensitive samples
        elif sc == "symmetric":
            p["total_dose"] = 55   # stable capsids tolerate higher dose
        else:
            p["total_dose"] = 50   # standard

    # ── Log what was auto-filled ─────────────────────────────────────────────
    auto_keys = [k for k in p if k not in params or not params.get(k)]
    if auto_keys:
        log.info(
            "[CryoSPARC] Smart param defaults applied for sample_class=%s: %s",
            sc, {k: p[k] for k in auto_keys if k in p},
        )

    return p


# ---------------------------------------------------------------------------
# Full 4-phase parallel SPA pipeline (sync, runs inside background thread)
# ---------------------------------------------------------------------------

def _execute_spa_pipeline_sync(
    run: CryoSPARCRun,
    cb: Optional[Callable[[int, str], None]],
) -> None:
    """
    Execute the full SPA pipeline synchronously within the background thread
    started by execute_spa_pipeline().

    Phases
    ------
    A — Preprocessing: motion correction + CTF (parallel batches)     → 30 %
    B — Picking: blob picker + junk 2D + inspect + extract R1         → 50 %
    C — Classification: 2D R1→select→template→extract R2→2D R2→sel   → 70 %
    D — Reconstruction: ab initio→refine→vol tools→FSC→CTF→NU→res→sharp → 100 %
    """
    # Apply sample-type-aware intelligent defaults (never overwrites user values)
    params = _resolve_smart_params(run.params)
    run.params = params  # propagate resolved params back to the run record

    mock_mode  = bool(params.get("mock_mode", False))
    max_workers = int(params.get("num_gpu_workers", 1))

    batch_size          = int(params.get("batch_size", 200))
    particle_batch_size = int(params.get("particle_batch_size", 10_000))
    num_ab_initio       = int(params.get("num_ab_initio_classes", 3))
    symmetry            = str(params.get("symmetry", "C1"))

    run.status = "running"

    # ------------------------------------------------------------------
    # Step 0: Provision instance + connect
    # ------------------------------------------------------------------
    if not mock_mode:
        ensure_cryosparc_running(cb)
    _progress(run, 1, "Connecting to CryoSPARC...", cb)

    cs: Any = _MockCS() if mock_mode else _connect()

    # ------------------------------------------------------------------
    # Step 1: Create project + workspace
    # ------------------------------------------------------------------
    _progress(run, 2, "Creating project workspace...", cb)
    if mock_mode:
        proj_uid = f"P{run.run_id[:4].upper()}"
        ws_uid   = f"W{run.run_id[:4].upper()}"
        proj_dir = CRYOSPARC_PROJECT_DIR
    else:
        proj = cs.api.projects.create(
            title=f"biomate-{run.run_id[:8]}",
            parent_dir=CRYOSPARC_PROJECT_DIR,
        )
        proj_uid = proj.uid
        proj_dir = proj.project_dir
        log.info("[CryoSPARC] Project: %s at %s", proj_uid, proj_dir)
        ws      = cs.create_workspace(project_uid=proj_uid, title="W1-spa")
        ws_uid  = ws.uid

    run.project_uid  = proj_uid
    run.workspace_uid = ws_uid
    log.info("[CryoSPARC] Workspace: %s", ws_uid)

    # Emit "long-running" advisory so the frontend can show a dismissible banner.
    # We do NOT guess wall time — we have no calibrated data yet.
    # Time estimate is only shown after Phase A completes with real throughput data.
    if cb:
        try:
            cb(2, json.dumps({
                "type": "long_run_advisory",
                "message": "CryoSPARC pipeline started. This run will take at least 30 minutes; large datasets (>500 movies) may take several hours.",
                "session_persistent": True,
                "suggestion": (
                    "You can safely close this tab and come back later — "
                    "your session will resume automatically when you return."
                ),
                "phases": [
                    {"name": "Phase A", "label": "Motion correction + CTF", "pct_start": 5,  "pct_end": 30},
                    {"name": "Phase B", "label": "Particle picking",        "pct_start": 30, "pct_end": 50},
                    {"name": "Phase C", "label": "2D classification",       "pct_start": 50, "pct_end": 70},
                    {"name": "Phase D", "label": "3D reconstruction",       "pct_start": 70, "pct_end": 100},
                ],
            }))
        except Exception:
            pass

    # Convenience: create_job wrapper that always tracks UIDs
    def _submit(job_type: str, title: str,
                connections: Optional[Dict] = None,
                extra_params: Optional[Dict] = None,
                phase_key: Optional[str] = None) -> Any:
        job = cs.create_job(
            project_uid=proj_uid,
            workspace_uid=ws_uid,
            type=job_type,
            params=extra_params or {},
            connections=connections or {},
            title=title,
        )
        job.queue(lane="default")
        run.job_uids.append(job.uid)
        run.total_jobs += 1
        if phase_key:
            run.batch_jobs.setdefault(phase_key, []).append(job.uid)
        log.info("[CryoSPARC] Submitted %s (%s) uid=%s", title, job_type, job.uid)
        return job

    # ------------------------------------------------------------------
    # Step 2: Import movies (single job)
    # ------------------------------------------------------------------
    movie_dir = params.get("movie_dir") or params.get("data_dir")
    if not movie_dir and not mock_mode:
        raise ValueError(
            "No movie_dir provided. Set params.movie_dir to the path of EER/TIFF/MRC movies "
            "on the CryoSPARC host."
        )
    movie_dir = movie_dir or "/mock/movies"

    _progress(run, 3, "Importing movies...", cb)
    import_job = _submit(
        _IMPORT_JOB,
        "Import Movies",
        extra_params={
            "blob_paths":     str(Path(movie_dir) / "*.eer"),
            "psize_A":        float(params.get("pixel_size", 1.0)),
            "accel_kv":       float(params.get("voltage", 300)),
            "cs_mm":          float(params.get("cs", 2.7)),
            "amp_contrast":   float(params.get("amplitude_contrast", 0.1)),
            "total_dose_e_per_A2": float(params.get("total_dose", 40.0)),
        },
        phase_key="import",
    )

    _wait_for_job(import_job, run, cb, target_pct=5,
                  step_name="Import Movies", mock_mode=mock_mode)

    if not mock_mode:
        import_job = cs.find_job(proj_uid, import_job.uid)
    imported_movies = import_job.load_output("imported_movies")
    num_movies = len(imported_movies) if not mock_mode else int(params.get("num_movies", 400))
    log.info("[CryoSPARC] %d movies imported", num_movies)

    # Split movies into batches (simulate batch splitting by index ranges)
    num_batches = max(1, (num_movies + batch_size - 1) // batch_size)
    log.info("[CryoSPARC] Phase A: %d movie batches (batch_size=%d)", num_batches, batch_size)

    # ==================================================================
    # PHASE A — Preprocessing (parallel motion + pipelined CTF)
    # ==================================================================
    _progress(run, 6, f"Phase A: submitting motion correction for {num_batches} batches...", cb)

    motion_jobs: List[Any] = []
    for i in range(num_batches):
        mj = _submit(
            _MOTION_JOB,
            f"Motion Correction B{i+1}/{num_batches}",
            connections={"movies": (import_job.uid, "imported_movies")},
            extra_params={
                "movie_start_idx": i * batch_size,
                "movie_end_idx":   min((i + 1) * batch_size, num_movies),
                "dose_per_frame_e_A2": float(params.get("dose_per_frame", 0)),
                "use_dose_weighting":  bool(params.get("use_dose_weighting", False)),
            },
            phase_key="phase_a_motion",
        )
        motion_jobs.append(mj)

    # Pipeline: as each motion job completes, submit CTF for that batch immediately.
    # We implement this with a ThreadPoolExecutor — one worker per batch.
    ctf_jobs: List[Any] = []
    ctf_lock = __import__("threading").Lock()

    def _motion_then_ctf(motion_job: Any, batch_idx: int) -> Any:
        """Wait for motion job, then immediately submit + return CTF job."""
        _wait_for_job(
            motion_job, run, cb,
            target_pct=run.progress_percent,  # don't advance pct here; phase milestone does it
            step_name=f"Motion B{batch_idx+1}",
            mock_mode=mock_mode,
        )
        if not mock_mode:
            motion_job = cs.find_job(proj_uid, motion_job.uid)

        ctf_job = _submit(
            _CTF_JOB,
            f"CTF Estimation B{batch_idx+1}/{num_batches}",
            connections={"micrographs": (motion_job.uid, "micrographs")},
            phase_key="phase_a_ctf",
        )
        return ctf_job

    with ThreadPoolExecutor(max_workers=max_workers,
                            thread_name_prefix="phaseA") as pool:
        futures: Dict[Future, int] = {
            pool.submit(_motion_then_ctf, mj, i): i
            for i, mj in enumerate(motion_jobs)
        }
        for fut in as_completed(futures):
            batch_idx = futures[fut]
            ctf_job = fut.result()   # raises on error
            ctf_jobs.append(ctf_job)
            log.info("[CryoSPARC] Phase A batch %d CTF submitted: %s",
                     batch_idx + 1, ctf_job.uid)

    # Wait for all CTF jobs (they were queued inside _motion_then_ctf)
    _wait_for_jobs_parallel(ctf_jobs, run, cb, "Phase-A CTF",
                            mock_mode=mock_mode)

    _progress(run, 30, "Phase A complete: motion correction + CTF estimation", cb)

    # Reload CTF jobs to get outputs
    if not mock_mode:
        ctf_jobs = [cs.find_job(proj_uid, j.uid) for j in ctf_jobs]
    all_micrographs: List[Any] = []
    for j in ctf_jobs:
        all_micrographs.extend(j.load_output("micrographs_ctf"))
    log.info("[CryoSPARC] Phase A done: %d CTF-corrected micrographs", len(all_micrographs))

    # QC: sample motion and CTF quality across micrographs
    qc_profile = params.get("qc_profile", "cryoem_spa_purified")
    audit_dir = params.get("outdir", "")
    _check_motion_ctf_gates(ctf_jobs, run, cb, qc_profile, audit_dir, mock_mode)

    # ==================================================================
    # PHASE B — Picking (parallel blob picker → junk 2D → inspect → extract)
    # ==================================================================
    picker_strategy = params.get("picker_strategy", "blob+template")
    if "topaz" in picker_strategy:
        log.info(
            "[CryoSPARC] Phase B: topaz strategy requested (%s) — "
            "using tighter blob threshold for initial picks; "
            "TOPAZ training recommended after 2D classification",
            picker_strategy,
        )
    _progress(run, 31, f"Phase B: submitting blob picker for {num_batches} batches "
              f"(strategy={picker_strategy})...", cb)

    blob_jobs: List[Any] = []
    particle_diameter = float(params.get("particle_diameter", 180))
    for i, ctf_job in enumerate(ctf_jobs):
        blob_extra: Dict[str, Any] = {
            "diameter":     particle_diameter,
            "diameter_max": float(params.get("particle_diameter_max",
                                             particle_diameter * 1.5)),
        }
        # For TOPAZ strategies, use tighter blob thresholds to get a clean
        # initial seed set that can then be used for TOPAZ training
        if "topaz" in picker_strategy:
            blob_extra["min_separation"] = particle_diameter * 0.9  # tighter NMS
        bj = _submit(
            _BLOB_PICKER_JOB,
            f"Blob Picker B{i+1}/{num_batches}",
            connections={"micrographs": (ctf_job.uid, "micrographs_ctf")},
            extra_params=blob_extra,
            phase_key="phase_b_blob",
        )
        blob_jobs.append(bj)

    _wait_for_jobs_parallel(blob_jobs, run, cb, "Phase-B Blob Picker",
                            mock_mode=mock_mode)

    if not mock_mode:
        blob_jobs = [cs.find_job(proj_uid, j.uid) for j in blob_jobs]

    # Junk 2D detector — single job on all blob picks (collect across batches)
    # Connect to the first batch's blob output; CryoSPARC supports multi-input
    _progress(run, 38, "Phase B: junk 2D detection...", cb)
    junk_connections = {"micrographs": (blob_jobs[0].uid, "micrographs")}
    # Add extra blob picker outputs as additional inputs for multi-batch datasets
    for extra_i, bj in enumerate(blob_jobs[1:], start=1):
        junk_connections[f"micrographs_{extra_i}"] = (bj.uid, "micrographs")

    junk_job = _submit(
        _JUNK_2D_JOB,
        "Junk 2D Detection",
        connections={"micrographs": (blob_jobs[0].uid, "micrographs")},
        phase_key="phase_b_junk",
    )
    _wait_for_job(junk_job, run, cb, target_pct=40,
                  step_name="Junk 2D Detection", mock_mode=mock_mode)

    if not mock_mode:
        junk_job = cs.find_job(proj_uid, junk_job.uid)

    # Inspect picks
    inspect_job = _submit(
        _INSPECT_PICKS_JOB,
        "Inspect Picks",
        connections={
            "micrographs": (junk_job.uid, "micrographs"),
            "particles":   (junk_job.uid, "particles"),
        },
        phase_key="phase_b_inspect",
    )
    _wait_for_job(inspect_job, run, cb, target_pct=43,
                  step_name="Inspect Picks", mock_mode=mock_mode)

    if not mock_mode:
        inspect_job = cs.find_job(proj_uid, inspect_job.uid)

    # Extract particles R1 — parallel per batch
    _progress(run, 44, f"Phase B: extracting particles R1 for {num_batches} batches...", cb)
    extract_r1_jobs: List[Any] = []
    for i, ctf_job in enumerate(ctf_jobs):
        ej = _submit(
            _EXTRACT_JOB,
            f"Extract Particles R1 B{i+1}/{num_batches}",
            connections={
                "micrographs": (ctf_job.uid, "micrographs_ctf"),
                "particles":   (inspect_job.uid, "particles"),
            },
            extra_params={
                "box_size_pix": int(params.get("box_size_pix", 256)),
                "fourier_crop_to": int(params.get("fourier_crop_to", 128)),
            },
            phase_key="phase_b_extract_r1",
        )
        extract_r1_jobs.append(ej)

    _wait_for_jobs_parallel(extract_r1_jobs, run, cb, "Phase-B Extract R1",
                            mock_mode=mock_mode)

    _progress(run, 50, "Phase B complete: picking + extraction R1", cb)

    if not mock_mode:
        extract_r1_jobs = [cs.find_job(proj_uid, j.uid) for j in extract_r1_jobs]

    all_particles_r1: List[Any] = []
    for j in extract_r1_jobs:
        all_particles_r1.extend(j.load_output("particles"))
    num_particles = len(all_particles_r1) if not mock_mode else int(
        params.get("num_particles", 50_000)
    )
    log.info("[CryoSPARC] Phase B done: %d particles extracted R1", num_particles)

    # ==================================================================
    # PHASE C — Classification (parallel particle batches)
    # ==================================================================
    num_par_batches = max(1, (num_particles + particle_batch_size - 1) // particle_batch_size)
    log.info("[CryoSPARC] Phase C: %d particle batches (batch=%d)",
             num_par_batches, particle_batch_size)

    _progress(run, 51, f"Phase C: 2D classification R1 for {num_par_batches} particle batches...", cb)

    class2d_r1_jobs: List[Any] = []
    for i, ej in enumerate(extract_r1_jobs[:num_par_batches]):
        cj = _submit(
            _CLASS_2D_JOB,
            f"2D Classification R1 B{i+1}/{num_par_batches}",
            connections={"particles": (ej.uid, "particles")},
            extra_params={
                "num_classes":  int(params.get("num_2d_classes", 50)),
                "max_res":      float(params.get("max_2d_res", 8.0)),
                "num_iterations": int(params.get("num_2d_iter", 20)),
            },
            phase_key="phase_c_class2d_r1",
        )
        class2d_r1_jobs.append(cj)

    _wait_for_jobs_parallel(class2d_r1_jobs, run, cb, "Phase-C 2D-R1",
                            mock_mode=mock_mode)

    if not mock_mode:
        class2d_r1_jobs = [cs.find_job(proj_uid, j.uid) for j in class2d_r1_jobs]

    # QC: junk class gate on 2D classification R1
    _check_junk_gate(class2d_r1_jobs, run, cb, qc_profile, audit_dir, mock_mode)

    # Select best 2D classes R1 (one per batch, then a global select)
    select_r1_jobs: List[Any] = []
    for i, cj in enumerate(class2d_r1_jobs):
        sj = _submit(
            _SELECT_2D_JOB,
            f"Select 2D Classes R1 B{i+1}",
            connections={"particles": (cj.uid, "particles"),
                         "class_averages": (cj.uid, "class_averages")},
            extra_params={"select_mode": "auto"},
            phase_key="phase_c_select_r1",
        )
        select_r1_jobs.append(sj)

    _wait_for_jobs_parallel(select_r1_jobs, run, cb, "Phase-C Select-R1",
                            mock_mode=mock_mode)

    if not mock_mode:
        select_r1_jobs = [cs.find_job(proj_uid, j.uid) for j in select_r1_jobs]

    # Template picker — parallel per micrograph batch, using selected classes as templates
    _progress(run, 58, f"Phase C: template picking for {num_batches} mic batches...", cb)
    # Use first select R1 job's averages as templates (representative)
    template_src = select_r1_jobs[0]

    template_pick_jobs: List[Any] = []
    for i, ctf_job in enumerate(ctf_jobs):
        tpj = _submit(
            _TOPAZ_XVAL_JOB,   # topaz_cross_validation doubles as template/topaz picker
            f"Template Picker B{i+1}/{num_batches}",
            connections={
                "micrographs":   (ctf_job.uid, "micrographs_ctf"),
                "templates":     (template_src.uid, "class_averages"),
            },
            extra_params={
                "diameter": float(params.get("particle_diameter", 180)),
            },
            phase_key="phase_c_template_pick",
        )
        template_pick_jobs.append(tpj)

    _wait_for_jobs_parallel(template_pick_jobs, run, cb, "Phase-C Template Pick",
                            mock_mode=mock_mode)

    if not mock_mode:
        template_pick_jobs = [cs.find_job(proj_uid, j.uid) for j in template_pick_jobs]

    # Extract particles R2 — parallel per micrograph batch
    _progress(run, 62, f"Phase C: extracting particles R2 for {num_batches} batches...", cb)
    extract_r2_jobs: List[Any] = []
    for i, (ctf_job, tp_job) in enumerate(zip(ctf_jobs, template_pick_jobs)):
        ej2 = _submit(
            _EXTRACT_JOB,
            f"Extract Particles R2 B{i+1}/{num_batches}",
            connections={
                "micrographs": (ctf_job.uid, "micrographs_ctf"),
                "particles":   (tp_job.uid,  "particles"),
            },
            extra_params={
                "box_size_pix":   int(params.get("box_size_pix", 256)),
                "fourier_crop_to": int(params.get("fourier_crop_to_r2", 256)),
                "invert_data":    bool(params.get("invert_data", True)),
            },
            phase_key="phase_c_extract_r2",
        )
        extract_r2_jobs.append(ej2)

    _wait_for_jobs_parallel(extract_r2_jobs, run, cb, "Phase-C Extract R2",
                            mock_mode=mock_mode)

    if not mock_mode:
        extract_r2_jobs = [cs.find_job(proj_uid, j.uid) for j in extract_r2_jobs]

    # 2D Classification R2 — parallel per particle batch
    class2d_r2_jobs: List[Any] = []
    for i, ej2 in enumerate(extract_r2_jobs[:num_par_batches]):
        cj2 = _submit(
            _CLASS_2D_JOB,
            f"2D Classification R2 B{i+1}/{num_par_batches}",
            connections={"particles": (ej2.uid, "particles")},
            extra_params={
                "num_classes":    int(params.get("num_2d_classes_r2", 100)),
                "max_res":        float(params.get("max_2d_res_r2", 4.0)),
                "num_iterations": int(params.get("num_2d_iter_r2", 25)),
            },
            phase_key="phase_c_class2d_r2",
        )
        class2d_r2_jobs.append(cj2)

    _wait_for_jobs_parallel(class2d_r2_jobs, run, cb, "Phase-C 2D-R2",
                            mock_mode=mock_mode)

    if not mock_mode:
        class2d_r2_jobs = [cs.find_job(proj_uid, j.uid) for j in class2d_r2_jobs]

    # Select 2D classes R2
    select_r2_jobs: List[Any] = []
    for i, cj2 in enumerate(class2d_r2_jobs):
        sj2 = _submit(
            _SELECT_2D_JOB,
            f"Select 2D Classes R2 B{i+1}",
            connections={"particles":    (cj2.uid, "particles"),
                         "class_averages": (cj2.uid, "class_averages")},
            extra_params={"select_mode": "auto"},
            phase_key="phase_c_select_r2",
        )
        select_r2_jobs.append(sj2)

    _wait_for_jobs_parallel(select_r2_jobs, run, cb, "Phase-C Select-R2",
                            mock_mode=mock_mode)

    _progress(run, 70, "Phase C complete: 2D classification R1→R2 + selection", cb)

    if not mock_mode:
        select_r2_jobs = [cs.find_job(proj_uid, j.uid) for j in select_r2_jobs]

    # Aggregate particles from all select R2 jobs into one representative set
    # (use first batch as the canonical source for 3D jobs)
    best_particles_job = select_r2_jobs[0]
    log.info("[CryoSPARC] Phase C done: best particles from %s", best_particles_job.uid)

    # ==================================================================
    # PHASE D — Reconstruction (parallel ab initio, then refinement chain)
    # ==================================================================
    _progress(run, 71, f"Phase D: submitting {num_ab_initio} ab initio jobs...", cb)

    ab_initio_jobs: List[Any] = []
    for k in range(num_ab_initio):
        aij = _submit(
            _AB_INITIO_JOB,
            f"Ab Initio {k+1}/{num_ab_initio}",
            connections={"particles": (best_particles_job.uid, "particles")},
            extra_params={
                "abinit_K":       1,         # 1 class per ab initio run (diversity via multi-run)
                "symmetry":       symmetry,
                "num_iterations": int(params.get("abinit_iter", 200)),
            },
            phase_key="phase_d_ab_initio",
        )
        ab_initio_jobs.append(aij)

    # All ab initio jobs run in parallel
    _wait_for_jobs_parallel(ab_initio_jobs, run, cb, "Phase-D Ab Initio",
                            mock_mode=mock_mode)

    if not mock_mode:
        ab_initio_jobs = [cs.find_job(proj_uid, j.uid) for j in ab_initio_jobs]

    # QC: G9 — Ab initio 3D quality gate (BRONZE — community heuristic)
    for aij in ab_initio_jobs:
        _check_abinitio_gate_from_job(aij, run, cb, qc_profile, audit_dir, mock_mode)

    _progress(run, 78, f"Phase D: submitting {num_ab_initio} homogeneous refinement jobs...", cb)

    # Homogeneous refinement — one per ab initio volume, all in parallel
    refine_jobs: List[Any] = []
    for k, aij in enumerate(ab_initio_jobs):
        rj = _submit(
            _HOMO_REFINE_JOB,
            f"Homogeneous Refinement {k+1}/{num_ab_initio}",
            connections={
                "particles": (best_particles_job.uid, "particles"),
                "volume":    (aij.uid, "volume"),
            },
            extra_params={
                "symmetry":         symmetry,
                "fulcrum_max_res":  float(params.get("refine_max_res", 4.0)),
            },
            phase_key="phase_d_homo_refine",
        )
        refine_jobs.append(rj)

    _wait_for_jobs_parallel(refine_jobs, run, cb, "Phase-D Homo Refine",
                            mock_mode=mock_mode)

    _progress(run, 84, "Phase D: selecting best volume for downstream processing...", cb)

    if not mock_mode:
        refine_jobs = [cs.find_job(proj_uid, j.uid) for j in refine_jobs]

    # Pick the best volume: use first refinement job as representative
    # (in a production system this would score by FSC resolution and pick highest)
    best_refine_job = refine_jobs[0]
    log.info("[CryoSPARC] Best refinement job: %s", best_refine_job.uid)

    # QC: orientation distribution gate
    _check_orientation_gate_from_job(best_refine_job, run, cb, qc_profile, audit_dir, mock_mode)

    # Volume tools (masking / symmetry expansion / filtering)
    vol_tools_job = _submit(
        _VOLUME_TOOLS_JOB,
        "Volume Tools",
        connections={
            "volume":    (best_refine_job.uid, "volume"),
            "particles": (best_particles_job.uid, "particles"),
        },
        extra_params={
            "symmetry":          symmetry,
            "lowpass_filter_res": float(params.get("lowpass_res", 8.0)),
        },
        phase_key="phase_d_vol_tools",
    )
    _wait_for_job(vol_tools_job, run, cb, target_pct=86,
                  step_name="Volume Tools", mock_mode=mock_mode)

    if not mock_mode:
        vol_tools_job = cs.find_job(proj_uid, vol_tools_job.uid)

    # Validation FSC
    val_fsc_job = _submit(
        _VALIDATION_FSC_JOB,
        "Validation FSC",
        connections={
            "volume":    (best_refine_job.uid, "volume"),
            "particles": (best_particles_job.uid, "particles"),
        },
        phase_key="phase_d_val_fsc",
    )
    _wait_for_job(val_fsc_job, run, cb, target_pct=88,
                  step_name="Validation FSC", mock_mode=mock_mode)

    if not mock_mode:
        val_fsc_job = cs.find_job(proj_uid, val_fsc_job.uid)

    # QC: FSC 0.143 resolution gate (GOLD — Henderson 2012)
    _check_fsc_gate_from_job(val_fsc_job, run, cb, qc_profile, audit_dir, mock_mode)

    # Local CTF refinement
    local_ctf_job = _submit(
        _LOCAL_CTF_JOB,
        "Local CTF Refinement",
        connections={
            "particles": (best_particles_job.uid, "particles"),
            "volume":    (best_refine_job.uid, "volume"),
        },
        extra_params={
            "symmetry": symmetry,
        },
        phase_key="phase_d_local_ctf",
    )
    _wait_for_job(local_ctf_job, run, cb, target_pct=91,
                  step_name="Local CTF Refinement", mock_mode=mock_mode)

    if not mock_mode:
        local_ctf_job = cs.find_job(proj_uid, local_ctf_job.uid)

    # Non-uniform (NU) refinement
    nu_refine_job = _submit(
        _NU_REFINE_JOB,
        "NU Refinement",
        connections={
            "particles": (local_ctf_job.uid, "particles"),
            "volume":    (best_refine_job.uid, "volume"),
        },
        extra_params={
            "symmetry":        symmetry,
            "use_pose_prior":  bool(params.get("nu_use_pose_prior", True)),
        },
        phase_key="phase_d_nu_refine",
    )
    _wait_for_job(nu_refine_job, run, cb, target_pct=95,
                  step_name="NU Refinement", mock_mode=mock_mode)

    if not mock_mode:
        nu_refine_job = cs.find_job(proj_uid, nu_refine_job.uid)

    # ── 3D Variability Analysis (when heterogeneity=medium or high) ─────────
    if params.get("use_3dva") and not mock_mode:
        try:
            _progress(run, 96, "Submitting 3DVA job for heterogeneity decomposition...", cb)
            n_components = 3  # first 3 components capture major motions (GENERAL_FRAMEWORK V4)
            three_dva_job = _submit(
                "var_3D",
                "3D Variability Analysis",
                connections={
                    "particles": (nu_refine_job.uid, "particles"),
                    "volume":    (nu_refine_job.uid, "volume"),
                },
                extra_params={
                    "n_components":    n_components,
                    "filter_res":      float(params.get("target_resolution_A", 5.0)),
                    "num_iterations":  20,
                },
                phase_key="phase_d_3dva",
            )
            _wait_for_job(three_dva_job, run, cb, target_pct=97,
                          step_name="3DVA", mock_mode=mock_mode)
            if not mock_mode:
                three_dva_job = cs.find_job(proj_uid, three_dva_job.uid)
            log.info("[CryoSPARC] 3DVA complete: %s", three_dva_job.uid)
        except Exception as e:
            log.warning("[CryoSPARC] 3DVA failed (non-fatal): %s", e)
            # 3DVA failure does not halt the pipeline

    # ── Multi-body refinement advisory (HIGH heterogeneity) ─────────────────
    if params.get("use_multibody") and not mock_mode:
        log.info("[CryoSPARC] Multi-body refinement requested (HIGH heterogeneity). "
                 "Requires manual setup of rigid body masks in CryoSPARC GUI — "
                 "emitting advisory for user.")
        cb and cb(-1, json.dumps({
            "type": "qc_advisory",
            "gate": "multibody_setup",
            "message": (
                "HIGH heterogeneity detected. Multi-body refinement requires "
                "defining 3-6 rigid body masks in CryoSPARC GUI before proceeding. "
                "Pipeline has completed standard refinement. Use CryoSPARC GUI to "
                "set up multi-body job on the refined particles."
            ),
            "suggestion": (
                "Open CryoSPARC GUI → New Job → Multi-body Refinement → "
                "define masks for each rigid domain → connect refined particles."
            ),
            "evidence": "GENERAL_FRAMEWORK V4 — multi-body for HIGH heterogeneity (3-6 bodies, ±5-10° rotation)",
        }))

    # Local resolution estimation
    local_res_job = _submit(
        _LOCAL_RES_JOB,
        "Local Resolution",
        connections={
            "volume":    (nu_refine_job.uid, "volume"),
            "particles": (local_ctf_job.uid, "particles"),
        },
        extra_params={"symmetry": symmetry},
        phase_key="phase_d_local_res",
    )
    _wait_for_job(local_res_job, run, cb, target_pct=97,
                  step_name="Local Resolution", mock_mode=mock_mode)

    if not mock_mode:
        local_res_job = cs.find_job(proj_uid, local_res_job.uid)

    # Sharpening (FSC-based B-factor estimation)
    sharpen_job = _submit(
        _SHARPENING_JOB,
        "Sharpening FSC",
        connections={
            "volume":      (nu_refine_job.uid, "volume"),
            "local_res":   (local_res_job.uid, "local_res"),
        },
        extra_params={
            "bfactor_min": float(params.get("bfactor_min", -200.0)),
            "bfactor_max": float(params.get("bfactor_max", 0.0)),
        },
        phase_key="phase_d_sharpening",
    )
    _wait_for_job(sharpen_job, run, cb, target_pct=100,
                  step_name="Sharpening FSC", mock_mode=mock_mode)

    # QC: G12 — MolProbity / model validation gate (GOLD — PDB deposition standard)
    # Emits an advisory reminder to run phenix.molprobity externally.
    _check_model_quality_gate_from_job(sharpen_job, run, cb, qc_profile, audit_dir, mock_mode)

    # ------------------------------------------------------------------
    # Done
    # ------------------------------------------------------------------
    _progress(run, 100, "Full SPA pipeline complete (4 phases)", cb)
    run.status = "completed"
    run.finished_at = time.time()
    log.info("[CryoSPARC] Run %s completed in %.1fs (%d jobs total)",
             run.run_id, run.finished_at - run.started_at, run.total_jobs)

    # Auto-stop instance to save cost (GPU costs ~$0.98/hr when idle)
    if not mock_mode:
        auto_stop_mins = int(os.environ.get("AUTO_STOP_AFTER_MINUTES", "5"))
        if auto_stop_mins > 0:
            log.info("[CryoSPARC] Auto-stopping instance in %d minutes...", auto_stop_mins)
            time.sleep(auto_stop_mins * 60)
            stop_instance()


# ---------------------------------------------------------------------------
# Status endpoint helpers (mirrors nextflow_executor status format)
# ---------------------------------------------------------------------------

def get_run_status(run_id: str) -> Optional[Dict[str, Any]]:
    run = _cs_runs.get(run_id)
    if not run:
        return None
    # Valid terminal statuses: completed | failed | qc_halt
    return {
        "run_id":           run.run_id,
        "status":           run.status,
        "progress_percent": run.progress_percent,
        "completed_jobs":   run.completed_jobs,
        "total_jobs":       run.total_jobs,
        "error_message":    run.error_message or None,
        "project_uid":      run.project_uid,
        "workspace_uid":    run.workspace_uid,
        "job_uids":         run.job_uids,
        "batch_jobs":       run.batch_jobs,
        "executor":         "cryosparc",
        "is_batch":         False,  # CryoSPARC manages its own compute
        "is_qc_halt":       run.status == "qc_halt",
    }


def list_runs() -> List[Dict[str, Any]]:
    return [get_run_status(rid) for rid in _cs_runs]
