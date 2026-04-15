#!/usr/bin/env python3
"""
run_sgi_bench.py — Run SGI-Bench (503 life-science samples) standalone.

Usage:
    python runners/run_sgi_bench.py
    python runners/run_sgi_bench.py --max-tasks 50 --output results/sgi_bench/
    python runners/run_sgi_bench.py --domain rna_seq
    python runners/run_sgi_bench.py --difficulty hard --dry-run
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import SGIBenchRunner


DOMAINS = [
    "rna_seq", "scrna_seq", "variant_calling", "atac_seq",
    "chip_seq", "metagenomics", "proteomics", "methylation",
    "structure_prediction", "drug_discovery", "pathway_analysis",
]
DIFFICULTIES = ["easy", "medium", "hard"]


def main():
    parser = argparse.ArgumentParser(description="SGI-Bench runner")
    parser.add_argument("--output", default="results/sgi_bench/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None)
    parser.add_argument("--skip", type=int, default=0,
                        help="Skip first N tasks (for sampling non-deep_research types)")
    parser.add_argument("--domain", choices=DOMAINS, default=None,
                        help="Filter to a single domain")
    parser.add_argument("--difficulty", choices=DIFFICULTIES, default=None,
                        help="Filter to a difficulty level")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    # Apply filters via config override
    if args.domain:
        config.setdefault("sgi_bench", {})["domain_filter"] = args.domain
    if args.difficulty:
        config.setdefault("sgi_bench", {})["difficulty_filter"] = args.difficulty

    adapter = SGIBenchRunner(config)
    tasks = adapter.load_tasks()
    if args.skip:
        tasks = tasks[args.skip:]
    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"SGI-Bench — {len(tasks)} tasks would run:\n")
        domain_counts: dict[str, int] = {}
        diff_counts: dict[str, int] = {}
        for t in tasks:
            domain_counts[t.domain] = domain_counts.get(t.domain, 0) + 1
            diff_counts[t.difficulty] = diff_counts.get(t.difficulty, 0) + 1
        print("  By domain:")
        for d, c in sorted(domain_counts.items()):
            print(f"    {d}: {c}")
        print("  By difficulty:")
        for d, c in sorted(diff_counts.items()):
            print(f"    {d}: {c}")
        return

    print(f"SGI-Bench")
    print(f"  Tasks:     {len(tasks)}")
    print(f"  Domain:    {args.domain or 'all'}")
    print(f"  Difficulty:{args.difficulty or 'all'}")
    print(f"  Output:    {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("sgi_bench", suite="standalone", config=config)

    t0 = time.time()
    results = adapter.run(client, max_tasks=args.max_tasks, skip=args.skip)
    store.save(run_id, results)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    all_summary = store.summary(run_id)
    summary = all_summary.get("sgi_bench_life", all_summary.get("sgi_bench", {}))
    n = len(results)
    mean = sum(r.score for r in results) / n if n else 0.0
    errors = sum(1 for r in results if r.error)

    # Per-task-type breakdown from metadata
    by_domain: dict[str, list[float]] = {}
    by_diff: dict[str, list[float]] = {}
    for r in results:
        task_type = r.metadata.get("task_type", "unknown") if isinstance(r.metadata, dict) else "unknown"
        by_domain.setdefault(task_type, []).append(r.score)
        by_diff.setdefault(r.metadata.get("difficulty", "unknown") if isinstance(r.metadata, dict) else "unknown", []).append(r.score)

    print(f"\n{'='*55}")
    print(f"SGI-Bench Results")
    print(f"{'='*55}")
    print(f"  Overall:  n={n}  mean={mean:.3f}  errors={errors}  elapsed={elapsed:.0f}s\n")

    print(f"  {'Task Type':<30} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*42}")
    for domain, scores in sorted(by_domain.items()):
        dm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {domain:<30} {len(scores):>4} {dm:>7.3f}")

    print(f"\n  {'Difficulty':<15} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*27}")
    for diff, scores in sorted(by_diff.items()):
        dm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {diff:<15} {len(scores):>4} {dm:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
