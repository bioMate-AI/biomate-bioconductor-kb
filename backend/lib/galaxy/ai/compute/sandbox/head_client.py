"""Nextflow-head client — runs *inside the backend* as the head subprocess when
``NF_HEAD_LAUNCHER_URL`` is set, so the backend no longer runs ``docker`` itself.

It reads the already-built sandbox ``docker run …`` argv (produced by
``build_sandbox_command``) from ``NF_HEAD_ARGV_FILE``, POSTs it to the narrow
launcher's ``/run_head`` endpoint, and relays the streamed head output to its own
stdout — which the head-launch primitive (``_launch_nextflow_head``) has already
redirected to the run's log file. It exits with the head container's exit code
(carried on the trailing ``__LAUNCHER_EXIT__ <code>`` sentinel line).

Net effect: the backend process holds NO docker access for the head launch; the
launcher validates the argv (mounts confined, forced runsc/non-root/caps, no
privileged/host) before running it — so even a compromised backend cannot craft
an escaping head. See docs/20260818_SANDBOX_SOCKET_PROXY_HARDENING.md.

Pure stdlib (urllib) — runs under the backend's python3.
"""
import json
import os
import sys
import urllib.request

_SENTINEL = "__LAUNCHER_EXIT__"


def main():
    url = os.environ.get("NF_HEAD_LAUNCHER_URL", "").rstrip("/")
    argv_file = os.environ.get("NF_HEAD_ARGV_FILE", "")
    token = os.environ.get("NF_HEAD_LAUNCHER_TOKEN", "")
    timeout = int(os.environ.get("NF_HEAD_TIMEOUT", "86400"))
    if not url or not argv_file:
        sys.stderr.write("[head_client] NF_HEAD_LAUNCHER_URL / NF_HEAD_ARGV_FILE not set\n")
        return 2
    try:
        with open(argv_file) as f:
            spec = json.load(f)
    except Exception as e:  # pragma: no cover - defensive
        sys.stderr.write(f"[head_client] cannot read argv file: {e}\n")
        return 2

    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{url}/run_head", data=json.dumps(spec).encode(), headers=headers)

    code = 1
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "replace")
                if line.startswith(_SENTINEL):
                    parts = line.strip().split()
                    try:
                        code = int(parts[1])
                    except Exception:
                        code = 1
                    break
                sys.stdout.write(line)
                sys.stdout.flush()
    except Exception as e:
        sys.stderr.write(f"[head_client] launcher call failed: {e}\n")
        return 1
    return code


if __name__ == "__main__":
    sys.exit(main())
