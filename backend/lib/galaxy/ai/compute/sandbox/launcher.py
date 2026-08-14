"""SandboxedHeadLauncher — decorates a base HeadLauncher.

The whole point of the M0.1 seam: the sandbox does NOT reimplement the
launch machinery (semaphore, FD-decoupled log, pid tracking, slot-release
reaper). It rewrites the command to the sandboxed ``docker/podman run ...``
argv and hands it to the base launcher, which runs it exactly as before.

    base   = CallableHeadLauncher(_launch_nextflow_head)   # M0.1
    sandbox = SandboxedHeadLauncher(base, config)
    sandbox.launch(req)   # runs `docker run <iso flags> image nextflow ...`
"""

from __future__ import annotations

from dataclasses import replace
from typing import Optional

from ..launcher import HeadLauncher, LaunchRequest
from .command import build_sandbox_command
from .config import SandboxConfig


class SandboxedHeadLauncher(HeadLauncher):
    """Wraps the head process in a locked-down container before launching."""

    def __init__(self, inner: HeadLauncher, config: SandboxConfig) -> None:
        self._inner = inner
        self._config = config

    @property
    def config(self) -> SandboxConfig:
        return self._config

    def launch(self, req: LaunchRequest):
        # nf_source_path: the .nf script is base_cmd's first non-flag arg after
        # "run"; the caller stashes it in req.extra for an exact bind-mount.
        nf_source_path: Optional[str] = req.extra.get("nf_source_path")
        wrapped_cmd = build_sandbox_command(
            list(req.cmd),
            work_dir=str(req.work_dir),
            nf_source_path=nf_source_path,
            container_env=dict(req.env or {}),
            config=self._config,
        )
        # New request: cmd is the docker wrapper; env stays the HOST env so the
        # docker/podman CLI itself can reach the daemon (container env was
        # filtered into -e flags inside wrapped_cmd).
        sandboxed = replace(req, cmd=wrapped_cmd)
        return self._inner.launch(sandboxed)
