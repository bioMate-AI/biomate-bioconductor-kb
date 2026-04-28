#!/usr/bin/env python3
"""
run_comprehensive_benchmark.py
-------------------------------
Full four-dimension benchmark runner for any model.
Covers: performance, time cost, stability, hallucination, financial cost.

Supported models:
  --model gemini-3-flash-preview   (direct Gemini API)
  --model gemma4:31b               (direct Ollama API)
  --model qwen3:32b                (direct Ollama API)
  --model qwen3:30b-a3b            (direct Ollama API)

Benchmarks run:
  biomni_eval1   — 223 tasks (or --max-tasks N)
  labbench       — 33 CloningScenarios tasks
  bixbench       — 30 MCQ tasks
  sgi_bench      — 100-task life-science subset

Dimensions measured per task:
  1. Performance  — accuracy score
  2. Time cost    — latency_sec mean/std/p95
  3. Financial cost — cost_usd per task (zero for Ollama, measured for Gemini)
  4. Hallucination — LLM judge label (grounded/hallucinated/unverifiable)

Stability (separate pass):
  20% sample × 3 repeats → consistency_rate, Cohen's κ, flip_rate

Usage:
    cd /home/yzhang/biomate/evaluation
    python runners/run_comprehensive_benchmark.py --model gemini-3-flash-preview
    python runners/run_comprehensive_benchmark.py --model gemma4:31b --max-tasks 60
    python runners/run_comprehensive_benchmark.py --model gemma4:31b --benchmarks labbench bixbench
    python runners/run_comprehensive_benchmark.py --model gemini-3-flash-preview --stability
    python runners/run_comprehensive_benchmark.py --model gemma4:31b --hallucination-audit

Output (all logs + DBs kept for auditing):
    results/comprehensive/<model_tag>/<benchmark>/eval_results.db
    results/comprehensive/<model_tag>/run.log
    results/comprehensive/<model_tag>/summary.json
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))

from core.base_adapter import BenchmarkResult
from core.results_store import ResultsStore
from core.hallucination_detector import HallucinationDetector
from core.stability_runner import StabilityRunner, _mean_pairwise_kappa, TaskStabilityResult

RESULTS_BASE = Path(__file__).parent.parent / "results" / "comprehensive"
EVAL_DIR     = Path(__file__).parent.parent

# ---------------------------------------------------------------------------
# Benchmark task loaders
# ---------------------------------------------------------------------------

def load_biomni_tasks(max_tasks: Optional[int] = None) -> List[Dict]:
    """Load BiomniEval1 tasks with questions from adapter."""
    import yaml
    with open(EVAL_DIR / "config.yaml") as f:
        config = yaml.safe_load(f)
    from evaluation.adapters.biomni_eval1_adapter import BiomniEval1Adapter
    tasks = BiomniEval1Adapter(config).load_tasks()
    if max_tasks:
        # Stratified: keep proportional subtask distribution
        from collections import defaultdict
        by_subtask = defaultdict(list)
        for t in tasks:
            by_subtask[t.task_id.split("__")[1]].append(t)
        sampled = []
        per = max(1, max_tasks // len(by_subtask))
        for group in by_subtask.values():
            sampled.extend(group[:per])
        tasks = sampled[:max_tasks]
    return [{"task_id": t.task_id, "question": t.question,
             "ground_truth": t.ground_truth, "benchmark": "biomni_eval1",
             "subtask": t.task_id.split("__")[1] if "__" in t.task_id else "biomni_eval1"}
            for t in tasks]


def load_labbench_tasks() -> List[Dict]:
    import yaml
    with open(EVAL_DIR / "config.yaml") as f:
        config = yaml.safe_load(f)
    from evaluation.adapters.labbench_adapter import LABBenchAdapter
    tasks = LABBenchAdapter(config).load_tasks()
    return [{"task_id": t.task_id, "question": t.question,
             "ground_truth": t.ground_truth, "benchmark": "labbench",
             "subtask": t.task_id.split("__")[1] if "__" in t.task_id else "labbench"}
            for t in tasks]


def load_bixbench_tasks(max_tasks: int = 30) -> List[Dict]:
    import sqlite3
    db = EVAL_DIR / "results/bixbench_v4/eval_results.db"
    if not db.exists():
        return []
    conn = sqlite3.connect(db)
    # repeat_id may not exist in older DBs — use GROUP BY task_id to deduplicate
    rows = conn.execute(
        "SELECT task_id, benchmark, score, ground_truth "
        "FROM results GROUP BY task_id LIMIT ?",
        (max_tasks,)
    ).fetchall()
    conn.close()
    return [{"task_id": r[0], "question": f"[BixBench task: {r[0]}]",
             "ground_truth": r[3], "benchmark": "bixbench", "subtask": "bixbench"}
            for r in rows]


def load_sgi_tasks(max_tasks: int = 100) -> List[Dict]:
    import sqlite3
    db = EVAL_DIR / "results/sgi_bench_v1/eval_results.db"
    if not db.exists():
        return []
    conn = sqlite3.connect(db)
    rows = conn.execute(
        "SELECT task_id, benchmark, score, ground_truth "
        "FROM results GROUP BY task_id "
        "ORDER BY task_id LIMIT ?",
        (max_tasks,)
    ).fetchall()
    conn.close()
    return [{"task_id": r[0], "question": f"[SGI-Bench: {r[0]}]",
             "ground_truth": r[3], "benchmark": "sgi_bench", "subtask": "sgi_bench"}
            for r in rows]


LOADERS = {
    "biomni_eval1": load_biomni_tasks,
    "labbench":     load_labbench_tasks,
    "bixbench":     load_bixbench_tasks,
    "sgi_bench":    load_sgi_tasks,
}

# ---------------------------------------------------------------------------
# Scorers (reuse from model_selection)
# ---------------------------------------------------------------------------

def _decode_gt(gt: Any) -> str:
    import json as _json
    raw = str(gt).strip()
    try:
        d = _json.loads(raw)
        if isinstance(d, str):
            return d
        return raw
    except Exception:
        return raw


def score_task(subtask: str, response: str, ground_truth: Any) -> float:
    import re, json as _json
    gt_raw = _decode_gt(ground_truth)

    if subtask in ("CloningScenarios", "labbench", "ProtocolQA", "LitQA2", "bixbench"):
        gt = gt_raw.strip().upper()
        for line in response.split("\n"):
            line = line.strip()
            if not line: continue
            m = re.match(r"^([A-D])[^a-zA-Z]?", line)
            if m: return 1.0 if m.group(1) == gt else 0.0
            if line in ("A","B","C","D"): return 1.0 if line == gt else 0.0
        m = re.search(r"\b([A-D])\b", response)
        if m: return 1.0 if m.group(1) == gt else 0.0
        return 0.0

    if subtask in ("gwas_causal_gene_pharmaprojects", "gwas_causal",
                   "rare_disease_diagnosis", "rare_disease",
                   "screen_gene_retrieval", "screen_gene",
                   "gwas_variant_prioritization", "gwas_variant"):
        try:
            obj = _json.loads(gt_raw)
            candidates = list(obj.values()) if isinstance(obj, dict) else [str(obj)]
        except Exception:
            candidates = [gt_raw]
        resp_up = response.upper()
        return 1.0 if any(str(c).upper() in resp_up for c in candidates) else 0.0

    if subtask in ("patient_gene_detection", "patient_gene"):
        gt = gt_raw.strip().upper()
        return 1.0 if gt in response.upper() else 0.0

    # generic: check if any key part of gt appears
    return 1.0 if gt_raw.strip().lower() in response.lower() else 0.0


def _infer_step_type(subtask: str) -> str:
    mapping = {
        "gwas_causal_gene_pharmaprojects": "gene_identification",
        "gwas_causal": "gene_identification",
        "gwas_variant_prioritization": "gene_identification",
        "gwas_variant": "gene_identification",
        "rare_disease_diagnosis": "disease_identification",
        "rare_disease": "disease_identification",
        "patient_gene_detection": "ensg_lookup",
        "patient_gene": "ensg_lookup",
        "CloningScenarios": "mcq_rationale",
        "labbench": "mcq_rationale",
        "ProtocolQA": "mcq_rationale",
        "LitQA2": "mcq_rationale",
        "bixbench": "scientific_claim",
        "sgi_bench": "scientific_claim",
        "screen_gene": "gene_identification",
        "screen_gene_retrieval": "gene_identification",
    }
    return mapping.get(subtask, "scientific_claim")

# ---------------------------------------------------------------------------
# Main benchmark runner
# ---------------------------------------------------------------------------

def make_client(model: str):
    """Return the right eval client for the given model string."""
    if "gemini" in model.lower():
        from core.gemini_eval_client import GeminiEvalClient
        return GeminiEvalClient(model=model)
    else:
        from core.ollama_eval_client import OllamaEvalClient
        return OllamaEvalClient(model=model)


def _run_single_task(args):
    """Worker for parallel execution. Returns (task, resp, score, hall_label)."""
    task, model, run_hallucination = args
    client = make_client(model)
    detector = HallucinationDetector() if run_hallucination else None

    resp = client.ask(task["question"])
    score = 0.0
    hall_label = None

    if not resp.error:
        score = score_task(task["subtask"], resp.text, task["ground_truth"])
        if detector and resp.text.strip():
            try:
                hr = detector.classify(
                    response=resp.text[:1500],
                    question=task["question"][:800],
                    step_type=_infer_step_type(task["subtask"]),
                    ground_truth=str(task["ground_truth"])[:300],
                )
                hall_label = hr.label
            except Exception:
                pass
    else:
        hall_label = "hallucinated"

    return task, resp, score, hall_label


def run_benchmark(
    model: str,
    benchmark: str,
    tasks: List[Dict],
    out_dir: Path,
    logger: logging.Logger,
    run_hallucination: bool = True,
    max_tasks: Optional[int] = None,
    parallel: int = 1,
) -> Dict[str, Any]:

    if max_tasks:
        tasks = tasks[:max_tasks]

    client = make_client(model)

    # Health check
    health = client.health_check()
    available = health.get("available", health.get("model_available", health.get("ollama_running", False)))
    if not available:
        logger.error(f"Model {model} not available: {health}")
        return {"benchmark": benchmark, "error": str(health)}

    db_path = str(out_dir / benchmark / "eval_results.db")
    (out_dir / benchmark).mkdir(parents=True, exist_ok=True)

    store  = ResultsStore(db_path)
    run_id = store.start_run(benchmark, model, {"model": model})

    detector = HallucinationDetector() if run_hallucination else None

    scores, latencies, costs, hw_costs = [], [], [], []
    n = len(tasks)

    logger.info(f"  {benchmark}: {n} tasks  (parallel={parallel})")

    if parallel > 1:
        # Parallel execution via thread pool (Gemini API is I/O bound)
        from concurrent.futures import ThreadPoolExecutor, as_completed
        args_list = [(task, model, run_hallucination) for task in tasks]
        completed = 0
        with ThreadPoolExecutor(max_workers=parallel) as pool:
            futures = {pool.submit(_run_single_task, a): a[0] for a in args_list}
            for fut in as_completed(futures):
                task, resp, score, hall_label = fut.result()
                completed += 1
                status = "✓" if score >= 0.5 else "✗"
                logger.info(f"  [{completed:3d}/{n}] {task['subtask'][:20]:20s} "
                            f"{status} score={score:.2f}  {resp.latency_sec:.1f}s  "
                            f"${resp.cost_usd:.6f}  hall={hall_label or '—'}")
                scores.append(score); latencies.append(resp.latency_sec)
                costs.append(resp.cost_usd); hw_costs.append(getattr(resp, "hw_cost_usd", 0.0))
                result = BenchmarkResult(
                    task_id=task["task_id"], benchmark=benchmark, score=score,
                    agent_response=resp.text[:4000], ground_truth=task["ground_truth"],
                    latency_sec=resp.latency_sec,
                    metadata={"subtask": task["subtask"], "tokens_per_sec": resp.tokens_per_sec},
                    input_tokens=resp.input_tokens, output_tokens=resp.output_tokens,
                    cost_usd=resp.cost_usd, model=model,
                )
                store.save_one(run_id, result, hallucination_label=hall_label, repeat_id=0)
    else:
        for i, task in enumerate(tasks, 1):
            task_id  = task["task_id"]
            subtask  = task["subtask"]
            question = task["question"]
            gt       = task["ground_truth"]

            logger.info(f"  [{i:3d}/{n}] {subtask[:25]:25s}", )

            resp = client.ask(question)
            score = 0.0
            hall_label = None

            if not resp.error:
                score = score_task(subtask, resp.text, gt)
                if detector and resp.text.strip():
                    try:
                        hr = detector.classify(
                            response=resp.text[:1500],
                            question=question[:800],
                            step_type=_infer_step_type(subtask),
                            ground_truth=str(gt)[:300],
                        )
                        hall_label = hr.label
                    except Exception as exc:
                        logger.warning(f"  hallucination judge failed: {exc}")
            else:
                hall_label = "hallucinated"
                logger.warning(f"  ERROR: {resp.error[:80]}")

            scores.append(score)
            latencies.append(resp.latency_sec)
            costs.append(resp.cost_usd)
            hw_costs.append(getattr(resp, "hw_cost_usd", 0.0))

            result = BenchmarkResult(
                task_id=task_id, benchmark=benchmark, score=score,
                agent_response=resp.text[:4000], ground_truth=gt,
                latency_sec=resp.latency_sec,
                metadata={"subtask": subtask, "tokens_per_sec": resp.tokens_per_sec,
                          "hw_cost_usd": getattr(resp, "hw_cost_usd", 0.0)},
                input_tokens=resp.input_tokens, output_tokens=resp.output_tokens,
                cost_usd=resp.cost_usd, model=model,
            )
            store.save_one(run_id, result, hallucination_label=hall_label, repeat_id=0)

            status = "✓" if score >= 0.5 else "✗"
            logger.info(f" {status}  score={score:.2f}  {resp.latency_sec:.1f}s  "
                        f"{resp.tokens_per_sec:.1f}tok/s  ${resp.cost_usd:.6f}"
                        f"  hall={hall_label or '—'}")

    store.finish_run(run_id)

    n_tasks = len(scores)
    mean_s  = sum(scores) / n_tasks if n_tasks else 0.0
    mean_l  = sum(latencies) / n_tasks if n_tasks else 0.0
    sorted_l = sorted(latencies)
    p95_l   = sorted_l[int(0.95 * n_tasks)] if sorted_l else 0.0
    std_l   = (sum((l - mean_l)**2 for l in latencies) / max(n_tasks-1, 1))**0.5
    total_cost = sum(costs)
    hall_labels = []
    # Re-read from DB for accurate counts
    import sqlite3
    conn = sqlite3.connect(db_path)
    hall_rows = conn.execute(
        "SELECT hallucination_label FROM results WHERE run_id=? AND hallucination_label IS NOT NULL",
        (run_id,)
    ).fetchall()
    conn.close()
    hall_counts = {}
    for (lbl,) in hall_rows:
        hall_counts[lbl] = hall_counts.get(lbl, 0) + 1
    assessable  = hall_counts.get("grounded", 0) + hall_counts.get("hallucinated", 0)
    hall_rate   = hall_counts.get("hallucinated", 0) / assessable if assessable > 0 else None

    summary = {
        "model": model,
        "benchmark": benchmark,
        "n_tasks": n_tasks,
        "run_id": run_id,
        "db_path": db_path,
        # Performance
        "mean_score": round(mean_s, 4),
        # Time
        "mean_latency_sec": round(mean_l, 2),
        "std_latency_sec":  round(std_l, 2),
        "p95_latency_sec":  round(p95_l, 2),
        # Cost
        "total_cost_usd":     round(total_cost, 6),
        "mean_cost_per_task": round(total_cost / max(n_tasks, 1), 6),
        # Hallucination
        "n_grounded":     hall_counts.get("grounded", 0),
        "n_hallucinated": hall_counts.get("hallucinated", 0),
        "n_unverifiable": hall_counts.get("unverifiable", 0),
        "hallucination_rate": round(hall_rate, 4) if hall_rate is not None else None,
    }

    logger.info(f"\n  ── {benchmark} ({model}) ──")
    logger.info(f"  Score:        {mean_s:.1%}  ({int(mean_s*n_tasks)}/{n_tasks})")
    logger.info(f"  Latency:      {mean_l:.1f}s ±{std_l:.1f}s  p95={p95_l:.1f}s")
    logger.info(f"  Total cost:   ${total_cost:.4f}  (${total_cost/max(n_tasks,1):.6f}/task)")
    logger.info(f"  Hallucination: {f'{hall_rate:.1%}' if hall_rate is not None else 'not assessed'}"
                f"  ({hall_counts})")

    return summary


def run_stability(
    model: str,
    benchmark: str,
    tasks: List[Dict],
    out_dir: Path,
    logger: logging.Logger,
    n_repeats: int = 3,
    sample_fraction: float = 0.2,
) -> Dict[str, Any]:
    """Run stability test: 20% sample × N repeats."""
    import random
    rng = random.Random(42)
    by_subtask: Dict[str, List] = {}
    for t in tasks:
        by_subtask.setdefault(t["subtask"], []).append(t)
    sampled = []
    for group in by_subtask.values():
        k = max(1, round(len(group) * sample_fraction))
        sampled.extend(rng.sample(group, min(k, len(group))))

    client = make_client(model)
    per_task_results = []
    n = len(sampled)

    logger.info(f"\n  Stability: {benchmark}  {n} tasks × {n_repeats} repeats")

    db_path = str(out_dir / f"{benchmark}_stability" / "eval_results.db")
    (out_dir / f"{benchmark}_stability").mkdir(parents=True, exist_ok=True)
    store  = ResultsStore(db_path)
    run_id = store.start_run(f"{benchmark}_stability", model, {"model": model})

    for i, task in enumerate(sampled):
        scores, latencies, costs = [], [], []
        for rep in range(n_repeats):
            logger.info(f"  [{i+1:2d}/{n}] {task['subtask'][:20]:20s} rep={rep+1}", )
            resp = client.ask(task["question"])
            sc = score_task(task["subtask"], resp.text, task["ground_truth"]) if not resp.error else 0.0
            scores.append(sc); latencies.append(resp.latency_sec); costs.append(resp.cost_usd)
            result = BenchmarkResult(
                task_id=task["task_id"], benchmark=f"{benchmark}_stability",
                score=sc, agent_response=resp.text[:2000],
                ground_truth=task["ground_truth"], latency_sec=resp.latency_sec,
                metadata={"subtask": task["subtask"], "rep": rep},
                input_tokens=resp.input_tokens, output_tokens=resp.output_tokens,
                cost_usd=resp.cost_usd, model=model,
            )
            store.save_one(run_id, result, repeat_id=rep)
            logger.info(f"  score={sc:.2f}  {resp.latency_sec:.1f}s")
            time.sleep(0.3)
        per_task_results.append(TaskStabilityResult(
            task_id=task["task_id"], scores=scores, latencies=latencies, costs=costs
        ))

    store.finish_run(run_id)

    n_consistent  = sum(1 for r in per_task_results if r.is_consistent)
    all_scores    = [s for r in per_task_results for s in r.scores]
    mean_score    = sum(all_scores) / len(all_scores) if all_scores else 0.0
    score_var     = sum(r.score_std for r in per_task_results) / n if n else 0.0
    run_sc_lists  = [[r.scores[rep] if rep < len(r.scores) else 0.0 for r in per_task_results]
                     for rep in range(n_repeats)]
    kappa         = _mean_pairwise_kappa(run_sc_lists) if n_repeats >= 2 else 1.0
    all_lat       = [l for r in per_task_results for l in r.latencies if l > 0]
    mean_lat      = sum(all_lat) / len(all_lat) if all_lat else 0.0

    result = {
        "model": model, "benchmark": benchmark,
        "n_tasks": n, "n_repeats": n_repeats,
        "consistency_rate": round(n_consistent / n, 4) if n else None,
        "flip_rate":        round(1 - n_consistent / n, 4) if n else None,
        "mean_score":       round(mean_score, 4),
        "score_variance":   round(score_var, 4),
        "kappa":            round(kappa, 4),
        "mean_latency_sec": round(mean_lat, 2),
        "db_path": db_path,
    }
    logger.info(f"\n  Stability {benchmark}: consistency={result['consistency_rate']:.1%}  "
                f"flip={result['flip_rate']:.1%}  κ={kappa:.3f}")
    return result


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Comprehensive four-dimension benchmark runner")
    parser.add_argument("--model", required=True,
                        help="Model to evaluate (e.g. gemini-3-flash-preview, gemma4:31b)")
    parser.add_argument("--benchmarks", nargs="+",
                        default=["biomni_eval1", "labbench", "bixbench", "sgi_bench"],
                        choices=list(LOADERS.keys()),
                        help="Which benchmarks to run")
    parser.add_argument("--max-tasks", type=int, default=None,
                        help="Max tasks per benchmark (default: all)")
    parser.add_argument("--stability", action="store_true",
                        help="Also run stability tests (20%% sample × 3 repeats)")
    parser.add_argument("--no-hallucination", action="store_true",
                        help="Skip hallucination audit (faster)")
    parser.add_argument("--n-repeats", type=int, default=3,
                        help="Stability repeats (default: 3)")
    parser.add_argument("--parallel", type=int, default=1,
                        help="Concurrent API workers (default 1; use 4-8 for Gemini)")
    args = parser.parse_args()

    model_tag = args.model.replace(":", "-").replace("/", "_")
    out_dir   = RESULTS_BASE / model_tag
    out_dir.mkdir(parents=True, exist_ok=True)

    # Set up logging — both console and file
    log_path = out_dir / "run.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(message)s",
        datefmt="%H:%M:%S",
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(str(log_path), mode="w"),
        ],
    )
    logger = logging.getLogger(__name__)
    logger.info(f"=== Comprehensive Benchmark: {args.model} ===")
    logger.info(f"Benchmarks: {args.benchmarks}")
    logger.info(f"Output dir: {out_dir}")
    logger.info(f"Log file:   {log_path}")

    # Speed calibration
    client = make_client(args.model)
    logger.info("\nSpeed calibration...")
    cal = client.speed_calibration(n=2)
    logger.info(f"  {args.model}: {cal.get('mean_tps', 0):.1f} tok/s  "
                f"{cal.get('mean_latency_sec', 0):.1f}s mean latency")

    all_summaries = {}
    all_tasks_cache: Dict[str, List[Dict]] = {}

    for bench in args.benchmarks:
        logger.info(f"\n{'='*60}\nBenchmark: {bench}\n{'='*60}")

        # Load tasks
        loader_kwargs = {}
        if args.max_tasks:
            loader_kwargs["max_tasks"] = args.max_tasks
        try:
            tasks = LOADERS[bench](**loader_kwargs)
        except TypeError:
            tasks = LOADERS[bench]()
            if args.max_tasks:
                tasks = tasks[:args.max_tasks]

        if not tasks:
            logger.warning(f"  No tasks loaded for {bench} — skipping")
            continue

        logger.info(f"  Loaded {len(tasks)} tasks")
        all_tasks_cache[bench] = tasks

        # Main benchmark run
        summary = run_benchmark(
            model=args.model, benchmark=bench, tasks=tasks,
            out_dir=out_dir, logger=logger,
            run_hallucination=not args.no_hallucination,
            parallel=args.parallel,
        )
        all_summaries[bench] = summary

        # Stability
        if args.stability:
            stab = run_stability(
                model=args.model, benchmark=bench, tasks=tasks,
                out_dir=out_dir, logger=logger, n_repeats=args.n_repeats,
            )
            all_summaries[f"{bench}_stability"] = stab

    # Save combined summary
    summary_path = out_dir / "summary.json"
    with open(summary_path, "w") as f:
        json.dump(all_summaries, f, indent=2)
    logger.info(f"\n\nAll results saved to {out_dir}")
    logger.info(f"Summary: {summary_path}")
    logger.info(f"Log:     {log_path}")

    # Print comparison table
    print("\n" + "="*90)
    print(f"FOUR-DIMENSION RESULTS — {args.model}")
    print("="*90)
    hdr = f"{'Benchmark':20s} {'Score':>8} {'Lat(s)':>8} {'±σ':>6} {'p95':>6} {'Cost/task':>11} {'Hall%':>7} {'Consist':>9}"
    print(hdr)
    print("-"*90)
    for bench, s in all_summaries.items():
        if "stability" in bench or "error" in s:
            continue
        hall = f"{s['hallucination_rate']:.1%}" if s.get("hallucination_rate") is not None else "—"
        cons = "—"
        if f"{bench}_stability" in all_summaries:
            cr = all_summaries[f"{bench}_stability"].get("consistency_rate")
            if cr is not None:
                cons = f"{cr:.1%}"
        print(f"{bench:20s} {s['mean_score']:>8.1%} {s['mean_latency_sec']:>8.1f} "
              f"{s['std_latency_sec']:>6.1f} {s['p95_latency_sec']:>6.1f} "
              f"${s['mean_cost_per_task']:>10.5f} {hall:>7} {cons:>9}")


if __name__ == "__main__":
    main()
