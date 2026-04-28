"""
UX-aware auto-loop orchestrator for Docking.

Extends `DockingAutoLoop` to emit rich progress events at each step through
a `ProgressReporter`.  This is the class that would be used in production
instead of the bare `DockingAutoLoop`.

Key differences from the base class:
  - Accepts a `ProgressReporter` alongside the phase runner
  - Passes params summary to `phase_start` so the user sees current settings
  - Calls `retry_triggered` with `EnrichedRemediation` objects (with citations)
  - Calls `phase_escalated` / `phase_passed` / `final_summary`
  - Respects `auto_loop_enabled` and `enabled_phases` toggles
"""

from __future__ import annotations

import json
import time
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich import box

from .audit_logger import AuditLogger
from .enriched_tuner import KnowledgeEnrichedDockingTuner, EnrichedRemediation
from .orchestrator import PHASES, LoopResult
from .params import DockingParams, PHASE_PARAM_OWNERS
from .qc_evaluator import DockingQCEvaluator, PhaseQCResult, QCAction, QCLevel


# ── Phase / gate display metadata ─────────────────────────────────────────────

PHASE_LABELS = {
    "phase_1_docking": "Phase 1 — Virtual Screening / Molecular Docking",
}

GATE_LABELS = {
    "valid_poses":        "Valid poses generated",
    "best_binding_score": "Best binding score (kcal/mol)",
}

ACTION_STYLE = {
    QCAction.PASS:     ("✓", "green"),
    QCAction.ADVISORY: ("⚠", "yellow"),
    QCAction.HALT:     ("✗", "red"),
}

LEVEL_STYLE = {
    QCLevel.GOLD:   ("GOLD",   "bold yellow"),
    QCLevel.SILVER: ("SILVER", "bold white"),
    QCLevel.BRONZE: ("BRONZE", "dark_orange"),
    QCLevel.FAIL:   ("FAIL",   "bold red"),
}


def _ts() -> str:
    return datetime.now(tz=timezone.utc).isoformat(timespec="seconds")


# ── Progress reporter ─────────────────────────────────────────────────────────

class ProgressReporter:
    """
    Dual-output reporter: Rich terminal + structured JSON event stream.

    Parameters
    ----------
    console:    Rich Console instance. Pass Console(file=StringIO()) to capture.
    json_sink:  If provided, every JSON event is written as NDJSON.
    verbose:    If False, suppress citation printing.
    """

    def __init__(
        self,
        console: Console | None = None,
        json_sink: Any = None,
        verbose: bool = True,
    ) -> None:
        self._console = console or Console(highlight=False)
        self._sink = json_sink
        self._verbose = verbose

    def _emit(self, event: dict) -> None:
        if self._sink is not None:
            self._sink.write(json.dumps(event) + "\n")
            if hasattr(self._sink, "flush"):
                self._sink.flush()

    def phase_start(self, phase: str, attempt: int, params_summary: dict) -> None:
        self._console.rule(f"[cyan]{PHASE_LABELS.get(phase, phase)} — attempt {attempt}[/]")
        self._emit({
            "event": "autoloop_phase_start",
            "ts": _ts(), "phase": phase, "attempt": attempt,
            "params_summary": params_summary,
        })

    def phase_running(self, phase: str, description: str) -> None:
        self._console.print(f"  [dim]{description}[/]")
        self._emit({
            "event": "autoloop_running",
            "ts": _ts(), "phase": phase, "description": description,
        })

    def gate_results(self, qc_result: PhaseQCResult) -> None:
        table = Table(box=box.SIMPLE, show_header=True, header_style="bold")
        table.add_column("Gate", style="dim", width=36)
        table.add_column("Value", justify="right")
        table.add_column("Threshold", justify="right")
        table.add_column("Status", justify="center")

        for g in qc_result.gate_results:
            sym, color = ACTION_STYLE.get(g.action, ("?", "white"))
            label = GATE_LABELS.get(g.gate, g.gate)
            table.add_row(
                label,
                f"{g.value:.3g}",
                f"{g.threshold:.3g}",
                f"[{color}]{sym} {g.action.value.upper()}[/]",
            )
        self._console.print(table)

        lvl, style = LEVEL_STYLE.get(qc_result.overall_level, ("?", "white"))
        self._console.print(f"  Overall: [{style}]{lvl}[/]")

        self._emit({
            "event": "autoloop_gate_results",
            "ts": _ts(),
            "phase": qc_result.phase,
            "overall_level": qc_result.overall_level.value,
            "passed": qc_result.passed,
            "gates": [
                {
                    "gate": g.gate,
                    "action": g.action.value,
                    "level": g.level.value,
                    "value": g.value,
                    "threshold": g.threshold,
                    "message": g.message,
                }
                for g in qc_result.gate_results
            ],
        })

    def retry_triggered(
        self,
        phase: str,
        attempt: int,
        enriched_remediations: list[EnrichedRemediation],
        next_attempt: int,
    ) -> None:
        self._console.print(
            f"\n  [bold yellow]⟳  Auto-loop retry — attempt {next_attempt}[/]\n"
        )
        for r in enriched_remediations:
            gate_label = GATE_LABELS.get(r.gate, r.gate)
            changes_str = ", ".join(f"{k}: {v}" for k, v in r.param_changes.items())
            panel_body = f"[bold]{gate_label}[/]\n{r.rationale}"
            if changes_str:
                panel_body += f"\n\n[cyan]Parameter changes:[/] {changes_str}"
            if self._verbose and r.citations:
                panel_body += "\n\n[green]Evidence:[/]"
                for c in r.citations[:2]:
                    panel_body += (
                        f"\n  [{c.short_ref()}]"
                        f"\n  \"{c.source_text[:200]}{'...' if len(c.source_text) > 200 else ''}\""
                    )
            self._console.print(Panel(panel_body, border_style="yellow", padding=(0, 1)))

        self._emit({
            "event": "autoloop_update",
            "ts": _ts(),
            "phase": phase,
            "attempt": attempt,
            "next_attempt": next_attempt,
            "remediations": [r.to_dict() for r in enriched_remediations],
        })

    def phase_passed(self, phase: str, attempt: int, level: str) -> None:
        self._console.print(
            f"\n  [bold green]✓  {PHASE_LABELS.get(phase, phase)} PASSED[/]  (level: {level})\n"
        )
        self._emit({
            "event": "autoloop_phase_complete",
            "ts": _ts(), "phase": phase, "attempt": attempt,
            "outcome": "pass", "level": level,
        })

    def phase_escalated(self, phase: str, attempt: int, failed_gates: list[str]) -> None:
        gate_labels = [GATE_LABELS.get(g, g) for g in failed_gates]
        self._console.print(
            f"\n  [bold red]✗  {PHASE_LABELS.get(phase, phase)} ESCALATED[/]"
            f"  — gates: {', '.join(gate_labels)}\n"
        )
        self._emit({
            "event": "autoloop_escalation",
            "ts": _ts(), "phase": phase, "attempt": attempt,
            "failed_gates": failed_gates,
        })

    def final_summary(
        self,
        phases_passed: list[str],
        phases_escalated: list[str],
        phases_failed: list[str],
        total_attempts: int,
        audit_path: str,
        summary_path: str,
    ) -> None:
        self._console.rule("[bold]Docking Auto-Loop Complete[/]")
        self._console.print(f"  Passed   : {phases_passed or '—'}")
        self._console.print(f"  Escalated: {phases_escalated or '—'}")
        self._console.print(f"  Attempts : {total_attempts}")
        self._console.print(f"  Audit    : {audit_path}")
        self._emit({
            "event": "autoloop_complete",
            "ts": _ts(),
            "phases_passed": phases_passed,
            "phases_escalated": phases_escalated,
            "phases_failed": phases_failed,
            "total_attempts": total_attempts,
            "audit_path": audit_path,
            "summary_path": summary_path,
        })


# ── UX-aware loop ─────────────────────────────────────────────────────────────

class UXAwareDockingAutoLoop:
    """
    Knowledge-enriched, progress-reporting Docking auto-loop.

    Parameters
    ----------
    run_id:                 Unique run identifier.
    params:                 Initial DockingParams.
    qc_profile:             QC threshold profile name.
    max_retries_per_phase:  Max additional attempts after first failure.
    output_dir:             Directory for audit/summary files.
    reporter:               ProgressReporter instance.
    phase_delay_s:          Optional sleep between phases.
    auto_loop_enabled:      If False, all phases run exactly once with no retry.
    enabled_phases:         Set of phase keys where auto-loop retry is active.
    """

    ALL_PHASES: frozenset[str] = frozenset(PHASES)

    def __init__(
        self,
        run_id: str,
        params: DockingParams | None = None,
        qc_profile: str = "docking_hit_finding",
        max_retries_per_phase: int = 2,
        output_dir: Path | None = None,
        reporter: ProgressReporter | None = None,
        phase_delay_s: float = 0.0,
        auto_loop_enabled: bool = True,
        enabled_phases: set[str] | None = None,
    ) -> None:
        self.run_id = run_id
        self.params = (params or DockingParams()).copy()
        self.max_retries_per_phase = max_retries_per_phase
        self.output_dir = Path(output_dir) if output_dir else Path(".")
        self.phase_delay_s = phase_delay_s
        self.auto_loop_enabled = auto_loop_enabled
        self.enabled_phases: frozenset[str] = (
            frozenset(enabled_phases) if enabled_phases is not None
            else self.ALL_PHASES
        )

        self._evaluator = DockingQCEvaluator(profile=qc_profile)
        self._tuner = KnowledgeEnrichedDockingTuner()
        self._logger = AuditLogger(self.run_id, self.output_dir)
        self._reporter = reporter or ProgressReporter()

    def run(
        self,
        phase_runner_fn: Callable[[str, DockingParams], dict],
    ) -> LoopResult:
        """Execute the docking pipeline with live progress reporting."""
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
        result.audit_path = self._logger.audit_path

        self._reporter.final_summary(
            phases_passed=result.phases_passed,
            phases_escalated=result.phases_escalated,
            phases_failed=result.phases_failed,
            total_attempts=result.total_attempts,
            audit_path=str(result.audit_path),
            summary_path=str(result.summary_path),
        )
        return result

    def _phase_retry_allowed(self, phase: str) -> bool:
        return self.auto_loop_enabled and phase in self.enabled_phases

    def _run_phase(
        self,
        phase: str,
        phase_runner_fn: Callable[[str, DockingParams], dict],
    ) -> tuple[str, int]:
        max_attempts = (self.max_retries_per_phase + 1) if self._phase_retry_allowed(phase) else 1
        attempt_number = 0

        for attempt in range(1, max_attempts + 1):
            attempt_number = attempt

            params_summary = self._relevant_params(phase)
            self._reporter.phase_start(phase, attempt, params_summary)
            self._reporter.phase_running(
                phase, self._running_description(phase, self.params)
            )

            metrics = phase_runner_fn(phase, self.params)
            qc_result = self._evaluator.evaluate_phase(phase, metrics)
            self._reporter.gate_results(qc_result)

            enriched_remeds: list[EnrichedRemediation] = []
            if not qc_result.passed:
                new_params, enriched_remeds = self._tuner.remediate(qc_result, self.params)
            else:
                new_params = self.params

            plain_remeds = [
                type("R", (), {
                    "phase": r.phase, "gate": r.gate,
                    "param_changes": r.param_changes, "rationale": r.rationale,
                })()
                for r in enriched_remeds
            ]
            self._logger.log_attempt(phase, attempt, self.params, qc_result, plain_remeds)

            if qc_result.passed:
                self._reporter.phase_passed(phase, attempt, qc_result.overall_level.value)
                self._logger.log_phase_final(phase, attempt, "pass")
                return "pass", attempt_number

            if attempt < max_attempts:
                self._reporter.retry_triggered(
                    phase=phase,
                    attempt=attempt,
                    enriched_remediations=enriched_remeds,
                    next_attempt=attempt + 1,
                )
                self.params = new_params
            else:
                failed_gates = [g.gate for g in qc_result.halts]
                self._reporter.phase_escalated(phase, attempt_number, failed_gates)
                self._logger.log_phase_final(phase, attempt_number, "escalated")
                return "escalated", attempt_number

        self._logger.log_phase_final(phase, attempt_number, "fail")
        return "fail", attempt_number

    def _relevant_params(self, phase: str) -> dict:
        owned = PHASE_PARAM_OWNERS.get(phase, [])
        all_params = asdict(self.params)
        return {k: v for k, v in all_params.items() if k in owned and v is not None}

    @staticmethod
    def _running_description(phase: str, params: DockingParams) -> str:
        desc = {
            "phase_1_docking": (
                f"Running {params.docking_precision} docking on {params.n_ligands} ligands "
                f"(exhaustiveness={params.exhaustiveness}, "
                f"box_expand={params.center_box_expand_A:.1f} Å, "
                f"n_poses={params.n_poses}). "
                f"Hit threshold: {params.min_binding_affinity_kcal_mol:.1f} kcal/mol (Vina) "
                f"/ {params.min_glide_score:.1f} (Glide)..."
            ),
        }
        return desc.get(phase, f"Running {phase}...")
