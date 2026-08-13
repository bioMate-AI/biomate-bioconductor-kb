"""AWS Batch backend — adapter around the existing Nextflow-on-Batch path.

Today this path is the ``executor == "awsbatch"`` branch of
``_generate_executor_config`` + the Batch-specific config generation in
``nextflow_executor.py`` (nf-amazon plugin, S3 workdir, memory-tier
``withLabel`` block, GPU queue routing). Phase 0 records its capabilities;
M0 parity work moves the launch behind :meth:`submit`.

boto3 is imported lazily inside methods so this module stays import-safe on
Python 3.9 hosts without AWS libs installed.
"""

from __future__ import annotations

import os
from typing import Any, Dict, List

from ..run_spec import RunSpec, TIER_RESOURCES, ResourceTier
from .base import BackendCapabilities, ComputeBackend, RunHandle, RunStatus


class AWSBatchBackend(ComputeBackend):
    """Runs Nextflow with the awsbatch executor against an AWS Batch queue."""

    name = "awsbatch"

    def capabilities(self) -> BackendCapabilities:
        # Max mem/cpu reflect the largest hardcoded tier today
        # (process_high_memory = 12 vCPU / 200 GB); GPU via process_gpu.
        high_mem = TIER_RESOURCES[ResourceTier.HIGH_MEMORY]
        return BackendCapabilities(
            name=self.name,
            supports_gpu=True,
            max_mem_gb=high_mem["mem_gb"],
            max_cpus=high_mem["cpus"],
            supports_s3=True,
            supports_local_fs=False,
            # Placeholder cost signal; Feature ③ replaces with live spot price.
            usd_per_vcpu_hour=0.04,
            data_localities=["s3"],
        )

    def submit(self, spec: RunSpec) -> RunHandle:  # pragma: no cover - stub
        raise NotImplementedError(
            "M0 parity work: wrap the existing awsbatch launch path "
            "(_generate_executor_config + Batch config) here."
        )

    def poll(self, handle: RunHandle) -> RunStatus:  # pragma: no cover - stub
        raise NotImplementedError

    def cancel(self, handle: RunHandle) -> bool:  # pragma: no cover - stub
        raise NotImplementedError

    def collect_outputs(self, handle: RunHandle) -> List[Dict[str, Any]]:  # pragma: no cover - stub
        raise NotImplementedError

    # --- helpers the future scheduler will use -----------------------

    @staticmethod
    def default_queue() -> str:
        return os.environ.get("AWS_BATCH_QUEUE", "biomate-nextflow-queue")

    @staticmethod
    def gpu_queue() -> str:
        return os.environ.get("GPU_BATCH_QUEUE", "biomate-gpu-spot-queue")
