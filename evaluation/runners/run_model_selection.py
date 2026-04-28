#!/usr/bin/env python3
"""
run_model_selection.py
----------------------
Runs the 30-task selection benchmark across candidate Ollama models to pick
one open-source LLM for BioMate. Also measures tok/s and amortized HW cost.

Usage:
    cd /home/yzhang/biomate/evaluation
    python runners/run_model_selection.py
    python runners/run_model_selection.py --models qwen3:32b gemma4:31b gemma3:27b
    python runners/run_model_selection.py --calibrate-only   # speed check only
    python runners/run_model_selection.py --skip-calibrate   # skip speed check

Output:
    results/model_selection/summary.json
    results/model_selection/<model>/eval_results.db
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

# Add biomate root so evaluation.* imports work (adapters use relative imports)
_EVAL_DIR = Path(__file__).parent.parent
_BIOMATE_ROOT = _EVAL_DIR.parent
sys.path.insert(0, str(_BIOMATE_ROOT))
sys.path.insert(0, str(_EVAL_DIR))

from core.ollama_eval_client import OllamaEvalClient, _HW_COST_PER_SEC
from core.base_adapter import BenchmarkResult
from core.results_store import ResultsStore

TASK_IDS_PATH = _EVAL_DIR / "datasets/model_selection/task_ids.json"
RESULTS_DIR   = _EVAL_DIR / "results/model_selection"

DEFAULT_MODELS = ["qwen3:32b", "gemma3:27b", "qwen3:30b-a3b"]

# Pre-loaded question cache: task_id -> question string (populated in main())
_QUESTION_CACHE: Dict[str, str] = {}

# ---------------------------------------------------------------------------
# Pre-load all task questions at startup (avoids repeated adapter instantiation
# and fixes relative import issues by loading adapters as a package).
# ---------------------------------------------------------------------------

def _load_all_questions() -> Dict[str, str]:
    """Return {task_id: question_text} for all available tasks."""
    questions: Dict[str, str] = {}
    eval_dir = Path(__file__).parent.parent

    # Ensure evaluation/ is treated as a package by adding its parent to path
    parent = str(eval_dir.parent)
    if parent not in sys.path:
        sys.path.insert(0, parent)

    # BiomniEval1 tasks
    try:
        from evaluation.adapters.biomni_eval1_adapter import BiomniEval1Adapter
        adapter = BiomniEval1Adapter({"data_path": str(eval_dir / "datasets")})
        for t in adapter.load_tasks():
            questions[t.task_id] = t.question
        print(f"  [preload] BiomniEval1: {len(questions)} questions loaded")
    except Exception as exc:
        print(f"  [preload warn] BiomniEval1 failed: {exc}")

    # LABBench tasks
    try:
        from evaluation.adapters.labbench_adapter import LABBenchAdapter
        adapter2 = LABBenchAdapter({"data_path": str(eval_dir / "datasets")})
        before = len(questions)
        for t in adapter2.load_tasks():
            questions[t.task_id] = t.question
        print(f"  [preload] LABBench: {len(questions) - before} questions loaded")
    except Exception as exc:
        print(f"  [preload warn] LABBench failed: {exc}")

    return questions


# Global question cache — populated in main() before any model runs
_QUESTION_CACHE: Dict[str, str] = {}

# ---------------------------------------------------------------------------
# Scoring helpers
# ---------------------------------------------------------------------------

def score_mcq(response: str, ground_truth: str) -> float:
    """Extract first capital letter from response and compare to ground truth."""
    import re
    raw = str(ground_truth).strip()
    # Ground truth may be double-JSON-encoded (e.g. '"C"' stored as JSON string)
    try:
        decoded = json.loads(raw)
        if isinstance(decoded, str):
            raw = decoded
    except Exception:
        pass
    gt = raw.strip().upper()
    # Try first line first letter
    for line in response.split("\n"):
        line = line.strip()
        if not line:
            continue
        m = re.match(r"^([A-D])[^a-zA-Z]?", line)
        if m:
            return 1.0 if m.group(1) == gt else 0.0
        # Single letter line
        if line in ("A", "B", "C", "D"):
            return 1.0 if line == gt else 0.0
    # Fallback: find first A/B/C/D anywhere
    m = re.search(r"\b([A-D])\b", response)
    if m:
        return 1.0 if m.group(1) == gt else 0.0
    return 0.0


def score_gene_name(response: str, ground_truth: str) -> float:
    """Check if ground truth gene/disease name appears in response (case-insensitive)."""
    gt = str(ground_truth).strip()
    # ground_truth may be JSON for rare_disease
    try:
        gt_obj = json.loads(gt)
        if isinstance(gt_obj, dict):
            candidates = list(gt_obj.values())
        else:
            candidates = [str(gt_obj)]
    except Exception:
        candidates = [gt]
    resp_upper = response.upper()
    for c in candidates:
        if str(c).upper() in resp_upper:
            return 1.0
    return 0.0


def score_ensg(response: str, ground_truth: str) -> float:
    """Check if ENSG ID appears in response."""
    raw = str(ground_truth).strip()
    try:
        decoded = json.loads(raw)
        if isinstance(decoded, str):
            raw = decoded
    except Exception:
        pass
    gt = raw.strip().upper()
    return 1.0 if gt in response.upper() else 0.0


SCORERS = {
    "gwas_causal":      score_gene_name,
    "rare_disease":     score_gene_name,
    "patient_gene":     score_ensg,
    "CloningScenarios": score_mcq,
    "labbench":         score_mcq,
    "ProtocolQA":       score_mcq,
    "LitQA2":           score_mcq,
}


def score_task(subtask: str, response: str, ground_truth: str) -> float:
    scorer = SCORERS.get(subtask, score_mcq)
    return scorer(response, ground_truth)


# ---------------------------------------------------------------------------
# Prompt builder
# ---------------------------------------------------------------------------

def build_prompt(task: Dict[str, Any]) -> str:
    """Return the original benchmark question from the pre-loaded cache."""
    task_id = task["task_id"]
    q = _QUESTION_CACHE.get(task_id)
    if q:
        return q
    # Cache miss: return a safe fallback with NO ground-truth leakage
    subtask = task["subtask"]
    return f"[Task ID: {task_id}]\n[Subtask: {subtask}]\nPlease answer this {subtask} biology question."


def _load_question_cache(tasks: List[Dict]) -> None:
    """Pre-load all questions from benchmark adapters into _QUESTION_CACHE."""
    import yaml
    from evaluation.adapters.biomni_eval1_adapter import BiomniEval1Adapter
    from evaluation.adapters.labbench_adapter import LABBenchAdapter

    cfg_path = _EVAL_DIR / "config.yaml"
    with open(cfg_path) as f:
        config = yaml.safe_load(f)

    biomni_ids = {t["task_id"] for t in tasks
                  if t["subtask"] in ("gwas_causal", "rare_disease", "patient_gene")}
    lab_ids    = {t["task_id"] for t in tasks
                  if t["subtask"] not in ("gwas_causal", "rare_disease", "patient_gene")}

    if biomni_ids:
        print("  Loading BiomniEval1 questions...")
        try:
            for bt in BiomniEval1Adapter(config).load_tasks():
                if bt.task_id in biomni_ids:
                    _QUESTION_CACHE[bt.task_id] = bt.question
            print(f"  → {len([t for t in tasks if t['task_id'] in _QUESTION_CACHE and t['subtask'] in ('gwas_causal','rare_disease','patient_gene')])} biomni questions cached")
        except Exception as exc:
            print(f"  [warn] BiomniEval1 load failed: {exc}")

    if lab_ids:
        print("  Loading LABBench questions...")
        try:
            for lt in LABBenchAdapter(config).load_tasks():
                if lt.task_id in lab_ids:
                    _QUESTION_CACHE[lt.task_id] = lt.question
            print(f"  → {len([t for t in tasks if t['task_id'] in _QUESTION_CACHE and t['subtask'] not in ('gwas_causal','rare_disease','patient_gene')])} labbench questions cached")
        except Exception as exc:
            print(f"  [warn] LABBench load failed: {exc}")

    missing = [t["task_id"] for t in tasks if t["task_id"] not in _QUESTION_CACHE]
    if missing:
        print(f"  [warn] {len(missing)} tasks have no cached question (will use safe fallback)")


# ---------------------------------------------------------------------------
# Main benchmark runner
# ---------------------------------------------------------------------------

def run_model(model: str, tasks: List[Dict], skip_calibrate: bool = False) -> Dict[str, Any]:
    print(f"\n{'='*60}")
    print(f"Model: {model}")
    print(f"{'='*60}")

    client = OllamaEvalClient(model=model)

    # Health check
    health = client.health_check()
    if not health["ollama_running"]:
        print(f"  ✗ Ollama not running: {health.get('error')}")
        return {"model": model, "error": "ollama_not_running"}
    if not health["model_available"]:
        print(f"  ✗ Model '{model}' not installed. Run: ollama pull {model}")
        return {"model": model, "error": f"model_not_installed"}

    # Speed calibration
    cal = {"mean_tps": None, "mean_latency_sec": None}
    if not skip_calibrate:
        print(f"  Calibrating speed (3 prompts)...")
        cal = client.speed_calibration(n=3)
        print(f"  → {cal['mean_tps']:.1f} tok/s  |  {cal['mean_latency_sec']:.1f}s mean latency")

    # Setup results store
    model_tag = model.replace(":", "-").replace("/", "_")
    db_path   = str(RESULTS_DIR / model_tag / "eval_results.db")
    os.makedirs(str(RESULTS_DIR / model_tag), exist_ok=True)
    store = ResultsStore(db_path)
    run_id = store.start_run("model_selection", model, {"model": model})

    scores = []
    latencies = []
    tps_list = []
    hw_costs = []
    instruction_following = []

    for i, task in enumerate(tasks, 1):
        subtask  = task["subtask"]
        gt       = task["ground_truth"]
        task_id  = task["task_id"]

        print(f"  [{i:2d}/{len(tasks)}] {subtask[:20]:20s}", end="", flush=True)

        prompt = build_prompt(task)
        t0 = time.time()
        resp = client.ask(prompt)

        score = 0.0
        if not resp.error:
            score = score_task(subtask, resp.text, gt)
            # Instruction following: did model produce a parseable answer?
            has_answer = bool(resp.text.strip())
            instruction_following.append(1.0 if has_answer else 0.0)
        else:
            print(f" ERROR: {resp.error[:50]}")
            instruction_following.append(0.0)

        scores.append(score)
        latencies.append(resp.latency_sec)
        tps_list.append(resp.tokens_per_sec)
        hw_costs.append(resp.hw_cost_usd)

        result = BenchmarkResult(
            task_id=task_id,
            benchmark=f"model_selection_{subtask}",
            score=score,
            agent_response=resp.text[:2000],
            ground_truth=gt,
            latency_sec=resp.latency_sec,
            metadata={"subtask": subtask, "tokens_per_sec": resp.tokens_per_sec,
                      "hw_cost_usd": resp.hw_cost_usd},
            input_tokens=resp.input_tokens,
            output_tokens=resp.output_tokens,
            cost_usd=resp.cost_usd,
            model=model,
        )
        store.save_one(run_id, result)

        status = "✓" if score == 1.0 else "✗"
        print(f" {status}  score={score:.2f}  {resp.latency_sec:.1f}s  {resp.tokens_per_sec:.1f}tok/s")

    store.finish_run(run_id)

    n = len(scores)
    mean_score      = sum(scores) / n if n else 0
    mean_latency    = sum(latencies) / n if n else 0
    mean_tps        = sum(t for t in tps_list if t > 0) / max(1, sum(1 for t in tps_list if t > 0))
    total_hw_cost   = sum(hw_costs)
    mean_hw_per_task = total_hw_cost / n if n else 0
    instruct_rate   = sum(instruction_following) / n if n else 0

    # Per-subtask breakdown
    subtask_scores: Dict[str, List[float]] = {}
    for task, sc in zip(tasks, scores):
        subtask_scores.setdefault(task["subtask"], []).append(sc)
    subtask_means = {k: round(sum(v)/len(v), 3) for k, v in subtask_scores.items()}

    summary = {
        "model":               model,
        "n_tasks":             n,
        "mean_score":          round(mean_score, 3),
        "subtask_scores":      subtask_means,
        "mean_latency_sec":    round(mean_latency, 1),
        "mean_tps":            round(mean_tps, 1),
        "calibration_tps":     cal.get("mean_tps"),
        "instruction_following_rate": round(instruct_rate, 3),
        "total_hw_cost_usd":   round(total_hw_cost, 4),
        "mean_hw_cost_per_task_usd": round(mean_hw_per_task, 6),
        "financial_cost_usd":  0.0,    # always zero for local Ollama
        "db_path":             db_path,
    }

    print(f"\n  ── Results for {model} ──────────────────")
    print(f"  Overall score:   {mean_score:.1%}  ({int(mean_score*n)}/{n})")
    print(f"  Subtask scores:  {subtask_means}")
    print(f"  Mean latency:    {mean_latency:.1f}s/task")
    print(f"  Mean tok/s:      {mean_tps:.1f}")
    print(f"  HW cost/task:    ${mean_hw_per_task:.5f}  (total ${total_hw_cost:.3f})")
    print(f"  Financial cost:  $0.00")
    print(f"  Instruction following: {instruct_rate:.1%}")

    return summary


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Open-source LLM selection benchmark")
    parser.add_argument("--models", nargs="+", default=DEFAULT_MODELS,
                        help="Ollama model tags to evaluate")
    parser.add_argument("--calibrate-only", action="store_true",
                        help="Only run speed calibration, no full eval")
    parser.add_argument("--skip-calibrate", action="store_true",
                        help="Skip speed calibration, run full eval only")
    parser.add_argument("--tasks", default=str(TASK_IDS_PATH),
                        help="Path to task_ids.json")
    args = parser.parse_args()

    with open(args.tasks) as f:
        tasks = json.load(f)
    print(f"Loaded {len(tasks)} tasks from {args.tasks}")

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    if not args.calibrate_only:
        print("\nPre-loading benchmark questions...")
        _load_question_cache(tasks)
        cached = sum(1 for t in tasks if t["task_id"] in _QUESTION_CACHE)
        print(f"  {cached}/{len(tasks)} questions ready\n")

    if args.calibrate_only:
        print("\n── Speed calibration only ──────────────────────────────")
        for model in args.models:
            client = OllamaEvalClient(model=model)
            h = client.health_check()
            if not h["model_available"]:
                print(f"{model}: not installed")
                continue
            cal = client.speed_calibration(n=3)
            tps = cal.get("mean_tps", 0)
            lat = cal.get("mean_latency_sec", 0)
            hw  = lat * _HW_COST_PER_SEC
            print(f"{model}: {tps:.1f} tok/s  |  {lat:.1f}s latency  |  ${hw:.5f}/task HW cost")
        return

    all_summaries = []
    for model in args.models:
        summary = run_model(model, tasks, skip_calibrate=args.skip_calibrate)
        all_summaries.append(summary)

    # Save combined summary
    out_path = RESULTS_DIR / "summary.json"
    with open(out_path, "w") as f:
        json.dump(all_summaries, f, indent=2)
    print(f"\n\nSummary saved to {out_path}")

    # Print comparison table
    print("\n" + "="*80)
    print("SELECTION BENCHMARK — COMPARISON TABLE")
    print("="*80)
    valid = [s for s in all_summaries if "error" not in s]
    if not valid:
        print("No valid results.")
        return

    header = f"{'Model':30s} {'Score':>7} {'tok/s':>7} {'Latency':>9} {'HW$/task':>10} {'Fin$':>6}"
    print(header)
    print("-" * 70)
    for s in sorted(valid, key=lambda x: x["mean_score"], reverse=True):
        model   = s["model"][:30]
        score   = f"{s['mean_score']:.1%}"
        tps     = f"{s['mean_tps']:.1f}"
        latency = f"{s['mean_latency_sec']:.1f}s"
        hw      = f"${s['mean_hw_cost_per_task_usd']:.5f}"
        fin     = "$0.00"
        print(f"{model:30s} {score:>7} {tps:>7} {latency:>9} {hw:>10} {fin:>6}")

    # Recommendation
    print("\n── Recommendation ──────────────────────────────────────────")
    ACCURACY_THRESHOLD  = 0.55   # must score ≥55% on selection subset
    SPEED_THRESHOLD     = 10.0   # must achieve ≥10 tok/s

    qualified = [s for s in valid
                 if s["mean_score"] >= ACCURACY_THRESHOLD
                 and (s.get("mean_tps") or 0) >= SPEED_THRESHOLD]

    if qualified:
        winner = max(qualified, key=lambda x: x["mean_score"])
        print(f"  ✅ SELECTED: {winner['model']}")
        print(f"     Score: {winner['mean_score']:.1%}  |  "
              f"Speed: {winner['mean_tps']:.1f} tok/s  |  "
              f"HW cost: ${winner['mean_hw_cost_per_task_usd']:.5f}/task")
        print(f"     Subtask breakdown: {winner['subtask_scores']}")
    else:
        best = max(valid, key=lambda x: x["mean_score"])
        print(f"  ⚠️  No model met both thresholds (≥{ACCURACY_THRESHOLD:.0%} accuracy AND ≥{SPEED_THRESHOLD} tok/s)")
        print(f"     Best candidate: {best['model']} at {best['mean_score']:.1%}")
        print(f"     Recommendation: Keep Claude Sonnet 4.6 as BioMate primary.")
        print(f"     Use {best['model']} for lightweight routing tasks to reduce API cost.")


if __name__ == "__main__":
    main()
