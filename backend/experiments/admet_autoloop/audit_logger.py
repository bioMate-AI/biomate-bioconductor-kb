"""
ADMET auto-loop audit logger — JSONL trail for all phase attempts.

One JSON line is appended to `{output_dir}/{run_id}_audit.jsonl` for every
attempt and every phase-final event.  A human-readable summary report is
written to `{output_dir}/{run_id}_summary.txt`.

Architecture is identical to cryo_em_autoloop.audit_logger — only the
module-level import differs (ADMET vs CryoEM qc_evaluator).

No external dependencies — stdlib only.
"""

from __future__ import annotations

import json
import textwrap
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING

from .qc_evaluator import PhaseQCResult

if TYPE_CHECKING:
    from .param_tuner import Remediation
    from .params import ADMETParams


def _now_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat(timespec="seconds")


class AuditLogger:
    """
    Append-only JSONL audit trail for a single ADMET auto-loop run.
    """

    def __init__(self, run_id: str, output_dir: Path) -> None:
        self.run_id = run_id
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self._audit_path   = self.output_dir / f"{run_id}_audit.jsonl"
        self._summary_path = self.output_dir / f"{run_id}_summary.txt"

        self._attempts: list[dict] = []
        self._phase_finals: list[dict] = []

    @property
    def audit_path(self) -> Path:
        return self._audit_path

    @property
    def summary_path(self) -> Path:
        return self._summary_path

    def log_attempt(
        self,
        phase: str,
        attempt: int,
        params_snapshot: "ADMETParams",
        qc_result: PhaseQCResult,
        remediations: "list[Remediation]",
    ) -> None:
        gate_results = [
            {
                "gate":      g.gate,
                "action":    g.action.value,
                "value":     g.value,
                "threshold": g.threshold,
            }
            for g in qc_result.gate_results
        ]
        rem_list = [
            {
                "gate":          r.gate,
                "param_changes": r.param_changes,
                "rationale":     r.rationale,
            }
            for r in remediations
        ]
        record = {
            "ts":           _now_iso(),
            "run_id":       self.run_id,
            "event":        "attempt",
            "phase":        phase,
            "attempt":      attempt,
            "params":       asdict(params_snapshot),
            "gate_results": gate_results,
            "remediations": rem_list,
            "outcome":      "pass" if qc_result.passed else "halt",
        }
        self._write_line(record)
        self._attempts.append(record)

    def log_phase_final(
        self,
        phase: str,
        total_attempts: int,
        outcome: str,
    ) -> None:
        if outcome not in ("pass", "fail", "escalated"):
            raise ValueError(f"outcome must be pass/fail/escalated; got {outcome!r}")
        record = {
            "ts":             _now_iso(),
            "run_id":         self.run_id,
            "event":          "phase_final",
            "phase":          phase,
            "total_attempts": total_attempts,
            "outcome":        outcome,
        }
        self._write_line(record)
        self._phase_finals.append(record)

    def write_summary_report(self) -> Path:
        lines: list[str] = []
        lines.append("=" * 70)
        lines.append(f"ADMET Auto-Loop Run: {self.run_id}")
        lines.append(f"Generated: {_now_iso()} UTC")
        lines.append("=" * 70)
        lines.append("")

        attempts_by_phase: dict[str, list[dict]] = {}
        for rec in self._attempts:
            attempts_by_phase.setdefault(rec["phase"], []).append(rec)

        finals_by_phase: dict[str, dict] = {
            rec["phase"]: rec for rec in self._phase_finals
        }

        all_phases = list(dict.fromkeys(
            [r["phase"] for r in self._attempts] +
            [r["phase"] for r in self._phase_finals]
        ))

        for phase in all_phases:
            phase_attempts = attempts_by_phase.get(phase, [])
            final = finals_by_phase.get(phase)
            final_outcome = final["outcome"].upper() if final else "UNKNOWN"
            outcome_mark = {
                "PASS": "[PASS]", "FAIL": "[FAIL]", "ESCALATED": "[ESCALATED]"
            }.get(final_outcome, f"[{final_outcome}]")
            lines.append(f"Phase {phase}  {outcome_mark}  ({len(phase_attempts)} attempt(s))")
            lines.append("-" * 50)

            for rec in phase_attempts:
                lines.append(f"  Attempt #{rec['attempt']}  outcome={rec['outcome']}")
                lines.append("    Gate results:")
                for g in rec["gate_results"]:
                    mark = "OK " if g["action"] == "pass" else (
                        "ADV" if g["action"] == "advisory" else "!!!"
                    )
                    lines.append(
                        f"      [{mark}] {g['gate']:<32}  "
                        f"value={g['value']:.4g}  threshold={g['threshold']:.4g}"
                    )
                if rec["remediations"]:
                    lines.append("    Remediations:")
                    for r in rec["remediations"]:
                        lines.append(f"      gate={r['gate']}")
                        if r["param_changes"]:
                            for k, v in r["param_changes"].items():
                                lines.append(f"        {k} → {v}")
                        else:
                            lines.append("        (advisory only — no param changes)")
                        wrapped = textwrap.fill(
                            r["rationale"], width=66,
                            initial_indent="        Rationale: ",
                            subsequent_indent="                   ",
                        )
                        lines.append(wrapped)
                lines.append("")

            if final:
                lines.append(
                    f"  Phase final: {final['outcome']} after {final['total_attempts']} attempt(s)"
                )
            lines.append("")

        pass_count = sum(1 for r in self._phase_finals if r["outcome"] == "pass")
        fail_count = sum(1 for r in self._phase_finals if r["outcome"] == "fail")
        esc_count  = sum(1 for r in self._phase_finals if r["outcome"] == "escalated")
        total_att  = sum(r["attempt"] for r in self._attempts)

        lines.append("=" * 70)
        lines.append("Summary")
        lines.append("-" * 50)
        lines.append(f"  Phases passed:     {pass_count}")
        lines.append(f"  Phases failed:     {fail_count}")
        lines.append(f"  Phases escalated:  {esc_count}")
        lines.append(f"  Total attempts:    {total_att}")
        lines.append("=" * 70)

        report_text = "\n".join(lines) + "\n"
        self._summary_path.write_text(report_text, encoding="utf-8")
        return self._summary_path

    def _write_line(self, record: dict) -> None:
        with self._audit_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, default=str) + "\n")
