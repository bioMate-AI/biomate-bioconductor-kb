#!/usr/bin/env python3
"""
run_bixbench.py — Run BixBench benchmark.

Usage:
    # Run BixBench-Verified-50 (recommended — ground truth verified)
    python runners/run_bixbench.py --split verified

    # Run full BixBench (caution: ~17% baseline due to GT errors)
    python runners/run_bixbench.py --split full --max-tasks 50

    python runners/run_bixbench.py --split verified --dry-run

Notes:
    - BixBench-Verified-50: 50 questions from Phylo team with corrected GT
      (Biomni Lab = 88.7%, Claude Code Opus 4.6 = 65.3%, GPT-4o = 40.2%)
    - Full BixBench: 293 questions, inflated FAIL rate due to GT errors
    - Requires: pip install datasets  (HuggingFace datasets library)
    - Repo at: https://github.com/context-dependent-biology/bixbench
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import BixBenchAdapter


SPLITS = ["verified", "full"]


def main():
    parser = argparse.ArgumentParser(description="BixBench runner")
    parser.add_argument("--output", default="results/bixbench/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None)
    parser.add_argument("--split", choices=SPLITS, default="verified",
                        help="verified (50, corrected GT) or full (293, raw)")
    parser.add_argument("--category", default=None,
                        help="Filter to a question category")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    config.setdefault("bixbench", {})["split"] = args.split
    if args.category:
        config["bixbench"]["category_filter"] = args.category

    adapter = BixBenchAdapter(config, mode="hf_mcq", category_filter=args.category)

    try:
        tasks = adapter.load_tasks()
    except ImportError:
        print("ERROR: HuggingFace datasets library not found.")
        print("Install with:  pip install datasets")
        sys.exit(1)
    except FileNotFoundError as e:
        print(f"ERROR: BixBench repo not found: {e}")
        print("Run:  bash scripts/download_benchmarks.sh")
        sys.exit(1)

    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"BixBench ({args.split}) — {len(tasks)} questions would run:\n")
        by_type: dict[str, int] = {}
        for t in tasks:
            by_type[t.task_type] = by_type.get(t.task_type, 0) + 1
        print("  By question type:")
        for tt, c in sorted(by_type.items(), key=lambda x: -x[1]):
            print(f"    {tt}: {c}")
        return

    # Competitor context
    competitor_scores = {
        "Biomni Lab (published)": 0.887,
        "Claude Code Opus 4.6":   0.653,
        "GPT-4o":                 0.402,
        "o1-preview":             0.388,
        "Frontier LLMs (full BixBench, raw GT)": 0.17,
    }

    print(f"BixBench ({args.split})")
    print(f"  Questions: {len(tasks)}")
    print(f"  Output:    {args.output}")
    print(f"\n  Competitor scores (BixBench-Verified-50):")
    for name, score in competitor_scores.items():
        print(f"    {name:<42}: {score:.1%}")
    print()

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("bixbench", suite="standalone", config=config)

    t0 = time.time()
    results = adapter.run(client, max_tasks=args.max_tasks)
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

    # Per-type breakdown
    by_type_scores: dict[str, list[float]] = {}
    for r in results:
        tt = r.metadata.get("eval_mode", "reasoning") if isinstance(r.metadata, dict) else "reasoning"
        by_type_scores.setdefault(tt, []).append(r.score)

    print(f"\n{'='*55}")
    print(f"BixBench ({args.split}) Results")
    print(f"{'='*55}")
    print(f"  BioMate:  n={n}  score={mean:.3f} ({mean:.1%})  elapsed={elapsed:.0f}s")
    print(f"  Exact (1.0): {exact}/{n} ({100*exact//n if n else 0}%)")
    print(f"  Partial:     {partial}/{n}")
    print(f"  Wrong (0.0): {wrong}/{n}")
    if errors_count:
        print(f"  Errors:      {errors_count}/{n}")

    print(f"\n  Competitor comparison (Verified-50):")
    for name, cscore in competitor_scores.items():
        diff = mean - cscore
        sign = "+" if diff >= 0 else ""
        print(f"    vs {name:<38}: {sign}{diff:+.1%}")

    print(f"\n  {'Question Type':<35} {'N':>4} {'Mean':>7}")
    print(f"  {'-'*47}")
    for tt, scores in sorted(by_type_scores.items(), key=lambda x: -sum(x[1])/max(len(x[1]),1)):
        tm = sum(scores) / len(scores) if scores else 0.0
        print(f"  {tt:<35} {len(scores):>4} {tm:>7.3f}")

    print(f"\n  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
