"""Build the sandboxed launch command (docker/podman run wrapper).

Wraps the original ``nextflow run ...`` argv so the **entire head process**
runs inside a locked-down container. Wrapping the head (not just Nextflow's
per-task ``-with-docker``) is deliberate: the Groovy in a user .nf executes
on the head at parse/eval time, so the head itself is an attack surface and
must be inside the boundary.

Pure functions returning argv lists — no side effects — so the isolation
flags are exhaustively unit-testable without a container runtime present.
"""

from __future__ import annotations

from typing import Dict, List, Optional, Tuple

from .config import (
    SandboxConfig,
    SandboxTier,
    IMAGE_OWNED_ENV,
    SAFE_ENV_ALLOWLIST,
    SECRET_ENV_MARKERS,
)


def is_secret_env_key(key: str) -> bool:
    """True if a key looks credential-bearing (must not enter the sandbox)."""
    upper = key.upper()
    return any(marker in upper for marker in SECRET_ENV_MARKERS)


def filter_container_env(env: Dict[str, str]) -> Dict[str, str]:
    """Keep only safe env; drop anything credential-bearing.

    Order matters: image-owned keys are dropped first (forwarding the host's
    PATH/HOME would clobber the container's own and break nextflow lookup),
    then secrets, then the allowlist + safe NXF_/public prefixes. This keeps
    AWS/LLM/DB/billing creds out of untrusted user code and never overrides
    the image's runtime infrastructure.
    """
    out: Dict[str, str] = {}
    for k, v in (env or {}).items():
        if k in IMAGE_OWNED_ENV:
            continue  # image provides these; forwarding host values breaks them
        if is_secret_env_key(k):
            continue
        if k in SAFE_ENV_ALLOWLIST:
            out[k] = v
            continue
        # Pass through non-secret NXF_*/BIOMATE_PUBLIC_ hints, drop the rest to
        # keep the sandbox env minimal and predictable.
        if k.startswith("NXF_") or k.startswith("BIOMATE_PUBLIC_"):
            out[k] = v
    return out


def _isolation_flags(config: SandboxConfig) -> List[str]:
    """The security-relevant `docker run` flags for the configured tier."""
    flags: List[str] = ["--rm"]

    # gVisor / alternative runtime (Tier 3).
    if config.gvisor_runtime:
        flags += ["--runtime", config.gvisor_runtime]

    # Non-root, per-run identity.
    if config.run_uid is not None:
        gid = config.run_gid if config.run_gid is not None else config.run_uid
        flags += ["--user", f"{config.run_uid}:{gid}"]

    # Capabilities + privilege escalation.
    if config.drop_all_caps:
        flags += ["--cap-drop", "ALL"]
    if config.no_new_privileges:
        flags += ["--security-opt", "no-new-privileges"]

    # seccomp: explicit profile if given, else the runtime default (which is
    # already restrictive). We never pass seccomp=unconfined.
    if config.seccomp_profile:
        flags += ["--security-opt", f"seccomp={config.seccomp_profile}"]

    # Read-only rootfs + a bounded tmpfs for scratch.
    if config.read_only_rootfs:
        flags += ["--read-only"]
        flags += ["--tmpfs", f"/tmp:rw,nosuid,nodev,size={config.tmpfs_size_mb}m"]

    # cgroup resource caps.
    flags += ["--cpus", str(config.cpus)]
    flags += ["--memory", f"{config.mem_gb}g"]
    flags += ["--pids-limit", str(config.pids_limit)]

    # Network / egress.
    flags += ["--network", config.network_mode]

    return flags


def _mount_flags(
    work_dir: str,
    nf_source_path: Optional[str],
    config: SandboxConfig,
) -> List[str]:
    """Bind-mount ONLY this run's work dir (rw) + the .nf (ro) + allowlist."""
    flags: List[str] = []
    # The run's work dir is the single writable surface.
    flags += ["-v", f"{work_dir}:{work_dir}:rw"]
    flags += ["-w", work_dir]
    # The user's .nf script, read-only, so the container can't rewrite it.
    if nf_source_path:
        flags += ["-v", f"{nf_source_path}:{nf_source_path}:ro"]
    # Operator-provided read-only mounts (reference data, etc.).
    for m in config.extra_ro_mounts:
        spec = m if m.count(":") >= 1 else f"{m}:{m}"
        if not spec.endswith(":ro"):
            spec = spec + ":ro"
        flags += ["-v", spec]
    return flags


def build_sandbox_command(
    base_cmd: List[str],
    *,
    work_dir: str,
    nf_source_path: Optional[str],
    container_env: Dict[str, str],
    config: SandboxConfig,
) -> List[str]:
    """Return the full ``<runtime> run [flags] <image> <nextflow ...>`` argv.

    ``base_cmd[0]`` is the host Nextflow binary path; it is replaced with the
    container's nextflow (on PATH in the sandbox image). The remaining args
    (run, <script>, -params-file, -c, -profile, ...) pass through unchanged.
    """
    if not base_cmd:
        raise ValueError("base_cmd must not be empty")

    argv: List[str] = [config.runtime, "run"]
    argv += _isolation_flags(config)
    argv += _mount_flags(work_dir, nf_source_path, config)

    # Filtered container env, one -e per key (kept out of the host env).
    for k, v in filter_container_env(container_env).items():
        argv += ["-e", f"{k}={v}"]

    argv += [config.image]

    # Replace the host nextflow binary with the container's.
    inner = list(base_cmd)
    inner[0] = config.container_nextflow_bin
    argv += inner
    return argv
