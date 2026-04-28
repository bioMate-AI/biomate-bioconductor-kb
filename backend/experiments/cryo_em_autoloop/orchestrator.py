"""
CryoEM auto-loop orchestrator — main retry/escalation loop.

The orchestrator drives one complete SPA pipeline attempt:
  phase_A → phase_B → phase_C → phase_D → phase_E

For each phase it calls the supplied `phase_runner_fn`, evaluates QC,
applies parameter remediations on failure, and retries up to
`max_retries_per_phase` times before escalating to the next phase.

No external dependencies — stdlib + local modules only.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .audit_logger import AuditLogger
from .param_tuner import ParamTuner
from .params import CryoEMParams
from .qc_evaluator import CryoEMQCEvaluator

# Canonical phase execution order
PHASES: list[str] = ["phase_A", "phase_B", "phase_C", "phase_D", "phase_E"]


# ── Result dataclass ─────────────────────────────────────────────────────────

@dataclass
class LoopResult:
    """Summary of a completed auto-loop run."""
    run_id: str
    phases_passed: list[str] = field(default_factory=list)
    phases_failed: list[str] = field(default_factory=list)
    phases_escalated: list[str] = field(default_factory=list)
    total_attempts: int = 0
    audit_path: Path = field(default=Path("."))
    summary_path: Path = field(default=Path("."))


# ── Orchestrator ─────────────────────────────────────────────────────────────

class CryoEMAutoLoop:
    """
    Main retry loop for a CryoSPARC SPA auto-loop run.

    Parameters
    ----------
    run_id:
        Unique identifier for this run (used in audit filenames).
        If omitted a UUID is generated.
    params:
        Initial CryoEMParams.  The orchestrator works on copies and never
        mutates the object you pass in.
    qc_profile:
        Name of the QC threshold profile (see qc_evaluator.QC_PROFILES).
    max_retries_per_phase:
        Number of *additional* attempts allowed after the first failure.
        Default is 2, meaning each phase can be attempted at most 3 times.
    output_dir:
        Directory for audit files.  Defaults to the current working directory.
    """

    def __init__(
        self,
        run_id: str | None = None,
        params: CryoEMParams | None = None,
        qc_profile: str = "cryoem_spa_purified",
        max_retries_per_phase: int = 2,
        output_dir: Path | None = None,
    ) -> None:
        self.run_id = run_id or str(uuid.uuid4())
        self.params = (params or CryoEMParams()).copy()
        self.max_retries_per_phase = max_retries_per_phase
        self.output_dir = Path(output_dir) if output_dir else Path(".")

        self._evaluator = CryoEMQCEvaluator(profile=qc_profile)
        self._tuner = ParamTuner()
        self._logger = AuditLogger(self.run_id, self.output_dir)

    # ── Public API ───────────────────────────────────────────────────────────

    def run(
        self,
        phase_runner_fn: Callable[[str, CryoEMParams], dict],
    ) -> LoopResult:
        """
        Execute the full pipeline loop.

        Parameters
        ----------
        phase_runner_fn:
            Callable that executes one phase and returns a metrics dict.
            Signature: ``(phase: str, params: CryoEMParams) -> dict``

        Returns
        -------
        LoopResult
            Full summary including audit and summary file paths.
        """
        result = LoopResult(
            run_id=self.run_id,
            audit_path=self._logger.audit_path,
            summary_path=self._logger.summary_path,
        )

        for phase in PHASES:
            phase_outcome, attempts_used = self._run_phase(
                phase=phase,
                phase_runner_fn=phase_runner_fn,
            )
            result.total_attempts += attempts_used

            if phase_outcome == "pass":
                result.phases_passed.append(phase)
            elif phase_outcome == "escalated":
                result.phases_escalated.append(phase)
            else:
                result.phases_failed.append(phase)

        # Write the human-readable summary and update paths in result
        result.summary_path = self._logger.write_summary_report()
        result.audit_path   = self._logger.audit_path
        return result

    # ── Internal helpers ─────────────────────────────────────────────────────

    def _run_phase(
        self,
        phase: str,
        phase_runner_fn: Callable[[str, CryoEMParams], dict],
    ) -> tuple[str, int]:
        """
        Attempt a single phase up to (max_retries_per_phase + 1) times.

        Returns (outcome, total_attempts_used) where outcome is one of
        "pass", "fail", or "escalated".
        """
        max_attempts = self.max_retries_per_phase + 1
        attempt_number = 0

        for attempt in range(1, max_attempts + 1):
            attempt_number = attempt

            # 1. Execute the phase
            metrics = phase_runner_fn(phase, self.params)

            # 2. Evaluate QC
            qc_result = self._evaluator.evaluate_phase(phase, metrics)

            # 3. Determine remediations (only meaningful on failure)
            remediations: list = []
            if not qc_result.passed:
                new_params, remediations = self._tuner.remediate(qc_result, self.params)
            else:
                new_params = self.params  # unchanged

            # 4. Log this attempt
            self._logger.log_attempt(
                phase=phase,
                attempt=attempt,
                params_snapshot=self.params,    # snapshot *before* applying changes
                qc_result=qc_result,
                remediations=remediations,
            )

            if qc_result.passed:
                # Phase passed — apply any param changes (none on pass) and move on
                self._logger.log_phase_final(
                    phase=phase,
                    total_attempts=attempt_number,
                    outcome="pass",
                )
                return "pass", attempt_number

            # Phase failed — apply remediations for the next attempt
            self._params_apply(new_params)

            if attempt >= max_attempts:
                # Out of retries
                self._logger.log_phase_final(
                    phase=phase,
                    total_attempts=attempt_number,
                    outcome="escalated",
                )
                return "escalated", attempt_number

        # Should not be reached, but guard against edge cases
        self._logger.log_phase_final(
            phase=phase,
            total_attempts=attempt_number,
            outcome="fail",
        )
        return "fail", attempt_number

    def _params_apply(self, new_params: CryoEMParams) -> None:
        """Replace the active params with the remediated copy."""
        self.params = new_params


# ── Mock phase runner — for testing ─────────────────────────────────────────

class MockPhaseRunner:
    """
    A deterministic phase runner for unit tests and local prototyping.

    Supply a dict mapping phase names to metrics dicts.  If a phase key maps
    to a *list* of dicts, successive calls for that phase consume entries in
    order (last entry is repeated when exhausted).  This lets you simulate
    "fail on attempt 1, pass on attempt 2" scenarios.

    Example::

        runner = MockPhaseRunner({
            "phase_A": [
                {"mean_total_drift_A": 60.0, ...},   # attempt 1: will fail
                {"mean_total_drift_A": 30.0, ...},   # attempt 2: will pass
            ],
            "phase_B": {"junk_fraction": 0.2, ...},  # always passes
        })
        loop.run(runner)
    """

    def __init__(self, phase_metrics: dict[str, dict | list[dict]]) -> None:
        # Normalise everything to lists for uniform handling
        self._metrics: dict[str, list[dict]] = {}
        for phase, value in phase_metrics.items():
            if isinstance(value, list):
                self._metrics[phase] = value
            else:
                self._metrics[phase] = [value]
        # Track call counts per phase
        self._call_counts: dict[str, int] = {}

    def __call__(self, phase: str, params: CryoEMParams) -> dict:
        """Return the next metrics dict for *phase*."""
        call_idx = self._call_counts.get(phase, 0)
        self._call_counts[phase] = call_idx + 1

        options = self._metrics.get(phase, [{}])
        # Clamp to last entry once exhausted
        entry_idx = min(call_idx, len(options) - 1)
        return options[entry_idx]
