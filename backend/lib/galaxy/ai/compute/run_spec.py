"""Normalized run descriptor shared by every compute backend.

``RunSpec`` collapses the ad-hoc routing inputs currently scattered across
``nextflow_executor.execute_nextflow`` (the ``NEXTFLOW_USE_AWS`` env read,
the ``executor`` request field, the ``/tmp/biomate_user_nf/`` personal-
workflow check, the ``s3://`` outdir / input autodetection) plus the
resource hints today encoded only as Nextflow process labels.

Phase 0 uses it purely as the input to :class:`Scheduler.select_backend`.
Later phases add the estimator (input-size -> data volume, label -> cpu/mem)
and the sandbox trust level.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class DataLocality(str, Enum):
    """Where the run's inputs/outputs primarily live."""

    LOCAL = "local"       # local filesystem paths only
    S3 = "s3"             # any s3:// input or outdir
    ONPREM = "onprem"     # MinIO / on-prem object store (air-gap)
    UNKNOWN = "unknown"


class TrustLevel(str, Enum):
    """Trust of the code being executed — drives the sandbox tier."""

    PLATFORM = "platform"   # BioMate-curated indexed workflow
    USER = "user"           # user-uploaded .nf / run_code (untrusted)


class ResourceTier(str, Enum):
    """Coarse resource class, mirrors Nextflow process labels.

    Values are the label strings so a spec can be built straight from a
    workflow's declared labels without a translation table.
    """

    LOW = "process_low"                 # 2 vCPU / 12 GB
    MEDIUM = "process_medium"           # 6 vCPU / 36 GB
    HIGH = "process_high"               # 12 vCPU / 72 GB
    HIGH_MEMORY = "process_high_memory"  # 12 vCPU / 200 GB
    GPU = "process_gpu"                 # 8 vCPU / 32 GB + 1 GPU


# Canonical cpu/mem/gpu for each tier — kept in sync with the hardcoded
# `withLabel` block in `_generate_executor_config` (nextflow_executor.py).
# Single source of truth so the future scheduler and the executor config
# generator can share it instead of duplicating magic numbers.
TIER_RESOURCES: Dict[ResourceTier, Dict[str, int]] = {
    ResourceTier.LOW: {"cpus": 2, "mem_gb": 12, "gpu": 0},
    ResourceTier.MEDIUM: {"cpus": 6, "mem_gb": 36, "gpu": 0},
    ResourceTier.HIGH: {"cpus": 12, "mem_gb": 72, "gpu": 0},
    ResourceTier.HIGH_MEMORY: {"cpus": 12, "mem_gb": 200, "gpu": 0},
    ResourceTier.GPU: {"cpus": 8, "mem_gb": 32, "gpu": 1},
}

# Path prefix that marks an ad-hoc user-uploaded workflow. Mirrors the
# constant used throughout nextflow_executor.py.
PERSONAL_WORKFLOW_PREFIX = "/tmp/biomate_user_nf/"


@dataclass
class RunSpec:
    """Everything a :class:`Scheduler` needs to pick a backend.

    Only the routing-relevant fields are required today; the resource /
    locality fields are advisory in Phase 0 (shadow mode) and become
    load-bearing when the scoring policy lands in Feature ③.
    """

    # --- routing inputs (mirror the legacy decision) -----------------
    executor_requested: str = ""
    """The `compute.executor` value from the request ("" | "awsbatch" | "local")."""

    nextflow_path: str = ""
    """Resolved path to the .nf file (personal workflows start with the prefix)."""

    outdir: str = ""
    """Effective `params.outdir` — an `s3://` value implies cloud execution."""

    param_values: List[str] = field(default_factory=list)
    """Non-outdir param string values, scanned for `s3://` inputs."""

    use_aws_env: bool = False
    """Snapshot of `NEXTFLOW_USE_AWS` at decision time."""

    # --- resource / locality hints (advisory in Phase 0) -------------
    tiers: List[ResourceTier] = field(default_factory=list)
    """Process labels present in the workflow, for the future estimator."""

    needs_gpu: bool = False
    est_data_gb: float = 0.0
    data_locality: DataLocality = DataLocality.UNKNOWN
    needs_network: bool = True
    trust_level: TrustLevel = TrustLevel.PLATFORM

    # --- context -----------------------------------------------------
    user_id: str = "unknown"
    run_id: str = ""
    extra: Dict[str, Any] = field(default_factory=dict)

    # ---------------------------------------------------------------

    @property
    def is_personal_workflow(self) -> bool:
        return str(self.nextflow_path or "").startswith(PERSONAL_WORKFLOW_PREFIX)

    @property
    def has_s3_outdir(self) -> bool:
        return str(self.outdir or "").startswith("s3://")

    @property
    def s3_inputs(self) -> List[str]:
        return [v for v in self.param_values if isinstance(v, str) and v.startswith("s3://")]

    @classmethod
    def from_request(
        cls,
        *,
        executor_requested: str,
        nextflow_path: str,
        outdir: str,
        params: Optional[Dict[str, Any]],
        use_aws_env: bool,
        user_id: str = "unknown",
        run_id: str = "",
        trust_level: Optional[TrustLevel] = None,
    ) -> "RunSpec":
        """Build a spec from the same inputs the legacy routing block reads.

        Kept intentionally close to ``execute_nextflow`` so the shadow-mode
        comparison is apples-to-apples.
        """
        params = params or {}
        param_values = [
            v for k, v in params.items()
            if k != "outdir" and isinstance(v, str)
        ]
        resolved_trust = trust_level
        if resolved_trust is None:
            resolved_trust = (
                TrustLevel.USER
                if str(nextflow_path or "").startswith(PERSONAL_WORKFLOW_PREFIX)
                else TrustLevel.PLATFORM
            )
        outdir_str = str(outdir or params.get("outdir", "") or "")
        locality = DataLocality.UNKNOWN
        if outdir_str.startswith("s3://") or any(
            isinstance(v, str) and v.startswith("s3://") for v in param_values
        ):
            locality = DataLocality.S3
        elif nextflow_path:
            locality = DataLocality.LOCAL
        return cls(
            executor_requested=executor_requested or "",
            nextflow_path=nextflow_path or "",
            outdir=outdir_str,
            param_values=param_values,
            use_aws_env=use_aws_env,
            data_locality=locality,
            trust_level=resolved_trust,
            user_id=user_id or "unknown",
            run_id=run_id or "",
        )
