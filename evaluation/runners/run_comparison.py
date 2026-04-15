#!/usr/bin/env python3
"""
run_comparison.py — BioMate vs Raw LLM baseline comparison runner.

Runs a selected benchmark twice — once with BioMateEvalClient, once with
BaselineLLMClient — and produces a side-by-side comparison table.

Supported benchmarks:
    autofix          — error diagnosis + fix planning (20 tasks)
    param_prefill    — parameter inference from natural language query (30 tasks)
    protocol_to_workflow — protocol text → workflow + params (15 tasks)
    sgi_bench        — SGI-Bench life-science subset (503 tasks, use --max-tasks)

Usage:
    cd /home/yzhang/biomate/evaluation
    python runners/run_comparison.py --benchmark autofix --max-tasks 20
    python runners/run_comparison.py --benchmark sgi_bench --max-tasks 50
    python runners/run_comparison.py --benchmark autofix --dry-run
    python runners/run_comparison.py --benchmark param_prefill --max-tasks 10 --skip-biomate
    python runners/run_comparison.py --benchmark autofix --max-tasks 5 --baseline-model claude-haiku-4-5-20251001
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import yaml

# Allow running from the evaluation/ directory or the repo root
_eval_dir = Path(__file__).parent.parent
_repo_root = _eval_dir.parent
for _p in [str(_eval_dir.parent), str(_eval_dir)]:
    if _p not in sys.path:
        sys.path.insert(0, _p)

from evaluation.core import BioMateEvalClient, BenchmarkResult
from evaluation.core.baseline_llm_client import BaselineLLMClient

# ---------------------------------------------------------------------------
# Benchmark registry
# ---------------------------------------------------------------------------

SUPPORTED_BENCHMARKS = ["autofix", "param_prefill", "protocol_to_workflow", "sgi_bench"]

_BENCHMARK_DISPLAY = {
    "autofix": "autofix_benchmark",
    "param_prefill": "param_prefill",
    "protocol_to_workflow": "protocol_to_workflow",
    "sgi_bench": "sgi_bench_life",
}

# Benchmarks where the adapter calls BioMate-specific endpoints in prepare()
# and cannot use a generic chat client directly. The comparison runner uses
# chat-based scoring for the baseline on these.
_BIOMATE_SPECIFIC_PREPARE = {"param_prefill"}


def _load_adapter(benchmark: str, config: dict):
    """Instantiate and return the appropriate adapter."""
    if benchmark == "autofix":
        from evaluation.adapters.autofix_benchmark_adapter import AutofixBenchmarkAdapter
        return AutofixBenchmarkAdapter(config)
    elif benchmark == "param_prefill":
        from evaluation.adapters.param_prefill_adapter import ParamPrefillAdapter
        return ParamPrefillAdapter(config)
    elif benchmark == "protocol_to_workflow":
        from evaluation.adapters.protocol_to_workflow_adapter import ProtocolToWorkflowAdapter
        return ProtocolToWorkflowAdapter(config)
    elif benchmark == "sgi_bench":
        from evaluation.adapters.sgi_bench_runner import SGIBenchRunner
        return SGIBenchRunner(config)
    else:
        raise ValueError(f"Unknown benchmark: {benchmark!r}. Choose from: {SUPPORTED_BENCHMARKS}")


# ---------------------------------------------------------------------------
# Baseline run for param_prefill
# ---------------------------------------------------------------------------

def _run_param_prefill_baseline(
    adapter,
    baseline_client: BaselineLLMClient,
    tasks,
) -> List[BenchmarkResult]:
    """
    ParamPrefillAdapter uses a BioMate-specific REST endpoint; the baseline
    client has no such endpoint. We instead ask the LLM to output the
    parameters as JSON and score using the same _compute_score logic.
    """
    import time as _time

    _PARAM_EXTRACT_PROMPT = """\
You are an expert bioinformatics parameter advisor. Given the following user
query describing a bioinformatics analysis, extract the workflow parameters
that can be inferred directly from the text.

USER QUERY:
{query}

Respond with ONLY a JSON object mapping parameter names to values.
For example: {{"genome": "GRCh38", "strandedness": "reverse", "max_reads": 5000000}}
If no parameters can be inferred, respond with: {{}}
"""

    results = []
    for i, task in enumerate(tasks):
        print(
            f"  [baseline {i+1}/{len(tasks)}] {task.task_id} ...",
            end=" ",
            flush=True,
        )
        t0 = _time.time()
        error = None
        score = 0.0
        agent_response = ""

        try:
            prompt = _PARAM_EXTRACT_PROMPT.format(query=task.question)
            resp = baseline_client.ask(prompt)
            agent_response = resp.text

            # Try to parse JSON from the response
            import re, json as _json
            json_match = re.search(r"\{[^{}]*\}", agent_response, re.DOTALL)
            generated: dict = {}
            if json_match:
                try:
                    generated = _json.loads(json_match.group())
                except Exception:
                    generated = {}

            expected = task.ground_truth if isinstance(task.ground_truth, dict) else {}
            must_not_fill = task.metadata.get("must_not_fill", [])
            score = adapter._compute_score(generated, expected, must_not_fill)

        except Exception as exc:
            error = str(exc)

        elapsed = _time.time() - t0
        indicator = "+" if score >= 0.75 else ("~" if score >= 0.4 else "-")
        print(f"{indicator} score={score:.2f} ({elapsed:.0f}s)")

        results.append(BenchmarkResult(
            task_id=task.task_id,
            benchmark="param_prefill",
            score=score,
            agent_response=agent_response[:2000],
            ground_truth=task.ground_truth,
            latency_sec=elapsed,
            metadata=task.metadata,
            error=error,
        ))

    return results


# ---------------------------------------------------------------------------
# Comparison statistics
# ---------------------------------------------------------------------------

def _mean(scores: List[float]) -> float:
    return sum(scores) / len(scores) if scores else 0.0


def _group_by_category(results: List[BenchmarkResult]) -> Dict[str, List[float]]:
    """Group scores by metadata category/task_type."""
    groups: Dict[str, List[float]] = {}
    for r in results:
        cat = "unknown"
        if isinstance(r.metadata, dict):
            cat = (
                r.metadata.get("category")
                or r.metadata.get("task_type")
                or r.metadata.get("discipline")
                or "unknown"
            )
        groups.setdefault(cat, []).append(r.score)
    return groups


def _print_comparison(
    benchmark: str,
    biomate_results: List[BenchmarkResult],
    baseline_results: List[BenchmarkResult],
    baseline_model: str,
) -> None:
    """Print the comparison summary table to stdout."""
    bm_scores = [r.score for r in biomate_results]
    bl_scores = [r.score for r in baseline_results]

    bm_mean = _mean(bm_scores)
    bl_mean = _mean(bl_scores)
    advantage_abs = bm_mean - bl_mean
    advantage_rel = (advantage_abs / bl_mean * 100) if bl_mean > 0 else float("inf")

    bm_groups = _group_by_category(biomate_results)
    bl_groups = _group_by_category(baseline_results)
    all_cats = sorted(set(bm_groups) | set(bl_groups))

    col_w = 32
    print()
    print(f"Comparison: {benchmark}")
    print(f"Tasks:      {len(biomate_results)} (BioMate) / {len(baseline_results)} (Baseline)")
    print()
    print(
        f"{'':28}  {'BioMate':>10}  {'Baseline (' + baseline_model + ')':>28}"
    )
    print(f"{'Overall mean:':28}  {bm_mean:>10.3f}  {bl_mean:>28.3f}")

    if all_cats:
        print()
        print("By category:")
        for cat in all_cats:
            bm_cat = _mean(bm_groups.get(cat, []))
            bl_cat = _mean(bl_groups.get(cat, []))
            print(f"  {cat:<26}  {bm_cat:>10.3f}  {bl_cat:>28.3f}")

    print()
    sign = "+" if advantage_abs >= 0 else ""
    if bl_mean > 0:
        print(
            f"BioMate advantage: {sign}{advantage_abs:.3f} (absolute), "
            f"{sign}{advantage_rel:.1f}% (relative)"
        )
    else:
        print("BioMate advantage: N/A (baseline mean = 0)")

    # Per-task table for small runs
    if len(biomate_results) <= 25:
        bl_by_id = {r.task_id: r for r in baseline_results}
        print()
        print(f"{'Task ID':<30}  {'BioMate':>8}  {'Baseline':>8}  {'Delta':>8}")
        print(f"  {'-'*60}")
        for r in sorted(biomate_results, key=lambda x: x.task_id):
            bl = bl_by_id.get(r.task_id)
            bl_score = bl.score if bl else float("nan")
            delta = r.score - bl_score if bl else float("nan")
            sign_d = "+" if delta >= 0 else ""
            print(
                f"  {r.task_id:<28}  {r.score:>8.3f}  {bl_score:>8.3f}  {sign_d}{delta:>7.3f}"
            )


# ---------------------------------------------------------------------------
# Save results
# ---------------------------------------------------------------------------

def _save_results(
    benchmark: str,
    biomate_results: List[BenchmarkResult],
    baseline_results: List[BenchmarkResult],
    baseline_model: str,
    output_dir: Path,
) -> Path:
    """Save comparison JSON to results/comparison/[benchmark]/[timestamp].json"""
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    out_path = output_dir / f"{ts}.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    def _serialise(results: List[BenchmarkResult]) -> List[dict]:
        out = []
        for r in results:
            out.append({
                "task_id": r.task_id,
                "benchmark": r.benchmark,
                "score": r.score,
                "agent_response": r.agent_response,
                "ground_truth": str(r.ground_truth)[:500],
                "latency_sec": round(r.latency_sec, 2),
                "metadata": r.metadata,
                "error": r.error,
                "timestamp": r.timestamp,
            })
        return out

    payload = {
        "benchmark": benchmark,
        "baseline_model": baseline_model,
        "timestamp": ts,
        "summary": {
            "biomate_mean": _mean([r.score for r in biomate_results]),
            "baseline_mean": _mean([r.score for r in baseline_results]),
            "n_biomate": len(biomate_results),
            "n_baseline": len(baseline_results),
        },
        "biomate_results": _serialise(biomate_results),
        "baseline_results": _serialise(baseline_results),
    }

    with open(out_path, "w") as f:
        json.dump(payload, f, indent=2, default=str)

    return out_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="BioMate vs raw LLM baseline comparison runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--benchmark",
        required=True,
        choices=SUPPORTED_BENCHMARKS,
        help="Which benchmark to run",
    )
    parser.add_argument(
        "--max-tasks",
        type=int,
        default=20,
        metavar="N",
        help="Maximum number of tasks to run per system (default: 20)",
    )
    parser.add_argument(
        "--config",
        default="config.yaml",
        help="Path to evaluation config YAML (default: config.yaml)",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Output directory (default: results/comparison/<benchmark>/)",
    )
    parser.add_argument(
        "--baseline-model",
        default=None,
        help=(
            "Override baseline model name (default: from config.baseline.model "
            "or claude-sonnet-4-6)"
        ),
    )
    parser.add_argument(
        "--skip-biomate",
        action="store_true",
        help="Skip BioMate run — only run the baseline (useful when BioMate server is down)",
    )
    parser.add_argument(
        "--skip-baseline",
        action="store_true",
        help="Skip baseline run — only run BioMate (useful for partial re-runs)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print tasks that would run without calling any API",
    )
    args = parser.parse_args()

    # ------------------------------------------------------------------
    # Load config
    # ------------------------------------------------------------------
    config_path = Path(args.config)
    if not config_path.is_absolute():
        # Try relative to evaluation dir first, then CWD
        for base in [_eval_dir, Path.cwd()]:
            candidate = base / args.config
            if candidate.exists():
                config_path = candidate
                break

    if not config_path.exists():
        print(f"ERROR: config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path) as f:
        config = yaml.safe_load(f)

    # Apply CLI model override to config baseline section
    if args.baseline_model:
        config.setdefault("baseline", {})["model"] = args.baseline_model

    baseline_model = config.get("baseline", {}).get("model", "claude-sonnet-4-6")

    # ------------------------------------------------------------------
    # Output directory
    # ------------------------------------------------------------------
    if args.output_dir:
        output_dir = Path(args.output_dir)
    else:
        output_dir = _eval_dir / "results" / "comparison" / args.benchmark

    # ------------------------------------------------------------------
    # Load adapter + tasks
    # ------------------------------------------------------------------
    print(f"Loading {args.benchmark} adapter ...", flush=True)
    adapter = _load_adapter(args.benchmark, config)

    # SGIBenchRunner needs prepare() with a dummy client to load datasets
    if args.benchmark == "sgi_bench":
        adapter.prepare(None)

    tasks = adapter.load_tasks()
    if args.max_tasks and args.max_tasks < len(tasks):
        tasks = tasks[: args.max_tasks]

    if args.dry_run:
        cats: Dict[str, int] = {}
        for t in tasks:
            cat = "unknown"
            if isinstance(t.metadata, dict):
                cat = (
                    t.metadata.get("category")
                    or t.metadata.get("task_type")
                    or "unknown"
                )
            cats[cat] = cats.get(cat, 0) + 1

        print(f"\nDry run — {args.benchmark}: {len(tasks)} tasks would run")
        print("By category:")
        for cat, n in sorted(cats.items()):
            print(f"  {cat}: {n}")
        print(
            f"\nWould compare:  BioMate  vs  Baseline ({baseline_model})"
        )
        return

    print(
        f"\nComparison: {args.benchmark}\n"
        f"  Tasks per system : {len(tasks)}\n"
        f"  Baseline model   : {baseline_model}\n"
        f"  Output dir       : {output_dir}\n"
    )

    # ------------------------------------------------------------------
    # BioMate run
    # ------------------------------------------------------------------
    biomate_results: List[BenchmarkResult] = []

    if not args.skip_biomate:
        print("--- BioMate run ---")
        try:
            biomate_client = BioMateEvalClient.from_config(config)
        except Exception as exc:
            print(f"  WARNING: Could not connect to BioMate: {exc}")
            print("  Use --skip-biomate to skip the BioMate run.")
            sys.exit(1)

        if args.benchmark == "param_prefill":
            # param_prefill uses a BioMate-specific endpoint; call prepare + run normally
            adapter.prepare(biomate_client)
            biomate_results = adapter.run(biomate_client, max_tasks=len(tasks))
        else:
            # Standard chat-based adapters: prepare then run
            adapter.prepare(biomate_client)
            biomate_results = adapter.run(biomate_client, max_tasks=len(tasks))

        print(
            f"  BioMate: {len(biomate_results)} results, "
            f"mean={_mean([r.score for r in biomate_results]):.3f}"
        )
    else:
        print("--- BioMate run skipped (--skip-biomate) ---")

    # ------------------------------------------------------------------
    # Baseline run
    # ------------------------------------------------------------------
    baseline_results: List[BenchmarkResult] = []

    if not args.skip_baseline:
        print(f"\n--- Baseline run ({baseline_model}) ---")
        try:
            baseline_client = BaselineLLMClient.from_config(config)
        except ValueError as exc:
            print(f"  ERROR: {exc}", file=sys.stderr)
            sys.exit(1)

        if args.benchmark == "param_prefill":
            # Use specialised text-based scoring (no BioMate endpoint available)
            baseline_results = _run_param_prefill_baseline(
                adapter, baseline_client, tasks
            )
        else:
            # Standard adapters: create a fresh adapter instance for baseline
            # so prepare() side-effects don't interfere
            baseline_adapter = _load_adapter(args.benchmark, config)
            if args.benchmark == "sgi_bench":
                baseline_adapter.prepare(None)
            else:
                # For chat-based adapters prepare() is usually a no-op or
                # records connection info — safe to pass the baseline client
                try:
                    baseline_adapter.prepare(baseline_client)
                except Exception:
                    pass  # baseline client may not have .base_url / .token

            baseline_results = baseline_adapter.run(
                baseline_client, max_tasks=len(tasks)
            )

        print(
            f"  Baseline: {len(baseline_results)} results, "
            f"mean={_mean([r.score for r in baseline_results]):.3f}"
        )
    else:
        print("--- Baseline run skipped (--skip-baseline) ---")

    # ------------------------------------------------------------------
    # Comparison summary
    # ------------------------------------------------------------------
    if biomate_results and baseline_results:
        _print_comparison(
            benchmark=args.benchmark,
            biomate_results=biomate_results,
            baseline_results=baseline_results,
            baseline_model=baseline_model,
        )

        out_path = _save_results(
            benchmark=args.benchmark,
            biomate_results=biomate_results,
            baseline_results=baseline_results,
            baseline_model=baseline_model,
            output_dir=output_dir,
        )
        print(f"\nResults saved to: {out_path}")

    elif biomate_results:
        bm_mean = _mean([r.score for r in biomate_results])
        print(f"\nBioMate-only results: n={len(biomate_results)}, mean={bm_mean:.3f}")

    elif baseline_results:
        bl_mean = _mean([r.score for r in baseline_results])
        print(f"\nBaseline-only results: n={len(baseline_results)}, mean={bl_mean:.3f}")

    else:
        print("\nNo results produced — both runs were skipped or failed.")


if __name__ == "__main__":
    main()
