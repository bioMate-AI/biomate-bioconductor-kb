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

# Prefixes a Nextflow-head bind mount source may resolve under. The head runs
# fully sandboxed; these are the only host paths it is allowed to see.
HEAD_PREFIXES = [
    os.path.realpath(p)
    for p in os.environ.get("LAUNCHER_HEAD_PREFIXES", "/tmp/nextflow_runs,/tmp/biomate_user_nf").split(",")
    if p.strip()
]

# Prefixes and allowed images for Galaxy interactive-tool (IT) containers.
# Stage 3 (Option C): IT still runs via DOCKER_HOST→proxy; these prefixes are
# used by the future /run_it endpoint (Option A: detached lifecycle through the
# launcher so IT mounts are also body-validated, not just endpoint-gated).
IT_PREFIXES = [
    os.path.realpath(p)
    for p in os.environ.get(
        "LAUNCHER_IT_PREFIXES",
        "/app/database/jobs_directory,/app/database/files,/app/tools/interactive,/app",
    ).split(",")
    if p.strip()
]
IT_ALLOWED_IMAGES = {
    x.strip()
    for x in os.environ.get(
        "LAUNCHER_IT_ALLOWED_IMAGES",
        "quay.io/bgruening/docker-jupyter-notebook,quay.io/bgruening/docker-rstudio,cxgene,jupyter",
    ).split(",")
    if x.strip()
}

EXIT_SENTINEL = "__LAUNCHER_EXIT__"


def _under_prefixes(path, prefixes):
    rp = os.path.realpath(path)
    return any(rp == p or rp.startswith(p + os.sep) for p in prefixes)


def validate_it_argv(argv, image):
    """Validate a caller-proposed ``docker run -d`` argv for an IT container.

    IT containers differ from the head in three ways:
      • they run detached (``-d``) — the caller gets back a container name/id;
      • they publish a port (``-p <guest>``) — allowed, but host-net is not;
      • they stay alive for the user's session duration.

    The same escape-closure philosophy as ``validate_head_argv``: we never trust
    the caller's argv; we ENFORCE the safe envelope by inspection.

    Not yet wired into Galaxy's IT runner (Option A, future). Called today only
    by ``POST /run_it`` which is not yet invoked in production — but the endpoint
    exists so Galaxy can be switched to use it without touching the launcher again.
    """
    if len(argv) < 3 or os.path.basename(str(argv[0])) not in ("docker", "podman") or argv[1] != "run":
        raise ValueError("not a docker/podman run")
    if "-d" not in argv and "--detach" not in argv:
        raise ValueError("IT containers must run detached (-d)")

    if IT_ALLOWED_IMAGES and image not in IT_ALLOWED_IMAGES:
        raise ValueError("IT image not in allowlist")
    if image not in argv:
        raise ValueError("declared image not present in argv")

    for i in range(len(argv) - 1):
        tok, nxt = argv[i], str(argv[i + 1])
        if tok in ("--privileged", "--cap-add", "--device", "--userns"):
            raise ValueError(f"forbidden flag {tok}")
        if tok in ("--network", "--net", "--pid", "--ipc", "--uts", "--cgroupns") and nxt in ("host", "=host"):
            raise ValueError(f"forbidden {tok} host")
        if tok.startswith(("--network=host", "--net=host", "--pid=host", "--ipc=host", "--privileged")):
            raise ValueError(f"forbidden {tok}")
        if tok == "--security-opt" and "unconfined" in nxt:
            raise ValueError("seccomp/apparmor unconfined forbidden")
        if tok == "--user":
            uid = nxt.split(":")[0]
            if uid in ("0", "root"):
                raise ValueError("root user forbidden")
        if tok in ("-v", "--volume", "--mount"):
            src = nxt.split(":")[0] if tok != "--mount" else ""
            if "docker.sock" in nxt or "/var/run" in nxt:
                raise ValueError("docker socket mount forbidden")
            if src and not _under_prefixes(src, IT_PREFIXES):
                raise ValueError(f"IT mount source not under allowed prefixes: {src}")
    return True


def validate_head_argv(argv, image):
    """Validate a caller-proposed ``docker/podman run ... nextflow`` argv.

    The backend builds the head command (build_sandbox_command) — complex logic
    we don't duplicate here — but we NEVER trust it: a compromised backend could
    craft an escaping argv. Enforce the safety envelope by inspection.
    """
    if len(argv) < 3 or os.path.basename(str(argv[0])) not in ("docker", "podman") or argv[1] != "run":
        raise ValueError("not a docker/podman run")

    def has_pair(flag, val):
        return any(argv[i] == flag and argv[i + 1] == val for i in range(len(argv) - 1))

    if not has_pair("--cap-drop", "ALL"):
        raise ValueError("missing --cap-drop ALL")
    if not has_pair("--security-opt", "no-new-privileges"):
        raise ValueError("missing --security-opt no-new-privileges")
    if ENFORCED_RUNTIME and not has_pair("--runtime", ENFORCED_RUNTIME):
        raise ValueError(f"missing --runtime {ENFORCED_RUNTIME}")

    if ALLOWED_IMAGES and image not in ALLOWED_IMAGES:
        raise ValueError("image not in allowlist")
    if image not in argv:
        raise ValueError("declared image not present in argv")

    user_ok = False
    for i in range(len(argv) - 1):
        tok, nxt = argv[i], argv[i + 1]
        # never share host namespaces
        if tok in ("--privileged", "--cap-add", "--device", "--userns"):
            raise ValueError(f"forbidden flag {tok}")
        if tok in ("--network", "--net", "--pid", "--ipc", "--uts", "--cgroupns") and nxt in ("host", "=host"):
            raise ValueError(f"forbidden {tok} host")
        if tok.startswith(("--network=host", "--net=host", "--pid=host", "--ipc=host", "--privileged")):
            raise ValueError(f"forbidden {tok}")
        if tok == "--security-opt" and "unconfined" in nxt:
            raise ValueError("seccomp/apparmor unconfined forbidden")
        if tok == "--user":
            uid = nxt.split(":")[0]
            if uid in ("0", "root"):
                raise ValueError("root user forbidden")
            user_ok = True
        if tok in ("-v", "--volume", "--mount"):
            src = nxt.split(":")[0] if tok != "--mount" else ""
            if "docker.sock" in nxt or "/var/run" in nxt:
                raise ValueError("docker socket mount forbidden")
            if src and not _under_prefixes(src, HEAD_PREFIXES):
                raise ValueError(f"mount source not under allowed prefixes: {src}")
    if not user_ok:
        raise ValueError("missing non-root --user")
    return True


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
        path = self.path.rstrip("/")
        if path == "/health":
            return self._send(200, {"ok": True})
        # GET /inspect_it/<name> — return published ports for an IT container.
        # Safe: read-only; the container name is alphanumeric (hex UUID).
        if path.startswith("/inspect_it/"):
            if TOKEN and self.headers.get("Authorization", "") != f"Bearer {TOKEN}":
                return self._send(401, {"error": "unauthorized"})
            return self._do_inspect_it(path[len("/inspect_it/"):])
        self._send(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.rstrip("/")
        if path not in ("/run", "/run_head", "/run_it", "/stop_it"):
            return self._send(404, {"error": "not found"})
        if TOKEN and self.headers.get("Authorization", "") != f"Bearer {TOKEN}":
            return self._send(401, {"error": "unauthorized"})
        if path == "/run_head":
            return self._do_run_head()
        if path == "/run_it":
            return self._do_run_it()
        if path == "/stop_it":
            return self._do_stop_it()
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

    # ------------------------------------------------------------------
    # Interactive-tool (IT) lifecycle endpoints — Option A hook.
    # Not yet wired into Galaxy's IT runner (Stage 3 uses DOCKER_HOST→proxy
    # via new_clean_env fix instead).  Implemented here so Galaxy can be
    # switched to the narrow-launcher path without touching the launcher again.
    # ------------------------------------------------------------------

    def _do_run_it(self):
        """POST /run_it — launch a Galaxy IT container detached, return name.

        Body: {"argv": [...], "image": "<name>"}
        Response: {"container": "<name>", "exitCode": 0} or error.
        """
        try:
            n = int(self.headers.get("Content-Length", "0"))
            spec = json.loads(self.rfile.read(n) or b"{}")
        except Exception as e:
            return self._send(400, {"error": f"bad json: {e}"})
        argv = spec.get("argv")
        image = str(spec.get("image", ""))
        if not isinstance(argv, list) or not argv:
            return self._send(400, {"error": "argv required"})
        try:
            validate_it_argv([str(a) for a in argv], image)
        except ValueError as e:
            return self._send(400, {"error": f"[launcher rejected] {e}"})
        try:
            p = subprocess.run(argv, capture_output=True, text=True, timeout=30)
            container = p.stdout.strip()
            self._send(200, {"container": container, "stderr": p.stderr[:2000], "exitCode": p.returncode})
        except subprocess.TimeoutExpired:
            self._send(200, {"container": "", "stderr": "[launcher] timeout", "exitCode": 124})
        except Exception as e:
            self._send(500, {"container": "", "stderr": f"[launcher error] {e}", "exitCode": 1})

    def _do_inspect_it(self, name):
        """GET /inspect_it/<name> — return published port mapping for IT container.

        Runs ``docker port <name>`` and returns the raw text so the caller
        (monitor.py replacement) can parse it without its own docker access.
        Response: {"ports": "<raw docker port output>", "exitCode": 0}
        """
        if not re.fullmatch(r"[a-z0-9_-]{1,128}", name):
            return self._send(400, {"error": "invalid container name"})
        try:
            p = subprocess.run(["docker", "port", name], capture_output=True, text=True, timeout=10)
            self._send(200, {"ports": p.stdout, "stderr": p.stderr[:1000], "exitCode": p.returncode})
        except Exception as e:
            self._send(500, {"ports": "", "stderr": f"[launcher error] {e}", "exitCode": 1})

    def _do_stop_it(self):
        """POST /stop_it — stop and remove an IT container by name.

        Body: {"container": "<name>"}
        Runs ``docker stop <name> && docker rm -f <name>``.
        """
        try:
            n = int(self.headers.get("Content-Length", "0"))
            spec = json.loads(self.rfile.read(n) or b"{}")
        except Exception as e:
            return self._send(400, {"error": f"bad json: {e}"})
        name = str(spec.get("container", ""))
        if not name or not re.fullmatch(r"[a-z0-9_-]{1,128}", name):
            return self._send(400, {"error": "invalid container name"})
        try:
            subprocess.run(["docker", "stop", name], capture_output=True, timeout=30)
            subprocess.run(["docker", "rm", "-f", name], capture_output=True, timeout=15)
            self._send(200, {"ok": True})
        except Exception as e:
            self._send(500, {"ok": False, "error": f"[launcher error] {e}"})

    def _do_run_head(self):
        """Run a long-lived, already-built sandbox head argv, streaming combined
        output back and terminating with a `__LAUNCHER_EXIT__ <code>` sentinel
        line so the caller (backend head-client) learns the exit code."""
        try:
            n = int(self.headers.get("Content-Length", "0"))
            spec = json.loads(self.rfile.read(n) or b"{}")
        except Exception as e:
            return self._send(400, {"error": f"bad json: {e}"})
        argv = spec.get("argv")
        image = str(spec.get("image", ""))
        if not isinstance(argv, list) or not argv:
            return self._send(400, {"error": "argv required"})
        try:
            validate_head_argv([str(a) for a in argv], image)
        except ValueError as e:
            return self._send(400, {"error": f"[launcher rejected] {e}"})
        # stream: 200 + chunked plain text; the head process's stdout/stderr are
        # relayed line-by-line, then a sentinel with the exit code.
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def chunk(data: bytes):
            self.wfile.write(f"{len(data):X}\r\n".encode())
            self.wfile.write(data)
            self.wfile.write(b"\r\n")
            self.wfile.flush()

        proc = None
        try:
            proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=1, text=True)
            for line in iter(proc.stdout.readline, ""):
                chunk(line.encode("utf-8", "replace"))
            proc.wait()
            code = proc.returncode
        except Exception as e:
            chunk(f"[launcher head error] {e}\n".encode())
            code = 1
            if proc:
                try:
                    proc.kill()
                except Exception:
                    pass
        chunk(f"{EXIT_SENTINEL} {code}\n".encode())
        self.wfile.write(b"0\r\n\r\n")  # terminating chunk
        self.wfile.flush()


if __name__ == "__main__":
    print(
        f"[launcher] :{PORT} prefix={WORKDIR_PREFIX} runtime={ENFORCED_RUNTIME or 'none'} "
        f"images={sorted(ALLOWED_IMAGES) or 'ANY'} "
        f"it_images={sorted(IT_ALLOWED_IMAGES) or 'ANY'} "
        f"endpoints=run,run_head,run_it,inspect_it,stop_it",
        flush=True,
    )
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
