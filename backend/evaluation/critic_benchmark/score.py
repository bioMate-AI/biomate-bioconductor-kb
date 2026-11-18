"""
score.py — deterministic scorer for the critic_benchmark task.

No LLM judge anywhere (RealBio / RealPharma discipline). Given the ground-truth
``data.jsonl`` and a predictions jsonl (from :mod:`harness`, or a real LLM run in the
same schema), it computes — PER ARCHETYPE, never pooled (committee §4.3):

    detection precision      = TP / (TP + FP)      [governance-gating metric]
    detection recall         = TP / (TP + FN)
    false-alarm rate         = FP / (clean items)  [the crying-wolf gate]
    harmful-remediation rate = (fired a non-FLAG fix on a clean/hard-neg item) / clean
                                                   [≈0 hard gate — the clinical red line]

plus Wilson 95% CIs (honest small-n bounds), then applies the acceptance gates
(:mod:`acceptance`). CLI:

    python3.9 score.py <data.jsonl> <predictions.jsonl>
"""
from __future__ import annotations

import json
import math
import sys
from typing import Any, Dict, List, Optional

try:
    from . import acceptance
except ImportError:  # run as a bare script
    import acceptance  # type: ignore


# Remediation kinds that actually change the analysis (a FLAG proposes no mechanical
# change, so a wrongly-fired FLAG is a false alarm but NOT a harmful remediation).
_ANALYSIS_ALTERING = {"refit", "add_covariate", "stratify", "time_transform",
                      "drop_sample", "renormalize"}


def wilson(k: int, n: int, z: float = 1.96):
    """Wilson score interval for a binomial proportion (matches RealBio score.py)."""
    if n == 0:
        return [None, None]
    p = k / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = (z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / denom
    return [round(max(0.0, centre - half), 4), round(min(1.0, centre + half), 4)]


def _safe_div(a: int, b: int) -> Optional[float]:
    return round(a / b, 4) if b else None


def load_jsonl(path: str) -> List[Dict[str, Any]]:
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def score(data: List[Dict[str, Any]], preds: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Score a predictions set against ground truth. Returns a nested results dict."""
    pred_by_id = {p["id"]: p for p in preds}

    # Bucket items by archetype.
    by_arch: Dict[str, List[Dict[str, Any]]] = {}
    for it in data:
        by_arch.setdefault(it["archetype"], []).append(it)

    per_archetype: Dict[str, Any] = {}
    for arch, items in sorted(by_arch.items()):
        spec = acceptance  # noqa (readability)
        governance = items[0].get("governance", "deterministic_advisory")
        clinical = bool(items[0].get("clinical", False))
        target_critic = items[0].get("target_critic")

        tp = fp = fn = tn = 0
        n_pos = n_clean = 0
        harmful = 0
        missed_preds = 0

        for it in items:
            label = it["label"]
            p = pred_by_id.get(it["id"])
            if p is None:
                missed_preds += 1
                fired = False
                kind = None
            else:
                fired = bool(p.get("fired_target"))
                kind = p.get("target_remediation_kind")

            if label == "positive":
                n_pos += 1
                if fired:
                    tp += 1
                else:
                    fn += 1
            else:  # negative / hard_negative
                n_clean += 1
                if fired:
                    fp += 1
                    if kind in _ANALYSIS_ALTERING:
                        harmful += 1
                else:
                    tn += 1

        precision = _safe_div(tp, tp + fp)
        recall = _safe_div(tp, tp + fn)
        false_alarm = _safe_div(fp, n_clean)
        harmful_rate = (harmful / n_clean) if n_clean else 0.0

        gate = acceptance.evaluate(
            archetype=arch, governance=governance, clinical=clinical,
            precision=precision, false_alarm_rate=false_alarm,
            harmful_remediation_rate=harmful_rate,
        )

        per_archetype[arch] = {
            "target_critic": target_critic,
            "governance": governance,
            "clinical": clinical,
            "counts": {"tp": tp, "fp": fp, "fn": fn, "tn": tn,
                       "n_positive": n_pos, "n_clean": n_clean, "missing_predictions": missed_preds},
            "precision": precision,
            "precision_ci95": wilson(tp, tp + fp),
            "recall": recall,
            "recall_ci95": wilson(tp, tp + fn),
            "false_alarm_rate": false_alarm,
            "false_alarm_ci95": wilson(fp, n_clean),
            "harmful_remediation_rate": round(harmful_rate, 4),
            "harmful_count": harmful,
            "gate": gate.to_dict(),
        }

    n_ship = sum(1 for a in per_archetype.values() if a["gate"]["ships"])
    n_hardfail = sum(1 for a in per_archetype.values() if not a["gate"]["hard_gate_pass"])

    return {
        "task": "critic_benchmark",
        "n_items": len(data),
        "n_archetypes": len(per_archetype),
        "arm": preds[0].get("arm") if preds else None,
        "summary": {
            "archetypes_shipping": n_ship,
            "archetypes_hardgate_fail": n_hardfail,
            "overall_hard_gate_pass": n_hardfail == 0,
        },
        "per_archetype": per_archetype,
    }


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def _fmt(x) -> str:
    return "  —  " if x is None else f"{x:.3f}"


def print_table(result: Dict[str, Any]) -> None:
    arm = result.get("arm")
    print(f"\ncritic_benchmark — arm={arm}  items={result['n_items']}  "
          f"archetypes={result['n_archetypes']}")
    header = (f"{'archetype':<24}{'prec':>7}{'recall':>8}{'falseAlarm':>12}"
              f"{'harmRem':>9}{'ships@':>22}")
    print(header)
    print("-" * len(header))
    for arch, a in result["per_archetype"].items():
        ships = a["gate"]["qualified_tier"] if a["gate"]["ships"] else "NO — " + a["gate"]["qualified_tier"]
        print(f"{arch:<24}{_fmt(a['precision']):>7}{_fmt(a['recall']):>8}"
              f"{_fmt(a['false_alarm_rate']):>12}{_fmt(a['harmful_remediation_rate']):>9}"
              f"{ships:>22}")
    s = result["summary"]
    print("-" * len(header))
    print(f"shipping: {s['archetypes_shipping']}/{result['n_archetypes']}   "
          f"hard-gate (harmful-rem≈0) overall: "
          f"{'PASS' if s['overall_hard_gate_pass'] else 'FAIL'}   "
          f"({s['archetypes_hardgate_fail']} archetype(s) fail the hard gate)")


def main(argv: List[str]) -> int:
    if len(argv) != 3:
        print("usage: python3.9 score.py <data.jsonl> <predictions.jsonl>")
        return 2
    data = load_jsonl(argv[1])
    preds = load_jsonl(argv[2])
    result = score(data, preds)
    print_table(result)
    print("\n" + json.dumps(result["summary"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
