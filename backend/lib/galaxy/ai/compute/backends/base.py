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
