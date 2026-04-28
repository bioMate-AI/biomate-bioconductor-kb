"""
ADMET auto-loop orchestrator — main retry/escalation loop.

The orchestrator drives one complete ADMET screening pipeline attempt:
  phase_2_admet_prediction → phase_3_herg_screen → phase_4_dili_ames

For each phase it calls the supplied `phase_runner_fn`, evaluates QC,
applies parameter remediations on failure, and retries up to
`max_retries_per_phase` times before escalating.

Architecture mirrors cryo_em_autoloop.orchestrator — only the phase list,
param type, evaluator type, and tuner type differ.

No external dependencies — stdlib + local modules only.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

from .audit_logger import AuditLogger
from .param_tuner import ADMETParamTuner
from .params import ADMETParams
from .qc_evaluator import ADMETQCEvaluator

# Canonical phase execution order — only ADMET phases (virtual screen phase_1
# runs upstream of this loop; PK phase_5 is advisory-only).
PHASES: list[str] = [
    "phase_2_admet_prediction",
    "phase_3_herg_screen",
    "phase_4_dili_ames",
]


# ── Result dataclass (identical shape to cryo_em_autoloop.LoopResult) ────────

@dataclass
class LoopResult:
    """Summary of a completed ADMET auto-loop run."""
    run_id: str
    phases_passed: list[str] = field(default_factory=list)
    phases_failed: list[str] = field(default_factory=list)
    phases_escalated: list[str] = field(default_factory=list)
    total_attempts: int = 0
    audit_path: Path = field(default=Path("."))
    summary_path: Path = field(default=Path("."))


# ── Orchestrator ──────────────────────────────────────────────────────────────

class ADMETAutoLoop:
    """
    Main retry loop for an ADMET compound safety auto-loop run.

    Parameters
    ----------
    run_id:
        Unique identifier for this run (used in audit filenames).
        If omitted, a UUID is generated.
    params:
        Initial ADMETParams.  The orchestrator works on copies and never
        mutates the object you pass in.
    qc_profile:
        Name of the QC threshold profile (see qc_evaluator.QC_PROFILES).
        Options: "admet_standard", "admet_cns", "admet_oncology".
    max_retries_per_phase:
        Number of *additional* attempts allowed after the first failure.
        Default 2 → each phase can be attempted at most 3 times.
    output_dir:
        Directory for audit files.  Defaults to the current directory.
    """

    def __init__(
        self,
        run_id: str | None = None,
        params: ADMETParams | None = None,
        qc_profile: str = "admet_standard",
        max_retries_per_phase: int = 2,
        output_dir: Path | None = None,
    ) -> None:
        self.run_id = run_id or str(uuid.uuid4())
        self.params = (params or ADMETParams()).copy()
        self.max_retries_per_phase = max_retries_per_phase
        self.output_dir = Path(output_dir) if output_dir else Path(".")

        self._evaluator = ADMETQCEvaluator(profile=qc_profile)
        self._tuner = ADMETParamTuner()
        self._logger = AuditLogger(self.run_id, self.output_dir)

    # ── Public API ────────────────────────────────────────────────────────────

    def run(
        self,
        phase_runner_fn: Callable[[str, ADMETParams], dict],
    ) -> LoopResult:
        """
        Execute the full ADMET pipeline loop.

        Parameters
        ----------
        phase_runner_fn:
            Callable that executes one phase and returns a metrics dict.
            Signature: ``(phase: str, params: ADMETParams) -> dict``
            The dict should match the toxicity_report.json schema.

        Returns
        -------
        LoopResult
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

        result.summary_path = self._logger.write_summary_report()
        result.audit_path   = self._logger.audit_path
        return result

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _run_phase(
        self,
        phase: str,
        phase_runner_fn: Callable[[str, ADMETParams], dict],
    ) -> tuple[str, int]:
        """
        Attempt a single phase up to (max_retries_per_phase + 1) times.

        Returns (outcome, total_attempts_used) where outcome is
        "pass", "fail", or "escalated".
        """
        max_attempts = self.max_retries_per_phase + 1
        attempt_number = 0

        for attempt in range(1, max_attempts + 1):
            attempt_number = attempt

            metrics = phase_runner_fn(phase, self.params)
            qc_result = self._evaluator.evaluate_phase(phase, metrics)

            remediations: list = []
            if not qc_result.passed:
                new_params, remediations = self._tuner.remediate(qc_result, self.params)
            else:
                new_params = self.params

            self._logger.log_attempt(
                phase=phase,
                attempt=attempt,
                params_snapshot=self.params,
                qc_result=qc_result,
                remediations=remediations,
            )

            if qc_result.passed:
                self._logger.log_phase_final(
                    phase=phase,
                    total_attempts=attempt_number,
                    outcome="pass",
                )
                return "pass", attempt_number

            self._params_apply(new_params)

            if attempt >= max_attempts:
                self._logger.log_phase_final(
                    phase=phase,
                    total_attempts=attempt_number,
                    outcome="escalated",
                )
                return "escalated", attempt_number

        self._logger.log_phase_final(
            phase=phase,
            total_attempts=attempt_number,
            outcome="fail",
        )
        return "fail", attempt_number

    def _params_apply(self, new_params: ADMETParams) -> None:
        """Replace the active params with the remediated copy."""
        self.params = new_params


# ── MockPhaseRunner — for testing ─────────────────────────────────────────────

class MockPhaseRunner:
    """
    Deterministic phase runner for unit tests.

    Maps phase names to metrics dicts (or lists of dicts for multi-attempt
    scenarios — last entry is repeated when exhausted).

    Example::

        runner = MockPhaseRunner({
            "phase_2_admet_prediction": [
                {"herg_ic50_uM": 3.5, ...},   # attempt 1: HALT
                {"herg_ic50_uM": 18.0, ...},  # attempt 2: PASS
            ],
            "phase_3_herg_screen": {"herg_ic50_uM": 18.0, ...},
        })
        loop.run(runner)
    """

    def __init__(self, phase_metrics: dict[str, dict | list[dict]]) -> None:
        self._metrics: dict[str, list[dict]] = {}
        for phase, value in phase_metrics.items():
            self._metrics[phase] = value if isinstance(value, list) else [value]
        self._call_counts: dict[str, int] = {}

    def __call__(self, phase: str, params: ADMETParams) -> dict:
        call_idx = self._call_counts.get(phase, 0)
        self._call_counts[phase] = call_idx + 1
        options = self._metrics.get(phase, [{}])
        return options[min(call_idx, len(options) - 1)]
