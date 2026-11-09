#!/usr/bin/env python3
"""Bounded native smoke runner for an explicitly approved non-production host.

Runs through SSM. Never prints credentials, changes IAM/network settings, prunes
Docker, or replaces an application service. Source and cached images remain.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import time


def run_remote(image, expected_arch, payload):
    registry = "399683337364.dkr.ecr.us-west-2.amazonaws.com"
    if not image.startswith(registry + "/biomate/") or "@sha256:" not in image:
        raise ValueError("An immutable neutral image in the approved registry is required")
    if platform.machine() != {"amd64": "x86_64", "arm64": "aarch64"}[expected_arch]:
        raise ValueError("Native architecture mismatch; emulation is not qualification")
    work = Path(tempfile.mkdtemp(prefix="biomate-native-smoke-", dir="/tmp"))
    auth = work / "auth"
    auth.mkdir(mode=0o700)
    smoke = work / "smoke.py"
    smoke.write_bytes(base64.b64decode(payload, validate=True))
    container_name = work.name
    result = {"image": image, "expected_arch": expected_arch, "host_arch": platform.machine(),
              "directory": str(work), "offline_inference": True, "passed": False}
    started = time.time()
    env = dict(os.environ, DOCKER_CONFIG=str(auth))
    try:
        result["stage"] = "resource-preflight"
        available = int(next(line.split()[1] for line in Path("/proc/meminfo").read_text().splitlines()
                             if line.startswith("MemAvailable:"))) * 1024
        result.update(available_memory_bytes=available, available_disk_bytes=shutil.disk_usage(work).free)
        if available < 3 * 1024**3 or result["available_disk_bytes"] < 6 * 1024**3:
            raise RuntimeError("Insufficient test-host memory or disk headroom")
        memory = min(6 * 1024**3, available - 1024**3)
        result["memory_limit_bytes"] = memory
        result["stage"] = "registry-login"
        token = subprocess.check_output(["aws", "ecr", "get-login-password", "--region", "us-west-2",
                                         "--cli-connect-timeout", "5", "--cli-read-timeout", "20"], timeout=90)
        login = subprocess.run(["docker", "login", "--username", "AWS", "--password-stdin", registry],
                               input=token, env=env, capture_output=True, timeout=45)
        del token
        if login.returncode:
            raise RuntimeError("Registry login failed; credential output deliberately omitted")
        result["stage"] = "image-pull"
        subprocess.run(["docker", "pull", image], env=env, check=True, timeout=900)
        details = json.loads(subprocess.check_output(["docker", "image", "inspect", image], env=env, timeout=30))[0]
        result["image_arch"] = details["Architecture"]
        result["repo_digests"] = details.get("RepoDigests", [])
        if details["Architecture"] != expected_arch:
            raise ValueError("Pulled image is not native")
        cpu = str(min(os.sched_getaffinity(0)))
        result["stage"] = "offline-inference"
        command = ["docker", "run", "--rm", "--name", container_name, "--network", "none", "--cap-drop", "ALL",
                   "--security-opt", "no-new-privileges", "--cpus", "1", "--cpuset-cpus", cpu,
                   "--memory", str(memory), "--memory-swap", str(memory), "--pids-limit", "256", "-e", "OMP_NUM_THREADS=1",
                   "-e", "MKL_NUM_THREADS=1", "-v", str(smoke) + ":/tmp/biomate-smoke.py:ro",
                   "--entrypoint", "python3", image, "/tmp/biomate-smoke.py"]
        checked = subprocess.run(command, env=env, capture_output=True, text=True, timeout=900)
        (work / "stdout.txt").write_text(checked.stdout)
        (work / "stderr.txt").write_text(checked.stderr)
        result.update(exit_code=checked.returncode, stdout=checked.stdout, stderr=checked.stderr,
                      passed=checked.returncode == 0 and "SMOKE PASS:" in checked.stdout)
    except Exception as error:
        result["error"] = type(error).__name__
    finally:
        # A subprocess timeout must not leave our test container running.
        subprocess.run(["docker", "rm", "-f", container_name], env=env,
                       capture_output=True, timeout=30)
        # Only this execution's private Docker token file; never shared config.
        (auth / "config.json").unlink(missing_ok=True)
        result["duration_s"] = round(time.time() - started, 3)
        (work / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2), flush=True)
    return 0 if result["passed"] else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("architecture", choices=("amd64", "arm64"))
    parser.add_argument("payload", help="Base64 of the reviewed smoke script, not credentials")
    args = parser.parse_args()
    return run_remote(args.image, args.architecture, args.payload)


if __name__ == "__main__":
    raise SystemExit(main())
