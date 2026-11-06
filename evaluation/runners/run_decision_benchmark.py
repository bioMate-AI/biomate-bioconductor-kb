#!/usr/bin/env python3
"""
run_decision_benchmark.py — DrugDev *decision* benchmark runner.

Runs the context-rich decision archetypes (lead-op triage, FEP-guided selection,
dose-escalation MTD, …) against the live BioMate agent and scores the DECISION the
agent reached — not tool routing. One runner iterates every dataset in
`DecisionBenchmarkAdapter.DECISION_DATASETS`; each is a project vignette whose ground
truth is real measured data (ADMET, experimental ΔΔG, BOIN operating characteristics).

The agent's run is graded end-to-end by execution_grader in a separate L5–L6 path
(live Batch); this runner grades the recommendation text (L1–L4 of the decision).

Usage:
    # Offline: list every decision task without running (no server needed)
    python runners/run_decision_benchmark.py --dry-run

    # Live: run all archetypes against the BioMate agent
    python runners/run_decision_benchmark.py

    # One archetype only
    python runners/run_decision_benchmark.py --dataset fep_selection

If the BioMate server is down, the runner builds the tasks, reports, and SKIPS
execution (it never launches a speculative live run).
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters.decision_benchmark_adapter import (
    DecisionBenchmarkAdapter, DECISION_DATASETS,
)


def _check_server(base_url: str) -> bool:
    import requests
    for endpoint in ("/health", "/api/health", "/"):
        try:
            if requests.get(f"{base_url}{endpoint}", timeout=10).status_code < 500:
                return True
        except Exception:
            continue
    return False


def _mock_task(result):
    from evaluation.core.base_adapter import BenchmarkTask
    return BenchmarkTask(task_id=result.task_id, question="", ground_truth={},
                         metadata=result.metadata)


def _load_all_tasks(config: dict, datasets: List[str]):
    """Return [(dataset_name, adapter, [tasks])] for each selected archetype dataset."""
    out = []
    for name in datasets:
        adapter = DecisionBenchmarkAdapter({**config, "dataset": name})
        # ground_truth lives on the task; re-attach for scoring from a result's metadata
        tasks = adapter.load_tasks()
        out.append((name, adapter, tasks))
    return out


def _summarise(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    """rows: [{dataset, archetype, difficulty, task_id, score, error}]. Aggregate."""
    def _mean(xs):
        return statistics.mean(xs) if xs else 0.0

    scored = [r for r in rows if not r.get("error")]
    by_arch: Dict[str, List[float]] = {}
    by_diff: Dict[str, List[float]] = {}
    for r in scored:
        by_arch.setdefault(r["archetype"] or r["dataset"], []).append(r["score"])
        by_diff.setdefault(r["difficulty"] or "?", []).append(r["score"])
    return {
        "n": len(rows),
        "n_errors": sum(1 for r in rows if r.get("error")),
        "overall_mean": _mean([r["score"] for r in scored]),
        "by_archetype": {k: {"n": len(v), "mean": _mean(v)} for k, v in by_arch.items()},
        "by_difficulty": {k: {"n": len(v), "mean": _mean(v)} for k, v in by_diff.items()},
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="DrugDev decision benchmark runner")
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--dataset", default=None,
                    help=f"one of {sorted(DECISION_DATASETS)}; default = all")
    ap.add_argument("--output", default="results/decision_benchmark_v1/")
    ap.add_argument("--max-tasks", type=int, default=None)
    ap.add_argument("--workers", type=int, default=None)
    ap.add_argument("--dry-run", action="store_true",
                    help="list tasks and exit; no server needed")
    args = ap.parse_args()

    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    datasets = [args.dataset] if args.dataset else list(DECISION_DATASETS)
    unknown = [d for d in datasets if d not in DECISION_DATASETS]
    if unknown:
        print(f"ERROR: unknown dataset(s) {unknown}; choose from {sorted(DECISION_DATASETS)}")
        sys.exit(1)

    bundles = _load_all_tasks(config, datasets)
    all_tasks = [(name, adapter, t) for name, adapter, tasks in bundles for t in tasks]
    if args.max_tasks:
        all_tasks = all_tasks[:args.max_tasks]

    # ---- dry run (offline) --------------------------------------------------
    if args.dry_run:
        print(f"Decision benchmark — {len(all_tasks)} tasks across "
              f"{len(datasets)} archetype(s):\n")
        for name, _adapter, task in all_tasks:
            arch = task.metadata.get("archetype", name)
            print(f"  [{task.task_id:16}] {name:16} {arch:22} "
                  f"({task.difficulty}, scorer={task.metadata.get('scorer')})")
        return

    # ---- server health ------------------------------------------------------
    base_url = config["biomate"]["base_url"]
    print(f"Checking BioMate server at {base_url}...", end=" ", flush=True)
    if not _check_server(base_url):
        print("DOWN")
        print("\nTasks built OK. Skipping execution — start the BioMate server and "
              "re-run. (This runner never launches a speculative live run.)")
        return
    print("UP")

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config.setdefault("paths", {})["results_db"] = str(output_dir / "eval_results.db")
    if args.workers:
        config.setdefault("concurrency", {})["max_parallel_tasks"] = args.workers

    client = BioMateEvalClient.from_config(config)
    store = ResultsStore(config["paths"]["results_db"])

    rows: List[Dict[str, Any]] = []
    t0 = time.time()

    # Run per-dataset so each adapter scores with its own dispatch. Tasks within a
    # dataset run concurrently via the adapter's thread pool.
    for name, adapter, tasks in bundles:
        if args.max_tasks:
            tasks = tasks[:args.max_tasks]
        run_id = store.start_run("decision_benchmark", suite=name, config=config)
        done = [0]

        def _on_result(r, _adapter=adapter, _n=len(tasks)):
            store.save_one(run_id, r)
            done[0] += 1
            detail = _adapter.score_detailed(_mock_task(r), r.agent_response)
            arch = r.metadata.get("archetype", name)
            err = f" [ERR {r.error[:40]}]" if r.error else ""
            print(f"  [{done[0]:>2}/{_n}] [{r.task_id:16}] {arch:22} "
                  f"score={r.score:.2f}{err}", flush=True)
            rows.append({"dataset": name, "archetype": arch,
                         "difficulty": r.metadata.get("difficulty")
                         or _mock_task(r).metadata.get("difficulty"),
                         "task_id": r.task_id, "score": r.score, "error": r.error,
                         "detail": detail})

        print(f"\n=== {name} ({len(tasks)} tasks) ===")
        adapter.run_tasks(client, tasks, on_result=_on_result)
        store.finish_run(run_id)

    elapsed = time.time() - t0
    summary = _summarise(rows)

    print(f"\n{'='*60}\nDecision Benchmark — Results\n{'='*60}")
    print(f"  Tasks:          {summary['n']}  ({summary['n_errors']} errors)")
    print(f"  Overall mean:   {summary['overall_mean']:.3f}")
    print(f"  By archetype:")
    for arch, s in sorted(summary["by_archetype"].items()):
        print(f"    {arch:24} n={s['n']:2}  mean={s['mean']:.3f}")
    print(f"  By difficulty:")
    for diff, s in sorted(summary["by_difficulty"].items()):
        print(f"    {diff:24} n={s['n']:2}  mean={s['mean']:.3f}")
    print(f"  Elapsed:        {elapsed:.0f}s")

    out_json = output_dir / "decision_metrics.json"
    with open(out_json, "w") as f:
        json.dump({"summary": summary, "rows": rows}, f, indent=2, default=str)
    print(f"\n  Metrics saved to: {out_json}")


if __name__ == "__main__":
    main()
