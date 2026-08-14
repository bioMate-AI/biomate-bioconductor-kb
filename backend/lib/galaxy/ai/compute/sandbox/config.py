"""Sandbox configuration — tier, resource limits, runtime, egress policy.

Feature ① (see docs/20260813 roadmap). Three tiers of increasing isolation:

* **Tier 1** — rootless container: cap-drop ALL, no-new-privileges, default
  seccomp, read-only rootfs + tmpfs workdir, cgroup cpu/mem/pids caps,
  non-root per-run UID. Network = default bridge. For trusted enterprise.
* **Tier 2** — Tier 1 + egress restricted (a named egress network or none)
  + optional custom seccomp profile. Multi-tenant SaaS default.
* **Tier 3** — Tier 2 + gVisor (`--runtime=runsc`) for kernel-level
  isolation of untrusted code. (Firecracker microVM/run is a documented
  Tier-3b alternative that needs host provisioning; not modeled here.)

Everything is env-driven and defaults to **disabled**, so importing/using
this module changes nothing until an operator opts in.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Dict, List, Optional

from ..run_spec import RunSpec, ResourceTier, TIER_RESOURCES


class SandboxTier(IntEnum):
    TIER1 = 1  # container isolation
    TIER2 = 2  # + restricted egress
    TIER3 = 3  # + gVisor / microVM


def _env_bool(name: str, default: bool = False) -> bool:
    v = os.environ.get(name)
    if v is None:
        return default
    return v.lower() in ("1", "true", "yes", "on")


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, "") or default)
    except (TypeError, ValueError):
        return default


# Secret-bearing env prefixes/substrings that must NEVER be handed to an
# untrusted sandboxed process. Credential leakage into user code is a primary
# multi-tenant risk — the container gets a filtered env (see command.py).
SECRET_ENV_MARKERS = (
    "AWS_", "_KEY", "_SECRET", "_TOKEN", "SECRET", "PASSWORD", "PASSWD",
    "LAGO_", "BILLING_", "DATABASE_URL", "REDIS_URL", "GALAXY_SECRET",
    "OPENAI", "ANTHROPIC", "GEMINI", "HF_TOKEN", "HUGGING",
)

# Env keys that are safe (and needed) inside the sandbox.
SAFE_ENV_ALLOWLIST = (
    "PATH", "HOME", "LANG", "LC_ALL", "TERM", "TZ",
    "NXF_VER", "NXF_HOME", "NXF_OFFLINE", "NXF_ANSI_LOG", "NXF_OPTS",
    "JAVA_HOME", "JAVA_OPTS",
)


@dataclass
class SandboxConfig:
    """Resolved sandbox policy for a single run."""

    enabled: bool = False
    tier: SandboxTier = SandboxTier.TIER1
    runtime: str = "docker"                 # "docker" | "podman"
    # Built + validated on test 2026-08-14 (docker/sandbox/Dockerfile), pushed
    # to ECR. Override with SANDBOX_IMAGE. Nothing pulls it unless enabled.
    image: str = "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-sandbox:latest"
    container_nextflow_bin: str = "nextflow"  # nextflow on PATH inside image

    # cgroup limits
    cpus: float = 2.0
    mem_gb: int = 12
    pids_limit: int = 512

    # isolation knobs
    read_only_rootfs: bool = True
    tmpfs_size_mb: int = 2048
    drop_all_caps: bool = True
    no_new_privileges: bool = True
    seccomp_profile: Optional[str] = None   # path; None = runtime default
    gvisor_runtime: Optional[str] = None    # e.g. "runsc" (Tier 3)

    # network / egress
    network_mode: str = "bridge"            # tier1: bridge; tier2: none|<net>

    # per-run identity + mounts
    run_uid: Optional[int] = None           # non-root uid for the container
    run_gid: Optional[int] = None
    extra_ro_mounts: List[str] = field(default_factory=list)

    # validation policy
    validate_uploads: bool = True           # run the static .nf pre-check
    reject_on_violation: bool = True        # block on a "block"-severity hit

    @property
    def strict(self) -> bool:
        return self.enabled and self.reject_on_violation

    @classmethod
    def from_env(
        cls,
        *,
        spec: Optional[RunSpec] = None,
        run_id: str = "",
    ) -> "SandboxConfig":
        """Build a config from SANDBOX_* env vars, sized by the RunSpec tier."""
        enabled = _env_bool("SANDBOX_ENABLED", False)
        tier = SandboxTier(_env_int("SANDBOX_TIER", 1))

        # Size cgroup caps from the workflow's heaviest declared tier, falling
        # back to LOW. Operators can hard-override via env.
        res = TIER_RESOURCES[ResourceTier.LOW]
        if spec and spec.tiers:
            heaviest = max(spec.tiers, key=lambda t: TIER_RESOURCES[t]["mem_gb"])
            res = TIER_RESOURCES[heaviest]
        cpus = float(os.environ.get("SANDBOX_CPUS", "") or res["cpus"])
        mem_gb = _env_int("SANDBOX_MEM_GB", res["mem_gb"])
        pids_limit = _env_int("SANDBOX_PIDS_LIMIT", 512)

        # Tier-driven defaults for egress + gVisor, overridable by env.
        default_network = "bridge"
        gvisor = None
        if tier >= SandboxTier.TIER2:
            default_network = os.environ.get("SANDBOX_EGRESS_NETWORK", "none")
        if tier >= SandboxTier.TIER3:
            gvisor = os.environ.get("SANDBOX_GVISOR_RUNTIME", "runsc")
        network_mode = os.environ.get("SANDBOX_NETWORK_MODE", default_network)

        ro_mounts = [
            m for m in os.environ.get("SANDBOX_RO_MOUNTS", "").split(",") if m.strip()
        ]

        # Deterministic non-root uid derived from run_id so concurrent runs
        # don't share an identity (avoids the shared /tmp/biomate_user_nf
        # cross-run surface). Range 20000-29999 avoids system/user collisions.
        run_uid = None
        if run_id:
            run_uid = 20000 + (abs(hash(run_id)) % 10000)

        return cls(
            enabled=enabled,
            tier=tier,
            runtime=os.environ.get("SANDBOX_RUNTIME", "docker"),
            image=os.environ.get(
                "SANDBOX_IMAGE",
                "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-sandbox:latest",
            ),
            container_nextflow_bin=os.environ.get("SANDBOX_NEXTFLOW_BIN", "nextflow"),
            cpus=cpus,
            mem_gb=mem_gb,
            pids_limit=pids_limit,
            seccomp_profile=os.environ.get("SANDBOX_SECCOMP_PROFILE") or None,
            gvisor_runtime=gvisor,
            network_mode=network_mode,
            run_uid=run_uid,
            run_gid=run_uid,
            extra_ro_mounts=ro_mounts,
            validate_uploads=_env_bool("SANDBOX_VALIDATE_UPLOADS", True),
            reject_on_violation=_env_bool("SANDBOX_REJECT_ON_VIOLATION", True),
        )
