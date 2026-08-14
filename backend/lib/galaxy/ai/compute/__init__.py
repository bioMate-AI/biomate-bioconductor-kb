"""BioMate compute-platform abstraction (Phase 0).

This package is the shared spine for three initiatives (see
``docs/20260813_ISOLATION_PRIVATE_DEPLOY_SCHEDULER_ROADMAP.md``):

* **Sandbox isolation** — a future ``SandboxedLocalBackend`` that wraps the
  bare ``subprocess.Popen`` local path in a container / microVM.
* **Private / air-gap deployment** — swappable backends
  (``AWSBatchBackend`` -> ``SlurmBackend`` / ``K8sBackend``) and storage
  (``S3Backend`` -> ``MinIOStorageBackend`` via ``endpoint_url``).
* **Scheduler** — ``Scheduler.select_backend`` upgraded from today's single
  ``NEXTFLOW_USE_AWS`` boolean into capability / cost-aware dispatch with
  fallback.

Phase 0 scope is deliberately narrow and **behavior-preserving**:

* Define the data model (:class:`~galaxy.ai.compute.run_spec.RunSpec`) and
  the two Protocols (``ComputeBackend``, ``StorageBackend``).
* Provide a :class:`~galaxy.ai.compute.scheduler.Scheduler` whose v1
  decision is *logic-equivalent* to the legacy routing block in
  ``nextflow_executor.execute_nextflow``.
* Gate everything behind the ``COMPUTE_BACKEND_V2`` env flag (default
  **off**). When on, the scheduler runs in **shadow mode** — it computes a
  decision and logs whether it agrees with the legacy path, but never acts
  on it. No production code path changes until this is proven at parity.

Import-safety: this package must import cleanly on Python 3.9 with no heavy
third-party deps (boto3 etc. are imported lazily inside methods), so it is
safe to import from ``nextflow_executor`` at module load. See the pre-sync
checklist (``docs/PRE_SYNC_CHECKLIST.md`` step 3).
"""

from __future__ import annotations

from .run_spec import RunSpec, DataLocality, TrustLevel, ResourceTier
from .scheduler import Scheduler, BackendChoice, compute_backend_v2_enabled
from .launcher import (
    HeadLauncher,
    LaunchRequest,
    CallableHeadLauncher,
    set_default_head_launcher,
    get_default_head_launcher,
)

__all__ = [
    "RunSpec",
    "DataLocality",
    "TrustLevel",
    "ResourceTier",
    "Scheduler",
    "BackendChoice",
    "compute_backend_v2_enabled",
    "HeadLauncher",
    "LaunchRequest",
    "CallableHeadLauncher",
    "set_default_head_launcher",
    "get_default_head_launcher",
]
