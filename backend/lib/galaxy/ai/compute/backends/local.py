"""Local subprocess backend — adapter around the existing local path.

Today the local path lives inline in ``nextflow_executor.py`` as a bare
``subprocess.Popen(...)`` launched under the backend process identity, with
no container / seccomp / egress / resource isolation. Phase 0 captures its
*capabilities* so the scheduler can reason about it; the M0 parity work will
move the actual launch code behind :meth:`submit`.

This is also the class that Feature ① replaces/subclasses as
``SandboxedLocalBackend`` — the sandbox is "this backend, but the
subprocess runs inside a locked-down container / microVM".
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from ..launcher import HeadLauncher
from ..run_spec import RunSpec
from .base import (
    BackendCapabilities,
    ComputeBackend,
    HeadLaunchMixin,
    RunHandle,
    RunStatus,
)


class LocalSubprocessBackend(HeadLaunchMixin, ComputeBackend):
    """Runs Nextflow as a local subprocess on the backend host.

    The head-launch step is wired: :meth:`launch_head` delegates to the
    injected/registered :class:`HeadLauncher` (the executor's
    ``_launch_nextflow_head``). The remaining piece of :meth:`submit` —
    building the command / executor config for a local run — is M0.2 and is
    extracted under E2E verification (see the roadmap).

    WARNING (documented, not yet fixed): no isolation. Suitable only for
    trusted single-tenant use until Feature ① lands — at which point this
    backend is subclassed as ``SandboxedLocalBackend`` with a sandboxed
    HeadLauncher.
    """

    name = "local"

    def __init__(self, head_launcher: Optional[HeadLauncher] = None) -> None:
        super().__init__(head_launcher=head_launcher)

    def capabilities(self) -> BackendCapabilities:
        return BackendCapabilities(
            name=self.name,
            supports_gpu=False,      # host may have one, but not modeled yet
            max_mem_gb=None,          # bounded by host, not by a queue
            max_cpus=None,
            supports_s3=False,        # nf-amazon/S3 workdir needs awsbatch
            supports_local_fs=True,
            usd_per_vcpu_hour=None,   # already-paid host capacity
            data_localities=["local"],
        )

    def submit(self, spec: RunSpec) -> RunHandle:  # pragma: no cover - stub
        raise NotImplementedError(
            "M0 parity work: wrap the existing local subprocess.Popen launch "
            "path from nextflow_executor.execute_nextflow here."
        )

    def poll(self, handle: RunHandle) -> RunStatus:  # pragma: no cover - stub
        raise NotImplementedError

    def cancel(self, handle: RunHandle) -> bool:  # pragma: no cover - stub
        raise NotImplementedError

    def collect_outputs(self, handle: RunHandle) -> List[Dict[str, Any]]:  # pragma: no cover - stub
        raise NotImplementedError
