"""Structured rule gates — the inference-time "gate before score" counterpart of the
composite GRPO reward (`trl_trainer._composite_component`).

The composite reward scores a model's *completion string*. A gate must instead enforce
the *same declarative rule* against the **structured run state** — a params dict, a QC
metrics dict, and an ordered step list — so one authored rule drives both:

    reward (training, text)  ──┐
                               ├── one declarative component vocabulary
    gate   (inference, struct)─┘

This realizes the dual-use rule unit of the SRVL design
(`docs/20261027_BIOMATE_NATIVE_RSI_THESIS.md`, Pillar C) and the structured-field
versions of gate families G1 (threshold), G6 (relational / cross-field) and G7
(ordering) called out as the completion-text analogs' structured counterparts in
`docs/20261027_EXPERT_FEEDBACK_RULES_GUARDRAILS_RSI.md` §1.1.

"Gate before score": a run is blocked when any component with severity "block" fails;
"advisory" failures are reported but do not block. Every violation names the offending
field / step / term, so the SRVL repair router (Pillar A) knows *what* to fix.

Pure stdlib, Python 3.9-safe (no PEP 604 unions) — safe to import anywhere.

Component vocabulary (shared with reward's COMPOSITE_COMPONENT_KINDS; keys that make a
component *structured* are noted):

  numeric_threshold  {field, op, value}         G1 — params[field]/metrics[field] `op` value
  implies            {if_fields, then_fields}   G6 — any if_field set ⇒ all then_fields set
                     {if_terms, then_terms, on} G6 — text form on context[on] (default "text")
  order              {before, after}            G7 — index(before) < index(after) over steps
  contains_all/any   {terms, field}             G2/G3 — on params[field] (or any string field)
  banned             {terms, field}             G3 — none of terms may appear
  regex              {pattern, field}            G4 — pattern must match
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field as _dc_field
from typing import Any, Dict, List, Optional

_NUM = re.compile(r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")
_OPS = {
    "<": lambda x, y: x < y, "<=": lambda x, y: x <= y,
    ">": lambda x, y: x > y, ">=": lambda x, y: x >= y,
    "==": lambda x, y: x == y, "!=": lambda x, y: x != y,
}


@dataclass
class GateViolation:
    kind: str                       # the component kind that failed
    message: str                    # human-readable "what went wrong"
    locus: str = ""                 # the field / step / term to fix (repair hint)
    severity: str = "block"         # "block" | "advisory"


@dataclass
class GateReport:
    passed: bool
    violations: List[GateViolation] = _dc_field(default_factory=list)
    evaluated: int = 0              # how many components could be judged (not skipped)

    def blocking(self) -> List[GateViolation]:
        return [v for v in self.violations if v.severity == "block"]


def _lookup(context: Dict[str, Any], key: str) -> Any:
    """Find `key` in params, then metrics, then the flat context. None if absent."""
    if not key:
        return None
    for bucket in ("params", "metrics"):
        b = context.get(bucket)
        if isinstance(b, dict) and key in b:
            return b[key]
    return context.get(key)


def _as_float(v: Any) -> Optional[float]:
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    m = _NUM.search(str(v)) if v is not None else None
    return float(m.group()) if m else None


def _truthy(v: Any) -> bool:
    """Is a field 'set'? Present and not None/empty-string/empty-list/False."""
    if v is None or v is False:
        return False
    if isinstance(v, str):
        return v.strip() != ""
    if isinstance(v, (list, tuple, dict, set)):
        return len(v) > 0
    return True


def _text_of(context: Dict[str, Any], key: str) -> str:
    if key and key != "text":
        return str(_lookup(context, key) or "")
    return str(context.get("text") or "")


def _eval_component(comp: dict, context: Dict[str, Any]) -> Optional[GateViolation]:
    """Return a GateViolation if the component is judged and fails; None if it passes or
    cannot be judged (missing data → skip, not fail — the gate never fabricates a block)."""
    kind = comp.get("kind")
    sev = "advisory" if comp.get("severity") == "advisory" else "block"

    if kind == "numeric_threshold":
        fld = comp.get("field") or comp.get("near")
        val = _as_float(_lookup(context, fld)) if comp.get("field") else _as_float(_text_of(context, comp.get("near", "")))
        thr = _as_float(comp.get("value"))
        op = _OPS.get(str(comp.get("op")))
        if val is None or thr is None or op is None:
            return None  # unjudgeable
        if not op(val, thr):
            return GateViolation(kind, f"{fld} = {val} violates {fld} {comp.get('op')} {thr}", str(fld or ""), sev)
        return None

    if kind == "implies":
        if comp.get("if_fields"):  # structured cross-field form
            if_fields = list(comp.get("if_fields") or [])
            then_fields = list(comp.get("then_fields") or [])
            if not any(_truthy(_lookup(context, f)) for f in if_fields):
                return None  # untriggered
            missing = [f for f in then_fields if not _truthy(_lookup(context, f))]
            if missing:
                return GateViolation(kind, f"{if_fields} set but {missing} missing", ",".join(missing), sev)
            return None
        # text form
        on = comp.get("on", "text")
        lc = _text_of(context, on).lower()
        if_terms = [str(t).lower() for t in comp.get("if_terms", [])]
        then_terms = [str(t).lower() for t in comp.get("then_terms", [])]
        if not any(t in lc for t in if_terms):
            return None
        missing = [t for t in then_terms if t not in lc]
        if missing:
            return GateViolation(kind, f"{if_terms} present but {missing} absent", ",".join(missing), sev)
        return None

    if kind == "order":
        before = str(comp.get("before", ""))
        after = str(comp.get("after", ""))
        steps = context.get("steps")
        if isinstance(steps, list) and steps:
            names = [str(s).lower() for s in steps]
            try:
                i_b = names.index(before.lower())
                i_a = names.index(after.lower())
            except ValueError:
                return None  # a step absent → unjudgeable
            if i_b >= i_a:
                return GateViolation(kind, f"'{before}' must precede '{after}' in the plan", f"{before}->{after}", sev)
            return None
        # text fallback
        lc = _text_of(context, comp.get("on", "text")).lower()
        i_b, i_a = lc.find(before.lower()), lc.find(after.lower())
        if i_b < 0 or i_a < 0:
            return None
        if i_b >= i_a:
            return GateViolation(kind, f"'{before}' must precede '{after}'", f"{before}->{after}", sev)
        return None

    if kind in ("contains_all", "contains_any", "banned", "regex"):
        s = _text_of(context, comp.get("field", "text")).lower()
        if kind == "regex":
            try:
                if re.search(str(comp.get("pattern", "")), s, re.IGNORECASE):
                    return None
            except re.error:
                return None
            return GateViolation(kind, f"pattern /{comp.get('pattern')}/ not found", comp.get("field", "text"), sev)
        terms = [str(t).lower() for t in comp.get("terms", [])]
        if kind == "contains_any":
            return None if any(t in s for t in terms) else GateViolation(kind, f"none of {terms} present", comp.get("field", "text"), sev)
        if kind == "contains_all":
            missing = [t for t in terms if t not in s]
            return GateViolation(kind, f"{missing} missing", ",".join(missing), sev) if missing else None
        if kind == "banned":
            hit = [t for t in terms if t in s]
            return GateViolation(kind, f"banned {hit} present", ",".join(hit), sev) if hit else None
    return None  # unknown kind → skip (reward interpreter owns kind validation)


def evaluate_rule_gates(rule_spec: List[dict], context: Dict[str, Any]) -> GateReport:
    """Evaluate a declarative rule spec against structured run state.

    context keys (all optional): ``params`` (dict), ``metrics`` (dict), ``steps``
    (ordered list of step names), ``text`` (any free text, e.g. a report). A component
    whose data is absent is *skipped*, never counted as a failure. "Gate before score":
    the report blocks iff any component with severity "block" fails.
    """
    violations: List[GateViolation] = []
    evaluated = 0
    for comp in (rule_spec or []):
        if not isinstance(comp, dict):
            continue
        evaluated += 1  # a well-formed component we processed
        v = _eval_component(comp, context)
        if v is not None:
            violations.append(v)
    passed = not any(v.severity == "block" for v in violations)
    return GateReport(passed=passed, violations=violations, evaluated=evaluated)
