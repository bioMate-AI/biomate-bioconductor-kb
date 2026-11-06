#!/usr/bin/env python3
"""
build_5d_leaderboard.py  (READ-ONLY aggregator)
-----------------------------------------------
Consolidate RealBio's 5 evaluation dimensions (Framework v1) into one per-model table.
D1 (accuracy) already lives in `leaderboard.csv`; the efficiency/trust dimensions are
captured per-result but were never surfaced. This emits `leaderboard_5d.{csv,md}` adding:

  D3 Time  — median (p50) + p95 latency per query, from each model's `*.usage.json`
  D4 Cost  — mean input/output tokens per query (the model-agnostic cost proxy; $ needs a
             per-model price map, TODO)
  D2 Stability     — pulled from results/stability/stability_summary.json where available,
                     else 'pending' (needs the multi-run consistency sweep, target ≥90%)
  D5 Hallucination — 'pending' (needs the per-model hallucination_detector sweep)

Keyed by the results/ model slug (self-consistent with the committed predictions; no
display-name join). Leaves the canonical D1 leaderboard untouched. Writes nothing but the
two 5d files.  Run: python3 build_5d_leaderboard.py [--stdout]
"""
from __future__ import annotations

import csv
import glob
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = os.path.join(HERE, "results")
STAB = os.path.join(HERE, "..", "..", "results", "stability", "stability_summary.json")


def _load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def _stability_index():
    """Best-effort map model-ish-key -> stability number from stability_summary.json."""
    data = _load(STAB)
    idx = {}
    if isinstance(data, dict):
        for k, v in data.items():
            if isinstance(v, dict):
                val = v.get("consistency_rate", v.get("stability", v.get("flip_rate")))
                if val is not None:
                    idx[k.lower()] = val
    return idx


def aggregate_model(slug_dir):
    usage = glob.glob(os.path.join(slug_dir, "*.usage.json"))
    p50s, p95s, tin, tout, ntasks = [], [], [], [], 0
    for u in usage:
        d = _load(u) or {}
        ntasks += 1
        if d.get("latency_ms_p50") is not None:
            p50s.append(d["latency_ms_p50"])
        if d.get("latency_ms_p95") is not None:
            p95s.append(d["latency_ms_p95"])
        if d.get("input_tokens_mean") is not None:
            tin.append(d["input_tokens_mean"])
        if d.get("output_tokens_mean") is not None:
            tout.append(d["output_tokens_mean"])
    if ntasks == 0:
        return None
    mean = lambda xs: round(statistics.mean(xs), 1) if xs else None
    return {
        "n_usage_tasks": ntasks,
        "D3_p50_s": round(statistics.mean(p50s) / 1000.0, 1) if p50s else None,
        "D3_p95_s": round(statistics.mean(p95s) / 1000.0, 1) if p95s else None,
        "D4_tok_in_per_q": mean(tin),
        "D4_tok_out_per_q": mean(tout),
    }


def build():
    stab = _stability_index()
    rows = []
    for d in sorted(glob.glob(os.path.join(RESULTS, "*/"))):
        slug = os.path.basename(d.rstrip("/"))
        agg = aggregate_model(d)
        if not agg:
            continue
        d2 = next((f"{v:.2f}" for k, v in stab.items() if k in slug.lower() or slug.lower() in k),
                  "pending")
        rows.append({
            "model_slug": slug,
            "D3_latency_p50_s": agg["D3_p50_s"], "D3_latency_p95_s": agg["D3_p95_s"],
            "D4_tok_in_per_q": agg["D4_tok_in_per_q"], "D4_tok_out_per_q": agg["D4_tok_out_per_q"],
            "D2_stability": d2, "D5_hallucination": "pending",
            "n_usage_tasks": agg["n_usage_tasks"],
        })
    # sort by output tokens/query (a rough cost/verbosity proxy)
    rows.sort(key=lambda r: (r["D4_tok_out_per_q"] or 0))
    return rows


COLS = ["model_slug", "D3_latency_p50_s", "D3_latency_p95_s",
        "D4_tok_in_per_q", "D4_tok_out_per_q", "D2_stability", "D5_hallucination", "n_usage_tasks"]


def main():
    rows = build()
    stdout = "--stdout" in sys.argv
    # CSV
    out_csv = os.path.join(HERE, "leaderboard_5d.csv")
    lines = [",".join(COLS)] + [",".join(str(r[c]) for c in COLS) for r in rows]
    text = "\n".join(lines) + "\n"
    # MD
    md = ["| " + " | ".join(COLS) + " |", "|" + "---|" * len(COLS)]
    md += ["| " + " | ".join(str(r[c]) for c in COLS) + " |" for r in rows]
    md_text = ("# RealBio 5-D leaderboard (D1 accuracy in leaderboard.csv; D2/D5 pending sweep)\n\n"
               "D3 Time + D4 Cost (tokens/query) from committed `*.usage.json`. $ needs a price map.\n\n"
               + "\n".join(md) + "\n")
    if stdout:
        print(text)
        return 0
    with open(out_csv, "w") as f:
        f.write(text)
    with open(os.path.join(HERE, "leaderboard_5d.md"), "w") as f:
        f.write(md_text)
    print(f"wrote leaderboard_5d.csv + .md ({len(rows)} models with usage data)")
    print("  D1 accuracy stays in leaderboard.csv; D2 stability populated where "
          "stability_summary.json maps, else 'pending'; D5 'pending' (needs hallucination sweep).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
