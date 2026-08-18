#!/usr/bin/env python3
"""BioMate narrow sandbox launcher.

A minimal *trusted* service that owns Docker access and runs run_code sandboxes
on behalf of the (untrusted) app containers. It implements the code-runner
sidecar contract (``POST /run``) but ENFORCES the safe sandbox envelope
regardless of what the caller sends:

  - the workdir bind mount MUST resolve under ``LAUNCHER_WORKDIR_PREFIX`` — this
    blocks an RCE'd caller from asking to bind-mount arbitrary host paths (``/``,
    ``/etc``, the docker socket, …);
  - the image MUST be in ``LAUNCHER_ALLOWED_IMAGES``;
  - runtime (gVisor), user (non-root), network (none), cap-drop, no-new-privileges,
    and the resource limits are forced by the launcher, NEVER taken from the caller.

Why this exists: an endpoint-level docker-socket-proxy cannot inspect a
``POST /containers/create`` body, so an RCE'd app that keeps create+start could
still create a container with a malicious host bind and escape. With the narrow
launcher the app containers have NO docker access at all — they can only ask the
launcher to run a validated RunSpec. See
docs/20260818_SANDBOX_SOCKET_PROXY_HARDENING.md.

Pure stdlib (no third-party deps) so the image stays tiny. Talks to the daemon
via the ``docker`` CLI honouring ``DOCKER_HOST`` (point it at the socket-proxy
for defence in depth: launcher -> proxy -> daemon).
"""
import json
import os
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("LAUNCHER_PORT", "8899"))
TOKEN = os.environ.get("LAUNCHER_TOKEN", "")
WORKDIR_PREFIX = os.path.realpath(os.environ.get("LAUNCHER_WORKDIR_PREFIX", "/tmp/biomate_code"))
ALLOWED_IMAGES = {x.strip() for x in os.environ.get("LAUNCHER_ALLOWED_IMAGES", "").split(",") if x.strip()}
ENFORCED_UID = os.environ.get("LAUNCHER_UID", "1000")
ENFORCED_GID = os.environ.get("LAUNCHER_GID", "1000")
ENFORCED_RUNTIME = os.environ.get("LAUNCHER_RUNTIME", "runsc")  # gVisor; "" disables
MAX_TIMEOUT = int(os.environ.get("LAUNCHER_MAX_TIMEOUT", "300"))
MEMORY = os.environ.get("LAUNCHER_MEMORY", "2g")
CPUS = os.environ.get("LAUNCHER_CPUS", "2")
PIDS_LIMIT = os.environ.get("LAUNCHER_PIDS_LIMIT", "512")
ALLOWED_INTERP = {"python3", "python", "Rscript", "R", "bash", "sh"}


def build_cmd(spec):
    """Validate the RunSpec and build the enforced-safe `docker run` argv.

    Raises ValueError on any policy violation (→ 400, never runs).
    """
    base_dir = os.path.realpath(str(spec.get("baseDir", "")))
    # ENFORCE: workdir must be under the allowed prefix. realpath() collapses
    # symlinks first, so a symlink inside the prefix can't point outside it.
    if not (base_dir == WORKDIR_PREFIX or base_dir.startswith(WORKDIR_PREFIX + os.sep)):
        raise ValueError(f"baseDir not under {WORKDIR_PREFIX}")
    if not os.path.isdir(base_dir):
        raise ValueError("baseDir does not exist")

    image = str(spec.get("image", ""))
    if ALLOWED_IMAGES and image not in ALLOWED_IMAGES:
        raise ValueError("image not in allowlist")

    interp = str(spec.get("interpreter", ""))
    if interp not in ALLOWED_INTERP:
        raise ValueError("interpreter not allowed")

    script = str(spec.get("scriptPath", ""))
    if not re.fullmatch(r"/work/[A-Za-z0-9._-]+", script):
        raise ValueError("scriptPath invalid")

    timeout = min(int(spec.get("timeoutSeconds", 30) or 30), MAX_TIMEOUT)
    read_only = bool(spec.get("readOnly"))
    tmpfs_mb = int(spec.get("tmpfsMb", 512) or 512)

    argv = ["docker", "run", "--rm"]
    if ENFORCED_RUNTIME:
        argv += ["--runtime", ENFORCED_RUNTIME]
    argv += [
        "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "--pids-limit", PIDS_LIMIT,
        "--network", "none",
        "--memory", MEMORY, "--cpus", CPUS,
        "--user", f"{ENFORCED_UID}:{ENFORCED_GID}",
        "-v", f"{base_dir}:/work",
        "-w", "/work/output",
        "-e", "DATA_DIR=/work/input",
        "-e", "OUTPUT_DIR=/work/output",
        "-e", "HOME=/tmp",
    ]
    if read_only:
        argv += ["--read-only", "--tmpfs", f"/tmp:rw,nosuid,nodev,size={tmpfs_mb}m"]
    argv += [image, interp, script]
    return argv, timeout


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):  # silence default access logging
        pass

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"ok": True})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path.rstrip("/") != "/run":
            return self._send(404, {"error": "not found"})
        if TOKEN and self.headers.get("Authorization", "") != f"Bearer {TOKEN}":
            return self._send(401, {"error": "unauthorized"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            spec = json.loads(self.rfile.read(n) or b"{}")
        except Exception as e:
            return self._send(400, {"error": f"bad json: {e}"})
        try:
            argv, timeout = build_cmd(spec)
        except ValueError as e:
            # Policy rejection — 400, and never touches docker.
            return self._send(400, {"stdout": "", "stderr": f"[launcher rejected] {e}", "exitCode": 1})
        try:
            p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout + 5)
            self._send(200, {"stdout": p.stdout[:8000], "stderr": p.stderr[:4000], "exitCode": p.returncode})
        except subprocess.TimeoutExpired:
            self._send(200, {"stdout": "", "stderr": "[launcher] timeout", "exitCode": 124})
        except Exception as e:
            self._send(500, {"stdout": "", "stderr": f"[launcher error] {e}", "exitCode": 1})


if __name__ == "__main__":
    print(
        f"[launcher] :{PORT} prefix={WORKDIR_PREFIX} runtime={ENFORCED_RUNTIME or 'none'} "
        f"images={sorted(ALLOWED_IMAGES) or 'ANY'}",
        flush=True,
    )
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
