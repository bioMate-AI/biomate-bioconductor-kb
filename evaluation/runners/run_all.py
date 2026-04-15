#!/usr/bin/env python3
"""
run_all.py — Master evaluation runner.

Usage:
    python runners/run_all.py --suite p0 --output results/
    python runners/run_all.py --suite all --output results/ --max-tasks 20
    python runners/run_all.py --benchmark biomni_eval1 --output results/

Suites are defined in config.yaml.
"""

import argparse
import os
import sys
import time
from pathlib import Path

import yaml

# Make evaluation/ importable
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import (
    BiomniEval1Adapter,
    SGIBenchRunner,
    BixBenchAdapter,
    RoutingBenchmarkAdapter,
    PrereqRecoveryAdapter,
    LicenseGatingAdapter,
    BioAgentBenchAdapter,
    SciAgentBenchAdapter,
    PharmaBenchAdapter,
    ProtocolThresholdsAdapter,
    AutofixBenchmarkAdapter,
    MemoryBenchmarkAdapter,
)


ADAPTER_REGISTRY = {
    "biomni_eval1":         BiomniEval1Adapter,
    "sgi_bench":            SGIBenchRunner,
    "bixbench":             BixBenchAdapter,
    "cross_domain_routing": RoutingBenchmarkAdapter,
    "prereq_recovery":      PrereqRecoveryAdapter,
    "license_gating":       LicenseGatingAdapter,
    "bioagentbench":        BioAgentBenchAdapter,
    "sciagentbench":        SciAgentBenchAdapter,
    "pharmabench":          PharmaBenchAdapter,
    "protocol_thresholds":  ProtocolThresholdsAdapter,
    "autofix_benchmark":    AutofixBenchmarkAdapter,
    "memory_benchmark":     MemoryBenchmarkAdapter,
}


def load_config(config_path: str = "config.yaml") -> dict:
    with open(config_path) as f:
        return yaml.safe_load(f)


def run_benchmark(name: str, config: dict, client: BioMateEvalClient,
                  store: ResultsStore, max_tasks: int | None = None) -> dict:
    cls = ADAPTER_REGISTRY.get(name)
    if not cls:
        print(f"  [SKIP] {name}: no adapter registered")
        return {}

    print(f"\n{'='*60}")
    print(f"  Running: {name}")
    print(f"{'='*60}")

    adapter = cls(config)
    run_id = store.start_run(name, suite="manual", config=config)

    t0 = time.time()
    try:
        results = adapter.run(client, max_tasks=max_tasks)
        store.save(run_id, results)
        store.finish_run(run_id)
    except Exception as exc:
        print(f"  [ERROR] {name} failed: {exc}")
        import traceback; traceback.print_exc()
        return {}

    elapsed = time.time() - t0
    summary = store.summary(run_id)
    bench_summary = summary.get(name, {})
    n = bench_summary.get("n", len(results))
    mean = bench_summary.get("mean", 0.0)
    errors = bench_summary.get("error_count", 0)

    print(f"\n  Results: {name}")
    print(f"    n={n}  mean={mean:.3f}  errors={errors}  elapsed={elapsed:.0f}s")
    return {"benchmark": name, "run_id": run_id, "n": n, "mean": mean, "elapsed": elapsed}


def main():
    parser = argparse.ArgumentParser(description="BioMate Evaluation Runner")
    parser.add_argument("--suite", default="p0",
                        help="Suite name from config.yaml (p0/p1/p2/all/datasets_only)")
    parser.add_argument("--benchmark", help="Run a single benchmark by name")
    parser.add_argument("--output", default="results/", help="Results directory")
    parser.add_argument("--config", default="config.yaml", help="Config file path")
    parser.add_argument("--max-tasks", type=int, default=None,
                        help="Limit tasks per benchmark (for quick testing)")
    parser.add_argument("--dry-run", action="store_true",
                        help="List tasks that would run without executing them")
    args = parser.parse_args()

    # Load config
    config_path = Path(__file__).parent.parent / args.config
    config = load_config(str(config_path))

    # Override results path
    config["paths"]["results_db"] = str(Path(args.output) / "eval_results.db")
    Path(args.output).mkdir(parents=True, exist_ok=True)

    # Determine which benchmarks to run
    if args.benchmark:
        benchmarks = [args.benchmark]
    else:
        benchmarks = config["suites"].get(args.suite, [])
        if not benchmarks:
            print(f"Unknown suite: {args.suite}")
            print(f"Available suites: {list(config['suites'].keys())}")
            sys.exit(1)

    print(f"\nBioMate Evaluation Harness")
    print(f"  Suite:      {args.suite}")
    print(f"  Benchmarks: {benchmarks}")
    print(f"  Max tasks:  {args.max_tasks or 'unlimited'}")
    print(f"  Output:     {args.output}")

    if args.dry_run:
        print("\n[DRY RUN] Would run:")
        for b in benchmarks:
            cls = ADAPTER_REGISTRY.get(b)
            if cls:
                try:
                    adapter = cls(config)
                    tasks = adapter.load_tasks()
                    n = min(len(tasks), args.max_tasks or len(tasks))
                    print(f"  {b}: {n} tasks")
                except Exception as e:
                    print(f"  {b}: [ERROR loading tasks] {e}")
            else:
                print(f"  {b}: [NO ADAPTER]")
        return

    # Create client and store
    print("\nConnecting to BioMate...")
    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])

    # Run all benchmarks
    all_summaries = []
    for bench_name in benchmarks:
        summary = run_benchmark(bench_name, config, client, store, args.max_tasks)
        if summary:
            all_summaries.append(summary)

    # Final summary table
    if all_summaries:
        print(f"\n{'='*60}")
        print("FINAL SUMMARY")
        print(f"{'='*60}")
        print(f"{'Benchmark':<30} {'N':>6} {'Mean':>8} {'Time':>8}")
        print("-" * 55)
        for s in all_summaries:
            print(f"{s['benchmark']:<30} {s['n']:>6} {s['mean']:>8.3f} {s['elapsed']:>7.0f}s")

    print(f"\nResults saved to: {config['paths']['results_db']}")
    print("Run generate_report.py to produce the competitive markdown report.")


if __name__ == "__main__":
    main()
