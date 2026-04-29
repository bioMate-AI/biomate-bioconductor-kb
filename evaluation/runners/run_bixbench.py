#!/usr/bin/env python3
"""
run_bixbench.py — Run BixBench benchmark.

Usage:
    # Default: MCQ mode (no data download needed)
    python runners/run_bixbench.py --mode hf_mcq --max-tasks 20

    # local_exec: download capsule data from HuggingFace, run reference notebooks
    python runners/run_bixbench.py --mode local_exec --max-tasks 5

    # biomate_exec: send data + question to BioMate, score computed result
    python runners/run_bixbench.py --mode biomate_exec --max-tasks 5

    # Dry run to preview tasks
    python runners/run_bixbench.py --mode local_exec --max-tasks 10 --dry-run

    # Filter by category
    python runners/run_bixbench.py --mode hf_mcq --category "RNA-seq"

Published baselines (exec mode):
    Biomni Lab:     88.7%
    Claude Code:    65.3%
    GPT-4o:         40.2%
    BioMate (MCQ):  23.3%  (baseline, session 5)

Capsule data is downloaded automatically from HuggingFace Hub.
No CodeOcean account needed.

Requires:
    pip install datasets huggingface_hub nbformat
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import BixBenchAdapter


MODES = ["hf_mcq", "local_exec", "biomate_exec"]


def main():
    parser = argparse.ArgumentParser(
        description="BixBench runner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--output", default="results/bixbench/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None,
                        help="Limit number of tasks (default: all 205)")
    parser.add_argument("--mode", choices=MODES, default="hf_mcq",
                        help=(
                            "hf_mcq: closed-book MCQ (default, no data needed); "
                            "local_exec: download capsule data + run notebooks locally; "
                            "biomate_exec: send data to BioMate for execution"
                        ))
    parser.add_argument("--category", default=None,
                        help="Filter to a question category (e.g. 'RNA-seq', 'Imaging')")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print task summary without running")
    parser.add_argument("--skip", type=int, default=0,
                        help="Skip first N tasks (for resuming partial runs)")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    adapter = BixBenchAdapter(
        config,
        mode=args.mode,
        max_tasks=args.max_tasks,
        category_filter=args.category,
    )

    print(f"Loading tasks (mode={args.mode})...")
    try:
        tasks = adapter.load_tasks()
    except ImportError as e:
        print(f"ERROR: Missing dependency: {e}")
        print("Install with:  pip install datasets huggingface_hub nbformat")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR loading tasks: {e}")
        sys.exit(1)

    if args.skip:
        tasks = tasks[args.skip:]
    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    # Competitor context
    competitor_scores = {
        "Biomni Lab (exec mode, published)":  0.887,
        "Claude Code (exec mode)":            0.653,
        "GPT-4o (exec mode)":                 0.402,
        "Claude 3.5 Sonnet (MCQ)":            0.450,
        "GPT-4o (MCQ)":                       0.400,
        "BioMate MCQ (session 5 baseline)":   0.233,
    }

    if args.dry_run:
        print(f"\nBixBench — {len(tasks)} tasks ({args.mode} mode)")
        print(f"  Category filter: {args.category or 'all'}")
        print()

        # By verifier type
        by_verifier: dict[str, int] = {}
        by_cat: dict[str, int] = {}
        for t in tasks:
            v = t.metadata.get("verifier_type", t.metadata.get("eval_mode", "unknown"))
            by_verifier[v] = by_verifier.get(v, 0) + 1
            for c in t.metadata.get("categories", "").split(","):
                c = c.strip()
                if c:
                    by_cat[c] = by_cat.get(c, 0) + 1

        print("  By verifier type:")
        for vt, c in sorted(by_verifier.items(), key=lambda x: -x[1]):
            print(f"    {vt}: {c}")

        print("\n  Top categories:")
        for cat, c in sorted(by_cat.items(), key=lambda x: -x[1])[:10]:
            print(f"    {c:3d} {cat}")

        if args.mode in ("local_exec", "biomate_exec"):
            capsules = set(t.metadata.get("capsule_uuid", "") for t in tasks)
            print(f"\n  Unique capsules to download: {len(capsules)}")
            print(f"  Data will be cached at: {adapter.data_dir}")
            print()
            print("  To download all capsule data upfront, run:")
            print(f"    python runners/run_bixbench.py --mode local_exec --dry-run --max-tasks {len(tasks)}")
            print("    (then remove --dry-run to actually run)")

        print("\n  Competitor scores:")
        for name, score in competitor_scores.items():
            print(f"    {name:<42}: {score:.1%}")
        return

    print(f"\nBixBench ({args.mode})")
    print(f"  Questions:  {len(tasks)}")
    print(f"  Category:   {args.category or 'all'}")
    print(f"  Output:     {args.output}")
    print(f"\n  Competitor scores:")
    for name, score in competitor_scores.items():
        print(f"    {name:<42}: {score:.1%}")
    print()

    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("bixbench", suite="standalone", config=config)
    t0 = time.time()

    if args.mode == "local_exec":
        # Local exec: no BioMate client needed — runs notebooks directly
        print("Running local_exec (downloading capsule data + running notebooks)...")
        results = adapter.run_local_exec(max_tasks=args.max_tasks)
    else:
        # hf_mcq or biomate_exec: send to BioMate
        client = BioMateEvalClient.from_config(config)
        results = adapter.run(client, max_tasks=args.max_tasks, skip=args.skip)

    store.save(run_id, results)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    summary = store.summary(run_id).get("bixbench", {})
    n = summary.get("n", len(results))
    mean = summary.get("mean", 0.0)

    # Score distribution
    exact = sum(1 for r in results if r.score >= 1.0)
    partial = sum(1 for r in results if 0.0 < r.score < 1.0)
    wrong = sum(1 for r in results if r.score == 0.0)
    errors_count = sum(1 for r in results if r.error)

    # Per-verifier breakdown
    by_verifier_scores: dict[str, list[float]] = {}
    for r in results:
        vt = r.metadata.get("verifier_type", r.metadata.get("eval_mode", "reasoning")) if isinstance(r.metadata, dict) else "reasoning"
        by_verifier_scores.setdefault(vt, []).append(r.score)

    print(f"\n{'='*60}")
    print(f"BixBench ({args.mode}) Results")
    print(f"{'='*60}")
    print(f"  BioMate:  n={n}  score={mean:.3f} ({mean:.1%})  elapsed={elapsed:.0f}s")
    print(f"  Exact (1.0): {exact}/{n} ({100*exact//n if n else 0}%)")
    if partial:
        print(f"  Partial:     {partial}/{n}")
    print(f"  Wrong (0.0): {wrong}/{n}")
    if errors_count:
        print(f"  Errors:      {errors_count}/{n}")

    print(f"\n  Competitor comparison:")
    for name, cscore in competitor_scores.items():
        diff = mean - cscore
        sign = "+" if diff >= 0 else ""
        print(f"    vs {name:<40}: {sign}{diff:+.1%}")

    print(f"\n  {'Verifier Type':<35} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*47}")
    for vt, scores in sorted(by_verifier_scores.items(), key=lambda x: -sum(x[1])/max(len(x[1]),1)):
        tm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {vt:<35} {len(scores):>4} {tm:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")

    # Show a few failures for debugging
    failures = [r for r in results if r.score == 0.0 and not r.error][:3]
    if failures:
        print(f"\n  Sample failures (first 3 of {wrong}):")
        for r in failures:
            print(f"    [{r.task_id}]")
            print(f"      GT:  {str(r.ground_truth)[:60]}")
            print(f"      Got: {str(r.agent_response)[:80]}")

    # 5-Dimension summary
    from evaluation.core.five_dimension_reporter import FiveDimensionReporter
    reporter = FiveDimensionReporter(store)
    report = reporter.compute(run_id)
    print(reporter.render_table([report]))


if __name__ == "__main__":
    main()
