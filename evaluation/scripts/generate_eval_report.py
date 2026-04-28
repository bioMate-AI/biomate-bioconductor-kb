#!/usr/bin/env python3
"""
generate_eval_report.py
-----------------------
Generates a unified four-dimension evaluation report for any benchmark DB.

Dimensions:
  1. Performance  — mean ± std score per subtask
  2. Time cost    — mean ± std ± p95 latency per task
  3. Stability    — consistency_rate, flip_rate, Cohen's κ (from stability DB if available)
  4. Hallucination— hallucination_rate per step type (from hallucination_label column)
  5. Financial cost — mean ± std cost per task; total

Usage:
    cd /home/yzhang/biomate/evaluation
    python scripts/generate_eval_report.py --db results/biomni_eval1_v20/eval_results.db
    python scripts/generate_eval_report.py --all
    python scripts/generate_eval_report.py --db results/labbench_v22/eval_results.db --format md
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional

RESULTS_DIR = Path(__file__).parent.parent / "results"
STABILITY_DIR = RESULTS_DIR / "stability"

# Published external baselines for comparison column
_PUBLISHED_BASELINES = {
    "biomni_eval1": {
        "performance": {"GPT-4o": 0.65, "Claude-3.5-Sonnet": 0.60, "Biomni": 0.70},
        "hallucination_rate": {},
        "consistency": {},
        "cost_per_task": {"GPT-4o": 0.011, "Claude-3.5-Sonnet": 0.017},
        "time_per_task_sec": {},
    },
    "labbench": {
        "performance": {"Claude-3.5-Sonnet": 0.60, "GPT-4o": 0.55, "Human": 0.60},
        "hallucination_rate": {},
        "consistency": {},
        "cost_per_task": {},
        "time_per_task_sec": {},
    },
    "bixbench": {
        "performance": {"Claude-3.5-Sonnet": 0.17, "GPT-4o": 0.09},
        "hallucination_rate": {},
        "consistency": {},
        "cost_per_task": {},
        "time_per_task_sec": {},
    },
    "sgi_bench": {
        "performance": {"GPT-4o": 0.18, "Claude-3.5-Sonnet": 0.13},
        "hallucination_rate": {},
        "consistency": {},
        "cost_per_task": {},
        "time_per_task_sec": {},
    },
}


def _std(vals: List[float]) -> float:
    if len(vals) < 2:
        return 0.0
    mean = sum(vals) / len(vals)
    return math.sqrt(sum((v - mean) ** 2 for v in vals) / (len(vals) - 1))


def _wilson_ci(p: float, n: int, z: float = 1.96) -> tuple:
    """Wilson score confidence interval for a proportion — correct for binary scores."""
    if n == 0:
        return 0.0, 1.0
    denom = 1 + z ** 2 / n
    center = (p + z ** 2 / (2 * n)) / denom
    margin = (z * math.sqrt(p * (1 - p) / n + z ** 2 / (4 * n ** 2))) / denom
    return max(0.0, center - margin), min(1.0, center + margin)


def _score_se(p: float, n: int) -> float:
    """Standard error of a proportion — correct uncertainty measure for binary scores."""
    return math.sqrt(p * (1 - p) / n) if n > 0 else 0.0


def _percentile(vals: List[float], p: float) -> float:
    if not vals:
        return 0.0
    s = sorted(vals)
    idx = int(p * len(s))
    return s[min(idx, len(s) - 1)]


def load_db_stats(db_path: str) -> Dict[str, Any]:
    """Extract all four dimension stats from a results DB."""
    conn = sqlite3.connect(db_path)
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
    if "results" not in tables:
        conn.close()
        return {}

    # Check which columns exist (older DBs predate hallucination_label / repeat_id)
    existing_cols = {r[1] for r in conn.execute("PRAGMA table_info(results)").fetchall()}
    hall_col   = "hallucination_label" if "hallucination_label" in existing_cols else "NULL"
    repeat_col = "COALESCE(repeat_id, 0)" if "repeat_id" in existing_cols else "0"

    rows = conn.execute(
        f"SELECT task_id, benchmark, score, latency_sec, cost_usd, "
        f"input_tokens, output_tokens, model, {hall_col}, {repeat_col} "
        f"FROM results WHERE (error='' OR error IS NULL)"
    ).fetchall()
    conn.close()

    if not rows:
        return {}

    # Separate original runs (repeat_id=0) from stability repeats
    original = [r for r in rows if r[9] == 0]
    repeats  = [r for r in rows if r[9] > 0]

    # --- Dimension 1+2+5: Performance, Time, Cost (from original runs) ---
    benchmarks: Dict[str, Dict] = {}
    for task_id, benchmark, score, latency, cost, in_tok, out_tok, model, hlabel, _ in original:
        b = benchmarks.setdefault(benchmark, {
            "scores": [], "latencies": [], "costs": [],
            "in_tokens": [], "out_tokens": [],
            "hallucination_labels": [],
        })
        b["scores"].append(score or 0.0)
        if latency and latency > 0:
            b["latencies"].append(latency)
        if cost is not None:
            b["costs"].append(cost)
        if in_tok:
            b["in_tokens"].append(in_tok)
        if out_tok:
            b["out_tokens"].append(out_tok)
        if hlabel:
            b["hallucination_labels"].append(hlabel)

    stats: Dict[str, Any] = {}
    for bench, d in benchmarks.items():
        scores = d["scores"]
        lats   = d["latencies"]
        costs  = d["costs"]
        hlabels = d["hallucination_labels"]

        n = len(scores)
        mean_score = sum(scores) / n if n else 0.0

        # Hallucination
        n_grounded     = hlabels.count("grounded")
        n_hallucinated = hlabels.count("hallucinated")
        n_unverifiable = hlabels.count("unverifiable")
        assessable     = n_grounded + n_hallucinated
        hall_rate      = n_hallucinated / assessable if assessable > 0 else None

        ci_lo, ci_hi = _wilson_ci(mean_score, n)
        se = _score_se(mean_score, n)
        stats[bench] = {
            # Performance — use Wilson CI, not Bernoulli std
            "n": n,
            "mean_score":    round(mean_score, 4),
            "score_se":      round(se, 4),          # standard error (correct)
            "ci_95_lo":      round(ci_lo, 4),        # Wilson 95% CI lower
            "ci_95_hi":      round(ci_hi, 4),        # Wilson 95% CI upper
            "score_std":     round(_std(scores), 4), # kept for reference; NOTE: not SE for binary scores
            # Time
            "mean_latency_sec": round(sum(lats) / len(lats), 2) if lats else None,
            "std_latency_sec":  round(_std(lats), 2) if lats else None,
            "p95_latency_sec":  round(_percentile(lats, 0.95), 2) if lats else None,
            "min_latency_sec":  round(min(lats), 2) if lats else None,
            "max_latency_sec":  round(max(lats), 2) if lats else None,
            # Cost
            "mean_cost_usd":      round(sum(costs) / len(costs), 6) if costs else None,
            "std_cost_usd":       round(_std(costs), 6) if costs else None,
            "total_cost_usd":     round(sum(costs), 4) if costs else None,
            "total_input_tokens": sum(d["in_tokens"]),
            "total_output_tokens":sum(d["out_tokens"]),
            # Hallucination
            "n_grounded":         n_grounded,
            "n_hallucinated":     n_hallucinated,
            "n_unverifiable":     n_unverifiable,
            "n_not_audited":      n - len(hlabels),
            "hallucination_rate": round(hall_rate, 4) if hall_rate is not None else None,
            # Stability placeholder (filled below)
            "consistency_rate":   None,
            "flip_rate":          None,
            "kappa":              None,
        }

    # --- Dimension 3: Stability (from repeat rows if present) ---
    if repeats:
        by_task: Dict[str, List[float]] = {}
        for _, benchmark, score, *_ in original:
            by_task.setdefault(f"{benchmark}__{_[6]}", []).append(score or 0.0)  # task_id not in this tuple
        # Rebuild from full row
        by_task_all: Dict[str, List[float]] = {}
        for task_id, benchmark, score, *_ in rows:
            by_task_all.setdefault(task_id, []).append(score or 0.0)

        # Tasks with >1 repeat
        multi = {tid: sc for tid, sc in by_task_all.items() if len(sc) > 1}
        if multi:
            n_consistent = sum(
                1 for sc in multi.values()
                if len(set(s >= 0.5 for s in sc)) == 1
            )
            consistency = n_consistent / len(multi)
            all_stds = [_std(sc) for sc in multi.values() if len(sc) > 1]
            mean_std = sum(all_stds) / len(all_stds) if all_stds else 0.0
            for bench in stats:
                stats[bench]["consistency_rate"] = round(consistency, 4)
                stats[bench]["flip_rate"]        = round(1 - consistency, 4)
                stats[bench]["mean_score_std"]   = round(mean_std, 4)

    # Load stability JSON if available
    bench_name = Path(db_path).parent.name.split("_v")[0].split("_20")[0]
    stability_path = STABILITY_DIR / f"{bench_name}_stability.json"
    if stability_path.exists():
        with open(stability_path) as f:
            stab = json.load(f)
        for bench in stats:
            stats[bench]["consistency_rate"] = stab.get("consistency_rate")
            stats[bench]["flip_rate"]        = stab.get("flip_rate")
            stats[bench]["kappa"]            = stab.get("kappa")

    return stats


def format_table(stats: Dict[str, Any], db_name: str, fmt: str = "text") -> str:
    """Format the four-dimension summary as text or markdown."""
    bench_name = db_name.split("_v")[0].split("_20")[0]
    published  = _PUBLISHED_BASELINES.get(bench_name, {})

    lines = []
    sep   = "─" * 90

    if fmt == "md":
        lines.append(f"## {db_name} — Four-Dimension Evaluation")
        lines.append("")
    else:
        lines.append(sep)
        lines.append(f"  {db_name}  —  Four-Dimension Evaluation")
        lines.append(sep)

    for bench, d in stats.items():
        # Performance
        pub_perf = published.get("performance", {})
        pub_str  = "  |  ".join(f"{k}: {v:.1%}" for k, v in pub_perf.items())

        # Hallucination
        hall_str = (f"{d['hallucination_rate']:.1%}" if d["hallucination_rate"] is not None
                    else f"not audited ({d['n_not_audited']} rows pending)")

        # Stability
        cons_str = (f"{d['consistency_rate']:.1%}" if d["consistency_rate"] is not None
                    else "not run yet")
        kappa_str = (f"κ={d['kappa']:.3f}" if d.get("kappa") is not None else "")

        # Cost
        cost_str = (f"${d['mean_cost_usd']:.5f}/task (σ=${d['std_cost_usd']:.5f})"
                    if d["mean_cost_usd"] is not None else "not tracked")
        pub_cost = published.get("cost_per_task", {})
        pub_cost_str = "  |  ".join(f"{k}: ${v:.4f}" for k, v in pub_cost.items())

        ci_str = f"[{d.get('ci_95_lo', 0):.1%}, {d.get('ci_95_hi', 1):.1%}]"
        se_str = f"±{d.get('score_se', 0):.1%} SE"

        if fmt == "md":
            lines += [
                f"### {bench}  (n={d['n']})",
                "",
                f"| Dimension | BioMate | Published baselines |",
                f"|-----------|---------|---------------------|",
                f"| **Performance** | **{d['mean_score']:.1%}** {se_str}, 95% CI {ci_str} | {pub_str or '—'} |",
                f"| **Time/task** | {d['mean_latency_sec'] or '?'}s mean, {d['std_latency_sec'] or '?'}s σ, {d['p95_latency_sec'] or '?'}s p95 | not reported |",
                f"| **Stability** | {cons_str}  {kappa_str} | — |",
                f"| **Hallucination rate** | {hall_str} | — |",
                f"| **Financial cost** | {cost_str} | {pub_cost_str or '—'} |",
                "",
            ]
        else:
            lines += [
                f"  Benchmark:     {bench}  (n={d['n']})",
                f"  Performance:   {d['mean_score']:.1%}  {se_str}  95%CI {ci_str}     Published: {pub_str or 'not available'}",
                f"  Time/task:     {d['mean_latency_sec'] or '?'}s mean  ±{d['std_latency_sec'] or '?'}s  p95={d['p95_latency_sec'] or '?'}s",
                f"  Stability:     {cons_str}  {kappa_str}",
                f"  Hallucination: {hall_str}",
                f"  Cost/task:     {cost_str}     Published: {pub_cost_str or 'not available'}",
                "",
            ]

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Four-dimension eval report generator")
    parser.add_argument("--db", default=None, help="Single DB path")
    parser.add_argument("--all", action="store_true", help="Report on all results/ DBs")
    parser.add_argument("--format", choices=["text", "md", "json"], default="text")
    parser.add_argument("--out", default=None, help="Output file (default: stdout)")
    args = parser.parse_args()

    # Select which DBs
    priority_dbs = [
        "results/biomni_eval1_v20/eval_results.db",
        "results/labbench_v22/eval_results.db",
        "results/bixbench_v4/eval_results.db",
        "results/sgi_bench_v1/eval_results.db",
        "results/routing_v11/eval_results.db",
    ]
    eval_dir = Path(__file__).parent.parent

    if args.all:
        dbs = sorted(glob.glob(str(eval_dir / "results/**/eval_results.db"), recursive=True))
        dbs = [d for d in dbs if "model_selection" not in d and "stability" not in d]
    elif args.db:
        dbs = [args.db]
    else:
        dbs = [str(eval_dir / d) for d in priority_dbs if (eval_dir / d).exists()]

    all_output = []
    all_stats  = {}

    for db in dbs:
        db_name = Path(db).parent.name
        stats = load_db_stats(db)
        if not stats:
            continue
        all_stats[db_name] = stats
        if args.format != "json":
            all_output.append(format_table(stats, db_name, args.format))

    if args.format == "json":
        output = json.dumps(all_stats, indent=2)
    else:
        output = "\n".join(all_output)

    if args.out:
        Path(args.out).write_text(output)
        print(f"Report written to {args.out}")
    else:
        print(output)


if __name__ == "__main__":
    main()
