#!/usr/bin/env python3
"""
run_stability.py
----------------
Measures response consistency by running the same tasks N times.

Usage:
    cd /home/yzhang/biomate/evaluation
    python runners/run_stability.py --benchmark biomni_eval1 --n-repeats 3 --sample 0.2
    python runners/run_stability.py --benchmark labbench --n-repeats 3
    python runners/run_stability.py --benchmark routing --n-repeats 5 --sample 0.15
    python runners/run_stability.py --all --n-repeats 3 --sample 0.2

Uses the BioMate client (full pipeline) for BioMate benchmarks and
the OllamaEvalClient for open-source model stability if --model is set.

Output:
    results/stability/<benchmark>_stability.json
    Console: consistency_rate, flip_rate, kappa, time stats
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))

from core.stability_runner import StabilityRunner
from core.results_store import ResultsStore

RESULTS_DIR = Path(__file__).parent.parent / "results" / "stability"

BENCHMARK_CONFIG = {
    "biomni_eval1": {
        "task_ids_db": "results/biomni_eval1_v20/eval_results.db",
        "adapter": "biomni_eval1",
        "client": "biomate",
    },
    "labbench": {
        "task_ids_db": "results/labbench_v22/eval_results.db",
        "adapter": "labbench",
        "client": "biomate",
    },
    "routing": {
        "task_ids_db": "results/routing_v11/eval_results.db",
        "adapter": "routing",
        "client": "biomate",
    },
    "bixbench": {
        "task_ids_db": "results/bixbench_v4/eval_results.db",
        "adapter": "bixbench",
        "client": "biomate",
    },
    "sgi_bench": {
        "task_ids_db": "results/sgi_bench_v1/eval_results.db",
        "adapter": "sgi_bench",
        "client": "biomate",
    },
}


def load_tasks_from_db(db_path: str, limit: int | None = None) -> list:
    """Load task records from an existing results DB."""
    import sqlite3
    conn = sqlite3.connect(db_path)
    # repeat_id may not exist in older DBs — check first
    existing = {r[1] for r in conn.execute("PRAGMA table_info(results)").fetchall()}
    if "repeat_id" in existing:
        where = "repeat_id=0 OR repeat_id IS NULL"
    else:
        where = "1=1"
    query = f"SELECT task_id, benchmark, score, ground_truth FROM results WHERE {where} GROUP BY task_id"
    if limit:
        query += f" LIMIT {limit}"
    rows = conn.execute(query).fetchall()
    conn.close()
    tasks = []
    for task_id, benchmark, score, gt_json in rows:
        parts = task_id.split("__")
        subtask = parts[1] if len(parts) >= 3 else benchmark
        try:
            gt = json.loads(gt_json)
            if isinstance(gt, str):
                try:
                    gt = json.loads(gt)
                except Exception:
                    pass
        except Exception:
            gt = gt_json or ""
        tasks.append({
            "task_id": task_id,
            "benchmark": benchmark,
            "subtask": subtask,
            "ground_truth": gt,
            "score_ref": score,
        })
    return tasks


def run_biomate_stability(
    benchmark: str,
    n_repeats: int,
    sample_fraction: float,
    verbose: bool,
) -> dict:
    """Run stability test for a BioMate benchmark using the full pipeline client."""
    from core.biomate_client import BioMateEvalClient
    import yaml

    cfg_path = Path(__file__).parent.parent / "config.yaml"
    with open(cfg_path) as f:
        config = yaml.safe_load(f)

    eval_dir = Path(__file__).parent.parent
    db_path = str(eval_dir / BENCHMARK_CONFIG[benchmark]["task_ids_db"])
    tasks = load_tasks_from_db(db_path)

    if not tasks:
        print(f"  No tasks found in {db_path}")
        return {}

    client = BioMateEvalClient.from_config(config)

    # Build question cache from adapter
    question_cache: dict = {}
    adapter_name = BENCHMARK_CONFIG[benchmark]["adapter"]
    try:
        if adapter_name == "biomni_eval1":
            from evaluation.adapters.biomni_eval1_adapter import BiomniEval1Adapter
            for t in BiomniEval1Adapter(config).load_tasks():
                question_cache[t.task_id] = t.question
        elif adapter_name == "labbench":
            from evaluation.adapters.labbench_adapter import LABBenchAdapter
            for t in LABBenchAdapter(config).load_tasks():
                question_cache[t.task_id] = t.question
        elif adapter_name in ("routing", "bixbench", "sgi_bench"):
            pass  # use task_id as question stub
    except Exception as exc:
        print(f"  [warn] adapter load failed: {exc}")

    def question_fn(task: dict) -> str:
        return question_cache.get(task["task_id"], f"[Task: {task['task_id']}]")

    def score_fn(subtask: str, response: str, ground_truth: str) -> float:
        from runners.run_model_selection import score_task
        return score_task(subtask, response, str(ground_truth))

    def ask_fn(question: str):
        resp = client.ask(question)
        return resp.message, resp.latency_sec, resp.cost_usd or 0.0

    # We need ask_fn to also score — wrap differently for StabilityRunner
    # The runner needs (score, latency, cost). We'll use a closure over the task.
    # Instead, run manually here:

    runner = StabilityRunner(
        ask_fn=None,  # we'll override below
        n_repeats=n_repeats,
        sample_fraction=sample_fraction,
        seed=42,
    )

    sampled = runner.sample_tasks(tasks)
    print(f"  Sampled {len(sampled)}/{len(tasks)} tasks × {n_repeats} repeats for {benchmark}")

    from core.stability_runner import TaskStabilityResult, StabilityReport, _mean_pairwise_kappa

    per_task_results = []
    for i, task in enumerate(sampled):
        task_id  = task["task_id"]
        subtask  = task["subtask"]
        gt       = task["ground_truth"]
        question = question_fn(task)
        scores, latencies, costs = [], [], []

        for rep in range(n_repeats):
            if verbose:
                print(f"  [{i+1:2d}/{len(sampled)}] {subtask[:20]:20s} rep={rep+1}", end="", flush=True)
            try:
                resp = client.ask(question)
                score = score_fn(subtask, resp.message, str(gt))
                scores.append(score)
                latencies.append(resp.latency_sec)
                costs.append(resp.cost_usd or 0.0)
                if verbose:
                    print(f" score={score:.2f} {resp.latency_sec:.1f}s")
            except Exception as exc:
                if verbose:
                    print(f" ERROR: {str(exc)[:50]}")
                scores.append(0.0); latencies.append(0.0); costs.append(0.0)
            time.sleep(0.5)

        per_task_results.append(TaskStabilityResult(
            task_id=task_id, scores=scores, latencies=latencies, costs=costs
        ))

    n = len(per_task_results)
    n_consistent  = sum(1 for r in per_task_results if r.is_consistent)
    all_scores    = [s for r in per_task_results for s in r.scores]
    mean_score    = sum(all_scores) / len(all_scores) if all_scores else 0.0
    score_var     = sum(r.score_std for r in per_task_results) / n if n else 0.0
    run_scores    = [[r.scores[rep] if rep < len(r.scores) else 0.0 for r in per_task_results]
                     for rep in range(n_repeats)]
    kappa         = _mean_pairwise_kappa(run_scores) if n_repeats >= 2 else 1.0
    all_lat       = [l for r in per_task_results for l in r.latencies if l > 0]
    sorted_lat    = sorted(all_lat)
    mean_lat      = sum(all_lat) / len(all_lat) if all_lat else 0.0
    std_lat       = (sum((l - mean_lat)**2 for l in all_lat) / max(len(all_lat)-1, 1))**0.5
    p95_lat       = sorted_lat[int(0.95*len(sorted_lat))] if sorted_lat else 0.0
    total_cost    = sum(c for r in per_task_results for c in r.costs)

    report = StabilityReport(
        benchmark=benchmark, model="biomate_claude_sonnet_4_6",
        n_tasks=n, n_repeats=n_repeats, sample_fraction=sample_fraction,
        consistency_rate=n_consistent/n if n else 0.0,
        flip_rate=1-(n_consistent/n) if n else 0.0,
        mean_score=mean_score, score_variance=score_var, kappa=kappa,
        mean_latency_sec=mean_lat, latency_std_sec=std_lat, p95_latency_sec=p95_lat,
        total_cost_usd=total_cost,
        mean_cost_per_task_usd=total_cost / max(n * n_repeats, 1),
        per_task=per_task_results,
    )
    print("\n" + report.summary())
    return report.to_dict()


def main():
    parser = argparse.ArgumentParser(description="Benchmark stability / consistency tester")
    parser.add_argument("--benchmark", choices=list(BENCHMARK_CONFIG.keys()),
                        help="Benchmark to test")
    parser.add_argument("--all", action="store_true", help="Run all benchmarks")
    parser.add_argument("--n-repeats", type=int, default=3,
                        help="Repeats per task (default: 3)")
    parser.add_argument("--sample", type=float, default=0.2,
                        help="Fraction of tasks to sample (default: 0.2)")
    parser.add_argument("--verbose", action="store_true", default=True)
    args = parser.parse_args()

    benchmarks = list(BENCHMARK_CONFIG.keys()) if args.all else [args.benchmark]
    if not benchmarks or benchmarks == [None]:
        parser.error("Specify --benchmark NAME or --all")

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    all_results = {}
    for bench in benchmarks:
        print(f"\n{'='*60}\nStability: {bench}  ({args.n_repeats}× repeats, {args.sample:.0%} sample)\n{'='*60}")
        result = run_biomate_stability(bench, args.n_repeats, args.sample, args.verbose)
        all_results[bench] = result

        out = RESULTS_DIR / f"{bench}_stability.json"
        with open(out, "w") as f:
            json.dump(result, f, indent=2)
        print(f"  Saved → {out}")

    # Combined output
    combined = RESULTS_DIR / "stability_summary.json"
    with open(combined, "w") as f:
        json.dump(all_results, f, indent=2)
    print(f"\nAll results → {combined}")


if __name__ == "__main__":
    main()
