#!/usr/bin/env python3
"""
run_autofix_benchmark.py — Run the BioMate autofix diagnostic benchmark.

Tests BioMate's ability to correctly diagnose workflow failures and propose
the right fix. Presents 20 synthetic broken workflow states (error logs +
parameters) and evaluates response quality with an LLM judge.

Categories:
  - genome_mismatch (5): Wrong genome build / annotation mismatch
  - missing_input   (5): Missing files, S3 paths, required params
  - param_type_error(5): String/bool/float type coercions
  - resource_failure(5): OOM, timeout, disk full

Usage:
    python runners/run_autofix_benchmark.py
    python runners/run_autofix_benchmark.py --category genome_mismatch
    python runners/run_autofix_benchmark.py --max-tasks 5 --dry-run
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import AutofixBenchmarkAdapter

CATEGORIES = ["genome_mismatch", "missing_input", "param_type_error", "resource_failure"]


def main():
    parser = argparse.ArgumentParser(description="Autofix Benchmark runner")
    parser.add_argument("--output", default="results/autofix_benchmark/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None)
    parser.add_argument("--category", choices=CATEGORIES, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    adapter = AutofixBenchmarkAdapter(config)
    tasks = adapter.load_tasks()

    # Apply category filter
    if args.category:
        tasks = [t for t in tasks if t.metadata.get("category") == args.category]

    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        by_cat: dict[str, int] = {}
        by_diff: dict[str, int] = {}
        for t in tasks:
            by_cat[t.metadata["category"]] = by_cat.get(t.metadata["category"], 0) + 1
            by_diff[t.metadata["fix_difficulty"]] = by_diff.get(t.metadata["fix_difficulty"], 0) + 1
        print(f"Autofix Benchmark — {len(tasks)} tasks would run:")
        print("  By category:")
        for c, n in sorted(by_cat.items()):
            print(f"    {c}: {n}")
        print("  By difficulty:")
        for d, n in sorted(by_diff.items()):
            print(f"    {d}: {n}")
        return

    print(f"Autofix Benchmark")
    print(f"  Tasks:    {len(tasks)}")
    print(f"  Category: {args.category or 'all'}")
    print(f"  Output:   {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("autofix_benchmark", suite="standalone", config=config)

    t0 = time.time()
    results = adapter.run(client, max_tasks=len(tasks))
    store.save(run_id, results)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    n = len(results)
    mean = sum(r.score for r in results) / n if n else 0.0
    errors = sum(1 for r in results if r.error)

    # Per-category breakdown
    by_cat: dict[str, list[float]] = {}
    by_diff: dict[str, list[float]] = {}
    for r in results:
        cat = r.metadata.get("category", "unknown") if isinstance(r.metadata, dict) else "unknown"
        diff = r.metadata.get("fix_difficulty", "unknown") if isinstance(r.metadata, dict) else "unknown"
        by_cat.setdefault(cat, []).append(r.score)
        by_diff.setdefault(diff, []).append(r.score)

    print(f"\n{'='*55}")
    print(f"Autofix Benchmark Results")
    print(f"{'='*55}")
    print(f"  Overall:  n={n}  mean={mean:.3f}  errors={errors}  elapsed={elapsed:.0f}s\n")

    print(f"  {'Category':<25} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*37}")
    for cat, scores in sorted(by_cat.items()):
        cm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {cat:<25} {len(scores):>4} {cm:>7.3f}")

    print(f"\n  {'Difficulty':<15} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*27}")
    for diff, scores in sorted(by_diff.items()):
        dm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {diff:<15} {len(scores):>4} {dm:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")

    # Per-task detail for failures
    failures = [r for r in results if r.score < 0.5]
    if failures:
        print(f"\n  Failures ({len(failures)}):")
        for r in failures:
            print(f"    [{r.task_id}] score={r.score:.2f} — {r.metadata.get('description', '')[:60]}")


if __name__ == "__main__":
    main()
