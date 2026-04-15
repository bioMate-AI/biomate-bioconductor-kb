#!/usr/bin/env python3
"""
run_protocol_thresholds.py — Protocol-Aware QC Threshold Benchmark.

Tests whether BioMate applies protocol-specific QC profiles instead of
naive universal thresholds on 20 labeled edge-case scenarios.

Usage:
    python runners/run_protocol_thresholds.py
    python runners/run_protocol_thresholds.py --max-tasks 5 --dry-run
    python runners/run_protocol_thresholds.py --protocol ffpe
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore  # noqa: E402
from evaluation.adapters.protocol_thresholds_adapter import ProtocolThresholdsAdapter  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description="Protocol-Aware QC Threshold benchmark runner")
    parser.add_argument("--output", default="results/protocol_thresholds/")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--max-tasks", type=int, default=None)
    parser.add_argument("--protocol", default=None, help="Filter to protocols containing this string")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    adapter = ProtocolThresholdsAdapter(config, protocol_filter=args.protocol)
    tasks = adapter.load_tasks()
    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"Protocol Thresholds — {len(tasks)} tasks would run:\n")
        for t in tasks:
            print(f"  [{t.metadata['protocol']}] {t.task_id}")
            print(f"    GT={t.ground_truth}  naive={t.metadata['expected_naive_action']}  "
                  f"profile={t.metadata['biomate_profile']}")
        return

    store = ResultsStore(config["paths"]["results_db"])
    client = BioMateEvalClient.from_config(config)

    run_id = store.start_run("protocol_thresholds", suite="standalone", config=config)
    print(f"\nProtocol Thresholds Benchmark")
    print(f"  Tasks:  {len(tasks)}")
    print(f"  Run ID: {run_id}\n")

    adapter.prepare(client)
    results = []
    for i, task in enumerate(tasks):
        t0 = time.time()
        error = None
        response_text = ""
        try:
            response = client.ask(adapter.task_prompt(task))
            response_text = response.text
        except Exception as exc:
            error = str(exc)

        score = 0.0
        if not error:
            try:
                score = adapter.score(task, response_text)
            except Exception as exc:
                error = f"scoring error: {exc}"

        latency = time.time() - t0
        status = "✓" if score >= 1.0 else ("~" if score >= 0.5 else "✗")
        print(f"  [{i+1:2d}/{len(tasks)}] {status} {task.metadata['entry_id']:8s} "
              f"({task.metadata['protocol'][:30]}) "
              f"score={score:.2f} latency={latency:.1f}s")
        if error:
            print(f"         ERROR: {error}")

        from evaluation.core.base_adapter import BenchmarkResult
        result = BenchmarkResult(
            task_id=task.task_id,
            benchmark=adapter.name,
            score=score,
            agent_response=response_text,
            ground_truth=task.ground_truth,
            latency_sec=latency,
            metadata=task.metadata,
            error=error,
        )
        results.append(result)
        store.save_one(run_id, result)

    # Summary
    scores = [r.score for r in results]
    n = len(scores)
    mean = sum(scores) / n if n else 0.0
    exact = sum(1 for s in scores if s >= 1.0)
    partial = sum(1 for s in scores if 0.5 <= s < 1.0)
    wrong = sum(1 for s in scores if s < 0.5)

    print(f"\n{'='*55}")
    print(f"Protocol Thresholds Results")
    print(f"{'='*55}")
    print(f"  Overall:  n={n}  mean={mean:.3f}")
    print(f"  Exact match (1.0): {exact} ({100*exact//n}%)")
    print(f"  Partial   (0.5):   {partial} ({100*partial//n}%)")
    print(f"  Wrong     (0.0):   {wrong} ({100*wrong//n}%)")
    print(f"\n  Results saved to: {config['paths']['results_db']}")


if __name__ == "__main__":
    main()
