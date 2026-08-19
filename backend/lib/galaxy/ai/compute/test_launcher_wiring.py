"""Self-test for the M0 head-launch seam (no pytest / no boto3 needed):

    cd backend && PYTHONPATH=lib python3 -m galaxy.ai.compute.test_launcher_wiring

Verifies the injection + default-registry wiring without launching any real
subprocess — a fake launch_fn records what it was called with.
"""

from __future__ import annotations

from .launcher import (
    CallableHeadLauncher,
    LaunchRequest,
    set_default_head_launcher,
    get_default_head_launcher,
)
from .backends import LocalSubprocessBackend, AWSBatchBackend


def _make_req() -> LaunchRequest:
    return LaunchRequest(
        cmd=["nextflow", "run", "x.nf"],
        env={"NXF_VER": "25.10.5"},
        work_dir="/tmp/nf/run1/work",
        log_path="/tmp/nf/run1/nf.log",
        run_id="run1",
    )


def run() -> int:
    failures = 0

    def _check(name: str, cond: bool) -> None:
        nonlocal failures
        print(f"[{'OK ' if cond else 'FAIL'}] {name}")
        if not cond:
            failures += 1

    # 1) CallableHeadLauncher adapts a plain fn and forwards the fields.
    seen = {}

    def _fake_launch(*, cmd, env, work_dir, log_path, run_id):
        seen.update(cmd=cmd, env=env, work_dir=work_dir, log_path=log_path, run_id=run_id)
        return f"proc:{run_id}"

    launcher = CallableHeadLauncher(_fake_launch)
    result = launcher.launch(_make_req())
    _check("CallableHeadLauncher returns fn result", result == "proc:run1")
    _check("CallableHeadLauncher forwards cmd", seen.get("cmd") == ["nextflow", "run", "x.nf"])
    _check("CallableHeadLauncher forwards run_id", seen.get("run_id") == "run1")

    # 2) Injected launcher: backend.launch_head delegates to it.
    local = LocalSubprocessBackend(head_launcher=launcher)
    _check("LocalSubprocessBackend.launch_head delegates", local.launch_head(_make_req()) == "proc:run1")

    # 3) No launcher available -> clear error, not a silent None.
    bare = AWSBatchBackend()
    set_default_head_launcher(None)
    raised = False
    try:
        bare.launch_head(_make_req())
    except RuntimeError:
        raised = True
    _check("missing launcher raises RuntimeError", raised)

    # 4) Default-registry path: set once, any backend picks it up.
    set_default_head_launcher(launcher)
    _check("get_default_head_launcher returns set value", get_default_head_launcher() is launcher)
    _check("backend falls back to default launcher", AWSBatchBackend().launch_head(_make_req()) == "proc:run1")
    set_default_head_launcher(None)  # reset global state

    print(f"\n{'-'*40}\n{'PASS' if not failures else 'FAIL'}: {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    import sys

    sys.exit(run())
