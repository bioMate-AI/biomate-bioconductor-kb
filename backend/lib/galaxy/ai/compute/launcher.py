"""The head-launch seam shared by every compute backend.

The Nextflow *head* process always runs as a local subprocess — local /
awsbatch / slurm / k8s differ only in the generated executor config, not in
how the head is launched. So "launch the head" is a single primitive that:

* every backend reuses (via :class:`HeadLauncher`), and
* Feature ① (sandbox) overrides — a ``SandboxedHeadLauncher`` wraps the
  same launch in a container / gVisor / microVM.

The concrete production launcher lives in ``nextflow_executor`` (as
``_launch_nextflow_head``); it is injected into backends as a
:class:`HeadLauncher` rather than imported, to avoid an import cycle
(``nextflow_executor`` already imports this package). See
``docs/20260813_ISOLATION_PRIVATE_DEPLOY_SCHEDULER_ROADMAP.md`` (M0).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Protocol, runtime_checkable


@dataclass
class LaunchRequest:
    """Everything the head-launch primitive needs — backend-agnostic.

    Mirrors the arguments of ``nextflow_executor._launch_nextflow_head`` so
    the executor's function adapts to :class:`HeadLauncher` with a trivial
    wrapper.
    """

    cmd: List[str]
    env: Dict[str, str]
    work_dir: Any            # pathlib.Path (kept Any to avoid importing here)
    log_path: Any            # pathlib.Path
    run_id: str
    extra: Dict[str, Any] = field(default_factory=dict)


@runtime_checkable
class HeadLauncher(Protocol):
    """Launches a Nextflow head process and returns a process handle.

    The return value is the backend-native process object (a
    ``subprocess.Popen`` for the local/production launcher). Callers treat it
    opaquely and hand it to the log-stream / QC-monitor threads, exactly as
    the legacy inline code did.
    """

    def launch(self, req: LaunchRequest) -> Any:
        ...


class CallableHeadLauncher(HeadLauncher):
    """Adapt a plain ``launch_fn(**kwargs) -> process`` into a HeadLauncher.

    Lets ``nextflow_executor`` expose its ``_launch_nextflow_head`` as a
    HeadLauncher without depending on this module at its own import time:

        from galaxy.ai.compute.launcher import CallableHeadLauncher
        launcher = CallableHeadLauncher(_launch_nextflow_head)
    """

    def __init__(self, launch_fn: Callable[..., Any]) -> None:
        self._launch_fn = launch_fn

    def launch(self, req: LaunchRequest) -> Any:
        return self._launch_fn(
            cmd=req.cmd,
            env=req.env,
            work_dir=req.work_dir,
            log_path=req.log_path,
            run_id=req.run_id,
        )


# Optional process-wide default, set once by the executor. Backends may also
# receive a launcher via constructor injection (preferred for testability);
# this registry is the convenience path for the production wiring.
_default_launcher: Optional[HeadLauncher] = None


def set_default_head_launcher(launcher: Optional[HeadLauncher]) -> None:
    global _default_launcher
    _default_launcher = launcher


def get_default_head_launcher() -> Optional[HeadLauncher]:
    return _default_launcher
