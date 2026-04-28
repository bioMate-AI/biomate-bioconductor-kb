"""
CryoEM Auto-Loop UX Demo
========================

Runs the full 5-phase pipeline with a SimulatedPhaseRunner and renders
rich terminal output showing exactly what the frontend UX will display:
  - Phase banner + active parameters
  - Live "running" status with description of what CryoSPARC is doing
  - QC gate results table (PASS / ADVISORY / HALT)
  - When a retry fires: parameter changes + full literature citation
  - Escalation panel if max retries exhausted
  - Final summary table

All events are also written as JSON (NDJSON) to demonstrate the SSE
event stream the frontend will receive.

Usage:
    python demo.py                        # default: retry_then_pass scenario
    python demo.py --scenario all_pass
    python demo.py --scenario retry_then_pass
    python demo.py --scenario escalation
    python demo.py --scenario membrane_profile
    python demo.py --scenario multi_gate_failure
    python demo.py --scenario all_pass --no-citations   # compact output
    python demo.py --all-scenarios --output /tmp/demo_output/
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import time
from io import StringIO
from pathlib import Path

from rich.console import Console

# Make packages importable from any working directory
HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))

from cryo_em_autoloop.params import CryoEMParams
from cryo_em_autoloop.simulation import ScenarioConfig, ScenarioRunner
from cryo_em_autoloop.metrics_extractor import MetricsExtractor

from .progress_reporter import ProgressReporter
from .ux_loop import UXAwareAutoLoop


# ── Simulated phase runner (same adapter from integration tests) ──────────────

class SimulatedPhaseRunner:
    """Wraps ScenarioRunner + MetricsExtractor → scalar metrics dict."""

    def __init__(self, config: ScenarioConfig, rng_seed: int = 42):
        self._scenario = ScenarioRunner(config, rng_seed=rng_seed)
        self._extractor = MetricsExtractor(pixel_size=config.pixel_size)

    def __call__(self, phase: str, params: CryoEMParams) -> dict:
        jobs = self._scenario(phase, params)
        return self._extractor.extract(phase, jobs)


# ── Scenario definitions ──────────────────────────────────────────────────────

SCENARIOS: dict[str, tuple[str, ScenarioConfig]] = {

    "all_pass": (
        "All phases pass on the first attempt — ideal dataset",
        ScenarioConfig(
            drift_per_attempt=[18.0],
            ctf_fom_per_attempt=[0.90],
            astig_per_attempt=[300.0],
            junk_fraction=0.15,
            anisotropy=2.5,
            best_class_score=0.40,
            fsc_resolution_A=3.8,
            n_batches=3,
            n_micrographs_per_batch=100,
        ),
    ),

    "retry_then_pass": (
        "Phase A fails first attempt (high drift), passes after auto-tuning",
        ScenarioConfig(
            drift_per_attempt=[85.0, 22.0],    # attempt 0: bad; attempt 1: good
            ctf_fom_per_attempt=[0.85, 0.88],
            astig_per_attempt=[400.0, 380.0],
            junk_fraction=0.18,
            anisotropy=3.0,
            best_class_score=0.35,
            fsc_resolution_A=4.5,
            n_batches=3,
            n_micrographs_per_batch=100,
        ),
    ),

    "escalation": (
        "Phase A always fails — escalates after max retries, other phases proceed",
        ScenarioConfig(
            drift_per_attempt=[200.0],         # always terrible
            ctf_fom_per_attempt=[0.30],        # also terrible
            astig_per_attempt=[400.0],
            junk_fraction=0.18,
            anisotropy=3.0,
            best_class_score=0.35,
            fsc_resolution_A=4.5,
        ),
    ),

    "membrane_profile": (
        "Membrane protein dataset: drift 65 Å — fails purified, passes membrane profile",
        ScenarioConfig(
            drift_per_attempt=[65.0],
            ctf_fom_per_attempt=[0.75],
            astig_per_attempt=[800.0],
            junk_fraction=0.15,
            anisotropy=3.0,
            best_class_score=0.35,
            fsc_resolution_A=4.5,
        ),
    ),

    "multi_gate_failure": (
        "Phase B: high junk fraction + Phase C: preferred orientation — both auto-fixed",
        ScenarioConfig(
            drift_per_attempt=[20.0],
            ctf_fom_per_attempt=[0.88],
            astig_per_attempt=[350.0],
            junk_fraction=0.75,             # → triggers junk_fraction HALT
            anisotropy=12.0,                # → triggers orientation_anisotropy HALT
            best_class_score=0.35,
            fsc_resolution_A=4.5,
        ),
    ),
}


# ── Main demo runner ──────────────────────────────────────────────────────────

def run_scenario(
    scenario_name: str,
    qc_profile: str = "cryoem_spa_purified",
    max_retries: int = 2,
    verbose: bool = True,
    output_dir: Path | None = None,
    console: Console | None = None,
    # Auto-loop toggles
    auto_loop_enabled: bool = True,
    enabled_phases: set | None = None,
    reporter: "ProgressReporter | None" = None,
) -> dict:
    """
    Run one named scenario and return a results dict including all SSE events.

    Returns
    -------
    dict with keys:
        scenario, description, phases_passed, phases_escalated,
        total_attempts, events (list of JSON-serialisable dicts)
    """
    if scenario_name not in SCENARIOS:
        raise ValueError(
            f"Unknown scenario: {scenario_name!r}. Options: {list(SCENARIOS)}"
        )

    description, config = SCENARIOS[scenario_name]

    # Override membrane profile when requested
    if qc_profile == "membrane" or scenario_name == "membrane_profile":
        qc_profile = "cryoem_spa_membrane"

    # Build reporter (caller may supply one for SSE streaming)
    json_buf = StringIO()
    if reporter is None:
        reporter = ProgressReporter(
            console=console or Console(),
            json_sink=json_buf,
            verbose=verbose,
        )

    # Title banner
    reporter.console.print()
    reporter.console.rule(
        f"[bold magenta]CryoEM Auto-Loop Demo  —  Scenario: {scenario_name}[/bold magenta]",
        style="magenta",
    )
    reporter.console.print(
        f"  [dim]{description}[/dim]\n"
        f"  [dim]QC profile: {qc_profile}  ·  max retries/phase: {max_retries}[/dim]"
    )
    reporter.console.print()

    # Output directory
    out_dir = output_dir or Path(tempfile.mkdtemp(prefix=f"autoloop_{scenario_name}_"))

    # Phase runner
    runner = SimulatedPhaseRunner(config)

    # UX-aware loop
    params = CryoEMParams(
        pixel_size=config.pixel_size,
        micrograph_batch_size=200,
        num_ab_initio_classes=3,
        particle_diameter_angstroms=120.0,  # set so junk tuner has something to adjust
        blob_picker_min_diameter=80.0,
    )
    from cryo_em_autoloop.orchestrator import PHASES as _ALL_PHASES
    loop = UXAwareAutoLoop(
        run_id=f"demo_{scenario_name}",
        params=params,
        qc_profile=qc_profile,
        max_retries_per_phase=max_retries,
        output_dir=out_dir,
        reporter=reporter,
        phase_delay_s=0.0,
        auto_loop_enabled=auto_loop_enabled,
        enabled_phases=enabled_phases if enabled_phases is not None else set(_ALL_PHASES),
    )

    result = loop.run(runner)

    # Parse events from JSON buffer
    events = [
        json.loads(line)
        for line in json_buf.getvalue().strip().splitlines()
        if line.strip()
    ]

    return {
        "scenario": scenario_name,
        "description": description,
        "qc_profile": qc_profile,
        "phases_passed": result.phases_passed,
        "phases_escalated": result.phases_escalated,
        "phases_failed": result.phases_failed,
        "total_attempts": result.total_attempts,
        "audit_path": str(result.audit_path),
        "summary_path": str(result.summary_path),
        "events": events,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="CryoEM Auto-Loop UX Demo",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--scenario",
        choices=list(SCENARIOS),
        default="retry_then_pass",
        help="\n".join(f"  {k}: {v[0]}" for k, v in SCENARIOS.items()),
    )
    parser.add_argument(
        "--all-scenarios",
        action="store_true",
        help="Run all scenarios sequentially",
    )
    parser.add_argument(
        "--qc-profile",
        choices=["cryoem_spa_purified", "cryoem_spa_membrane", "cryoem_spa_phase_plate"],
        default="cryoem_spa_purified",
    )
    parser.add_argument("--max-retries", type=int, default=2)
    parser.add_argument("--no-citations", action="store_true",
                        help="Suppress citation blocks (compact output)")
    parser.add_argument("--output", type=Path, default=None,
                        help="Directory for audit/summary files and events JSON")
    args = parser.parse_args()

    scenarios_to_run = list(SCENARIOS) if args.all_scenarios else [args.scenario]
    console = Console()

    for scenario_name in scenarios_to_run:
        out_dir = (args.output / scenario_name) if args.output else None
        results = run_scenario(
            scenario_name=scenario_name,
            qc_profile=args.qc_profile,
            max_retries=args.max_retries,
            verbose=not args.no_citations,
            output_dir=out_dir,
            console=console,
        )

        if args.output:
            out_dir = args.output / scenario_name
            out_dir.mkdir(parents=True, exist_ok=True)
            events_path = out_dir / "sse_events.jsonl"
            events_path.write_text(
                "\n".join(json.dumps(e) for e in results["events"]) + "\n"
            )
            console.print(
                f"\n  [dim]SSE events written to: {events_path}[/dim]"
            )

        if args.all_scenarios and scenario_name != scenarios_to_run[-1]:
            console.print("\n" + "═" * 70 + "\n")
            time.sleep(0.5)


if __name__ == "__main__":
    main()
