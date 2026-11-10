"""Parity self-test for the Phase 0 scheduler.

Runnable with plain python (no pytest needed — the sandbox lacks it):

    cd backend && PYTHONPATH=lib python3 -m galaxy.ai.compute.test_scheduler_parity

Each case encodes an input state and the executor the LEGACY routing block
in nextflow_executor.execute_nextflow produces for it, then asserts the new
Scheduler agrees. Keep this in lockstep with the legacy rules (~L4783-4880).
"""

from __future__ import annotations

from .run_spec import RunSpec
from .scheduler import SCHEDULER, BACKEND_LOCAL, BACKEND_AWSBATCH


# (name, spec-kwargs, expected legacy executor)
CASES = [
    (
        "aws_env_on",
        dict(use_aws_env=True, nextflow_path="/wf/rnaseq.nf"),
        BACKEND_AWSBATCH,
    ),
    (
        "executor_awsbatch_requested",
        dict(executor_requested="awsbatch", nextflow_path="/wf/admet.nf"),
        BACKEND_AWSBATCH,
    ),
    (
        # 2026-11-09: personal workflow on a Batch platform now runs on Batch
        # (was local; the SaaS Galaxy container has no docker). Screened by the
        # mandatory upload source pre-check before dispatch.
        "personal_wf_on_batch_platform",
        dict(use_aws_env=True, nextflow_path="/tmp/biomate_user_nf/u1/x.nf"),
        BACKEND_AWSBATCH,
    ),
    (
        # No Batch platform flag → local docker (on-prem / local dev).
        "personal_wf_default",
        dict(nextflow_path="/tmp/biomate_user_nf/u1/x.nf"),
        BACKEND_LOCAL,
    ),
    (
        "s3_outdir_autodetect",
        dict(nextflow_path="/wf/wgs.nf", outdir="s3://bkt/out/x"),
        BACKEND_AWSBATCH,
    ),
    (
        "s3_input_autodetect",
        dict(nextflow_path="/wf/wgs.nf", param_values=["s3://bkt/reads/a.fq"]),
        BACKEND_AWSBATCH,
    ),
    (
        "default_local",
        dict(nextflow_path="/wf/local.nf", outdir="/tmp/out"),
        BACKEND_LOCAL,
    ),
]


def run() -> int:
    failures = 0
    for name, kwargs, expected in CASES:
        spec = RunSpec(**kwargs)
        choice = SCHEDULER.select_backend(spec)
        ok = choice.backend == expected
        status = "OK " if ok else "FAIL"
        print(f"[{status}] {name}: got={choice.backend} want={expected} ({choice.rule})")
        if not ok:
            failures += 1
    print(f"\n{len(CASES) - failures}/{len(CASES)} parity cases passed")
    return 1 if failures else 0


if __name__ == "__main__":
    import sys

    sys.exit(run())
