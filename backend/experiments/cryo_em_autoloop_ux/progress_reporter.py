"""
Progress reporter for the CryoEM auto-loop.

Emits two outputs simultaneously:
  1. Rich terminal output (ANSI colors, unicode, tables) — for the CLI demo
  2. JSON events — identical to what the real frontend SSE stream will receive

The JSON event schema matches the `autoloop_update` / `autoloop_escalation`
SSE events designed in docs/20260416_CRYOEM_AUTOLOOP_ARCHITECTURE.md.

Frontend consumers listen for these event types on the SSE stream and update
`AutoLoopStatusPanel` accordingly.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from io import StringIO
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TimeElapsedColumn
from rich.rule import Rule
from rich.table import Table
from rich.text import Text
from rich import box

sys.path.insert(0, str(Path(__file__).parent.parent))

from cryo_em_autoloop.qc_evaluator import PhaseQCResult, QCAction, QCLevel
from .enriched_tuner import EnrichedRemediation


# ── Phase metadata ────────────────────────────────────────────────────────────

PHASE_LABELS = {
    "phase_A": "Phase A — Motion Correction + CTF Estimation",
    "phase_B": "Phase B — Particle Picking + Extraction",
    "phase_C": "Phase C — 2D Classification",
    "phase_D": "Phase D — Ab-Initio 3D Reconstruction",
    "phase_E": "Phase E — FSC Validation & Final Map",
}

GATE_LABELS = {
    "motion_drift":          "Total motion drift (Å)",
    "per_frame_drift":       "Per-frame drift (Å/frame)",
    "ctf_fit_quality":       "CTF fit quality (FOM)",
    "astigmatism":           "Astigmatism (Å)",
    "junk_fraction":         "Junk class fraction",
    "particle_yield":        "Particles selected",
    "orientation_anisotropy":"Orientation anisotropy",
    "class_quality":         "Mean 2D class quality",
    "abinitio_class_score":  "Ab-initio class score",
    "abinitio_resolution":   "Ab-initio resolution (Å)",
    "fsc_resolution":        "FSC 0.143 resolution (Å)",
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


# ── Main reporter class ───────────────────────────────────────────────────────

class ProgressReporter:
    """
    Dual-output reporter: rich terminal + structured JSON event stream.

    Parameters
    ----------
    console:
        Rich Console instance. Pass Console(file=StringIO()) to capture.
    json_sink:
        If provided, every JSON event is written as a newline-delimited line.
        Typical usage: open("events.jsonl", "w")
    verbose:
        If False, suppress citation printing (useful for compact output).
    """

    def __init__(
        self,
        console: Console | None = None,
        json_sink: Any = None,
        verbose: bool = True,
    ) -> None:
        self.console = console or Console()
        self._json_sink = json_sink
        self.verbose = verbose
        self._events: list[dict] = []   # in-memory log of all events

    @property
    def events(self) -> list[dict]:
        """All JSON events emitted so far (for tests and post-run inspection)."""
        return list(self._events)

    # ── Phase lifecycle ───────────────────────────────────────────────────────

    def phase_start(self, phase: str, attempt: int, params_summary: dict) -> None:
        label = PHASE_LABELS.get(phase, phase)
        self.console.print()
        self.console.rule(
            f"[bold cyan]{label}[/bold cyan]  "
            f"[dim]Attempt {attempt}[/dim]",
            style="cyan",
        )

        # Show relevant params for this phase
        if params_summary:
            t = Table(box=box.SIMPLE, show_header=False, padding=(0, 1))
            t.add_column("param", style="dim")
            t.add_column("value")
            for k, v in params_summary.items():
                t.add_row(k, str(v))
            self.console.print(t)

        self._emit({
            "type": "autoloop_phase_start",
            "ts": _ts(),
            "phase": phase,
            "attempt": attempt,
            "params_summary": params_summary,
        })

    def phase_running(self, phase: str, description: str) -> None:
        """Called while the phase is executing (progress spinner tick)."""
        self.console.print(f"  [cyan]⟳[/cyan]  {description}")
        self._emit({
            "type": "autoloop_running",
            "ts": _ts(),
            "phase": phase,
            "description": description,
        })

    def gate_results(self, qc_result: PhaseQCResult) -> None:
        """Render QC gate evaluation results."""
        self.console.print()
        self.console.print("  [bold]QC Gate Results:[/bold]")
        t = Table(
            box=box.ROUNDED,
            show_header=True,
            header_style="bold dim",
            padding=(0, 1),
        )
        t.add_column("Gate",      min_width=30)
        t.add_column("Result",    min_width=6,  justify="center")
        t.add_column("Measured",  min_width=12, justify="right")
        t.add_column("Threshold", min_width=12, justify="right")
        t.add_column("Level",     min_width=8,  justify="center")

        for g in qc_result.gate_results:
            sym, color  = ACTION_STYLE.get(g.action, ("?", "white"))
            lvl_str, lvl_color = LEVEL_STYLE.get(g.level, ("?", "white"))
            label = GATE_LABELS.get(g.gate, g.gate)
            t.add_row(
                label,
                f"[{color}]{sym}[/{color}]",
                f"{g.value:.4g}",
                f"{g.threshold:.4g}",
                f"[{lvl_color}]{lvl_str}[/{lvl_color}]",
            )
        self.console.print(t)

        self._emit({
            "type": "autoloop_gate_results",
            "ts": _ts(),
            "phase": qc_result.phase,
            "passed": qc_result.passed,
            "overall_level": qc_result.overall_level.value,
            "gates": [
                {
                    "gate": g.gate,
                    "action": g.action.value,
                    "level": g.level.value,
                    "value": g.value,
                    "threshold": g.threshold,
                    "message": g.message,
                    "suggestion": g.suggestion,
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
        """Called when at least one HALT gate fired and a retry is scheduled."""
        self.console.print()
        self.console.print(
            Panel(
                self._format_retry_panel(enriched_remediations),
                title=f"[bold yellow]⚡  Auto-Loop Retry Triggered — Attempt {attempt} → {next_attempt}[/bold yellow]",
                border_style="yellow",
                padding=(1, 2),
            )
        )

        self._emit({
            "type": "autoloop_update",
            "ts": _ts(),
            "phase": phase,
            "attempt": attempt,
            "outcome": "halt",
            "next_attempt": next_attempt,
            "remediations": [r.to_dict() for r in enriched_remediations],
        })

    def phase_passed(self, phase: str, attempt: int, overall_level: str) -> None:
        label = PHASE_LABELS.get(phase, phase)
        retry_note = f" (after {attempt} attempt{'s' if attempt > 1 else ''})" if attempt > 1 else ""
        self.console.print()
        self.console.print(
            f"  [bold green]✓  {label} PASSED{retry_note}[/bold green]  "
            f"[dim]QC level: {overall_level}[/dim]"
        )

        self._emit({
            "type": "autoloop_phase_complete",
            "ts": _ts(),
            "phase": phase,
            "outcome": "pass",
            "attempts_used": attempt,
            "overall_level": overall_level,
        })

    def phase_escalated(
        self,
        phase: str,
        total_attempts: int,
        failed_gates: list[str],
    ) -> None:
        label = PHASE_LABELS.get(phase, phase)
        self.console.print()
        self.console.print(
            Panel(
                f"[bold red]{label}[/bold red] could not be resolved after "
                f"[bold]{total_attempts}[/bold] attempt(s).\n\n"
                f"Gates still failing: [red]{', '.join(failed_gates)}[/red]\n\n"
                f"[dim]The pipeline will continue from the next phase,\n"
                f"but upstream quality issues may limit final map resolution.\n"
                f"[bold]Human review is required.[/bold][/dim]",
                title="[bold red]⛔  Escalation — Manual Review Required[/bold red]",
                border_style="red",
                padding=(1, 2),
            )
        )

        self._emit({
            "type": "autoloop_escalation",
            "ts": _ts(),
            "phase": phase,
            "total_attempts": total_attempts,
            "gates_failed": failed_gates,
            "message": (
                f"{label} could not be resolved after {total_attempts} attempts. "
                f"Gates still failing: {', '.join(failed_gates)}. Human review required."
            ),
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
        """Render the post-run summary table."""
        self.console.print()
        self.console.rule("[bold]Auto-Loop Run Complete[/bold]", style="green")
        self.console.print()

        t = Table(
            box=box.HEAVY_HEAD,
            title="[bold]Phase Outcomes[/bold]",
            show_header=True,
            header_style="bold",
            padding=(0, 2),
        )
        t.add_column("Phase", min_width=42)
        t.add_column("Outcome", min_width=12, justify="center")

        all_phases = ["phase_A", "phase_B", "phase_C", "phase_D", "phase_E"]
        for p in all_phases:
            label = PHASE_LABELS.get(p, p)
            if p in phases_passed:
                t.add_row(label, "[bold green]PASSED[/bold green]")
            elif p in phases_escalated:
                t.add_row(label, "[bold red]ESCALATED[/bold red]")
            elif p in phases_failed:
                t.add_row(label, "[bold orange1]FAILED[/bold orange1]")
            else:
                t.add_row(label, "[dim]–[/dim]")

        self.console.print(t)
        self.console.print()
        self.console.print(f"  [dim]Total job executions:[/dim]  {total_attempts}")
        self.console.print(f"  [dim]Audit log:          [/dim]  {audit_path}")
        self.console.print(f"  [dim]Summary report:     [/dim]  {summary_path}")

        self._emit({
            "type": "autoloop_complete",
            "ts": _ts(),
            "phases_passed": phases_passed,
            "phases_escalated": phases_escalated,
            "phases_failed": phases_failed,
            "total_attempts": total_attempts,
            "audit_path": audit_path,
            "summary_path": summary_path,
        })

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _format_retry_panel(self, remeds: list[EnrichedRemediation]) -> str:
        """
        Build the content for the retry panel using rich markup.
        For each remediation: show what changed, why, and the citations.
        """
        parts: list[str] = []

        for r in remeds:
            parts.append(f"[bold]Gate:[/bold] [red]{GATE_LABELS.get(r.gate, r.gate)}[/red]")
            parts.append("")

            if r.param_changes:
                parts.append("[bold]Parameter changes:[/bold]")
                for param, new_val in r.param_changes.items():
                    parts.append(f"  [cyan]{param}[/cyan]  →  [bold]{new_val}[/bold]")
            else:
                parts.append("[bold]Parameter changes:[/bold]  [dim]none (advisory)[/dim]")

            parts.append("")
            parts.append(f"[bold]Why:[/bold]  {r.rationale}")

            if r.citations and self.verbose:
                parts.append("")
                parts.append("[bold]📚 Knowledge basis (from BioMate skill docs):[/bold]")
                for c in r.citations:
                    parts.append("")
                    parts.append(
                        f"  [bold dim]{c.paper_ref}[/bold dim]  "
                        f"[dim]doi:{c.paper_doi}[/dim]"
                    )
                    parts.append(f"  [dim]Source: {c.source_file}[/dim]")
                    parts.append(f"  [green]{c.finding}[/green]")
                    parts.append(f"  [italic dim]\"{c.source_text}\"[/italic dim]")

            if len(remeds) > 1:
                parts.append("")
                parts.append("─" * 50)
                parts.append("")

        return "\n".join(parts)

    def _emit(self, event: dict) -> None:
        """Store event in memory and optionally write to json_sink."""
        self._events.append(event)
        if self._json_sink is not None:
            self._json_sink.write(json.dumps(event) + "\n")
            if hasattr(self._json_sink, "flush"):
                self._json_sink.flush()
