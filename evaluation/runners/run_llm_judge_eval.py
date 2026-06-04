#!/usr/bin/env python3
"""LLM-judge eval orchestrator (v2).

Loads cached per-model jsonl outputs (the GPU runs are NOT re-executed - only
the judge call is new), joins each output with its prompt via corpus.load_corpus,
calls score_with_judge per example, writes results + summary.csv.

Inputs:
  evaluation/results/regulatory_llm_v2_judge/raw_inputs/<model>.jsonl
    - each line has at least example_id, section_type, output

Outputs:
  evaluation/results/regulatory_llm_v2_judge/<model>.jsonl
  evaluation/results/regulatory_llm_v2_judge/summary.csv

Usage:
  python -m evaluation.runners.run_llm_judge_eval --models regulatory_llm_v6 qwen3_8b_base gpt_5 claude_sonnet_4_6
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Optional

from .corpus import load_corpus
from .checker_suite_v2 import (
    score_with_judge,
    RUBRIC_DIMENSIONS,
    JUDGE_MODEL_DEFAULT,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
RESULTS_DIR = REPO_ROOT / "evaluation" / "results" / "regulatory_llm_v2_judge"
RAW_DIR = RESULTS_DIR / "raw_inputs"

DEFAULT_MODELS = [
    "regulatory_llm_v6",
    "qwen3_8b_base",
    "gpt_5",
    "claude_sonnet_4_6",
]


def _load_raw(model: str) -> list[dict]:
    p = RAW_DIR / f"{model}.jsonl"
    if not p.exists():
        raise FileNotFoundError(f"raw outputs not staged: {p}")
    out = []
    with p.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def _build_prompt_map() -> dict[str, tuple[str, str]]:
    """example_id -> (section_type, user_prompt)."""
    corpus = load_corpus(limit=None)
    return {ex.id: (ex.section_type, ex.user_prompt) for ex in corpus}


def _completed_ids(path: Path) -> set[str]:
    if not path.exists():
        return set()
    seen = set()
    with path.open() as f:
        for line in f:
            try:
                seen.add(json.loads(line)["example_id"])
            except Exception:
                continue
    return seen


def _judge_one(rec: dict, prompt_map: dict, judge_model: str) -> dict:
    ex_id = rec.get("example_id")
    section = rec.get("section_type") or prompt_map.get(ex_id, ("unknown", ""))[0]
    prompt = prompt_map.get(ex_id, ("", ""))[1]
    output = rec.get("output") or ""
    res = score_with_judge(section, prompt, output, judge_model=judge_model)
    return {
        "example_id": ex_id,
        "section_type": section,
        "output_chars": len(output),
        "rubric_scores": res.rubric_scores,
        "macro": res.macro,
        "rationale": res.rationale,
        "error": res.error,
    }


def _eval_model(model: str, prompt_map: dict, judge_model: str, concurrency: int, resume: bool) -> None:
    raw = _load_raw(model)
    out_path = RESULTS_DIR / f"{model}.jsonl"
    done = _completed_ids(out_path) if resume else set()
    pending = [r for r in raw if r.get("example_id") not in done]
    print(f"[{model}] pending={len(pending)} done={len(done)} total={len(raw)}")
    if not pending:
        return
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=concurrency) as pool, out_path.open("a") as out_f:
        futs = {pool.submit(_judge_one, r, prompt_map, judge_model): r for r in pending}
        for i, fut in enumerate(as_completed(futs), 1):
            try:
                row = fut.result()
            except Exception as e:
                row = {"example_id": futs[fut].get("example_id"), "error": f"{type(e).__name__}: {e}", "macro": 0.0, "rubric_scores": {d: 0 for d in RUBRIC_DIMENSIONS}}
            out_f.write(json.dumps(row) + "\n")
            out_f.flush()
            if i % 10 == 0:
                print(f"[{model}] {i}/{len(pending)}")


def _write_summary() -> None:
    summary_path = RESULTS_DIR / "summary.csv"
    rows = []
    for jp in sorted(RESULTS_DIR.glob("*.jsonl")):
        model = jp.stem
        if model == "summary":
            continue
        n = 0
        macro_sum = 0.0
        per_dim_sum = defaultdict(float)
        errs = 0
        with jp.open() as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                n += 1
                macro_sum += float(rec.get("macro") or 0.0)
                rs = rec.get("rubric_scores") or {}
                for d in RUBRIC_DIMENSIONS:
                    per_dim_sum[d] += float(rs.get(d, 0))
                if rec.get("error"):
                    errs += 1
        if n == 0:
            continue
        row = {"model": model, "n": n, "errors": errs,
               "macro_avg": round(macro_sum / n, 4)}
        for d in RUBRIC_DIMENSIONS:
            # normalize per-dim avg to 0..1 (max 2 per example)
            row[d] = round(per_dim_sum[d] / (2 * n), 4)
        rows.append(row)
    if not rows:
        print("[summary] no results")
        return
    fields = ["model", "n", "errors", "macro_avg"] + RUBRIC_DIMENSIONS
    with summary_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    print(f"[summary] wrote {summary_path}")
    for r in rows:
        print(f"  {r['model']:<28} n={r['n']:>3} macro={r['macro_avg']:.4f}")


def main(argv=None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--models", nargs="*", default=DEFAULT_MODELS)
    p.add_argument("--judge-model", default=JUDGE_MODEL_DEFAULT)
    p.add_argument("--concurrency", type=int, default=4)
    p.add_argument("--no-resume", action="store_true")
    p.add_argument("--summary-only", action="store_true")
    args = p.parse_args(argv)

    if args.summary_only:
        _write_summary()
        return 0

    prompt_map = _build_prompt_map()
    print(f"[corpus] loaded {len(prompt_map)} prompts")

    for model in args.models:
        try:
            _eval_model(model, prompt_map, args.judge_model, args.concurrency, resume=not args.no_resume)
        except FileNotFoundError as e:
            print(f"[{model}] skipped: {e}")
        except KeyboardInterrupt:
            print(f"[{model}] interrupted")
            break

    _write_summary()
    return 0


if __name__ == "__main__":
    sys.exit(main())
