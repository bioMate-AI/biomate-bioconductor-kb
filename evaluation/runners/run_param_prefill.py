#!/usr/bin/env python3
"""
run_param_prefill.py — Parameter Pre-filling Benchmark runner.

Tests BioMate's ability to automatically infer Nextflow workflow parameters
from natural-language user queries via _infer_params_from_intent_llm().

The adapter calls /api/ai_assistant/search_nextflow_workflow directly (not
chat) because generated_parameters are only available in that endpoint's
response, not in the chat stream.

100 cases across 7 categories:
  genome_inference       (20): organism → genome build
  strandedness_inference (15): library kit → strandedness flag
  tool_flag_selection    (15): protocol → boolean/enum tool flags
  numeric_param_inference(15): explicit numbers → numeric params
  reference_file_selection(15): chemistry/primers/databases
  multi_param_inference  (10): ≥3 params per case
  negative_cases         (10): vague queries that should fill nothing

Scoring:
  F1 over expected_params (with genome alias normalisation)
  − 0.20 penalty per must_not_fill key incorrectly populated

Usage:
    # Run all 100 cases
    python runners/run_param_prefill.py

    # Single category
    python runners/run_param_prefill.py --category genome_inference

    # Dry-run (show task counts, no API calls)
    python runners/run_param_prefill.py --dry-run

    # Limit to first N tasks
    python runners/run_param_prefill.py --max-tasks 10

    # Override config or output path
    python runners/run_param_prefill.py --config config.yaml --output results/param_prefill/
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters.param_prefill_adapter import ParamPrefillAdapter

CATEGORIES = [
    "genome_inference",
    "strandedness_inference",
    "tool_flag_selection",
    "numeric_param_inference",
    "reference_file_selection",
    "multi_param_inference",
    "negative_cases",
    "all",
]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parameter Pre-filling Benchmark runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--output",
        default="results/param_prefill/",
        help="Directory to write eval_results.db (default: results/param_prefill/)",
    )
    parser.add_argument(
        "--config",
        default="config.yaml",
        help="Path to config YAML relative to evaluation/ (default: config.yaml)",
    )
    parser.add_argument(
        "--max-tasks",
        type=int,
        default=None,
        metavar="N",
        help="Run at most N tasks (useful for smoke tests)",
    )
    parser.add_argument(
        "--category",
        choices=CATEGORIES,
        default="all",
        help="Run only tasks in this category (default: all)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show task counts by category/difficulty without making any API calls",
    )
    args = parser.parse_args()

    # ── Load config ──────────────────────────────────────────────────────
    eval_root = Path(__file__).parent.parent
    config_path = eval_root / args.config
    if not config_path.exists():
        print(f"ERROR: config not found at {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config.setdefault("paths", {})
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    # ── Load tasks ───────────────────────────────────────────────────────
    adapter = ParamPrefillAdapter(config)
    all_tasks = adapter.load_tasks()

    # Apply category filter
    selected_category = args.category
    if selected_category and selected_category != "all":
        tasks = [t for t in all_tasks if t.metadata.get("category") == selected_category]
    else:
        tasks = all_tasks

    if args.max_tasks:
        tasks = tasks[: args.max_tasks]

    # ── Dry-run ──────────────────────────────────────────────────────────
    if args.dry_run:
        by_cat: dict[str, int] = {}
        by_diff: dict[str, int] = {}
        for t in tasks:
            cat = t.metadata.get("category", "unknown")
            diff = t.difficulty
            by_cat[cat] = by_cat.get(cat, 0) + 1
            by_diff[diff] = by_diff.get(diff, 0) + 1

        print(f"Parameter Pre-filling Benchmark — DRY RUN")
        print(f"  {len(tasks)} tasks would run (category={selected_category}):\n")
        print(f"  {'Category':<30} {'N':>4}")
        print(f"  {'-'*35}")
        for cat, n in sorted(by_cat.items()):
            print(f"  {cat:<30} {n:>4}")
        print(f"\n  {'Difficulty':<15} {'N':>4}")
        print(f"  {'-'*20}")
        for diff, n in sorted(by_diff.items()):
            print(f"  {diff:<15} {n:>4}")
        return

    # ── Live run ─────────────────────────────────────────────────────────
    print("Parameter Pre-filling Benchmark")
    print(f"  Tasks:    {len(tasks)}")
    print(f"  Category: {selected_category}")
    print(f"  Output:   {args.output}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("param_prefill", suite="standalone", config=config)

    t0 = time.time()
    results = adapter.run(client, max_tasks=len(tasks))
    store.save(run_id, results)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    # ── Summary ──────────────────────────────────────────────────────────
    n = len(results)
    mean = sum(r.score for r in results) / n if n else 0.0
    errors = sum(1 for r in results if r.error)

    by_cat: dict[str, list[float]] = {}
    by_diff: dict[str, list[float]] = {}
    for r in results:
        cat = r.metadata.get("category", "unknown") if isinstance(r.metadata, dict) else "unknown"
        diff = r.metadata.get("difficulty", "unknown") if isinstance(r.metadata, dict) else "unknown"
        by_cat.setdefault(cat, []).append(r.score)
        by_diff.setdefault(diff, []).append(r.score)

    # Per-category expected size for context
    EXPECTED_SIZES = {
        "genome_inference": 20,
        "strandedness_inference": 15,
        "tool_flag_selection": 15,
        "numeric_param_inference": 15,
        "reference_file_selection": 15,
        "multi_param_inference": 10,
        "negative_cases": 10,
    }

    print(f"\n{'='*60}")
    print(f"Parameter Pre-filling Benchmark Results")
    print(f"{'='*60}")
    print(f"  Overall:  n={n}  F1={mean:.3f}  errors={errors}  elapsed={elapsed:.0f}s\n")

    print(f"  {'Category':<30} {'N':>4} {'Expected':>9} {'F1':>7}")
    print(f"  {'-'*52}")
    for cat, scores in sorted(by_cat.items()):
        cm = sum(scores) / len(scores) if scores else 0.0
        exp = EXPECTED_SIZES.get(cat, "?")
        print(f"  {cat:<30} {len(scores):>4} {str(exp):>9} {cm:>7.3f}")

    print(f"\n  {'Difficulty':<15} {'N':>4} {'F1':>7}")
    print(f"  {'-'*28}")
    for diff, scores in sorted(by_diff.items()):
        dm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {diff:<15} {len(scores):>4} {dm:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")

    # Detail for failures (score < 0.5)
    failures = sorted(
        [r for r in results if r.score < 0.5],
        key=lambda r: r.score,
    )
    if failures:
        print(f"\n  Failures ({len(failures)}):")
        for r in failures:
            notes = r.metadata.get("notes", "") if isinstance(r.metadata, dict) else ""
            err_note = f" | ERROR: {r.error[:60]}" if r.error else ""
            print(
                f"    [{r.task_id}] score={r.score:.2f}"
                f" — {notes[:55]}{err_note}"
            )

    # Summary banner
    f1_pct = mean * 100
    if f1_pct >= 80:
        grade = "PASS"
    elif f1_pct >= 60:
        grade = "MARGINAL"
    else:
        grade = "FAIL"
    print(f"\n  Grade: {grade}  (F1={f1_pct:.1f}%,  threshold=80%)")


if __name__ == "__main__":
    main()
