#!/usr/bin/env python3
"""
run_protocol_to_workflow.py — Protocol-to-Workflow Benchmark runner.

Tests BioMate's ability to read a bioinformatics methods section (or lab SOP)
and translate it into an executable workflow with correctly filled parameters.

Scoring (three dimensions):
  routing_accuracy       40 %  — did BioMate pick the right workflow?
  param_extraction       40 %  — did it extract the right parameter values?
  clarification_handling 20 %  — for ambiguous protocols, did it ask correctly?

Dataset: evaluation/datasets/protocol_to_workflow/cases.yaml
  35 cases:
    - 20 published_methods
    - 10 lab_sop
    - 5  ambiguous

Usage:
    python runners/run_protocol_to_workflow.py
    python runners/run_protocol_to_workflow.py --source-type published_methods
    python runners/run_protocol_to_workflow.py --source-type ambiguous
    python runners/run_protocol_to_workflow.py --max-tasks 10 --dry-run
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters.protocol_to_workflow_adapter import ProtocolToWorkflowAdapter

SOURCE_TYPES = ["published_methods", "lab_sop", "ambiguous", "all"]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Protocol-to-Workflow Benchmark runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--output",
        default="results/protocol_to_workflow/",
        help="Directory for result DB and logs (default: results/protocol_to_workflow/)",
    )
    parser.add_argument(
        "--config",
        default="config.yaml",
        help="Path to config.yaml relative to the evaluation/ directory",
    )
    parser.add_argument(
        "--max-tasks",
        type=int,
        default=None,
        metavar="N",
        help="Run at most N tasks (useful for quick smoke tests)",
    )
    parser.add_argument(
        "--source-type",
        choices=SOURCE_TYPES,
        default="all",
        help="Filter cases by source_type (default: all)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print task breakdown without running any API calls",
    )
    args = parser.parse_args()

    # ------------------------------------------------------------------
    # Load config
    # ------------------------------------------------------------------
    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    # ------------------------------------------------------------------
    # Load tasks and apply filters
    # ------------------------------------------------------------------
    adapter = ProtocolToWorkflowAdapter(config)
    all_tasks = adapter.load_tasks()

    source_filter = args.source_type if args.source_type != "all" else None
    if source_filter:
        tasks = [t for t in all_tasks if t.metadata.get("source_type") == source_filter]
    else:
        tasks = all_tasks

    if args.max_tasks:
        tasks = tasks[: args.max_tasks]

    # ------------------------------------------------------------------
    # Dry-run: just show breakdown
    # ------------------------------------------------------------------
    if args.dry_run:
        by_source: dict[str, int] = {}
        by_domain: dict[str, int] = {}
        ambiguous_with_null_wf = 0
        for t in tasks:
            src = t.metadata.get("source_type", "unknown")
            dom = t.metadata.get("domain", "unknown")
            by_source[src] = by_source.get(src, 0) + 1
            by_domain[dom] = by_domain.get(dom, 0) + 1
            if t.metadata.get("expected_workflow") is None:
                ambiguous_with_null_wf += 1

        print(f"Protocol-to-Workflow Benchmark — {len(tasks)} tasks would run")
        print(f"  Source filter: {args.source_type}")
        print()
        print("  By source_type:")
        for src, n in sorted(by_source.items()):
            print(f"    {src:<22} {n}")
        print()
        print("  By domain:")
        for dom, n in sorted(by_domain.items()):
            print(f"    {dom:<22} {n}")
        if ambiguous_with_null_wf:
            print()
            print(f"  Fully ambiguous (expected_workflow=null): {ambiguous_with_null_wf}")
        return

    # ------------------------------------------------------------------
    # Run
    # ------------------------------------------------------------------
    print("Protocol-to-Workflow Benchmark")
    print(f"  Tasks:       {len(tasks)}")
    print(f"  Source:      {args.source_type}")
    print(f"  Output:      {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run(
        "protocol_to_workflow",
        suite="standalone",
        config=config,
    )

    t0 = time.time()
    results = adapter.run(
        client,
        max_tasks=len(tasks),
        source_type=source_filter,
    )
    store.save(run_id, results)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    n = len(results)
    if n == 0:
        print("No results to display.")
        return

    mean_overall = sum(r.score for r in results) / n
    errors = sum(1 for r in results if r.error)

    # Per-dimension means
    def _dim_mean(key: str) -> float:
        vals = [r.metadata.get(key, 0.0) for r in results if isinstance(r.metadata, dict)]
        return sum(vals) / len(vals) if vals else 0.0

    routing_mean = _dim_mean("routing_score")
    param_mean = _dim_mean("param_score")
    clarif_mean = _dim_mean("clarification_score")

    # Per-source breakdown
    by_source: dict[str, list[float]] = {}
    for r in results:
        src = r.metadata.get("source_type", "unknown") if isinstance(r.metadata, dict) else "unknown"
        by_source.setdefault(src, []).append(r.score)

    # Per-domain breakdown
    by_domain: dict[str, list[float]] = {}
    for r in results:
        dom = r.metadata.get("domain", "unknown") if isinstance(r.metadata, dict) else "unknown"
        by_domain.setdefault(dom, []).append(r.score)

    print()
    print("=" * 60)
    print("Protocol-to-Workflow Benchmark Results")
    print("=" * 60)
    print(f"  n={n}  mean={mean_overall:.3f}  errors={errors}  elapsed={elapsed:.0f}s")
    print()
    print("  Dimension scores (weighted contribution):")
    print(f"    routing_accuracy       (40%)  {routing_mean:.3f}")
    print(f"    param_extraction       (40%)  {param_mean:.3f}")
    print(f"    clarification_handling (20%)  {clarif_mean:.3f}")

    print()
    print(f"  {'Source type':<25} {'N':>4} {'Mean':>7}")
    print(f"  {'-' * 37}")
    for src, scores in sorted(by_source.items()):
        sm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {src:<25} {len(scores):>4} {sm:>7.3f}")

    print()
    print(f"  {'Domain':<25} {'N':>4} {'Mean':>7}")
    print(f"  {'-' * 37}")
    for dom, scores in sorted(by_domain.items()):
        dm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {dom:<25} {len(scores):>4} {dm:>7.3f}")

    # Per-task detail for failures
    failures = sorted(
        [r for r in results if r.score < 0.5],
        key=lambda r: r.score,
    )
    if failures:
        print()
        print(f"  Failures ({len(failures)} / {n} below 0.5):")
        for r in failures:
            expected_wf = r.metadata.get("expected_workflow", "?")
            route = r.metadata.get("routing_score", 0.0)
            param = r.metadata.get("param_score", 0.0)
            clarif = r.metadata.get("clarification_score", 0.0)
            err_tag = f" [ERROR: {r.error[:60]}]" if r.error else ""
            print(
                f"    [{r.task_id}] total={r.score:.2f}"
                f"  route={route:.2f} param={param:.2f} clarif={clarif:.2f}"
                f"  expected={expected_wf}{err_tag}"
            )

    print()
    print(f"  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
