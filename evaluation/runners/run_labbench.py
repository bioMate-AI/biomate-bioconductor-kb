#!/usr/bin/env python3
"""
run_labbench.py — Run LAB-Bench benchmark.

Usage:
    python runners/run_labbench.py
    python runners/run_labbench.py --subtasks CloningScenarios ProtocolQA
    python runners/run_labbench.py --subtasks all
    python runners/run_labbench.py --max-per-subtask 20 --dry-run
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters.labbench_adapter import LABBenchAdapter, LAB_BENCH_CONFIGS, DEFAULT_SUBTASKS

ALL_TEXT_SUBTASKS = ["CloningScenarios", "ProtocolQA", "LitQA2", "SeqQA", "DbQA"]


def main():
    parser = argparse.ArgumentParser(description="LAB-Bench benchmark runner")
    parser.add_argument("--output", default="results/labbench/",
                        help="Output directory")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--subtasks", nargs="+", default=None,
                        help="Subtasks to run (default: CloningScenarios ProtocolQA LitQA2). "
                             "Use 'all' for all text subtasks.")
    parser.add_argument("--max-per-subtask", type=int, default=None,
                        help="Max questions per subtask (default: all)")
    parser.add_argument("--workers", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--no-pubmed", action="store_true",
                        help="Disable PubMed context injection for LitQA2 (default: enabled)")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")
    if args.workers:
        config.setdefault("concurrency", {})["max_parallel_tasks"] = args.workers

    subtasks = args.subtasks
    if subtasks and subtasks[0] == "all":
        subtasks = ALL_TEXT_SUBTASKS
    elif subtasks is None:
        subtasks = DEFAULT_SUBTASKS

    # PubMed context for LitQA2 is on by default — it queries PubMed to retrieve
    # supporting abstracts for each question before MCQ selection.
    # Adds ~5-8s latency per LitQA2 question; disable with --no-pubmed.
    use_pubmed = not args.no_pubmed
    adapter = LABBenchAdapter(
        config,
        subtasks=subtasks,
        max_per_subtask=args.max_per_subtask,
        seed=args.seed,
        use_pubmed=use_pubmed,
    )
    tasks = adapter.load_tasks()

    if args.dry_run:
        print(f"LAB-Bench — {len(tasks)} tasks would run:")
        by_sub = {}
        for t in tasks:
            sub = t.metadata.get("subtask", "?")
            by_sub[sub] = by_sub.get(sub, 0) + 1
        for sub, n in sorted(by_sub.items()):
            print(f"  {sub}: {n} tasks")
        print(f"\nSample question ({tasks[0].task_id}):")
        print(tasks[0].question[:400])
        return

    print("LAB-Bench Benchmark")
    print(f"  Subtasks: {subtasks}")
    print(f"  Tasks:    {len(tasks)}")
    print(f"  Output:   {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("labbench", suite="standalone", config=config)

    completed = [0]

    def _on_result(r):
        store.save_one(run_id, r)
        completed[0] += 1
        sub = r.metadata.get("subtask", "?")
        status = "✓" if r.score >= 1.0 else "✗"
        err = f" [ERR: {r.error[:40]}]" if r.error else ""
        print(f"  [{completed[0]:>3}/{len(tasks)}] {status} {sub:<22} "
              f"score={r.score:.2f}  {r.latency_sec:.0f}s{err}", flush=True)

    t0 = time.time()
    results = adapter.run_tasks(client, tasks, on_result=_on_result)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    # Per-subtask breakdown
    by_sub: dict[str, list[float]] = {}
    for r in results:
        sub = r.metadata.get("subtask", "unknown")
        by_sub.setdefault(sub, []).append(r.score)

    n_total = len(results)
    overall = sum(s for scores in by_sub.values() for s in scores) / max(n_total, 1)

    print(f"\n{'='*50}")
    print(f"LAB-Bench Results")
    print(f"{'='*50}")
    print(f"  Overall:  n={n_total}  mean={overall:.3f}  elapsed={elapsed:.0f}s\n")
    print(f"  {'Subtask':<24} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*38}")
    for sub, scores in sorted(by_sub.items()):
        sub_mean = sum(scores) / len(scores) if scores else 0.0
        print(f"  {sub:<24} {len(scores):>4} {sub_mean:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
