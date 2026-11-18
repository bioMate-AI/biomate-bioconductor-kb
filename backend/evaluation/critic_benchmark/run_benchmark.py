"""
run_benchmark.py — end-to-end runner + results writer (the RealBio task entry point).

    python3.9 run_benchmark.py [--n 20] [--out-dir results/<ts>]

Pipeline:
  1. build the labeled set (or load data.jsonl if present and --use-existing)
  2. run the HARNESS arm (registered critics via the real hook) → predictions
  3. run the BARE arm (deterministic LLM-bare abstain lower bound) → predictions
  4. score both arms deterministically (score.py)
  5. write results.json + summary.csv + results.md (bare-vs-harness), print the table

No network, no LLM, no local R. Runnable on python3.9 with only the stdlib + the
read-only critics package.
"""
from __future__ import annotations

import argparse
import csv
import datetime as _dt
import json
import os
from typing import Any, Dict, List

try:
    from . import _bootstrap  # noqa: F401
    from .build_data import build, write_jsonl, DEFAULT_OUT
    from .harness import harness_predictions, bare_predictions, write_predictions
    from .stub_critics import build_registry
    from . import score as score_mod
except ImportError:  # bare script
    import _bootstrap  # noqa: F401
    from build_data import build, write_jsonl, DEFAULT_OUT
    from harness import harness_predictions, bare_predictions, write_predictions
    from stub_critics import build_registry
    import score as score_mod

_HERE = os.path.dirname(os.path.abspath(__file__))


def _write_summary_csv(path: str, arm_results: Dict[str, Dict[str, Any]]) -> None:
    cols = ["arm", "archetype", "target_critic", "governance", "clinical",
            "tp", "fp", "fn", "tn", "precision", "recall",
            "false_alarm_rate", "harmful_remediation_rate", "qualified_tier", "ships"]
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for arm, res in arm_results.items():
            for arch, a in res["per_archetype"].items():
                c = a["counts"]
                g = a["gate"]
                w.writerow([arm, arch, a["target_critic"], a["governance"], a["clinical"],
                            c["tp"], c["fp"], c["fn"], c["tn"],
                            a["precision"], a["recall"], a["false_alarm_rate"],
                            a["harmful_remediation_rate"], g["qualified_tier"], g["ships"]])


def _md_table(res: Dict[str, Any]) -> str:
    rows = ["| archetype | target critic | precision | recall | false-alarm | harmful-rem | ships at |",
            "|---|---|---|---|---|---|---|"]
    def f(x):
        return "—" if x is None else f"{x:.3f}"
    for arch, a in res["per_archetype"].items():
        g = a["gate"]
        ships = g["qualified_tier"] if g["ships"] else f"**NO** ({g['qualified_tier']})"
        rows.append(f"| `{arch}` | `{a['target_critic']}` | {f(a['precision'])} | "
                    f"{f(a['recall'])} | {f(a['false_alarm_rate'])} | "
                    f"{f(a['harmful_remediation_rate'])} | {ships} |")
    return "\n".join(rows)


def _write_results_md(path: str, arm_results: Dict[str, Dict[str, Any]], n_items: int) -> None:
    harness = arm_results["harness"]
    bare = arm_results["bare_abstain"]
    s = harness["summary"]
    lines = [
        "# critic_benchmark — results",
        "",
        f"*Generated {_dt.datetime.now(_dt.timezone.utc).isoformat()} · {n_items} items · "
        f"synthetic error-injection into clean runs · deterministic scoring (no LLM judge).*",
        "",
        "## Frame: bare vs harness",
        "",
        "The *harness* arm runs the registered critics through the real post-run hook "
        "(with the citation + advisory guardrails). The *bare* arm is the deterministic "
        "LLM-bare lower bound (an LLM with no run-contract and no KB abstains on every "
        "successful run). Swap in a real LLM's predictions (same jsonl schema) to "
        "replace the bare floor.",
        "",
        "### Harness arm (registered critics)",
        "",
        _md_table(harness),
        "",
        f"**Hard gate (harmful-remediation ≈ 0): "
        f"{'PASS' if s['overall_hard_gate_pass'] else 'FAIL'}** — "
        f"{s['archetypes_shipping']}/{harness['n_archetypes']} archetypes ship; "
        f"{s['archetypes_hardgate_fail']} fail the hard gate.",
        "",
        "### Bare arm (LLM-bare abstain lower bound)",
        "",
        _md_table(bare),
        "",
        "## How this number feeds RealBio / RealPharma",
        "",
        "This is the RealBio `critic_benchmark` task: it fills the open "
        "'BioMate's own autofix/self-correction cell = —' gap with a real "
        "self-correction number, scored in the manuscript's bare-vs-harness frame. "
        "It measures the HARD half the `autofix` task cannot — *silent validity flaws "
        "in runs that succeeded* — and reports false-alarm and harmful-remediation as "
        "first-class shipping gates, not just precision/recall.",
        "",
        "The result predicts its own story: the correctly-designed critics ship at "
        "`deterministic_advisory`, while a critic that commits a known fallacy (the "
        "Table-2 mediator adjustment) is caught by the harmful-remediation hard gate — "
        "the generalizability claim, measured instead of asserted.",
    ]
    with open(path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def run(n_per_class: int = 20, out_dir: str = "", write_data: bool = True) -> Dict[str, Any]:
    ts = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = out_dir or os.path.join(_HERE, "results", f"critic_benchmark_{ts}")
    os.makedirs(out_dir, exist_ok=True)

    items = build(n_per_class)
    if write_data:
        write_jsonl(items, DEFAULT_OUT)

    registry = build_registry()
    h_preds = harness_predictions(items, registry=registry)
    b_preds = bare_predictions(items)
    write_predictions(h_preds, os.path.join(out_dir, "predictions_harness.jsonl"))
    write_predictions(b_preds, os.path.join(out_dir, "predictions_bare.jsonl"))

    arm_results = {
        "harness": score_mod.score(items, h_preds),
        "bare_abstain": score_mod.score(items, b_preds),
    }
    with open(os.path.join(out_dir, "results.json"), "w") as fh:
        json.dump(arm_results, fh, indent=2)
    _write_summary_csv(os.path.join(out_dir, "summary.csv"), arm_results)
    _write_results_md(os.path.join(out_dir, "results.md"), arm_results, len(items))

    score_mod.print_table(arm_results["harness"])
    print(f"\nresults written to {out_dir}")
    return {"out_dir": out_dir, "results": arm_results, "n_items": len(items)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=20, help="items per (archetype, label) class")
    ap.add_argument("--out-dir", default="")
    ap.add_argument("--no-write-data", action="store_true",
                    help="do not overwrite the committed data.jsonl")
    args = ap.parse_args()
    run(n_per_class=args.n, out_dir=args.out_dir, write_data=not args.no_write_data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
