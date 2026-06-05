"""Defensible multi-task cross-judge eval.

Stratified sample from the actual v6 test split (n=326, 7 task types) +
cross-judge with Claude Opus + GPT-5 + Gemini. Replaces the n=200
section_generation-only pilot which was an unfair comparison.

Output:
  evaluation/results/multitask_crossjudge_v1/
    sample_pool.jsonl                       (the stratified sample)
    <model>_<judge>.jsonl                   (per-judge raw scores)
    summary_per_task.csv                    (per-task per-model means)
    summary_overall.csv                     (overall means + bootstrap CIs)
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import statistics
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "evaluation" / "runners"))

from adapters.anthropic_adapter import AnthropicAdapter
from adapters.gemini_adapter import GeminiAdapter
from adapters.openai_adapter import OpenAIAdapter
from checker_suite_v2 import RUBRIC_DIMENSIONS, score_with_judge

OUT_DIR = REPO_ROOT / "evaluation" / "results" / "multitask_crossjudge_v1"
OUT_DIR.mkdir(parents=True, exist_ok=True)

V6_TEST_PATH = REPO_ROOT / "data" / "regulatory_training" / "tasks" / "splits_v6" / "test.jsonl"

TASK_SECTION_GUESS = {
    "section_generation": "tox_overview",
    "skeleton_completion": "tox_overview",
    "region_adaptation": "tox_overview",
    "tabulated_summary": "tox_overview",
    "mrsd_computation": "tox_overview",
    "adversity_language": "tox_overview",
    "phase_gating": "pbpk",
}


# ---------------------------------------------------------------------------
# Stratified sample
# ---------------------------------------------------------------------------

def stratified_sample(path: Path, per_task: int, seed: int = 42) -> list[dict]:
    records = [json.loads(l) for l in path.read_text().splitlines() if l.strip()]
    by_task = defaultdict(list)
    for r in records:
        t = r.get("meta", {}).get("task", "?")
        by_task[t].append(r)
    rng = random.Random(seed)
    out = []
    for task, group in by_task.items():
        if task == "?":
            continue
        rng.shuffle(group)
        for i, r in enumerate(group[:per_task]):
            sec_type = r.get("meta", {}).get("section_type") or TASK_SECTION_GUESS.get(task, "tox_overview")
            out.append({
                "example_id": f"{task}_{i:03d}",
                "task": task,
                "section_type": sec_type,
                "system_prompt": r["messages"][0]["content"],
                "user_prompt": r["messages"][1]["content"],
                "target": r["messages"][2]["content"] if len(r["messages"]) > 2 else "",
                "meta": r.get("meta", {}),
            })
    return out


# ---------------------------------------------------------------------------
# Candidate generation
# ---------------------------------------------------------------------------

def run_candidate(model_label: str, ex: dict) -> dict:
    if model_label == "gpt_5":
        adapter = OpenAIAdapter(model="gpt-5")
    elif model_label == "gpt_5_mini":
        adapter = OpenAIAdapter(model="gpt-5-mini")
    elif model_label == "claude_sonnet_4_6":
        adapter = AnthropicAdapter(model="claude-sonnet-4-6")
    elif model_label == "claude_haiku_4_5":
        adapter = AnthropicAdapter(model="claude-haiku-4-5")
    elif model_label == "gemini_3_1_pro_preview":
        adapter = GeminiAdapter(model="gemini-3.1-pro-preview")
    elif model_label == "gemini_3_5_flash":
        adapter = GeminiAdapter(model="gemini-3.5-flash")
    else:
        return {"output": "", "elapsed_s": 0, "error": f"unknown {model_label}"}
    t0 = time.time()
    try:
        out = adapter.generate(ex["system_prompt"], ex["user_prompt"], max_new_tokens=500)
        return {"output": out, "elapsed_s": round(time.time() - t0, 2), "error": None}
    except Exception as exc:
        return {"output": "", "elapsed_s": round(time.time() - t0, 2), "error": str(exc)}


# ---------------------------------------------------------------------------
# Cross-judge: 3 judges, median per dimension
# ---------------------------------------------------------------------------

JUDGES = ["claude-opus-4-7", "gpt-5", "gemini-3.1-pro-preview"]


def score_with_judge_safe(judge_model: str, **kw) -> dict:
    """Wraps score_with_judge — returns {scores, macro, rationale, error}."""
    try:
        from checker_suite_v2 import _call_judge
    except Exception:
        pass
    try:
        result = score_with_judge(judge_model=judge_model, **kw)
        return {
            "judge": judge_model,
            "rubric_scores": result.rubric_scores,
            "macro": result.macro,
            "rationale": result.rationale,
            "error": None,
        }
    except Exception as exc:
        return {
            "judge": judge_model,
            "rubric_scores": {d: 0 for d in RUBRIC_DIMENSIONS},
            "macro": 0.0,
            "rationale": "",
            "error": str(exc),
        }


def cross_judge(ex: dict, candidate_output: str) -> dict:
    """Score candidate with all 3 judges, take per-dimension median."""
    prompt = (
        f"section_type: {ex['section_type']}\n"
        f"task: {ex['task']}\n"
        f"target_reference (for grading): {ex.get('target','')[:500]}"
    )
    per_judge = []
    for j in JUDGES:
        per_judge.append(score_with_judge_safe(
            judge_model=j,
            section_type=ex["section_type"],
            prompt=prompt,
            candidate=candidate_output,
        ))
    # Median per dimension across judges (drop judges that errored)
    valid = [p for p in per_judge if not p["error"]]
    median_scores = {}
    for dim in RUBRIC_DIMENSIONS:
        vals = [p["rubric_scores"].get(dim, 0) for p in valid]
        median_scores[dim] = statistics.median(vals) if vals else 0
    macro = sum(median_scores.values()) / (2.0 * len(RUBRIC_DIMENSIONS)) if valid else 0.0
    return {"median_scores": median_scores, "median_macro": macro, "per_judge": per_judge}


# ---------------------------------------------------------------------------
# Bootstrap CIs
# ---------------------------------------------------------------------------

def bootstrap_ci(values: list[float], n_boot: int = 1000, ci: float = 0.95) -> tuple[float, float]:
    if not values:
        return (0.0, 0.0)
    rng = random.Random(0xB007)
    means = []
    n = len(values)
    for _ in range(n_boot):
        sample = [values[rng.randrange(n)] for _ in range(n)]
        means.append(sum(sample) / n)
    means.sort()
    lo = means[int((1 - ci) / 2 * n_boot)]
    hi = means[int((1 + ci) / 2 * n_boot)]
    return (lo, hi)


# ---------------------------------------------------------------------------
# Orchestrate
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-task", type=int, default=10,
                        help="Stratified sample size per task")
    parser.add_argument("--models", nargs="+", default=["gpt_5", "claude_sonnet_4_6"])
    parser.add_argument("--judges", nargs="+", default=JUDGES)
    parser.add_argument("--resume", action="store_true",
                        help="Skip examples that already have all judges scored")
    args = parser.parse_args()

    globals()["JUDGES"] = args.judges

    print(f"[1] Stratified sample from {V6_TEST_PATH.name} ({args.per_task} per task)...")
    sample = stratified_sample(V6_TEST_PATH, args.per_task)
    print(f"    pulled {len(sample)} examples")
    sample_path = OUT_DIR / "sample_pool.jsonl"
    with sample_path.open("w") as f:
        for ex in sample:
            f.write(json.dumps(ex) + "\n")

    if not sample:
        return 1

    # Per-model jsonl that captures BOTH the output and the cross-judge median
    print(f"\n[2] Running {len(args.models)} models × cross-judge ({len(JUDGES)} judges) on n={len(sample)}...")
    print(f"    Expected ~{len(sample) * len(args.models) * (1 + len(JUDGES))} API calls")
    per_model: dict[str, list[dict]] = {m: [] for m in args.models}
    for model in args.models:
        out_path = OUT_DIR / f"{model}.jsonl"
        # Resume: load existing rows
        seen_ids = set()
        if args.resume and out_path.exists():
            for line in out_path.read_text().splitlines():
                if line.strip():
                    try:
                        seen_ids.add(json.loads(line)["example_id"])
                    except Exception:
                        pass
        mode = "a" if args.resume and out_path.exists() else "w"
        with out_path.open(mode) as f:
            for ex in sample:
                if ex["example_id"] in seen_ids:
                    continue
                print(f"  [{model}] {ex['example_id']} (task={ex['task']})...", end="", flush=True)
                cand = run_candidate(model, ex)
                if cand.get("error") or not cand.get("output"):
                    row = {
                        "example_id": ex["example_id"],
                        "task": ex["task"],
                        "model": model,
                        "output": cand.get("output", ""),
                        "error": cand.get("error"),
                        "median_macro": 0.0,
                    }
                    f.write(json.dumps(row) + "\n")
                    f.flush()
                    per_model[model].append(row)
                    print(" ERROR")
                    continue
                cj = cross_judge(ex, cand["output"])
                row = {
                    "example_id": ex["example_id"],
                    "task": ex["task"],
                    "section_type": ex["section_type"],
                    "model": model,
                    "output": cand["output"],
                    "elapsed_s": cand["elapsed_s"],
                    "median_scores": cj["median_scores"],
                    "median_macro": cj["median_macro"],
                    "per_judge": cj["per_judge"],
                }
                f.write(json.dumps(row) + "\n")
                f.flush()
                per_model[model].append(row)
                print(f" median={cj['median_macro']:.2f}")
        # Re-load full set including resumed rows
        per_model[model] = []
        for line in out_path.read_text().splitlines():
            if line.strip():
                per_model[model].append(json.loads(line))
        print(f"  -> {out_path} ({len(per_model[model])} rows)")

    print(f"\n[3] Per-task summary:")
    by_task: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    for model, rows in per_model.items():
        for r in rows:
            if r.get("error") or "median_macro" not in r:
                continue
            by_task[r["task"]][model].append(r["median_macro"])

    print(f"{'task':<24} {'n':<5} " + " ".join(f"{m:<18}" for m in args.models))
    csv_rows = []
    for task in sorted(by_task.keys()):
        n = len(next(iter(by_task[task].values()))) if by_task[task] else 0
        line = f"{task:<24} {n:<5} "
        for model in args.models:
            scores = by_task[task].get(model, [])
            mean = sum(scores) / len(scores) if scores else 0.0
            lo, hi = bootstrap_ci(scores) if scores else (0.0, 0.0)
            line += f"{mean:.3f} [{lo:.2f},{hi:.2f}] "
            csv_rows.append({"task": task, "model": model, "n": len(scores),
                             "mean": round(mean, 3), "ci_lo": round(lo, 3), "ci_hi": round(hi, 3)})
        print(line)
    (OUT_DIR / "summary_per_task.csv").open("w").close()
    with (OUT_DIR / "summary_per_task.csv").open("w") as f:
        w = csv.DictWriter(f, fieldnames=["task", "model", "n", "mean", "ci_lo", "ci_hi"])
        w.writeheader()
        for r in csv_rows:
            w.writerow(r)

    print(f"\n[4] Overall summary (median across all tasks):")
    overall = {}
    for model, rows in per_model.items():
        scores = [r["median_macro"] for r in rows if "median_macro" in r and not r.get("error")]
        mean = sum(scores) / len(scores) if scores else 0.0
        lo, hi = bootstrap_ci(scores) if scores else (0.0, 0.0)
        overall[model] = {"mean": mean, "n": len(scores), "ci_lo": lo, "ci_hi": hi}
        print(f"  {model}: mean={mean:.3f}  [{lo:.3f}, {hi:.3f}]  n={len(scores)}")

    with (OUT_DIR / "summary_overall.csv").open("w") as f:
        w = csv.writer(f)
        w.writerow(["model", "n", "mean_median_macro", "ci_lo", "ci_hi"])
        for m, s in overall.items():
            w.writerow([m, s["n"], f"{s['mean']:.3f}", f"{s['ci_lo']:.3f}", f"{s['ci_hi']:.3f}"])

    print(f"\nWrote summary_per_task.csv + summary_overall.csv to {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
