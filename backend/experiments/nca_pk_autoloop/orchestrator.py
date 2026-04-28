"""NCA PK auto-loop orchestrator."""
from __future__ import annotations
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable
from .audit_logger import AuditLogger
from .param_tuner import NCAPKParamTuner
from .params import NCAPKParams
from .qc_evaluator import NCAPKQCEvaluator

PHASES: list[str] = ["phase_1_nca_analysis"]


@dataclass
class LoopResult:
    run_id: str
    phases_passed: list[str] = field(default_factory=list)
    phases_failed: list[str] = field(default_factory=list)
    phases_escalated: list[str] = field(default_factory=list)
    total_attempts: int = 0
    audit_path: Path = field(default=Path("."))
    summary_path: Path = field(default=Path("."))


class NCAPKAutoLoop:
    def __init__(self, run_id=None, params=None, qc_profile="nca_standard",
                 max_retries_per_phase=2, output_dir=None):
        self.run_id = run_id or str(uuid.uuid4())
        self.params = (params or NCAPKParams()).copy()
        self.max_retries_per_phase = max_retries_per_phase
        self.output_dir = Path(output_dir) if output_dir else Path(".")
        self._evaluator = NCAPKQCEvaluator(profile=qc_profile)
        self._tuner = NCAPKParamTuner()
        self._logger = AuditLogger(self.run_id, self.output_dir)

    def run(self, phase_runner_fn: Callable) -> LoopResult:
        result = LoopResult(run_id=self.run_id,
                            audit_path=self._logger.audit_path,
                            summary_path=self._logger.summary_path)
        for phase in PHASES:
            outcome, attempts = self._run_phase(phase, phase_runner_fn)
            result.total_attempts += attempts
            (result.phases_passed if outcome == "pass" else
             result.phases_escalated if outcome == "escalated" else
             result.phases_failed).append(phase)
        result.summary_path = self._logger.write_summary_report()
        result.audit_path = self._logger.audit_path
        return result

    def _run_phase(self, phase, phase_runner_fn):
        max_attempts = self.max_retries_per_phase + 1
        attempt_number = 0
        for attempt in range(1, max_attempts + 1):
            attempt_number = attempt
            metrics = phase_runner_fn(phase, self.params)
            qc_result = self._evaluator.evaluate_phase(phase, metrics)
            remediations = []
            if not qc_result.passed:
                new_params, remediations = self._tuner.remediate(qc_result, self.params)
            else:
                new_params = self.params
            self._logger.log_attempt(phase, attempt, self.params, qc_result, remediations)
            if qc_result.passed:
                self._logger.log_phase_final(phase, attempt_number, "pass")
                return "pass", attempt_number
            self.params = new_params
            if attempt >= max_attempts:
                self._logger.log_phase_final(phase, attempt_number, "escalated")
                return "escalated", attempt_number
        self._logger.log_phase_final(phase, attempt_number, "fail")
        return "fail", attempt_number


class MockPhaseRunner:
    def __init__(self, phase_metrics: dict):
        self._metrics = {k: (v if isinstance(v, list) else [v]) for k, v in phase_metrics.items()}
        self._call_counts: dict = {}

    def __call__(self, phase: str, params: NCAPKParams) -> dict:
        idx = self._call_counts.get(phase, 0)
        self._call_counts[phase] = idx + 1
        opts = self._metrics.get(phase, [{}])
        return opts[min(idx, len(opts) - 1)]
