"""The ``ComputeBackend`` Protocol and its supporting value types.

A backend is anything that can take a :class:`RunSpec`, start the run,
report status, cancel it, and hand back output locations. The two existing
paths (local subprocess, AWS Batch via Nextflow) become the first two
implementations; the sandbox / Slurm / K8s backends are added later without
touching this contract.

Phase 0 note: these are Protocols + lightweight dataclasses only. The
concrete backends currently raise ``NotImplementedError`` from ``submit``
until Phase 0's parity work (M0) wraps the real launch code — nothing calls
them in production yet.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Protocol, runtime_checkable

from ..run_spec import RunSpec
from ..launcher import HeadLauncher, LaunchRequest, get_default_head_launcher


class RunStatus(str, Enum):
    """Normalized run lifecycle status across all backends."""

    PENDING = "pending"
    FETCHING = "fetching_accessions"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    INTERRUPTED = "interrupted"
    CANCELLED = "cancelled"


@dataclass
class RunHandle:
    """Opaque handle a backend returns from ``submit``.

    Carries enough for ``poll`` / ``cancel`` to find the run regardless of
    backend (a local PID + workdir, or a Batch/Nextflow session id).
    """

    run_id: str
    backend: str
    native_id: Optional[str] = None   # OS pid, Batch job id, k8s job name...
    work_dir: Optional[str] = None
    log_path: Optional[str] = None
    extra: Dict[str, Any] = field(default_factory=dict)


@dataclass
class BackendCapabilities:
    """What a backend can do — consumed by the future scoring policy (③).

    Populated cheaply in Phase 0 (static values); later backed by live
    queue-depth / spot-price probes.
    """

    name: str
    supports_gpu: bool = False
    max_mem_gb: Optional[int] = None
    max_cpus: Optional[int] = None
    supports_s3: bool = False
    supports_local_fs: bool = False
    # Rough cost signal for the scheduler; None = "free"/local.
    usd_per_vcpu_hour: Optional[float] = None
    # Data localities this backend can read/write natively.
    data_localities: List[str] = field(default_factory=list)


class HeadLaunchMixin:
    """Shared plumbing for backends whose head process is launched the same way.

    Local / AWS-Batch / Slurm / K8s all launch an identical local Nextflow
    head; they differ only in the executor config they generate. This mixin
    holds the injected :class:`HeadLauncher` and exposes :meth:`launch_head`
    so those backends share one launch path (and the sandbox backend swaps in
    a sandboxed launcher). Injection is preferred for tests; falling back to
    the process-wide default keeps production wiring a one-liner.
    """

    def __init__(self, head_launcher: Optional[HeadLauncher] = None) -> None:
        self._head_launcher = head_launcher

    @property
    def head_launcher(self) -> Optional[HeadLauncher]:
        return self._head_launcher or get_default_head_launcher()

    def launch_head(self, req: LaunchRequest) -> Any:
        launcher = self.head_launcher
        if launcher is None:
            raise RuntimeError(
                "No HeadLauncher available. Inject one into the backend or "
                "call launcher.set_default_head_launcher() from the executor. "
                "See docs/20260813 roadmap (M0)."
            )
        return launcher.launch(req)


@runtime_checkable
class ComputeBackend(Protocol):
    """Contract every execution backend implements."""

    def capabilities(self) -> BackendCapabilities:
        """Static/dynamic description used by the scheduler's scoring."""
        ...

    def submit(self, spec: RunSpec) -> RunHandle:
        """Start the run. Returns a handle; does not block to completion."""
        ...

    def poll(self, handle: RunHandle) -> RunStatus:
        """Return the current normalized status of a submitted run."""
        ...

    def cancel(self, handle: RunHandle) -> bool:
        """Best-effort cancel. Returns True if a stop signal was delivered."""
        ...

    def collect_outputs(self, handle: RunHandle) -> List[Dict[str, Any]]:
        """Return output descriptors (uri/filename/...) for a finished run."""
        ...
