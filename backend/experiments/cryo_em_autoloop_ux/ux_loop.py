"""
UX-aware auto-loop orchestrator.

Extends `CryoEMAutoLoop` to emit rich progress events at each step through
a `ProgressReporter`.  This is the class that would be used in production
instead of the bare `CryoEMAutoLoop`.

Key difference from the base class:
  - Accepts a `ProgressReporter` alongside the phase runner
  - Passes params summary to `phase_start` so the user sees current settings
  - Calls `retry_triggered` with `EnrichedRemediation` objects (with citations)
  - Calls `phase_escalated` / `phase_passed` / `final_summary`
"""

from __future__ import annotations

import sys
import time
from dataclasses import asdict
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).parent.parent))

from cryo_em_autoloop.audit_logger import AuditLogger
from cryo_em_autoloop.orchestrator import PHASES, LoopResult
from cryo_em_autoloop.params import CryoEMParams, PHASE_PARAM_OWNERS
from cryo_em_autoloop.qc_evaluator import CryoEMQCEvaluator

from .enriched_tuner import KnowledgeEnrichedTuner, EnrichedRemediation
from .progress_reporter import ProgressReporter


class UXAwareAutoLoop:
    """
    Knowledge-enriched, progress-reporting CryoEM auto-loop.

    Parameters
    ----------
    run_id:         Unique run identifier.
    params:         Initial CryoEMParams.
    qc_profile:     QC threshold profile name.
    max_retries_per_phase:  Max additional attempts after first failure.
    output_dir:     Directory for audit/summary files.
    reporter:       ProgressReporter instance (terminal + JSON events).
    phase_delay_s:  Optional sleep between phases (makes demo more readable).
    auto_loop_enabled: If False, all phases run exactly once with no retry.
    enabled_phases:  Set of phase keys where auto-loop retry is active.
                     Defaults to all five phases.  Use to disable per-phase.
                     e.g. {"phase_A", "phase_C"} — only A and C will retry.
    """

    ALL_PHASES: frozenset[str] = frozenset(
        {"phase_A", "phase_B", "phase_C", "phase_D", "phase_E"}
    )

    def __init__(
        self,
        run_id: str,
        params: CryoEMParams | None = None,
        qc_profile: str = "cryoem_spa_purified",
        max_retries_per_phase: int = 2,
        output_dir: Path | None = None,
        reporter: ProgressReporter | None = None,
        phase_delay_s: float = 0.0,
        auto_loop_enabled: bool = True,
        enabled_phases: set[str] | None = None,
    ) -> None:
        self.run_id = run_id
        self.params = (params or CryoEMParams()).copy()
        self.max_retries_per_phase = max_retries_per_phase
        self.output_dir = Path(output_dir) if output_dir else Path(".")
        self.phase_delay_s = phase_delay_s
        self.auto_loop_enabled = auto_loop_enabled
        self.enabled_phases: frozenset[str] = (
            frozenset(enabled_phases) if enabled_phases is not None
            else self.ALL_PHASES
        )

        self._evaluator = CryoEMQCEvaluator(profile=qc_profile)
        self._tuner = KnowledgeEnrichedTuner()
        self._logger = AuditLogger(self.run_id, self.output_dir)
        self._reporter = reporter or ProgressReporter()

    # ── Public API ────────────────────────────────────────────────────────────

    def run(
        self,
        phase_runner_fn: Callable[[str, CryoEMParams], dict],
    ) -> LoopResult:
        """
        Execute the full 5-phase pipeline with live progress reporting.

        `phase_runner_fn(phase, params) → metrics dict`
        """
        result = LoopResult(
            run_id=self.run_id,
            audit_path=self._logger.audit_path,
            summary_path=self._logger.summary_path,
        )

        for phase in PHASES:
            phase_outcome, attempts_used = self._run_phase(phase, phase_runner_fn)
            result.total_attempts += attempts_used

            if phase_outcome == "pass":
                result.phases_passed.append(phase)
            elif phase_outcome == "escalated":
                result.phases_escalated.append(phase)
            else:
                result.phases_failed.append(phase)

            if self.phase_delay_s > 0:
                time.sleep(self.phase_delay_s)

        result.summary_path = self._logger.write_summary_report()
        result.audit_path   = self._logger.audit_path

        self._reporter.final_summary(
            phases_passed=result.phases_passed,
            phases_escalated=result.phases_escalated,
            phases_failed=result.phases_failed,
            total_attempts=result.total_attempts,
            audit_path=str(result.audit_path),
            summary_path=str(result.summary_path),
        )
        return result

    # ── Internal phase loop ───────────────────────────────────────────────────

    def _phase_retry_allowed(self, phase: str) -> bool:
        """Return True if auto-loop retry is enabled for this phase."""
        return self.auto_loop_enabled and phase in self.enabled_phases

    def _run_phase(
        self,
        phase: str,
        phase_runner_fn: Callable[[str, CryoEMParams], dict],
    ) -> tuple[str, int]:
        max_attempts = (self.max_retries_per_phase + 1) if self._phase_retry_allowed(phase) else 1
        attempt_number = 0

        for attempt in range(1, max_attempts + 1):
            attempt_number = attempt

            # Emit start event with relevant params for this phase
            params_summary = self._relevant_params(phase)
            self._reporter.phase_start(phase, attempt, params_summary)

            # Describe what is about to run
            self._reporter.phase_running(
                phase,
                self._running_description(phase, self.params),
            )

            # Execute the phase
            metrics = phase_runner_fn(phase, self.params)

            # Evaluate QC
            qc_result = self._evaluator.evaluate_phase(phase, metrics)

            # Render gate results
            self._reporter.gate_results(qc_result)

            # Determine remediations
            enriched_remeds: list[EnrichedRemediation] = []
            if not qc_result.passed:
                new_params, enriched_remeds = self._tuner.remediate(qc_result, self.params)
            else:
                new_params = self.params

            # Log to JSONL (base remediations for backward-compat)
            plain_remeds = [
                type("R", (), {
                    "phase": r.phase,
                    "gate": r.gate,
                    "param_changes": r.param_changes,
                    "rationale": r.rationale,
                })()
                for r in enriched_remeds
            ]
            self._logger.log_attempt(phase, attempt, self.params, qc_result, plain_remeds)

            if qc_result.passed:
                self._reporter.phase_passed(phase, attempt, qc_result.overall_level.value)
                self._logger.log_phase_final(phase, attempt, "pass")
                return "pass", attempt_number

            # Retry case
            if attempt < max_attempts:
                self._reporter.retry_triggered(
                    phase=phase,
                    attempt=attempt,
                    enriched_remediations=enriched_remeds,
                    next_attempt=attempt + 1,
                )
                self.params = new_params
            else:
                # Exhausted retries
                failed_gates = [g.gate for g in qc_result.halts]
                self._reporter.phase_escalated(phase, attempt_number, failed_gates)
                self._logger.log_phase_final(phase, attempt_number, "escalated")
                return "escalated", attempt_number

        self._logger.log_phase_final(phase, attempt_number, "fail")
        return "fail", attempt_number

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _relevant_params(self, phase: str) -> dict:
        """Return the subset of params owned by this phase (for display)."""
        owned = PHASE_PARAM_OWNERS.get(phase, [])
        all_params = asdict(self.params)
        return {k: v for k, v in all_params.items() if k in owned and v is not None}

    @staticmethod
    def _running_description(phase: str, params: CryoEMParams) -> str:
        desc = {
            "phase_A": (
                f"Running MotionCor2 on {params.micrograph_batch_size} micrographs/batch, "
                f"then estimating CTF with CTFFIND4 "
                f"(fit window {params.ctf_fitting_resolution_min:.0f}–{params.ctf_fitting_resolution_max:.0f} Å)..."
            ),
            "phase_B": (
                f"Running blob/template particle picker "
                + (f"(diameter ≈ {params.particle_diameter_angstroms:.0f} Å)" if params.particle_diameter_angstroms else "(auto diameter)")
                + "..."
            ),
            "phase_C": (
                f"Running 2D classification with {params.num_2d_classes} classes, "
                f"{params.class2d_iterations} iterations "
                f"(batch size {params.particle_batch_size:,})..."
            ),
            "phase_D": (
                f"Running ab-initio reconstruction with {params.num_ab_initio_classes} class(es), "
                f"max resolution {params.max_resolution_refinement:.1f} Å, symmetry {params.symmetry}..."
            ),
            "phase_E": (
                "Computing gold-standard FSC between half-maps "
                "(Scheres & Chen 2012; 0.143 criterion)..."
            ),
        }
        return desc.get(phase, f"Running {phase}...")
