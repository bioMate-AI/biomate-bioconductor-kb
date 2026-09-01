"""Self-tests for validate_it_argv in launcher.py.

Run without any dependencies (pure stdlib, no docker, no HTTP calls):

    python3 deploy/sandbox-launcher/test_it_launcher.py

Covers the security validation that guards POST /run_it (IT container launch).
Each test function patches the module-level constants in place and restores them
in a finally block so tests are independent of run order.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import launcher as _lm  # noqa: E402 — must come after sys.path patch

_FAILS = 0


def _check(name: str, cond: bool) -> None:
    global _FAILS
    print(f"[{'OK ' if cond else 'FAIL'}] {name}")
    if not cond:
        _FAILS += 1


def _expect_reject(label: str, argv: list, image: str) -> None:
    try:
        _lm.validate_it_argv(argv, image)
        _check(label, False)
    except ValueError:
        _check(label, True)


# ------------------------------------------------------------------
# Fixtures
# ------------------------------------------------------------------

_JUPYTER = "quay.io/bgruening/docker-jupyter-notebook"
_EVIL = "evil.com/malicious:latest"


def _good_argv(image: str = _JUPYTER) -> list:
    return ["docker", "run", "-d", "--rm", "--name", "abc123hex", "-p", "8888", image]


# ------------------------------------------------------------------
# Tests
# ------------------------------------------------------------------

def test_happy_path():
    """A well-formed IT argv passes validation and returns True."""
    _check("happy: valid argv returns True",
           _lm.validate_it_argv(_good_argv(), _JUPYTER) is True)
    # --detach long form also accepted
    argv_long = ["docker", "run", "--detach", "--rm", "--name", "abc123",
                 "-p", "8888", _JUPYTER]
    _check("happy: --detach long form accepted",
           _lm.validate_it_argv(argv_long, _JUPYTER) is True)


def test_not_docker_run():
    """Non-docker/podman commands are rejected outright."""
    _expect_reject("python3 script rejected", ["python3", "script.py"], _JUPYTER)
    _expect_reject("docker exec rejected",
                   ["docker", "exec", "abc", "bash"], _JUPYTER)


def test_missing_detach_flag():
    """IT containers MUST be launched detached (-d / --detach)."""
    argv = ["docker", "run", "--rm", "--name", "abc123", "-p", "8888", _JUPYTER]
    _expect_reject("no -d flag rejected", argv, _JUPYTER)


def test_image_allowlist():
    """Only images in IT_ALLOWED_IMAGES pass; anything else is rejected.

    Prefix matching: allowlist entry 'repo/img' covers 'repo/img:tag' and
    'repo/img/variant' but NOT 'repo/img-evil'.
    """
    saved = _lm.IT_ALLOWED_IMAGES[:]
    _lm.IT_ALLOWED_IMAGES[:] = [_JUPYTER]
    try:
        # Unknown image rejected
        _expect_reject("unknown image rejected", _good_argv(_EVIL), _EVIL)

        # Different repo sharing the same prefix must also fail
        sibling = "quay.io/bgruening/evil:latest"
        _expect_reject("sibling-repo image rejected", _good_argv(sibling), sibling)

        # Tagged version of allowlisted image passes (startswith check)
        tagged = f"{_JUPYTER}:2021-03-05"
        _check("tagged allowlisted image passes",
               _lm.validate_it_argv(_good_argv(tagged), tagged) is True)

        # Empty allowlist (LAUNCHER_IT_ALLOWED_IMAGES='') means allow-all
        _lm.IT_ALLOWED_IMAGES[:] = []
        _check("empty allowlist is allow-all",
               _lm.validate_it_argv(_good_argv(_EVIL), _EVIL) is True)
    finally:
        _lm.IT_ALLOWED_IMAGES[:] = saved


def test_socket_mount_forbidden():
    """Any bind mount of the docker socket is rejected."""
    cases = [
        ("-v docker.sock path",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "-v", "/var/run/docker.sock:/var/run/docker.sock:ro",
          "-p", "8888", _JUPYTER]),
        ("--volume /var/run path",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--volume", "/var/run:/var/run:ro",
          "-p", "8888", _JUPYTER]),
    ]
    for label, argv in cases:
        _expect_reject(label, argv, _JUPYTER)


def test_privileged_and_cap_add_forbidden():
    """Privilege-escalation flags are always rejected."""
    cases = [
        ("--privileged",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--privileged", "-p", "8888", _JUPYTER]),
        ("--cap-add SYS_ADMIN",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--cap-add", "SYS_ADMIN", "-p", "8888", _JUPYTER]),
        ("--device /dev/kvm",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--device", "/dev/kvm", "-p", "8888", _JUPYTER]),
    ]
    for label, argv in cases:
        _expect_reject(label, argv, _JUPYTER)


def test_host_namespace_forbidden():
    """Sharing host network, pid, ipc, or uts namespaces is rejected."""
    cases = [
        ("--network host",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--network", "host", "-p", "8888", _JUPYTER]),
        ("--net host",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--net", "host", "-p", "8888", _JUPYTER]),
        ("--pid host",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--pid", "host", "-p", "8888", _JUPYTER]),
        ("--ipc host",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--ipc", "host", "-p", "8888", _JUPYTER]),
        ("--security-opt seccomp=unconfined",
         ["docker", "run", "-d", "--rm", "--name", "abc",
          "--security-opt", "seccomp=unconfined", "-p", "8888", _JUPYTER]),
    ]
    for label, argv in cases:
        _expect_reject(label, argv, _JUPYTER)


def test_volume_prefix_enforcement():
    """Bind mounts outside IT_PREFIXES are rejected; mounts inside pass."""
    saved = _lm.IT_PREFIXES[:]
    _lm.IT_PREFIXES[:] = [os.path.realpath("/app/database/jobs_directory")]
    try:
        # Mount outside prefix
        argv_bad = ["docker", "run", "-d", "--rm", "--name", "abc",
                    "-v", "/etc/passwd:/etc/passwd:ro",
                    "-p", "8888", _JUPYTER]
        _expect_reject("mount outside prefix rejected", argv_bad, _JUPYTER)

        # Mount inside prefix
        inside = "/app/database/jobs_directory/job42"
        argv_ok = ["docker", "run", "-d", "--rm", "--name", "abc",
                   "-v", f"{inside}:{inside}:rw",
                   "-p", "8888", _JUPYTER]
        _check("mount inside prefix passes",
               _lm.validate_it_argv(argv_ok, _JUPYTER) is True)
    finally:
        _lm.IT_PREFIXES[:] = saved


def test_non_root_enforcement():
    """Root UID is rejected when IT_ENFORCE_NON_ROOT is active; default is off."""
    saved = _lm.IT_ENFORCE_NON_ROOT

    # Default (off): root uid allowed
    argv_root = ["docker", "run", "-d", "--rm", "--name", "abc",
                 "--user", "0:0", "-p", "8888", _JUPYTER]
    _check("root uid allowed by default (enforcement off)",
           _lm.validate_it_argv(argv_root, _JUPYTER) is True)

    _lm.IT_ENFORCE_NON_ROOT = True
    try:
        _expect_reject("root uid=0 rejected when enforcement on", argv_root, _JUPYTER)
        _expect_reject("uid=root string rejected when enforcement on",
                       ["docker", "run", "-d", "--rm", "--name", "abc",
                        "--user", "root", "-p", "8888", _JUPYTER],
                       _JUPYTER)
        # Non-root should still pass
        argv_ok = ["docker", "run", "-d", "--rm", "--name", "abc",
                   "--user", "1000:1000", "-p", "8888", _JUPYTER]
        _check("non-root uid passes enforcement",
               _lm.validate_it_argv(argv_ok, _JUPYTER) is True)
    finally:
        _lm.IT_ENFORCE_NON_ROOT = saved


# ------------------------------------------------------------------
# Runner
# ------------------------------------------------------------------

def run() -> int:
    test_happy_path()
    test_not_docker_run()
    test_missing_detach_flag()
    test_image_allowlist()
    test_socket_mount_forbidden()
    test_privileged_and_cap_add_forbidden()
    test_host_namespace_forbidden()
    test_volume_prefix_enforcement()
    test_non_root_enforcement()
    print(f"\n{'-' * 44}")
    print(f"{'PASS' if not _FAILS else 'FAIL'}: {_FAILS} failure(s)")
    return 1 if _FAILS else 0


if __name__ == "__main__":
    sys.exit(run())
