#!/usr/bin/env python3
"""
generate_report.py — Competitive markdown report.

Reads results from the SQLite store and generates a markdown table
comparing BioMate's scores to competitor published scores.

Usage:
    python runners/generate_report.py --results-dir results/ --output results/report.md
"""

import argparse
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import ResultsStore


# Published competitor scores (source: docs/papers/20260401_COMPETITOR_BENCHMARK_LANDSCAPE.md)
COMPETITOR_SCORES = {
    "bixbench": {
        "GPT-4o (baseline)": 0.17,
        "Claude 3.5 Sonnet": 0.17,
        "Claude Code Opus 4.6": 0.395,
        "OpenAI Agents SDK": 0.385,
        "Edison Analysis": 0.424,
        "Biomni Lab": 0.522,
    },
    "bixbench_verified50": {
        "Claude Code Opus 4.6": 0.653,
        "OpenAI Agents SDK": 0.613,
        "Edison Analysis": 0.780,
        "Biomni Lab": 0.887,
    },
    "biomni_eval1__rare_disease_diagnosis": {
        "Biomni (original)": 0.67,
    },
    "sgi_bench_life": {
        # No published aggregate score; reference individual task types
    },
    "cross_domain_routing": {
        # BioMate-unique — no competitor baseline published
        "BM25 keyword (est.)": 0.35,
        "Raw LLM + GalaxyMCP (est.)": 0.45,
    },
    "prereq_recovery": {
        # BioMate-unique — no competitor baseline published
        "Raw LLM (est.)": 0.38,
        "GalaxyMCP (est.)": 0.42,
    },
    "license_gating": {
        # BioMate-unique — no competitor has this capability
        "Any other system": "N/A",
    },
    "protocol_thresholds": {
        # BioMate-unique — no competitor has protocol-aware QC profiles
        "MultiQC (universal thresholds)": "N/A (naive=FAIL on all 20 edge cases)",
    },
    "autofix_benchmark": {
        # BioMate-unique — AI Scientist (Lu et al. 2024) comparable recovery rate
        "AI Scientist (Lu et al. 2024, CS domain)": 0.65,
    },
    "sgi_bench_life": {
        # Published SGI-Bench baselines (wet/dry experiment framing)
        "GPT-4o": 0.72,
        "Claude 3.5 Sonnet": 0.69,
    },
    "sgi_bench": {
        # Same as sgi_bench_life — benchmark stored under this key by runner
        "GPT-4o": 0.72,
        "Claude 3.5 Sonnet": 0.69,
    },
}

TARGET_SCORES = {
    "bixbench": 0.40,
    "bixbench_verified50": 0.70,
    "biomni_eval1": 0.65,
    "sgi_bench_life": 0.60,
    "cross_domain_routing": 0.80,
    "prereq_recovery": 0.85,
    "license_gating": 0.90,
    "protocol_thresholds": 0.80,
    "autofix_benchmark": 0.90,
}


def load_config(config_path: str = "config.yaml") -> dict:
    with open(config_path) as f:
        return yaml.safe_load(f)


def format_score(score) -> str:
    if score == "N/A":
        return "N/A"
    if isinstance(score, float):
        return f"{score:.1%}"
    return str(score)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", default="results/")
    parser.add_argument("--output", default="results/competitive_report.md")
    parser.add_argument("--config", default="config.yaml")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    config = load_config(str(config_path))
    results_dir = Path(args.results_dir)

    # Collect all runs from master DB + all subdirectory DBs
    all_runs: list = []
    db_paths_scanned: list[str] = []

    # Master DB (may be empty)
    master_db = results_dir / "eval_results.db"
    if master_db.exists():
        store = ResultsStore(str(master_db))
        all_runs.extend(store.all_run_summaries())
        db_paths_scanned.append(str(master_db))

    # Sub-directory DBs
    for sub_db in sorted(results_dir.glob("*/eval_results.db")):
        try:
            sub_store = ResultsStore(str(sub_db))
            sub_runs = sub_store.all_run_summaries()
            all_runs.extend(sub_runs)
            db_paths_scanned.append(str(sub_db))
        except Exception:
            pass

    # Get latest run per benchmark (last write wins)
    latest: dict = {}
    for run in sorted(all_runs, key=lambda r: r["finished_at"] or ""):
        if run["n"] > 0:  # skip empty runs
            latest[run["benchmark"]] = run

    lines = []
    lines.append("# BioMate Evaluation — Competitive Report")
    lines.append(f"\n_Generated from {len(db_paths_scanned)} result DBs in: {args.results_dir}_\n")

    lines.append("## BioMate Scores vs Competitors\n")
    lines.append("| Benchmark | BioMate | Target | Best Competitor | All Competitors |")
    lines.append("|---|---|---|---|---|")

    all_benchmarks = set(list(latest.keys()) + list(COMPETITOR_SCORES.keys()))
    for bench in sorted(all_benchmarks):
        biomate_run = latest.get(bench)
        biomate_score = f"{biomate_run['mean_score']:.1%} (n={biomate_run['n']})" if biomate_run else "**TBD**"

        target = TARGET_SCORES.get(bench)
        target_str = f"{target:.1%}" if target else "—"

        competitors = COMPETITOR_SCORES.get(bench, {})
        if competitors and competitors != {"Any other system": "N/A"}:
            best_name = max(
                [(k, v) for k, v in competitors.items() if isinstance(v, float)],
                key=lambda x: x[1],
                default=(None, None)
            )
            best_str = f"{best_name[0]}: {best_name[1]:.1%}" if best_name[0] else "—"
            all_comp = "; ".join(f"{k}: {format_score(v)}" for k, v in competitors.items())
        else:
            best_str = "No competitor (BioMate-unique)"
            all_comp = "No competitor has this capability"

        lines.append(f"| {bench} | {biomate_score} | {target_str} | {best_str} | {all_comp} |")

    lines.append("\n## Run History\n")
    lines.append("| run_id | benchmark | n | mean_score | finished_at |")
    lines.append("|---|---|---|---|---|")
    for run in sorted(all_runs, key=lambda r: r["finished_at"] or "", reverse=True)[:20]:
        lines.append(
            f"| {run['run_id']} | {run['benchmark']} | {run['n']} "
            f"| {run['mean_score']:.3f} | {run['finished_at']} |"
        )

    lines.append("\n## Notes\n")
    lines.append("- Competitor scores sourced from: `docs/papers/20260401_COMPETITOR_BENCHMARK_LANDSCAPE.md`")
    lines.append("- `(est.)` scores are rough estimates, not from published papers")
    lines.append("- BioMate-unique benchmarks have no published competitor baseline")
    lines.append("- Scores on BixBench should note: original ground truth has errors (see BixBench-Verified-50)")

    report = "\n".join(lines)
    Path(args.output).write_text(report)
    print(f"Report written to: {args.output}")
    print(report[:1000])


if __name__ == "__main__":
    main()
