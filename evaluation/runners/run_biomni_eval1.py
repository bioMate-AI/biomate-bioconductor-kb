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
import os
import random
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

# Reproducibility: seed all stdlib + numpy + torch RNGs at module load so any
# tool downstream that uses a non-seeded RNG is bound to a fixed seed.
# Also set PYTHONHASHSEED so dict/set iteration order is stable across Python
# processes (otherwise Python uses a random hash seed per interpreter start).
_EVAL_SEED = int(os.environ.get("BIOMATE_EVAL_SEED", "42"))
os.environ.setdefault("PYTHONHASHSEED", str(_EVAL_SEED))
random.seed(_EVAL_SEED)
try:
    import numpy as _np
    _np.random.seed(_EVAL_SEED)
except ImportError:
    pass
try:
    import torch as _torch
    _torch.manual_seed(_EVAL_SEED)
    if _torch.cuda.is_available():
        _torch.cuda.manual_seed_all(_EVAL_SEED)
except ImportError:
    pass

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
    parser.add_argument("--workers", type=int, default=None,
                        help="Override max_parallel_tasks from config (e.g. 16)")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")
    if args.workers:
        config.setdefault("concurrency", {})["max_parallel_tasks"] = args.workers

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

    completed = [0]

    def _on_result(r):
        store.save_one(run_id, r)
        completed[0] += 1
        task_name = r.metadata.get("task_name", "?")
        status = "✓" if r.score >= 1.0 else ("~" if r.score > 0 else "✗")
        err = f" [ERR: {r.error[:40]}]" if r.error else ""
        print(f"  [{completed[0]:>3}/{len(tasks)}] {status} {task_name:<38} "
              f"score={r.score:.2f}  {r.latency_sec:.0f}s{err}", flush=True)

    t0 = time.time()
    results = adapter.run_tasks(client, tasks, on_result=_on_result)
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

    # 5-Dimension summary
    from evaluation.core.five_dimension_reporter import FiveDimensionReporter
    reporter = FiveDimensionReporter(store)
    report = reporter.compute(run_id)
    print(reporter.render_table([report]))


if __name__ == "__main__":
    main()
