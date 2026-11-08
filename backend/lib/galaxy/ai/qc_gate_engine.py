"""General, data-driven QC gate engine — the GENERAL counterpart to the hardcoded
per-process QC branches.

Today QC gates live in giant if/elif chains keyed on Nextflow process names
(~45 bespoke parsers + ~38 threshold branches in jobs/qc_trace_monitor.py), so a
BRAND-NEW domain gets no gate until someone writes Python in 2-3 places. This
engine is the general path: a workflow DECLARES its gates as data (name, metric,
op, threshold, severity, evidence) — e.g. inside its qc_metrics.json — and the
engine evaluates them generically, classifying each as pass / advisory (提醒) /
halt (中止) with provenance. Any domain gets gates from DATA; no per-workflow code.

This is additive and self-contained: it does not modify the existing hardcoded
path. Wiring it in as the fallback for unmatched processes (so unmatched domains
evaluate declared gates instead of returning "not_evaluated") is a follow-up that
touches qc_trace_monitor.py and needs a dev run to validate.

3.9-safe, pure stdlib.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

# action vocabulary (English canonical + the 中文 labels the UI shows)
PASS = "pass"
ADVISORY = "advisory"      # 提醒 — a warning, does not stop the run
HALT = "halt"              # 中止 — blocks / stops the run
ACTION_ZH = {PASS: "通过", ADVISORY: "提醒", HALT: "中止"}

_OPS = {
    "<":  lambda a, b: a < b,
    "<=": lambda a, b: a <= b,
    ">":  lambda a, b: a > b,
    ">=": lambda a, b: a >= b,
    "==": lambda a, b: a == b,
    "!=": lambda a, b: a != b,
}


class GateSpecError(ValueError):
    pass


@dataclass
class GateSpec:
    """A declared QC gate. ``op`` + ``threshold`` define the PASSING condition
    (e.g. metric='read_depth', op='>=', threshold=20 → pass when measured >= 20).
    ``severity`` is what a FAILED gate does: 'halt' (中止) or 'advisory' (提醒)."""
    name: str
    metric: str
    op: str
    threshold: float
    severity: str = HALT
    evidence: str = ""          # citation / provenance (industry standard, paper, institutional rule)
    provenance: str = ""        # e.g. "literature" | "standard" | "institutional" | "heuristic"

    def validate(self) -> None:
        if self.op not in _OPS:
            raise GateSpecError(f"gate '{self.name}': unknown op {self.op!r} (use {sorted(_OPS)})")
        if self.severity not in (HALT, ADVISORY):
            raise GateSpecError(f"gate '{self.name}': severity must be 'halt' or 'advisory', got {self.severity!r}")


@dataclass
class GateResult:
    name: str
    metric: str
    measured: Optional[float]
    op: str
    threshold: float
    passed: Optional[bool]       # None → metric absent (not evaluated)
    action: str                  # pass | advisory | halt | not_evaluated
    action_zh: str
    severity: str
    evidence: str = ""
    provenance: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name, "metric": self.metric, "measured": self.measured,
            "op": self.op, "threshold": self.threshold, "passed": self.passed,
            "action": self.action, "action_zh": self.action_zh, "severity": self.severity,
            "evidence": self.evidence, "provenance": self.provenance,
        }


@dataclass
class GateReport:
    results: List[GateResult] = field(default_factory=list)

    @property
    def blocked(self) -> bool:
        """True iff any halt-severity gate failed."""
        return any(r.action == HALT for r in self.results)

    @property
    def n_halt(self) -> int:
        return sum(1 for r in self.results if r.action == HALT)

    @property
    def n_advisory(self) -> int:
        return sum(1 for r in self.results if r.action == ADVISORY)

    @property
    def n_not_evaluated(self) -> int:
        return sum(1 for r in self.results if r.action == "not_evaluated")

    def to_dict(self) -> Dict[str, Any]:
        return {
            "blocked": self.blocked, "n_halt": self.n_halt, "n_advisory": self.n_advisory,
            "n_not_evaluated": self.n_not_evaluated,
            "results": [r.to_dict() for r in self.results],
        }


def parse_gate_specs(declared: Any) -> List[GateSpec]:
    """Build GateSpecs from a workflow's declared gates (list of dicts, or a dict
    of name→spec). Accepts the common aliases a qc_metrics.json self-description
    uses: metric/name, op/operator/comparator, threshold/limit/value,
    severity/action, evidence/citation, provenance/source."""
    rows: List[dict]
    if isinstance(declared, dict):
        rows = []
        for name, body in declared.items():
            b = dict(body or {})
            b.setdefault("name", name)
            rows.append(b)
    elif isinstance(declared, list):
        rows = [dict(r) for r in declared]
    else:
        raise GateSpecError("declared gates must be a list or a dict")

    specs: List[GateSpec] = []
    for r in rows:
        metric = r.get("metric") or r.get("name")
        if metric is None:
            raise GateSpecError(f"gate spec missing 'metric'/'name': {r}")
        op = r.get("op") or r.get("operator") or r.get("comparator") or ">="
        threshold = r.get("threshold", r.get("limit", r.get("value")))
        if threshold is None:
            raise GateSpecError(f"gate '{metric}' missing threshold/limit/value")
        severity = (r.get("severity") or r.get("action") or HALT).lower()
        if severity in ("block", "blocking", "中止", "stop"):
            severity = HALT
        elif severity in ("warn", "warning", "提醒"):
            severity = ADVISORY
        spec = GateSpec(
            name=str(r.get("name", metric)), metric=str(metric), op=str(op),
            threshold=float(threshold), severity=severity,
            evidence=str(r.get("evidence") or r.get("citation") or ""),
            provenance=str(r.get("provenance") or r.get("source") or ""),
        )
        spec.validate()
        specs.append(spec)
    return specs


def evaluate_gate(spec: GateSpec, metrics: Dict[str, Any]) -> GateResult:
    raw = metrics.get(spec.metric)
    if raw is None:
        return GateResult(spec.name, spec.metric, None, spec.op, spec.threshold, None,
                          "not_evaluated", "未评估", spec.severity, spec.evidence, spec.provenance)
    try:
        measured = float(raw)
    except (TypeError, ValueError):
        return GateResult(spec.name, spec.metric, None, spec.op, spec.threshold, None,
                          "not_evaluated", "未评估", spec.severity, spec.evidence, spec.provenance)
    passed = _OPS[spec.op](measured, spec.threshold)
    action = PASS if passed else spec.severity
    return GateResult(spec.name, spec.metric, measured, spec.op, spec.threshold, passed,
                      action, ACTION_ZH[action], spec.severity, spec.evidence, spec.provenance)


def evaluate_gates(declared: Any, metrics: Dict[str, Any]) -> GateReport:
    """Evaluate a workflow's DECLARED gates against measured metrics — generically,
    for ANY domain. ``declared`` is parsed via :func:`parse_gate_specs`."""
    if isinstance(declared, list) and declared and isinstance(declared[0], GateSpec):
        specs = declared                      # already-parsed specs
    else:
        specs = parse_gate_specs(declared)
    return GateReport(results=[evaluate_gate(s, metrics) for s in specs])
