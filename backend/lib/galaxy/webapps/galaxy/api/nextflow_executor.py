"""
Nextflow Executor API

Provides POST /api/nextflow/execute — launches a Nextflow workflow
as a background subprocess and returns tracking IDs.

Does NOT require Galaxy workflow/invocation infrastructure.
"""
import logging
import os
import re
import subprocess
import threading
import uuid
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import (
    DependsOnTrans,
    Router,
)

log = logging.getLogger(__name__)

router = Router(tags=["nextflow"])

# In-process registry: run_id → {status, process, outdir, ...}
_runs: Dict[str, Dict[str, Any]] = {}
_runs_lock = threading.Lock()

# QC handler registry: invocation_id → NextflowQCGateHandler
# Populated by _start_qc_monitor so the export endpoint can retrieve live state.
_qc_handlers: Dict[str, Any] = {}
_qc_handlers_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class NextflowExecuteRequest(BaseModel):
    nextflow_path: str
    parameters: Optional[Dict[str, Any]] = None
    profile: Optional[str] = "standard"
    entry: Optional[str] = None
    history_id: Optional[str] = None
    compute_config: Optional[Dict[str, Any]] = None
    qc_overrides: Optional[Dict[str, Any]] = None
    qc_profile: Optional[str] = None
    workflow_domain: Optional[str] = None


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


def _candidate_bases() -> list[Path]:
    """
    Build ordered search roots for resolving logical Nextflow paths.

    We intentionally keep DB paths relative (portable across sites) and resolve
    them here against deployment-specific roots.
    """
    roots: list[Path] = []

    env_roots = os.environ.get("NEXTFLOW_SEARCH_ROOTS", "")
    if env_roots:
        for part in env_roots.split(":"):
            part = part.strip()
            if part:
                roots.append(Path(part))

    # Common in-repo defaults (relative to this file's location).
    this_file = Path(__file__).resolve()
    backend_root = this_file.parents[5]
    roots.extend([
        backend_root,  # allows resolving paths already rooted at backend/
        backend_root / "biomni_workflows" / "nextflow_nfcore",
        backend_root / "biomni_workflows" / "nextflow_nfcore" / "subworkflows",
        backend_root / "biomni_workflows" / "nextflow_nfcore" / "workflows",
        backend_root / "nf-core-workflows",
        backend_root / "nf-core-modules",
        backend_root / "nf-core-modules" / "subworkflows" / "nf-core",
    ])

    # Preserve order and uniqueness.
    seen: set[str] = set()
    unique_roots: list[Path] = []
    for root in roots:
        key = str(root)
        if key not in seen:
            seen.add(key)
            unique_roots.append(root)
    return unique_roots


def _resolve_nextflow_path(raw_path: str) -> Path:
    """
    Resolve DB/logical nextflow path to an executable local .nf script.

    Supported inputs:
    - absolute path to script
    - relative path to script
    - logical IDs like:
      - nfcore/<pipeline>/main.nf
      - nfcore/subworkflows/<name>
      - biomni_nf/<domain>/<name>.nf
    """
    provided = Path(raw_path)
    if provided.is_absolute() and provided.exists():
        return provided
    if provided.exists():
        return provided.resolve()

    # Normalize logical aliases used in indexed DB rows.
    logical_candidates: list[Path] = [Path(raw_path)]

    if raw_path.startswith("nfcore/subworkflows/"):
        name = raw_path.split("nfcore/subworkflows/", 1)[1].strip("/")
        logical_candidates.extend([
            Path("subworkflows") / name / "main.nf",
            Path(name) / "main.nf",
        ])
    elif raw_path.startswith("nfcore/"):
        rest = raw_path.split("nfcore/", 1)[1].strip("/")
        logical_candidates.extend([
            Path(rest),
            Path(rest) / "main.nf",
        ])
    elif raw_path.startswith("biomni_nf/"):
        rest = raw_path.split("biomni_nf/", 1)[1].strip("/")
        logical_candidates.extend([
            Path("subworkflows") / rest,
            Path("subworkflows") / rest / "main.nf",
        ])

    # If DB stored path without extension, try main.nf / .nf variants.
    expanded_candidates: list[Path] = []
    for candidate in logical_candidates:
        expanded_candidates.append(candidate)
        if candidate.suffix != ".nf":
            expanded_candidates.append(candidate.with_suffix(".nf"))
            expanded_candidates.append(candidate / "main.nf")

    # Search all candidates under configured roots.
    for root in _candidate_bases():
        for candidate in expanded_candidates:
            test_path = (root / candidate).resolve()
            if test_path.exists() and test_path.is_file() and test_path.suffix == ".nf":
                return test_path

    raise FileNotFoundError(
        f"Could not resolve Nextflow script '{raw_path}'. "
        f"Set NEXTFLOW_SEARCH_ROOTS to include your workflow roots."
    )


def _detect_nextflow_entry(nf_path: Path) -> Optional[str]:
    """
    Detect entry workflow name for scripts that define only named workflows.

    If an anonymous `workflow { ... }` exists, Nextflow can use default entry and
    no explicit `-entry` is needed.
    """
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return None

    # Anonymous workflow block exists; default entry is available.
    if re.search(r"(?m)^\s*workflow\s*\{", text):
        return None

    named_entries = re.findall(r"(?m)^\s*workflow\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{", text)
    if not named_entries:
        return None

    preferred = [name for name in named_entries if name.lower() in ("main", "run", "workflow")]
    return preferred[0] if preferred else named_entries[0]


def _extract_documented_images() -> list[str]:
    """
    Extract workflow container images from local BioMate docs.
    This keeps runtime image selection aligned with documented, previously built images.
    """
    docs = [
        Path(__file__).resolve().parents[5] / "20260119_1538_DOCKER_CONTAINER_ROUTING_APPROACH.md",
        Path(__file__).resolve().parents[5] / "20260116_BIOMNI_DOCKER_TEST_RESULTS.md",
        Path(__file__).resolve().parents[5] / "biomni_workflows" / "galaxy" / "docker" / "20251203_DOCKER_TOOL_EXECUTION_GUIDE.md",
        Path(__file__).resolve().parents[5] / "biomni_workflows" / "20251204_NEXTFLOW_DOCKER_CONFIGURATION.md",
    ]
    image_pattern = re.compile(r"(biomate/[a-zA-Z0-9._-]+(?::[a-zA-Z0-9._-]+)?)")
    images: list[str] = []
    for doc in docs:
        if not doc.exists():
            continue
        try:
            text = doc.read_text(errors="replace")
        except OSError:
            continue
        for match in image_pattern.findall(text):
            if match not in images:
                images.append(match)
    return images


def _is_local_docker_image(image: str) -> bool:
    """Return True if Docker image exists locally."""
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", image],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=10,
        )
        return result.returncode == 0
    except Exception:
        return False


def _host_arch() -> str:
    """Return normalized host architecture: arm64 | amd64 | unknown."""
    machine = os.uname().machine.lower()
    if machine in ("aarch64", "arm64"):
        return "arm64"
    if machine in ("x86_64", "amd64"):
        return "amd64"
    return "unknown"


def _image_declared_arch(image: str) -> str:
    """
    Best-effort arch hint from image tag naming convention.
    Returns: arm64 | amd64 | unknown
    """
    image_l = image.lower()
    if ":arm64" in image_l or "-arm64" in image_l:
        return "arm64"
    if ":x86" in image_l or ":amd64" in image_l or "-x86" in image_l or "-amd64" in image_l:
        return "amd64"
    return "unknown"


def _image_runtime_arch(image: str) -> str:
    """Inspect local image architecture via Docker metadata."""
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", "--format", "{{.Architecture}}", image],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return "unknown"
        arch = result.stdout.strip().lower()
        if arch in ("arm64", "aarch64"):
            return "arm64"
        if arch in ("amd64", "x86_64"):
            return "amd64"
        return "unknown"
    except Exception:
        return "unknown"


def _is_image_arch_compatible(image: str) -> tuple[bool, str, str]:
    """
    Returns (compatible, host_arch, image_arch).
    By default cross-arch is disabled; enable with NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER=true.
    """
    host_arch = _host_arch()
    image_arch = _image_runtime_arch(image)
    if image_arch == "unknown":
        image_arch = _image_declared_arch(image)

    allow_cross = os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false").lower() in ("1", "true", "yes")
    if allow_cross:
        return True, host_arch, image_arch
    if host_arch == "unknown" or image_arch == "unknown":
        return True, host_arch, image_arch
    return host_arch == image_arch, host_arch, image_arch


def _extract_python_imports(nf_path: Path) -> list[str]:
    """
    Best-effort extraction of Python imports embedded in Nextflow scripts.
    """
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return []

    imports: set[str] = set()
    for mod in re.findall(r"^\s*import\s+([a-zA-Z_][a-zA-Z0-9_\.]*)", text, flags=re.MULTILINE):
        imports.add(mod.split(".")[0])
    for mod in re.findall(r"^\s*from\s+([a-zA-Z_][a-zA-Z0-9_\.]*)\s+import", text, flags=re.MULTILINE):
        imports.add(mod.split(".")[0])

    stdlib = {
        "os", "sys", "re", "json", "math", "time", "datetime", "pathlib", "typing",
        "collections", "itertools", "functools", "subprocess", "logging", "argparse",
        "csv", "gzip", "shutil", "glob",
    }
    return sorted([m for m in imports if m not in stdlib])


def _docker_has_python_modules(image: str, modules: list[str]) -> bool:
    """Check whether image has all required Python modules."""
    if not modules:
        return True
    script = "; ".join([f"import {m}" for m in modules])
    cmd = ["docker", "run", "--rm", "--entrypoint", "python", image, "-c", script]
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=30,
        )
        return result.returncode == 0
    except Exception:
        return False


def _host_has_python_modules(modules: list[str]) -> tuple[bool, list[str]]:
    """Return (all_present, missing_modules) for host Python runtime."""
    missing: list[str] = []
    for mod in modules:
        try:
            __import__(mod)
        except Exception:
            missing.append(mod)
    return len(missing) == 0, missing


def _auto_install_host_modules(modules: list[str]) -> list[str]:
    """Attempt pip install for missing modules. Returns modules still missing."""
    if not modules:
        return []
    still_missing: list[str] = []
    for mod in modules:
        pkg = mod
        try:
            result = subprocess.run(
                ["python", "-m", "pip", "install", pkg],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                still_missing.append(mod)
                continue
            try:
                __import__(mod)
            except Exception:
                still_missing.append(mod)
        except Exception:
            still_missing.append(mod)
    return still_missing


def _choose_container_strategy(nf_path: Path, raw_nextflow_path: str) -> Dict[str, Any]:
    """
    Choose execution strategy:
      1) Prefer documented local Docker images that satisfy module requirements.
      2) Fallback to host mode with automatic module installation.
    """
    required_modules = _extract_python_imports(nf_path)
    documented_images = _extract_documented_images()

    # Domain-aware preference order
    image_preferences: list[str] = []
    if raw_nextflow_path.startswith("biomni_nf/"):
        image_preferences.extend(["biomate/biomni-tools:latest", "biomate/biotools:arm64"])
    elif raw_nextflow_path.startswith("nfcore/"):
        image_preferences.extend(["biomate/rnaseq:x86", "biomate/biotools:arm64"])

    # Optional explicit priority list (comma-separated image refs).
    custom_priority = os.environ.get("NEXTFLOW_RUNTIME_IMAGE_PRIORITY", "").strip()
    if custom_priority:
        for image in [p.strip() for p in custom_priority.split(",") if p.strip()]:
            if image not in image_preferences:
                image_preferences.append(image)

    for image in documented_images:
        if image not in image_preferences:
            image_preferences.append(image)

    local_candidates: list[str] = []
    host_arch = _host_arch()
    for img in image_preferences:
        if not _is_local_docker_image(img):
            continue
        compatible, _, image_arch = _is_image_arch_compatible(img)
        if not compatible:
            log.info(
                f"[Nextflow runtime] Skipping cross-arch image {img} "
                f"(host={host_arch}, image={image_arch}). "
                "Set NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER=true to allow emulation."
            )
            continue
        local_candidates.append(img)

    for image in local_candidates:
        if _docker_has_python_modules(image, required_modules):
            docker_opts: list[str] = ['-u $(id -u):$(id -g)', '--entrypoint ""']
            biomni_mount = Path(__file__).resolve().parents[6] / "Biomni"
            if biomni_mount.exists():
                docker_opts.append(f"-v {biomni_mount}:/app/Biomni:ro")
            return {
                "mode": "docker",
                "image": image,
                "docker_opts": " ".join(docker_opts),
                "required_modules": required_modules,
                "missing_modules": [],
                "host_arch": host_arch,
                "image_arch": _image_runtime_arch(image),
                "cross_arch_allowed": os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false"),
            }

    # Fallback: host mode with auto install
    _, missing = _host_has_python_modules(required_modules)
    remaining = _auto_install_host_modules(missing)
    return {
        "mode": "host",
        "image": None,
        "docker_opts": "",
        "required_modules": required_modules,
        "missing_modules": remaining,
        "host_arch": host_arch,
        "image_arch": None,
        "cross_arch_allowed": os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false"),
    }


def _start_qc_monitor(
    invocation_id: str,
    work_dir: Path,
    qc_overrides: Dict[str, Any],
    workflow_domain: str,
    qc_profile: Optional[str] = None,
) -> None:
    """
    Spawn a background thread that polls the Nextflow trace file and fires
    QC gate / warning events via SSE inject for the direct-executor path.

    The thread exits gracefully once the process finishes (no more trace updates
    for 120 s with a COMPLETED/FAILED final status) or after a 12-hour hard cap.
    """
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
    except ImportError:
        log.warning("[QC Monitor] QC gate handler not available — skipping QC monitoring")
        return

    import os as _os
    import json as _json
    import urllib.request as _urllib

    frontend_url = _os.environ.get("FRONTEND_URL", "http://localhost:5000")
    inject_url = f"{frontend_url}/internal/sse-inject"

    def _sse_callback(event_type: str, data: dict) -> None:
        payload = _json.dumps({
            "invocation_id": invocation_id,
            "event_type": event_type,
            "data": data,
        }).encode("utf-8")
        try:
            req = _urllib.Request(
                inject_url,
                data=payload,
                headers={"Content-Type": "application/json"},
            )
            with _urllib.urlopen(req, timeout=5):
                pass
        except Exception as exc:
            log.debug(f"[QC Monitor] SSE inject failed for {event_type}: {exc}")

    handler = NextflowQCGateHandler(
        invocation_id=invocation_id,
        work_dir=work_dir,
        sse_callback=_sse_callback,
        app=None,
        workflow_domain=workflow_domain,
        qc_overrides=qc_overrides,
        qc_profile=qc_profile,
    )

    # Register handler so export endpoint can access live QC state.
    with _qc_handlers_lock:
        _qc_handlers[invocation_id] = handler

    def _poll() -> None:
        import time as _time
        trace_file = work_dir / "workflow-trace.txt"
        seen_tasks: set = set()
        idle_seconds = 0
        max_idle = 120  # seconds without new trace lines before giving up
        hard_cap = 12 * 3600  # 12-hour hard stop

        deadline = _time.monotonic() + hard_cap

        while _time.monotonic() < deadline:
            _time.sleep(5)
            if not trace_file.exists():
                idle_seconds += 5
                if idle_seconds >= max_idle:
                    break
                continue

            try:
                lines = trace_file.read_text(errors="replace").splitlines()
            except OSError:
                continue

            new_task_found = False
            for line in lines[1:]:  # skip header
                if not line.strip():
                    continue
                parts = line.split("\t")
                if len(parts) < 5:
                    continue
                task_id = parts[0].strip()
                process_hash = parts[1].strip()
                process_name = parts[3].strip()
                task_status = parts[4].strip()

                task_key = f"{task_id}:{task_status}"
                if task_key not in seen_tasks and task_status in ("COMPLETED", "FAILED"):
                    seen_tasks.add(task_key)
                    new_task_found = True
                    try:
                        handler.handle_process_completion(
                            task_id=task_id,
                            process_name=process_name,
                            process_hash=process_hash,
                            status=task_status,
                        )
                    except Exception as exc:
                        log.warning(f"[QC Monitor] Error handling {process_name}: {exc}")

            if new_task_found:
                idle_seconds = 0
            else:
                idle_seconds += 5
                if idle_seconds >= max_idle:
                    break

        log.debug(f"[QC Monitor] Monitoring thread for {invocation_id} exiting")
        # Keep handler in registry even after thread exits — it holds the
        # complete in-memory event log that the export endpoint reads.

    t = threading.Thread(target=_poll, daemon=True, name=f"qc-monitor-{invocation_id[:8]}")
    t.start()
    log.info(
        f"[QC Monitor] Started QC monitoring for {invocation_id} "
        f"(domain={workflow_domain}, profile={qc_profile!r}, overrides={list(qc_overrides.keys())})"
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
    try:
        nf_path = _resolve_nextflow_path(request.nextflow_path)
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=404,
            detail=str(exc)
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

    # Entry selection: honor explicit request first; otherwise auto-detect for
    # scripts with named-only workflows (e.g. runnable subworkflows).
    selected_entry = (request.entry or "").strip() or _detect_nextflow_entry(nf_path)
    if selected_entry:
        cmd += ["-entry", selected_entry]

    # Resolve runtime environment using documented local Docker images first.
    strategy = _choose_container_strategy(nf_path, request.nextflow_path)
    if strategy["mode"] == "docker" and strategy["image"]:
        cmd += ["-with-docker", strategy["image"]]
    elif strategy["missing_modules"]:
        raise HTTPException(
            status_code=503,
            detail=(
                "Missing required runtime modules and auto-install failed: "
                + ", ".join(strategy["missing_modules"])
            ),
        )

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
    if selected_entry:
        log.info(f"[Nextflow run {run_id}] entry: {selected_entry}")

    log_path = log_dir / "nextflow.log"

    # Environment
    env = os.environ.copy()
    env["NXF_HOME"] = str(log_dir / ".nextflow")
    if strategy["mode"] == "docker" and strategy["docker_opts"]:
        env["NXF_DOCKER_OPTS"] = strategy["docker_opts"]

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

    # Validate qc_overrides and qc_profile if provided
    qc_overrides = request.qc_overrides or {}
    qc_profile = request.qc_profile or None
    workflow_domain = request.workflow_domain or "unknown"
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
        if qc_overrides:
            valid, errors = NextflowQCGateHandler.validate_qc_overrides(qc_overrides)
            if not valid:
                raise HTTPException(
                    status_code=422,
                    detail={"error": "Invalid qc_overrides", "errors": errors}
                )
        if qc_profile:
            valid, errors = NextflowQCGateHandler.validate_qc_profile(qc_profile)
            if not valid:
                raise HTTPException(
                    status_code=422,
                    detail={"error": "Unknown qc_profile", "errors": errors}
                )
    except ImportError:
        log.warning("[QC] QC gate handler not available — skipping override/profile validation")

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
            "qc_overrides": qc_overrides,
            "qc_profile": qc_profile,
            "workflow_domain": workflow_domain,
            "work_dir": str(work_dir),
            "runtime_mode": strategy["mode"],
            "runtime_image": strategy["image"],
            "entry": selected_entry,
            "required_modules": strategy["required_modules"],
            "missing_modules": strategy["missing_modules"],
            "host_arch": strategy.get("host_arch"),
            "image_arch": strategy.get("image_arch"),
        }

    # Stream logs in background
    t = threading.Thread(
        target=_stream_logs,
        args=(process, run_id, log_path),
        daemon=True,
        name=f"nf-log-{run_id[:8]}",
    )
    t.start()

    # QC monitoring thread — reads trace file and fires QC gate events
    _start_qc_monitor(
        invocation_id=invocation_id,
        work_dir=work_dir,
        qc_overrides=qc_overrides,
        workflow_domain=workflow_domain,
        qc_profile=qc_profile,
    )

    return {
        "success": True,
        "run_id": run_id,
        "invocation_id": invocation_id,
        "status": "running",
        "outputs": {
            "outdir": str(outdir),
        },
        "runtime": {
            "mode": strategy["mode"],
            "image": strategy["image"],
            "entry": selected_entry,
            "required_modules": strategy["required_modules"],
            "missing_modules": strategy["missing_modules"],
            "host_arch": strategy.get("host_arch"),
            "image_arch": strategy.get("image_arch"),
            "cross_arch_allowed": strategy.get("cross_arch_allowed"),
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


@router.get("/api/qc/profiles", summary="List available named QC profiles")
def list_qc_profiles() -> Dict[str, Any]:
    """
    Return all available named QC profiles (Layer 3 — curated threshold sets).

    Each profile includes:
      - id:          str  — profile identifier for use in qc_profile field
      - description: str  — human-readable summary
      - domain_hint: str  — primary workflow domain
      - overrides:   dict — threshold keys and values applied when profile is selected
      - references:  list — primary literature / guideline citations
    """
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
        profiles = NextflowQCGateHandler.list_profiles()
    except ImportError:
        profiles = []
    return {
        "profiles": profiles,
        "count": len(profiles),
    }


@router.get("/api/invocations/{invocation_id}/qc-events",
            summary="Get QC event log for a workflow invocation")
def get_invocation_qc_events(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Return all QC gate and warning events recorded for a workflow invocation.

    Includes:
    - All blocking gate events (type='gate') with failures, metrics, suggestions
    - All near-threshold warning events (type='warning')
    - A methods_text paragraph suitable for inserting into paper methods sections
    - Summary counts (gates_triggered, warnings_emitted)
    """
    try:
        from galaxy.jobs.runners.nextflow_monitor import get_monitor_service
        monitor_service = get_monitor_service(trans.app)

        # Try integer lookup first (Galaxy invocation IDs), then string
        monitor = None
        for key in (invocation_id, int(invocation_id) if invocation_id.isdigit() else None):
            if key is None:
                continue
            monitor = monitor_service.monitors.get(key)
            if monitor:
                break

        if monitor is None or monitor.qc_handler is None:
            # Attempt to locate a persisted JSONL audit log even if monitor is gone
            import json as _json
            jobs_dir = getattr(getattr(trans.app, 'config', None), 'root', None)
            if jobs_dir:
                from pathlib import Path as _Path
                audit_path = (_Path(jobs_dir) / 'database' / 'jobs_directory'
                              / 'nextflow_workflows' / f"workflow_{invocation_id}"
                              / "qc_overrides_audit.jsonl")
                if audit_path.exists():
                    entries = []
                    for line in audit_path.read_text().splitlines():
                        try:
                            entries.append(_json.loads(line))
                        except Exception:
                            pass
                    return {
                        "invocation_id": invocation_id,
                        "source": "audit_jsonl",
                        "gates_triggered": sum(1 for e in entries if e.get("event_type") == "gate_triggered"),
                        "warnings_emitted": 0,
                        "events": entries,
                        "methods_text": "QC governance applied (see audit log for details).",
                    }
            return {
                "invocation_id": invocation_id,
                "source": "not_found",
                "gates_triggered": 0,
                "warnings_emitted": 0,
                "events": [],
                "methods_text": "No QC events recorded for this invocation.",
            }

        report = monitor.qc_handler.get_qc_report()
        report["source"] = "live_monitor"
        return report

    except Exception as e:
        log.error(f"[QC Events] Failed to retrieve events for {invocation_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to retrieve QC events: {e}")


# ---------------------------------------------------------------------------
# QC Report Export
# ---------------------------------------------------------------------------

class QCReportExportRequest(BaseModel):
    invocation_id: str
    format: str = "html"


def _lookup_work_dir_for_invocation(invocation_id: str) -> Optional[Path]:
    """
    Resolve the Nextflow work directory for a given invocation_id.

    Searches the in-process _runs registry (keyed by run_id) for a run whose
    invocation_id matches.  Returns None if no matching run is found.
    """
    with _runs_lock:
        for run_info in _runs.values():
            if run_info.get("invocation_id") == invocation_id:
                wd = run_info.get("work_dir")
                return Path(wd) if wd else None
    return None


def _build_qc_report_from_jsonl(invocation_id: str, audit_path: Path) -> Dict[str, Any]:
    """
    Reconstruct a minimal QC report from a persisted JSONL audit file.

    The audit file records override/profile initialisation and gate-trigger events.
    It does NOT contain full metric snapshots, so the reconstructed report has
    less detail than the live in-memory version.
    """
    import json as _json

    entries = []
    try:
        for line in audit_path.read_text(errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(_json.loads(line))
            except Exception:
                pass
    except OSError:
        pass

    gate_entries = [e for e in entries if e.get("event_type") == "gate_triggered"]
    active_profile = next(
        (e.get("active_profile") for e in entries if e.get("active_profile")), None
    )
    active_overrides = next(
        (e.get("configured_overrides", {}) for e in entries), {}
    )

    events = []
    for e in gate_entries:
        events.append({
            "type": "gate",
            "process_name": e.get("applied_overrides", {}).get("process_name", "unknown"),
            "timestamp": e.get("timestamp", ""),
            "metrics": {},
            "failures": [],
            "suggestions": [],
            "active_profile": e.get("active_profile"),
        })

    return {
        "invocation_id": invocation_id,
        "active_profile": active_profile,
        "active_overrides": active_overrides,
        "gates_triggered": len(gate_entries),
        "warnings_emitted": 0,
        "events": events,
        "methods_text": "QC governance applied (see audit log for details).",
        "source": "audit_jsonl",
    }


def _html_escape(value: Any) -> str:
    """Minimal HTML escaping for values embedded in table cells."""
    s = str(value)
    return (
        s.replace("&", "&amp;")
         .replace("<", "&lt;")
         .replace(">", "&gt;")
         .replace('"', "&quot;")
    )


def _render_qc_report_html(report: Dict[str, Any]) -> str:
    """
    Generate a self-contained HTML QC report from a structured report dict.

    The report dict is the same shape returned by NextflowQCGateHandler.get_qc_report().
    """
    from datetime import datetime as _dt, timezone as _tz

    invocation_id = report.get("invocation_id", "unknown")
    active_profile = report.get("active_profile") or "none"
    active_overrides = report.get("active_overrides", {})
    gates_triggered = report.get("gates_triggered", 0)
    warnings_emitted = report.get("warnings_emitted", 0)
    events = report.get("events", [])
    methods_text = _html_escape(report.get("methods_text", ""))
    source = report.get("source", "unknown")

    generated_at = _dt.now(_tz.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    # Summary counts
    gate_events = [e for e in events if e.get("type") == "gate"]
    warn_events = [e for e in events if e.get("type") == "warning"]
    total_steps = len(set(e.get("process_name", "") for e in events))
    failed_steps = len(set(e.get("process_name", "") for e in gate_events))
    warning_steps = len(set(e.get("process_name", "") for e in warn_events))
    passed_steps = total_steps - failed_steps

    # Build overrides table rows
    overrides_rows = ""
    if active_overrides:
        for metric, val in sorted(active_overrides.items()):
            overrides_rows += (
                f"<tr><td>{_html_escape(metric)}</td>"
                f"<td>{_html_escape(val)}</td></tr>\n"
            )
    else:
        overrides_rows = '<tr><td colspan="2" class="none">No custom overrides applied</td></tr>'

    # Build per-step event rows
    step_rows = ""
    for event in events:
        etype = event.get("type", "")
        process_name = _html_escape(event.get("process_name", "unknown"))
        timestamp = _html_escape(event.get("timestamp", ""))
        profile_used = _html_escape(event.get("active_profile") or "none")

        if etype == "gate":
            status_cell = '<td class="status-failed">FAILED</td>'
            row_class = "row-failed"
            failures = event.get("failures", [])
            detail_cells = _render_failures_cells(failures)
        elif etype == "warning":
            status_cell = '<td class="status-warning">WARNING</td>'
            row_class = "row-warning"
            warnings_list = event.get("warnings", [])
            detail_cells = _render_warnings_cells(warnings_list)
        else:
            status_cell = '<td class="status-passed">PASSED</td>'
            row_class = "row-passed"
            detail_cells = "<td>-</td><td>-</td><td>-</td><td>-</td>"

        step_rows += (
            f'<tr class="{row_class}">'
            f"<td>{process_name}</td>"
            f"{status_cell}"
            f"<td>{timestamp}</td>"
            f"<td>{profile_used}</td>"
            f"{detail_cells}"
            f"</tr>\n"
        )

    if not step_rows:
        step_rows = (
            '<tr><td colspan="8" class="none">'
            "No QC events recorded — all processes passed automatically."
            "</td></tr>"
        )

    # Build suggestions section (only if any gate events have suggestions)
    suggestions_section = ""
    all_suggestions = []
    for event in gate_events:
        for s in event.get("suggestions", []):
            all_suggestions.append((event.get("process_name", ""), s))

    if all_suggestions:
        sug_rows = ""
        for proc, s in all_suggestions:
            sug_rows += (
                f"<tr>"
                f"<td>{_html_escape(proc)}</td>"
                f"<td>{_html_escape(s.get('parameter', ''))}</td>"
                f"<td>{_html_escape(s.get('currentValue', ''))}</td>"
                f"<td>{_html_escape(s.get('suggestedValue', ''))}</td>"
                f"<td>{_html_escape(s.get('reason', ''))}</td>"
                f"<td>{_html_escape(s.get('confidence', ''))}</td>"
                f"</tr>\n"
            )
        suggestions_section = f"""
        <h2>Parameter Suggestions</h2>
        <table>
          <thead>
            <tr>
              <th>Process</th><th>Parameter</th><th>Current Value</th>
              <th>Suggested Value</th><th>Reason</th><th>Confidence</th>
            </tr>
          </thead>
          <tbody>{sug_rows}</tbody>
        </table>
        """

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>BioMate QC Report — {_html_escape(invocation_id)}</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 14px;
      color: #1a1a1a;
      background: #f5f5f5;
      margin: 0;
      padding: 24px;
    }}
    .container {{
      max-width: 1200px;
      margin: 0 auto;
      background: #fff;
      border-radius: 8px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.1);
      padding: 32px;
    }}
    h1 {{
      font-size: 22px;
      font-weight: 700;
      margin: 0 0 4px;
      color: #111;
    }}
    h2 {{
      font-size: 16px;
      font-weight: 600;
      margin: 28px 0 10px;
      border-bottom: 1px solid #e0e0e0;
      padding-bottom: 6px;
      color: #333;
    }}
    .meta {{
      font-size: 12px;
      color: #666;
      margin-bottom: 24px;
    }}
    .meta span {{ margin-right: 18px; }}
    .summary-grid {{
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 12px;
      margin-bottom: 24px;
    }}
    .summary-card {{
      border-radius: 6px;
      padding: 14px 18px;
      text-align: center;
    }}
    .card-total   {{ background: #f0f4ff; border: 1px solid #c5d3f7; }}
    .card-passed  {{ background: #f0faf4; border: 1px solid #a8d5b8; }}
    .card-failed  {{ background: #fff4f4; border: 1px solid #f5c5c5; }}
    .card-warning {{ background: #fff9ec; border: 1px solid #f5dfa5; }}
    .summary-card .number {{
      font-size: 28px;
      font-weight: 700;
      line-height: 1.2;
    }}
    .summary-card .label {{
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #555;
      margin-top: 2px;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
      margin-bottom: 16px;
    }}
    th {{
      background: #f5f5f5;
      text-align: left;
      padding: 8px 10px;
      border: 1px solid #ddd;
      font-weight: 600;
      white-space: nowrap;
    }}
    td {{
      padding: 7px 10px;
      border: 1px solid #e8e8e8;
      vertical-align: top;
    }}
    tr:hover td {{ background: #fafafa; }}
    .row-failed td {{ background: #fff8f8; }}
    .row-warning td {{ background: #fffbf0; }}
    .row-passed td {{ background: #f8fff9; }}
    .status-passed  {{ color: #1a7f3c; font-weight: 600; }}
    .status-failed  {{ color: #b91c1c; font-weight: 600; }}
    .status-warning {{ color: #b45309; font-weight: 600; }}
    .tier-gold   {{ color: #b45309; font-weight: 600; }}
    .tier-silver {{ color: #64748b; font-weight: 600; }}
    .tier-bronze {{ color: #92400e; font-weight: 600; }}
    .advisory    {{ color: #6d4c41; font-style: italic; }}
    .methods-box {{
      background: #f8faff;
      border: 1px solid #d0d9f0;
      border-radius: 6px;
      padding: 14px 18px;
      font-size: 13px;
      line-height: 1.6;
      margin-bottom: 24px;
    }}
    .overrides-small {{
      font-size: 12px;
      color: #555;
    }}
    .none {{
      color: #888;
      font-style: italic;
    }}
    .footer {{
      margin-top: 32px;
      padding-top: 14px;
      border-top: 1px solid #e8e8e8;
      font-size: 11px;
      color: #999;
      text-align: center;
    }}
    .badge {{
      display: inline-block;
      padding: 1px 7px;
      border-radius: 9px;
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }}
    .badge-source {{
      background: #e8f0fe;
      color: #1a73e8;
    }}
  </style>
</head>
<body>
<div class="container">

  <h1>BioMate QC Governance Report</h1>
  <div class="meta">
    <span><strong>Invocation ID:</strong> {_html_escape(invocation_id)}</span>
    <span><strong>Generated:</strong> {generated_at}</span>
    <span><strong>QC Profile:</strong> {_html_escape(active_profile)}</span>
    <span><span class="badge badge-source">{_html_escape(source)}</span></span>
  </div>

  <h2>Summary</h2>
  <div class="summary-grid">
    <div class="summary-card card-total">
      <div class="number">{total_steps}</div>
      <div class="label">Total Steps with QC Events</div>
    </div>
    <div class="summary-card card-passed">
      <div class="number">{passed_steps}</div>
      <div class="label">Passed Steps</div>
    </div>
    <div class="summary-card card-failed">
      <div class="number">{failed_steps}</div>
      <div class="label">Failed Steps</div>
    </div>
    <div class="summary-card card-warning">
      <div class="number">{warning_steps + warnings_emitted}</div>
      <div class="label">Advisory Warnings</div>
    </div>
  </div>

  <h2>Methods Summary</h2>
  <div class="methods-box">{methods_text}</div>

  <h2>Per-Step QC Gate Results</h2>
  <table>
    <thead>
      <tr>
        <th>Process Name</th>
        <th>Status</th>
        <th>Timestamp</th>
        <th>Profile</th>
        <th>Metric</th>
        <th>Value</th>
        <th>Threshold</th>
        <th>Tier</th>
      </tr>
    </thead>
    <tbody>
      {step_rows}
    </tbody>
  </table>

  {suggestions_section}

  <h2>Active Threshold Overrides</h2>
  <table class="overrides-small">
    <thead>
      <tr><th>Metric</th><th>Override Value</th></tr>
    </thead>
    <tbody>
      {overrides_rows}
    </tbody>
  </table>

  <div class="footer">
    Generated by BioMate QC Governance Engine &mdash;
    <a href="https://biomate.ai" style="color:#999;">biomate.ai</a>
  </div>

</div>
</body>
</html>"""

    return html


def _render_failures_cells(failures: list) -> str:
    """Render the Metric / Value / Threshold / Tier table cells for gate failures."""
    if not failures:
        return "<td>-</td><td>-</td><td>-</td><td>-</td>"

    metric_parts, value_parts, threshold_parts, tier_parts = [], [], [], []
    for f in failures:
        metric = _html_escape(f.get("metric", ""))
        value = _html_escape(f.get("value", ""))
        threshold = _html_escape(f.get("threshold", ""))
        tier = _html_escape(f.get("tier", f.get("severity", "")))
        advisory = f.get("advisory", False)
        msg = _html_escape(f.get("message", ""))

        tier_class = ""
        if "GOLD" in tier.upper():
            tier_class = "tier-gold"
        elif "SILVER" in tier.upper():
            tier_class = "tier-silver"
        elif "BRONZE" in tier.upper():
            tier_class = "tier-bronze"

        adv_note = ' <span class="advisory">(advisory)</span>' if advisory else ""

        metric_parts.append(f"{metric}{adv_note}")
        value_parts.append(str(value))
        threshold_parts.append(f"{threshold} &mdash; {msg}" if msg else str(threshold))
        tier_parts.append(f'<span class="{tier_class}">{tier}</span>' if tier_class else tier)

    sep = "<br>"
    return (
        f"<td>{sep.join(metric_parts)}</td>"
        f"<td>{sep.join(value_parts)}</td>"
        f"<td>{sep.join(threshold_parts)}</td>"
        f"<td>{sep.join(tier_parts)}</td>"
    )


def _render_warnings_cells(warnings: list) -> str:
    """Render the Metric / Value / Threshold / Tier table cells for near-threshold warnings."""
    if not warnings:
        return "<td>-</td><td>-</td><td>-</td><td>-</td>"

    metric_parts, value_parts, threshold_parts, tier_parts = [], [], [], []
    for w in warnings:
        metric = _html_escape(w.get("metric", ""))
        value = _html_escape(w.get("value", ""))
        threshold = _html_escape(w.get("threshold", ""))
        severity = _html_escape(w.get("severity", "near_threshold"))
        msg = _html_escape(w.get("message", ""))

        metric_parts.append(metric)
        value_parts.append(str(value))
        threshold_parts.append(f"{threshold} &mdash; {msg}" if msg else str(threshold))
        tier_parts.append(severity)

    sep = "<br>"
    return (
        f"<td>{sep.join(metric_parts)}</td>"
        f"<td>{sep.join(value_parts)}</td>"
        f"<td>{sep.join(threshold_parts)}</td>"
        f"<td>{sep.join(tier_parts)}</td>"
    )


@router.post(
    "/api/export/qc_report",
    summary="Export QC governance report as HTML",
    response_class=HTMLResponse,
)
def export_qc_report(
    request: QCReportExportRequest,
) -> HTMLResponse:
    """
    Generate and return an HTML QC governance report for a workflow invocation.

    Lookup order:
      1. In-memory QC handler registry (_qc_handlers) — populated when the workflow
         is launched via POST /api/nextflow/execute.
      2. Persisted JSONL audit log at <work_dir>/qc_overrides_audit.jsonl — used when
         the handler has been evicted or the process was launched in a previous session.

    Accepted formats: "html" (only format supported in v1).

    Returns Content-Type: text/html.
    """
    invocation_id = request.invocation_id.strip()
    fmt = (request.format or "html").lower()

    if fmt != "html":
        raise HTTPException(
            status_code=422,
            detail=f"Unsupported format '{fmt}'. Only 'html' is supported.",
        )

    if not invocation_id:
        raise HTTPException(status_code=422, detail="invocation_id must not be empty.")

    report: Optional[Dict[str, Any]] = None

    # --- Path 1: live in-memory handler ---
    with _qc_handlers_lock:
        handler = _qc_handlers.get(invocation_id)

    if handler is not None:
        try:
            report = handler.get_qc_report()
            report["source"] = "live_handler"
        except Exception as exc:
            log.warning(f"[QC Export] Failed to get report from live handler: {exc}")

    # --- Path 2: persisted JSONL audit file ---
    if report is None:
        work_dir = _lookup_work_dir_for_invocation(invocation_id)
        if work_dir is not None:
            audit_path = work_dir / "qc_overrides_audit.jsonl"
            if audit_path.exists():
                report = _build_qc_report_from_jsonl(invocation_id, audit_path)

    # --- Path 3: empty report (no QC data recorded yet) ---
    if report is None:
        report = {
            "invocation_id": invocation_id,
            "active_profile": None,
            "active_overrides": {},
            "gates_triggered": 0,
            "warnings_emitted": 0,
            "events": [],
            "methods_text": (
                "No QC events have been recorded for this invocation. "
                "The workflow may still be running, or QC monitoring was not enabled."
            ),
            "source": "not_found",
        }

    try:
        html_content = _render_qc_report_html(report)
    except Exception as exc:
        log.error(f"[QC Export] HTML rendering failed for {invocation_id}: {exc}")
        raise HTTPException(status_code=500, detail=f"HTML rendering failed: {exc}")

    return HTMLResponse(content=html_content, status_code=200)
