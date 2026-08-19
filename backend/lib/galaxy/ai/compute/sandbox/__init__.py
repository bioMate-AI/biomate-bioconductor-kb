"""Feature ① — execution sandbox for user-supplied code.

Keeps BioMate's "run arbitrary .nf / run_code" capability while wrapping
each run's Nextflow head process in a locked-down container / gVisor /
microVM. Built on the M0.1 head-launch seam: :class:`SandboxedHeadLauncher`
decorates the base launcher, so all the existing concurrency / logging / pid
/ orphan-recovery machinery is reused unchanged.

See docs/20260813_ISOLATION_PRIVATE_DEPLOY_SCHEDULER_ROADMAP.md (Feature ①).
"""

from __future__ import annotations

from .config import SandboxConfig, SandboxTier
from .command import (
    build_sandbox_command,
    filter_container_env,
    is_secret_env_key,
)
from .validator import (
    Violation,
    validate_nextflow_source,
    has_blocking,
    format_violations,
)
from .launcher import SandboxedHeadLauncher

__all__ = [
    "SandboxConfig",
    "SandboxTier",
    "build_sandbox_command",
    "filter_container_env",
    "is_secret_env_key",
    "Violation",
    "validate_nextflow_source",
    "has_blocking",
    "format_violations",
    "SandboxedHeadLauncher",
]
