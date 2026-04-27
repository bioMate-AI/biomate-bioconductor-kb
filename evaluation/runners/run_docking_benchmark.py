#!/usr/bin/env python3
"""
run_docking_benchmark.py — B2 Docking Triage benchmark runner.

Tests BioMate's ability to:
  - Route docking queries to the correct workflow (Type A: complete queries)
  - Detect missing prerequisites and ask for them (Type B: incomplete queries)
  - Reject ADMET queries from docking routing (Type C: negative cases)

Dataset: datasets/drug_discovery_e2e/pdb_systems.yaml (15 systems × 3 tasks = 45 total)

Usage:
    python runners/run_docking_benchmark.py
    python runners/run_docking_benchmark.py --max-tasks 9  # 3 systems
    python runners/run_docking_benchmark.py --query-type A  # only Type A tasks
    python runners/run_docking_benchmark.py --dry-run
    python runners/run_docking_benchmark.py --output results/docking_benchmark_v1/
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters.docking_benchmark_adapter import DockingBenchmarkAdapter


def main():
    parser = argparse.ArgumentParser(description="B2 Docking Triage benchmark runner")
    parser.add_argument(
        "--output",
        default="results/docking_benchmark_v1/",
        help="Output directory for eval_results.db",
    )
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument(
        "--max-tasks",
        type=int,
        default=None,
        metavar="N",
        help="Limit to first N tasks (default: all 45)",
    )
    parser.add_argument(
        "--query-type",
        choices=["A", "B", "C", "all"],
        default="all",
        help="Filter to one task type (A=complete, B=incomplete, C=negative)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List tasks without running them",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=None,
        help="Override max_parallel_tasks from config",
    )
    args = parser.parse_args()

    eval_root = Path(__file__).parent.parent
    config_path = eval_root / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config.setdefault("paths", {})
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    if args.workers:
        config.setdefault("concurrency", {})["max_parallel_tasks"] = args.workers

    adapter = DockingBenchmarkAdapter(config)
    all_tasks = adapter.load_tasks()

    # Filter by query type
    if args.query_type != "all":
        suffix = f"_type{args.query_type}"
        all_tasks = [t for t in all_tasks if t.task_id.endswith(suffix)]

    if args.max_tasks:
        all_tasks = all_tasks[: args.max_tasks]

    # ── Dry run ──────────────────────────────────────────────────────────────
    if args.dry_run:
        by_type: dict[str, int] = {}
        for t in all_tasks:
            qt = t.metadata.get("query_type", "?")
            by_type[qt] = by_type.get(qt, 0) + 1

        print("Docking Benchmark — DRY RUN")
        print(f"  {len(all_tasks)} tasks would run (type={args.query_type}):\n")
        print(f"  {'Query Type':<15} {'N':>4}")
        print(f"  {'-'*20}")
        for qt, n in sorted(by_type.items()):
            print(f"  {qt:<15} {n:>4}")
        print("\n  First 5 tasks:")
        for t in all_tasks[:5]:
            print(f"    [{t.task_id}] {t.question[:80]}...")
        return

    # ── Live run ─────────────────────────────────────────────────────────────
    print("Docking Benchmark (B2 Docking Triage)")
    print(f"  Tasks:      {len(all_tasks)}")
    print(f"  Query type: {args.query_type}")
    print(f"  Output:     {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("docking_benchmark", suite="standalone", config=config)

    completed = [0]

    def _on_result(r):
        store.save_one(run_id, r)
        completed[0] += 1
        qt = r.metadata.get("query_type", "?")
        status = "✓" if r.score >= 1.0 else ("~" if r.score > 0 else "✗")
        err = f" [ERR: {r.error[:40]}]" if r.error else ""
        print(
            f"  [{completed[0]:>3}/{len(all_tasks)}] {status} [{qt}] {r.task_id:<22} "
            f"score={r.score:.2f}  {r.latency_sec:.0f}s{err}",
            flush=True,
        )

    t0 = time.time()
    results = adapter.run_tasks(client, all_tasks, on_result=_on_result)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    # ── Summary ──────────────────────────────────────────────────────────────
    n = len(results)
    mean = sum(r.score for r in results) / n if n else 0.0
    errors = sum(1 for r in results if r.error)

    by_qt: dict[str, list[float]] = {}
    for r in results:
        qt = r.metadata.get("query_type", "?") if isinstance(r.metadata, dict) else "?"
        by_qt.setdefault(qt, []).append(r.score)

    print(f"\n{'='*60}")
    print("Docking Benchmark (B2) Results")
    print(f"{'='*60}")
    print(f"  Overall:  n={n}  mean={mean:.3f}  errors={errors}  elapsed={elapsed:.0f}s\n")

    print(f"  {'Query Type':<15} {'N':>4} {'Mean':>8} {'Description'}")
    print(f"  {'-'*60}")
    type_desc = {
        "complete":   "Complete query (PDB + SMILES) → route to docking",
        "incomplete": "Incomplete query (no PDB) → ask for prereq",
        "negative":   "ADMET query → must NOT route to docking",
    }
    for qt, scores in sorted(by_qt.items()):
        qm = sum(scores) / len(scores) if scores else 0.0
        desc = type_desc.get(qt, "")
        print(f"  {qt:<15} {len(scores):>4} {qm:>8.3f}  {desc}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")

    # Grade
    if mean >= 0.80:
        grade = "PASS"
    elif mean >= 0.60:
        grade = "MARGINAL"
    else:
        grade = "FAIL"
    print(f"\n  Grade: {grade}  (mean={mean:.1%}, threshold=80%)")


if __name__ == "__main__":
    main()
