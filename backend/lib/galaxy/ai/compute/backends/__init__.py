"""Compute backends — the pluggable execution layer.

Phase 0 defines the :class:`ComputeBackend` Protocol and thin adapter
stubs (:class:`LocalSubprocessBackend`, :class:`AWSBatchBackend`) that
document how the existing two execution paths in
``nextflow_executor.py`` will be wrapped. They are NOT wired into the
production launch path yet — the executor keeps its current code and only
consults the :class:`~galaxy.ai.compute.scheduler.Scheduler` in shadow
mode.

Future backends hang off the same Protocol:
* ``SandboxedLocalBackend`` — Feature ① (container / gVisor / microVM)
* ``SlurmBackend`` / ``K8sBackend`` — Feature ②-B (air-gap)
"""

from __future__ import annotations

from .base import ComputeBackend, RunHandle, RunStatus, BackendCapabilities
from .local import LocalSubprocessBackend
from .aws_batch import AWSBatchBackend

__all__ = [
    "ComputeBackend",
    "RunHandle",
    "RunStatus",
    "BackendCapabilities",
    "LocalSubprocessBackend",
    "AWSBatchBackend",
]
