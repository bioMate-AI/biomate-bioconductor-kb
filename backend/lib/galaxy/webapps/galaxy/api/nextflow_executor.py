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
