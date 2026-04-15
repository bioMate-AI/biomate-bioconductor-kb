#!/usr/bin/env python3
"""
run_biomni_eval1.py — Run BiomniEval1 benchmark standalone.

Usage:
    python runners/run_biomni_eval1.py
    python runners/run_biomni_eval1.py --max-tasks 5 --output results/biomni_eval1/
    python runners/run_biomni_eval1.py --dry-run
    python runners/run_biomni_eval1.py --task-type gwas_variant_prioritization
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import BiomniEval1Adapter


def main():
    parser = argparse.ArgumentParser(description="BiomniEval1 benchmark runner")
    parser.add_argument("--output", default="results/biomni_eval1/",
                        help="Output directory")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None,
                        help="Limit number of tasks (default: all)")
    parser.add_argument("--task-type", default=None,
                        help="Filter to one task type (e.g. gwas_variant_prioritization)")
    parser.add_argument("--dry-run", action="store_true",
                        help="List tasks without running them")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    adapter = BiomniEval1Adapter(config)

    tasks = adapter.load_tasks()

    if args.task_type:
        tasks = [t for t in tasks if t.metadata.get("task_name") == args.task_type]

    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"BiomniEval1 — {len(tasks)} tasks would run:\n")
        for t in tasks:
            print(f"  [{t.task_type}] {t.task_id}: {t.question[:80]}...")
        return

    print(f"BiomniEval1 Benchmark")
    print(f"  Tasks:    {len(tasks)}")
    print(f"  Output:   {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("biomni_eval1", suite="standalone", config=config)

    t0 = time.time()
    # Run the pre-filtered task list directly (adapter.run() reloads without filter)
    results = adapter.run_tasks(client, tasks)
    store.save(run_id, results)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    summary = store.summary(run_id).get("biomni_eval1", {})
    n = summary.get("n", len(results))
    mean = summary.get("mean", 0.0)

    # Per-task-type breakdown
    by_type: dict[str, list[float]] = {}
    for r in results:
        tt = r.metadata.get("task_name", r.metadata.get("task_type", "unknown"))
        by_type.setdefault(tt, []).append(r.score)

    print(f"\n{'='*55}")
    print(f"BiomniEval1 Results")
    print(f"{'='*55}")
    print(f"  Overall:  n={n}  mean={mean:.3f}  elapsed={elapsed:.0f}s\n")
    print(f"  {'Task Type':<40} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*52}")
    for tt, scores in sorted(by_type.items()):
        tt_mean = sum(scores) / len(scores) if scores else 0.0
        print(f"  {tt:<40} {len(scores):>4} {tt_mean:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
