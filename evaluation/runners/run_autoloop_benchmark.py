#!/usr/bin/env python3
"""
run_autoloop_benchmark.py — Auto-loop QC convergence benchmark.

Measures BioMate's ability to autonomously remediate failing compounds/protocols
through repeated QC-evaluate → tune-params → re-run cycles until all gates pass.

Runs entirely locally against the orchestrator (no HTTP requests) — fast, deterministic.

Usage:
    python runners/run_autoloop_benchmark.py
    python runners/run_autoloop_benchmark.py --domains ADMET CYP_DDI
    python runners/run_autoloop_benchmark.py --max-per-domain 5 --dry-run
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.adapters.autoloop_benchmark_adapter import AutoLoopBenchmarkAdapter

ALL_DOMAINS = ["ADMET", "CYP_DDI", "Docking", "NCA_PK"]


def main():
    parser = argparse.ArgumentParser(description="Auto-loop QC convergence benchmark")
    parser.add_argument("--output", default="results/autoloop/", help="Output directory")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--domains", nargs="+", default=None,
                        help=f"Domains to run (default: all). Options: {ALL_DOMAINS}")
    parser.add_argument("--max-per-domain", type=int, default=None,
                        help="Max tasks per domain (default: all)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    domains = args.domains or ALL_DOMAINS

    adapter = AutoLoopBenchmarkAdapter(
        config,
        domains=domains,
        max_per_domain=args.max_per_domain,
    )
    tasks = adapter.load_tasks()

    if args.dry_run:
        print(f"Auto-loop benchmark — {len(tasks)} tasks would run:")
        by_domain: dict = {}
        for t in tasks:
            d = t.metadata.get("domain", "?")
            by_domain[d] = by_domain.get(d, 0) + 1
        for d, n in sorted(by_domain.items()):
            print(f"  {d}: {n} tasks")
        print(f"\nSample: {tasks[0].task_id}")
        print(f"  {tasks[0].question}")
        return

    print("Auto-loop QC Convergence Benchmark")
    print(f"  Domains: {domains}")
    print(f"  Tasks:   {len(tasks)}")
    print()

    completed = [0]

    def _on_result(r):
        completed[0] += 1
        domain = r.metadata.get("domain", "?")
        gate = r.metadata.get("gate_type", "?")
        loop_res = r.metadata.get("loop_result", {})
        iters = loop_res.get("iterations", "?")
        status = "✓" if r.score >= 0.8 else ("~" if r.score >= 0.5 else "✗")
        err = f" [ERR: {r.error[:40]}]" if r.error else ""
        print(f"  [{completed[0]:>3}/{len(tasks)}] {status} {domain:<10} {gate:<16} "
              f"score={r.score:.1f}  iters={iters}  {r.latency_sec:.1f}s{err}",
              flush=True)

    t0 = time.time()
    results = adapter.run_tasks(None, tasks, on_result=_on_result)
    elapsed = time.time() - t0

    # Aggregate
    by_domain: dict[str, list] = {}
    for r in results:
        d = r.metadata.get("domain", "unknown")
        by_domain.setdefault(d, []).append(r)

    n_total = len(results)
    overall_score = sum(r.score for r in results) / max(n_total, 1)
    n_converged = sum(1 for r in results if r.score >= 0.8)
    n_passatone = sum(1 for r in results if r.score >= 1.0)

    print(f"\n{'='*60}")
    print(f"Auto-loop QC Benchmark Results")
    print(f"{'='*60}")
    print(f"  Overall:       n={n_total}  mean_score={overall_score:.3f}  elapsed={elapsed:.0f}s")
    print(f"  Gate-pass@1:   {n_passatone}/{n_total} = {n_passatone/max(n_total,1):.1%}")
    print(f"  Convergence≤3: {n_converged}/{n_total} = {n_converged/max(n_total,1):.1%}")
    print()
    print(f"  {'Domain':<12} {'N':>4} {'Score':>7} {'Pass@1':>7} {'Conv≤3':>7}")
    print(f"  {'-'*44}")
    for domain, domain_results in sorted(by_domain.items()):
        n = len(domain_results)
        sc = sum(r.score for r in domain_results) / n
        p1 = sum(1 for r in domain_results if r.score >= 1.0)
        c3 = sum(1 for r in domain_results if r.score >= 0.8)
        print(f"  {domain:<12} {n:>4} {sc:>7.3f} {p1/n:>7.1%} {c3/n:>7.1%}")

    # Save results CSV
    results_csv = output_dir / "autoloop_results.csv"
    with open(results_csv, "w") as f:
        f.write("task_id,domain,gate_type,score,iterations,escalated,expected_convergence\n")
        for r in results:
            loop_res = r.metadata.get("loop_result", {})
            f.write(f"{r.task_id},"
                    f"{r.metadata.get('domain','')},"
                    f"{r.metadata.get('gate_type','')},"
                    f"{r.score},"
                    f"{loop_res.get('iterations','?')},"
                    f"{loop_res.get('escalated','')},"
                    f"{r.metadata.get('expected_convergence','')}\n")
    print(f"\n  Results saved to: {results_csv}")


if __name__ == "__main__":
    main()
