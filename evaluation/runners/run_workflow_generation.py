#!/usr/bin/env python3
"""
run_workflow_generation.py — Run the BioMate Workflow Generation benchmark.

Tests two capabilities:
  Partition A (20 tasks): routing accuracy — BioMate should return an existing
    workflow (template_reuse or template_adapt) for common in-catalog analysis types.
  Partition B (20 tasks): generation quality — BioMate must produce correct
    Nextflow DSL2 code from scratch for novel, out-of-catalog analysis requests.

Scoring:
  Partition A — 0.0–1.0 (0.5 for correct source, 0.5 for category keyword match)
  Partition B — 0.0–1.0 (LLM judge: tool_correctness + process_ordering +
                param_completeness, averaged; −0.1 each for missing DSL2 /
                workflow block; keyword fallback when judge unavailable)

Usage:
    python runners/run_workflow_generation.py
    python runners/run_workflow_generation.py --partition A
    python runners/run_workflow_generation.py --partition B --max-tasks 5
    python runners/run_workflow_generation.py --dry-run
    python runners/run_workflow_generation.py --output results/wf_gen/ --workers 2
"""

import argparse
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters.workflow_generation_adapter import WorkflowGenerationAdapter


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Workflow Generation benchmark runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--output", default="results/workflow_generation/",
        help="Directory for results DB and JSON summary (default: results/workflow_generation/)",
    )
    parser.add_argument(
        "--config", default="config.yaml",
        help="Path to evaluation config YAML (relative to evaluation/ directory)",
    )
    parser.add_argument(
        "--partition", choices=["A", "B", "all"], default="all",
        help="Run only partition A, B, or both (default: all)",
    )
    parser.add_argument(
        "--max-tasks", type=int, default=None,
        help="Limit total number of tasks to run (applied after partition filter)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print task breakdown without contacting BioMate",
    )
    parser.add_argument(
        "--workers", type=int, default=4,
        help="Parallel worker threads (default: 4; lower is safer — generation is slow)",
    )
    args = parser.parse_args()

    # ── Load config ────────────────────────────────────────────────────────
    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as fh:
        config = yaml.safe_load(fh)

    # Inject partition filter into config so adapter honours it
    if args.partition != "all":
        config.setdefault("workflow_generation", {})["partition_filter"] = args.partition

    # Inject worker count into concurrency config
    config.setdefault("concurrency", {})["max_parallel_tasks"] = args.workers

    # ── Prepare output directory ───────────────────────────────────────────
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    # ── Load tasks ─────────────────────────────────────────────────────────
    adapter = WorkflowGenerationAdapter(config)
    tasks = adapter.load_tasks()

    if args.max_tasks:
        tasks = tasks[: args.max_tasks]

    # ── Dry-run mode ───────────────────────────────────────────────────────
    if args.dry_run:
        by_partition: dict[str, int] = {}
        by_difficulty: dict[str, int] = {}
        for t in tasks:
            part = t.metadata.get("partition", "?")
            diff = t.difficulty
            by_partition[part] = by_partition.get(part, 0) + 1
            by_difficulty[diff] = by_difficulty.get(diff, 0) + 1

        print(f"Workflow Generation Benchmark — {len(tasks)} tasks would run:")
        print(f"  Partition filter : {args.partition}")
        print(f"  Workers          : {args.workers}")
        print()
        print("  By partition:")
        for p, n in sorted(by_partition.items()):
            print(f"    Partition {p}: {n}")
        print("  By difficulty:")
        for d, n in sorted(by_difficulty.items()):
            print(f"    {d}: {n}")
        print()
        print("  Task list:")
        for t in tasks:
            print(
                f"    [{t.task_id}] part={t.metadata['partition']} "
                f"diff={t.difficulty}  {t.metadata['intent'][:70]}"
            )
        return

    # ── Banner ─────────────────────────────────────────────────────────────
    print("Workflow Generation Benchmark")
    print(f"  Tasks     : {len(tasks)}")
    print(f"  Partition : {args.partition}")
    print(f"  Workers   : {args.workers}")
    print(f"  Output    : {args.output}")
    print()

    # ── Connect to BioMate ─────────────────────────────────────────────────
    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run(
        "workflow_generation",
        suite="standalone",
        config=config,
    )

    # ── Execute tasks in parallel ─────────────────────────────────────────
    t0_total = time.time()
    all_results = []

    # We call the adapter's _run_one logic directly so we can print progress.
    # Re-use the adapter's internal _score_full() through a thin wrapper that
    # mirrors what the overridden run() does — but drives it here so we can
    # print per-task progress in-order.
    completed_count = 0
    total = len(tasks)

    def _run_task(task):
        t0 = time.time()
        error: Optional[str] = None
        response_text = ""
        workflow_card = None

        try:
            response = client.ask(adapter.task_prompt(task))
            response_text = response.text
            workflow_card = response.workflow_card
        except Exception as exc:
            error = str(exc)

        score = 0.0
        extra_meta: dict = {}
        if not error:
            try:
                score, extra_meta = adapter._score_full(task, response_text, workflow_card)
            except Exception as exc:
                error = f"scoring error: {exc}"

        from evaluation.core.base_adapter import BenchmarkResult
        return BenchmarkResult(
            task_id=task.task_id,
            benchmark="workflow_generation",
            score=score,
            agent_response=response_text[:2000],
            ground_truth=task.ground_truth,
            latency_sec=time.time() - t0,
            metadata={**task.metadata, **extra_meta},
            error=error,
        )

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(_run_task, t): t for t in tasks}
        for future in as_completed(futures):
            result = future.result()
            all_results.append(result)
            completed_count += 1

            part = result.metadata.get("partition", "?")
            indicator = (
                "✓" if result.score >= 0.75 else ("~" if result.score >= 0.4 else "✗")
            )
            err_suffix = f"  ERR: {result.error[:60]}" if result.error else ""
            print(
                f"  [{completed_count:>2}/{total}] {result.task_id} (part={part})"
                f"  {indicator} score={result.score:.2f}"
                f"  ({result.latency_sec:.0f}s){err_suffix}"
            )

    store.save(run_id, all_results)
    store.finish_run(run_id)
    elapsed_total = time.time() - t0_total

    # ── Summary ────────────────────────────────────────────────────────────
    n = len(all_results)
    mean_overall = sum(r.score for r in all_results) / n if n else 0.0
    errors = sum(1 for r in all_results if r.error)

    # Partition-level breakdown
    part_scores: dict[str, list[float]] = {}
    for r in all_results:
        part = r.metadata.get("partition", "?") if isinstance(r.metadata, dict) else "?"
        part_scores.setdefault(part, []).append(r.score)

    # Category breakdown (Partition A only)
    cat_scores: dict[str, list[float]] = {}
    for r in all_results:
        if isinstance(r.metadata, dict) and r.metadata.get("partition") == "A":
            cat = r.metadata.get("expected_category", "unknown")
            cat_scores.setdefault(cat, []).append(r.score)

    # Difficulty breakdown
    diff_scores: dict[str, list[float]] = {}
    for r in all_results:
        diff = r.metadata.get("difficulty", r.task_id) if isinstance(r.metadata, dict) else "unknown"
        diff_scores.setdefault(diff, []).append(r.score)

    print()
    print("=" * 60)
    print("Workflow Generation Benchmark — Results")
    print("=" * 60)
    print(f"  Overall : n={n}  mean={mean_overall:.3f}  errors={errors}  elapsed={elapsed_total:.0f}s")
    print()

    print(f"  {'Partition':<12} {'N':>4} {'Mean':>7}")
    print(f"  {'-' * 24}")
    for part, scores in sorted(part_scores.items()):
        pm = sum(scores) / len(scores) if scores else 0.0
        label = f"Partition {part}"
        print(f"  {label:<12} {len(scores):>4} {pm:>7.3f}")

    if cat_scores:
        print()
        print(f"  {'Category (A)':<28} {'N':>4} {'Mean':>7}")
        print(f"  {'-' * 40}")
        for cat, scores in sorted(cat_scores.items()):
            cm = sum(scores) / len(scores) if scores else 0.0
            print(f"  {cat:<28} {len(scores):>4} {cm:>7.3f}")

    print()
    print(f"  {'Difficulty':<15} {'N':>4} {'Mean':>7}")
    print(f"  {'-' * 27}")
    for diff, scores in sorted(diff_scores.items()):
        dm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {diff:<15} {len(scores):>4} {dm:>7.3f}")

    print()
    print(f"  Results saved to: {config['paths']['results_db']}")

    # Per-task failure detail
    failures = [r for r in all_results if r.score < 0.5]
    if failures:
        print(f"\n  Failures ({len(failures)}):")
        for r in sorted(failures, key=lambda x: x.task_id):
            intent = r.metadata.get("intent", "")[:65] if isinstance(r.metadata, dict) else ""
            print(f"    [{r.task_id}] score={r.score:.2f}  {intent}")
            if r.error:
                print(f"      error: {r.error[:80]}")


if __name__ == "__main__":
    main()
