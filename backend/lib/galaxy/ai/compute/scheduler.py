"""Backend selection — Phase 0 (behavior-preserving) implementation.

``Scheduler.select_backend`` reproduces, *exactly*, the routing decision
that ``nextflow_executor.execute_nextflow`` makes today. The point of Phase
0 is not to change behavior but to (a) move the decision into a single
testable function and (b) let us run it in **shadow mode** next to the
legacy code to prove parity before Feature ③ upgrades it to cost/capacity
scoring.

Legacy decision order (from `execute_nextflow`, ~L4783–4872):

    1. NEXTFLOW_USE_AWS=true OR executor == "awsbatch"      -> awsbatch
    2. nextflow_path under /tmp/biomate_user_nf/ (personal) -> awsbatch when
       on a Batch platform (NEXTFLOW_USE_AWS / awsbatch requested), else local
    3. outdir is s3:// and no executor set yet              -> awsbatch
    4. any s3:// param input and no executor set yet        -> awsbatch
    5. otherwise                                            -> local

Rule 2 is applied *after* rule 1 in the source. Before 2026-11-09 it forced
local unconditionally (which could not run on SaaS — the Galaxy container has
no docker); it now keeps the Batch routing on a Batch platform and only forces
local on local/on-prem deployments.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Optional

from .run_spec import RunSpec

# Backend name constants — match the `compute["executor"]` values the
# executor already uses, so shadow-mode comparison is direct.
BACKEND_LOCAL = "local"
BACKEND_AWSBATCH = "awsbatch"


def compute_backend_v2_enabled() -> bool:
    """Whether the Phase 0 scheduler runs (in shadow mode). Default off."""
    return os.environ.get("COMPUTE_BACKEND_V2", "false").lower() in (
        "1",
        "true",
        "yes",
    )


@dataclass
class BackendChoice:
    """Result of a scheduling decision."""

    backend: str          # BACKEND_LOCAL | BACKEND_AWSBATCH
    reason: str           # human-readable "why", for the decision log
    rule: str             # short rule id, for programmatic comparison

    def __str__(self) -> str:  # pragma: no cover - trivial
        return f"{self.backend} (rule={self.rule}: {self.reason})"


class Scheduler:
    """Selects a compute backend for a :class:`RunSpec`.

    Phase 0: a pure, deterministic re-encoding of the legacy rules. No
    capability registry, no cost model, no fallback yet — those arrive with
    Feature ③ and will be layered on top without changing this contract.
    """

    def select_backend(self, spec: RunSpec) -> BackendChoice:
        # Rule 2 (personal workflow) is checked first because in the legacy
        # code it is applied last and overrides everything else. Encoding it
        # first here yields the identical final result with less branching.
        if spec.is_personal_workflow:
            # 2026-11-09: personal workflows run on Batch wherever Batch is the
            # platform (SaaS: NEXTFLOW_USE_AWS, or an explicit awsbatch request) —
            # the SaaS Galaxy container has no docker, so the former
            # unconditional-local rule could not execute there (exit 127). They
            # fall back to the local docker executor only on local/on-prem
            # deployments. Isolation on Batch = the job boundary + the mandatory
            # upload source pre-check (validate_nextflow_source).
            if spec.use_aws_env or spec.executor_requested == BACKEND_AWSBATCH:
                return BackendChoice(
                    backend=BACKEND_AWSBATCH,
                    reason="personal workflow on a Batch platform "
                    "(NEXTFLOW_USE_AWS / awsbatch requested) — screened by the "
                    "upload source pre-check",
                    rule="personal_workflow_awsbatch",
                )
            return BackendChoice(
                backend=BACKEND_LOCAL,
                reason="personal workflow on a local/on-prem deployment "
                "(local docker executor)",
                rule="personal_workflow_local",
            )

        # Rule 1: explicit awsbatch request or the global platform flag.
        if spec.use_aws_env:
            return BackendChoice(
                backend=BACKEND_AWSBATCH,
                reason="NEXTFLOW_USE_AWS=true (platform default: all Batch)",
                rule="use_aws_env",
            )
        if spec.executor_requested == BACKEND_AWSBATCH:
            return BackendChoice(
                backend=BACKEND_AWSBATCH,
                reason="executor='awsbatch' requested by caller",
                rule="executor_requested_awsbatch",
            )

        # An explicit non-awsbatch executor request is honored as-is.
        if spec.executor_requested and spec.executor_requested != BACKEND_AWSBATCH:
            return BackendChoice(
                backend=spec.executor_requested,
                reason=f"executor='{spec.executor_requested}' requested by caller",
                rule="executor_requested_explicit",
            )

        # Rule 3: s3:// outdir implies cloud execution.
        if spec.has_s3_outdir:
            return BackendChoice(
                backend=BACKEND_AWSBATCH,
                reason=f"s3:// outdir detected ({spec.outdir}) — auto-select Batch",
                rule="s3_outdir_autodetect",
            )

        # Rule 4: any s3:// input implies cloud execution.
        if spec.s3_inputs:
            return BackendChoice(
                backend=BACKEND_AWSBATCH,
                reason=f"s3:// input(s) detected ({len(spec.s3_inputs)}) — auto-select Batch",
                rule="s3_input_autodetect",
            )

        # Rule 5: default to local.
        return BackendChoice(
            backend=BACKEND_LOCAL,
            reason="no cloud signal (no flag, no awsbatch request, no s3:// paths)",
            rule="default_local",
        )


# Module-level singleton — the executor imports this for shadow-mode.
SCHEDULER = Scheduler()


def shadow_compare(spec: RunSpec, legacy_executor: str) -> Optional[BackendChoice]:
    """Run the scheduler in shadow mode and return its choice (or None).

    Only does work when ``COMPUTE_BACKEND_V2`` is enabled. The caller passes
    the executor the *legacy* code already settled on; this function returns
    the scheduler's choice so the caller can log agreement. It never mutates
    anything — Phase 0 is strictly observational.
    """
    if not compute_backend_v2_enabled():
        return None
    choice = SCHEDULER.select_backend(spec)
    # Normalize: legacy "" (unset, later defaulted to local at launch) maps
    # to local for comparison purposes.
    legacy = legacy_executor or BACKEND_LOCAL
    choice_agrees = choice.backend == legacy
    choice.reason += f" | shadow: legacy={legacy} agree={choice_agrees}"
    return choice
