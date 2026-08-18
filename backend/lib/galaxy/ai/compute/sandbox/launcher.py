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

import json
import os
import sys
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


class LauncherClientHeadLauncher(HeadLauncher):
    """Route the (already-sandboxed) head argv to the narrow launcher service.

    Sits between :class:`SandboxedHeadLauncher` (which builds the ``docker run``
    argv) and the base launcher (``_launch_nextflow_head``). Instead of running
    the ``docker run`` locally — which requires the backend to hold docker
    access — it hands the argv to a tiny client subprocess
    (``galaxy.ai.compute.sandbox.head_client``) that POSTs it to the launcher's
    ``/run_head`` endpoint and relays the streamed output. The client is what the
    base launcher actually Popens, so it reuses ALL the existing machinery
    (concurrency slot, FD-decoupled log redirection, pid tracking, reaper).

    Flag-gated: only inserted when ``NF_HEAD_LAUNCHER_URL`` is set. When absent,
    the wiring uses the base launcher directly and nothing changes.

    Security: the launcher re-validates the argv (mounts confined to allowed
    prefixes, forced runsc/non-root/caps, no privileged/host) before running it,
    so a compromised backend cannot craft an escaping head. This closes the
    create+bind residual for the local .nf head, the same way it is closed for
    run_code.
    """

    def __init__(self, base: HeadLauncher, launcher_url: str, image: str) -> None:
        self._base = base
        self._url = launcher_url
        self._image = image

    def launch(self, req: LaunchRequest):
        docker_argv = list(req.cmd)  # full `docker run <iso flags> image nextflow …`
        argv_file = os.path.join(str(req.work_dir), ".head_argv.json")
        with open(argv_file, "w") as f:
            json.dump({"argv": docker_argv, "image": self._image}, f)

        client_cmd = [sys.executable, "-m", "galaxy.ai.compute.sandbox.head_client"]
        client_env = dict(req.env or {})
        client_env["NF_HEAD_LAUNCHER_URL"] = self._url
        client_env["NF_HEAD_ARGV_FILE"] = argv_file
        token = os.environ.get("NF_HEAD_LAUNCHER_TOKEN", "")
        if token:
            client_env["NF_HEAD_LAUNCHER_TOKEN"] = token
        # PYTHONPATH so `-m galaxy...` resolves in the head subprocess.
        py_path = client_env.get("PYTHONPATH") or os.environ.get("PYTHONPATH", "")
        lib_root = os.environ.get("GALAXY_LIB", "/app/lib")
        client_env["PYTHONPATH"] = f"{lib_root}:{py_path}" if py_path else lib_root

        return self._base.launch(replace(req, cmd=client_cmd, env=client_env))
