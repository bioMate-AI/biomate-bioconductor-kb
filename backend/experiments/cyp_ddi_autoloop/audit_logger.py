"""CYP DDI auto-loop audit logger — identical logic to admet_autoloop.audit_logger."""

from __future__ import annotations
import json, textwrap
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING
from .qc_evaluator import PhaseQCResult

if TYPE_CHECKING:
    from .param_tuner import Remediation
    from .params import CYPDDIParams


def _now_iso() -> str:
    return datetime.now(tz=timezone.utc).isoformat(timespec="seconds")


class AuditLogger:
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

    def log_attempt(self, phase, attempt, params_snapshot, qc_result, remediations) -> None:
        record = {
            "ts": _now_iso(), "run_id": self.run_id, "event": "attempt",
            "phase": phase, "attempt": attempt,
            "params": asdict(params_snapshot),
            "gate_results": [{"gate": g.gate, "action": g.action.value, "value": g.value, "threshold": g.threshold} for g in qc_result.gate_results],
            "remediations": [{"gate": r.gate, "param_changes": r.param_changes, "rationale": r.rationale} for r in remediations],
            "outcome": "pass" if qc_result.passed else "halt",
        }
        self._write_line(record)
        self._attempts.append(record)

    def log_phase_final(self, phase, total_attempts, outcome) -> None:
        if outcome not in ("pass", "fail", "escalated"):
            raise ValueError(f"outcome must be pass/fail/escalated; got {outcome!r}")
        record = {"ts": _now_iso(), "run_id": self.run_id, "event": "phase_final",
                  "phase": phase, "total_attempts": total_attempts, "outcome": outcome}
        self._write_line(record)
        self._phase_finals.append(record)

    def write_summary_report(self) -> Path:
        lines = [f"CYP-DDI Auto-Loop Run: {self.run_id}", f"Generated: {_now_iso()} UTC", ""]
        attempts_by_phase: dict = {}
        for rec in self._attempts:
            attempts_by_phase.setdefault(rec["phase"], []).append(rec)
        finals_by_phase = {rec["phase"]: rec for rec in self._phase_finals}
        all_phases = list(dict.fromkeys([r["phase"] for r in self._attempts + self._phase_finals]))
        for phase in all_phases:
            final = finals_by_phase.get(phase)
            outcome = final["outcome"].upper() if final else "UNKNOWN"
            lines.append(f"Phase {phase}  [{outcome}]  ({len(attempts_by_phase.get(phase, []))} attempt(s))")
            for rec in attempts_by_phase.get(phase, []):
                lines.append(f"  Attempt #{rec['attempt']}  outcome={rec['outcome']}")
                for g in rec["gate_results"]:
                    mark = "OK " if g["action"] == "pass" else ("ADV" if g["action"] == "advisory" else "!!!")
                    lines.append(f"    [{mark}] {g['gate']:<32} value={g['value']:.4g}  threshold={g['threshold']:.4g}")
                for r in rec["remediations"]:
                    lines.append(f"    Remediation gate={r['gate']}: {list(r['param_changes'].items())}")
            lines.append("")
        pass_c = sum(1 for r in self._phase_finals if r["outcome"] == "pass")
        esc_c  = sum(1 for r in self._phase_finals if r["outcome"] == "escalated")
        lines += [f"Phases passed: {pass_c}", f"Phases escalated: {esc_c}"]
        text = "\n".join(lines) + "\n"
        self._summary_path.write_text(text, encoding="utf-8")
        return self._summary_path

    def _write_line(self, record: dict) -> None:
        with self._audit_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record, default=str) + "\n")
