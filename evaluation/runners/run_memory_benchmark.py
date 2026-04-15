#!/usr/bin/env python3
"""
run_memory_benchmark.py — BioMate Memory Benchmark runner.

Tests episodic memory injection (P1) and correction routing injection (P2).
Scenario taxonomy aligned with LongMemEval (ICLR 2025) and LoCoMo (ACL 2024).

Scenario types and targets:
  recall      (MB-A)  ≥ 60%  — LongMemEval: information extraction
  correction  (MB-B)  ≥ 80%  — LongMemEval: knowledge update
  baseline    (MB-C)  ≥ 95%  — LongMemEval: abstention (no pollution)
  temporal    (MB-T)  ≥ 55%  — LongMemEval: temporal reasoning
  synthesis   (MB-S)  ≥ 50%  — LongMemEval: multi-session reasoning
  adversarial (MB-X)  ≥ 70%  — BABILong adversarial + LongMemEval abstention

Overall target: ≥ 75% weighted

Usage:
    cd /home/yzhang/biomate/evaluation
    python runners/run_memory_benchmark.py
    python runners/run_memory_benchmark.py --type recall
    python runners/run_memory_benchmark.py --type correction --output results/memory/
    python runners/run_memory_benchmark.py --dry-run
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.core.base_adapter import BenchmarkResult
from evaluation.adapters import MemoryBenchmarkAdapter

VALID_TYPES = ["recall", "correction", "baseline", "temporal", "synthesis", "adversarial"]

# Targets aligned with LongMemEval baselines adjusted for domain-specific injection
TARGETS = {
    "recall":      0.60,
    "correction":  0.80,
    "baseline":    0.95,
    "temporal":    0.55,
    "synthesis":   0.50,
    "adversarial": 0.70,
    "overall":     0.75,
}

# LongMemEval GPT-4o baselines (no external memory injection) — for comparison
LONGMEMEVAL_BASELINES = {
    "recall":      0.55,   # info extraction
    "correction":  0.60,   # knowledge update
    "baseline":    0.80,   # abstention
    "temporal":    0.35,   # temporal reasoning
    "synthesis":   0.40,   # multi-session reasoning
    "adversarial": 0.55,   # adversarial/abstention
}


def main():
    parser = argparse.ArgumentParser(description="BioMate memory benchmark runner")
    parser.add_argument("--output", default="results/memory/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument(
        "--type",
        choices=VALID_TYPES,
        default=None,
        help="Run only scenarios of this type (default: all)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print scenario IDs and queries without calling BioMate",
    )
    parser.add_argument(
        "--max-tasks", type=int, default=None,
        help="Limit total number of scenarios (for quick smoke tests)",
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = Path(__file__).parent.parent / config_path
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "memory_eval_results.db")

    adapter = MemoryBenchmarkAdapter(config)
    tasks = adapter.load_tasks()

    # Filter by type
    if args.type:
        tasks = [t for t in tasks if t.ground_truth.get("type") == args.type]
        print(f"Filtered to {len(tasks)} tasks of type '{args.type}'")

    if args.max_tasks:
        tasks = tasks[: args.max_tasks]

    if args.dry_run:
        print(f"\n{'='*70}")
        print(f"Memory Benchmark — DRY RUN — {len(tasks)} scenarios")
        print(f"{'='*70}")
        for t in tasks:
            sc_type = t.ground_truth.get("type", "?")
            seed_info = []
            if t.metadata.get("seed_episode"):
                seed_info.append("episode")
            if t.metadata.get("seed_episode_2"):
                seed_info.append("episode_2")
            if t.metadata.get("seed_correction"):
                seed_info.append("correction")
            seed_str = f"[seeds: {', '.join(seed_info)}]" if seed_info else "[no seed]"
            print(f"\n  {t.task_id:<20} type={sc_type:<12} {seed_str}")
            print(f"  Q: {t.question[:90]}")
            recall = t.ground_truth.get("expected_recall") or t.ground_truth.get("expected_workflow", [])
            print(f"  Expected: {recall[:4]}")
        return

    # Connect to BioMate
    print(f"\nConnecting to BioMate at {config['biomate']['base_url']} ...")
    client = BioMateEvalClient.from_config(config)

    # Seed memory data via prepare()
    print("\nSeeding episodes and corrections ...")
    try:
        adapter.prepare(client)
    except Exception as e:
        print(f"WARNING: prepare() failed: {e}")
        print("Continuing — recall/correction scores may be 0.")

    store = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("memory_benchmark", suite="standalone", config=config)
    results = []

    print(f"\n{'='*70}")
    print(f"Memory Benchmark — {len(tasks)} scenarios")
    print(f"{'='*70}\n")

    for i, task in enumerate(tasks, 1):
        sc_type = task.ground_truth.get("type", "baseline")
        print(f"[{i:2}/{len(tasks)}] {task.task_id} ({sc_type}) ...", end=" ", flush=True)
        t0 = time.time()
        error_msg = None
        response_text = ""
        wf_card = None

        try:
            resp = client.ask(task.question)
            response_text = resp.text
            wf_card = resp.workflow_card
        except Exception as e:
            error_msg = str(e)

        latency = time.time() - t0
        sc = 0.0
        if not error_msg:
            try:
                sc = adapter.score(task, response_text, wf_card)
            except Exception as e:
                error_msg = f"scoring error: {e}"

        result = BenchmarkResult(
            task_id=task.task_id,
            benchmark="memory_benchmark",
            score=sc,
            agent_response=response_text if not error_msg else f"ERROR: {error_msg}",
            ground_truth=task.ground_truth,
            latency_sec=latency,
            metadata={
                **task.metadata,
                "scenario_type": sc_type,
            },
            error=error_msg,
        )
        store.save_one(run_id, result)
        results.append(result)

        marker = "✓" if sc >= 0.5 else "✗"
        print(f"{marker} score={sc:.1f}  ({latency:.1f}s)")

    store.finish_run(run_id)

    # Summary
    print(f"\n{'='*70}")
    print("MEMORY BENCHMARK RESULTS")
    print(f"{'='*70}")

    summary = MemoryBenchmarkAdapter.compute_weighted_score(results)
    per_type = summary["per_type"]
    counts = summary["by_type_counts"]

    print(f"\n{'Type':<14} {'N':>4} {'Score':>8} {'Target':>8} {'LME-Base':>10} {'Delta':>7} {'Pass?':>6}")
    print("-" * 60)
    for t in VALID_TYPES:
        if t not in per_type:
            continue
        avg = per_type[t]
        target = TARGETS.get(t, 0.0)
        baseline = LONGMEMEVAL_BASELINES.get(t, 0.0)
        delta = avg - baseline
        n = counts.get(t, 0)
        passed = "✓" if avg >= target else "✗"
        print(f"  {t:<12} {n:>4} {avg*100:>7.1f}% {target*100:>7.1f}%  {baseline*100:>7.1f}%  {delta*100:>+6.1f}%  {passed}")

    weighted = summary["weighted_overall"]
    overall_target = TARGETS["overall"]
    overall_pass = "✓ PASS" if weighted >= overall_target else "✗ BELOW TARGET"
    print("-" * 60)
    total_n = sum(counts.values())
    print(f"  {'WEIGHTED':12} {total_n:>4} {weighted*100:>7.1f}% {overall_target*100:>7.1f}%  {'55.0%':>8}  {(weighted-0.55)*100:>+6.1f}%  {overall_pass}")

    print(f"\nLME-Base = LongMemEval GPT-4o baseline (no memory injection)")
    print(f"Delta    = BioMate injection benefit over LME baseline")
    print(f"{'='*70}")


if __name__ == "__main__":
    main()
