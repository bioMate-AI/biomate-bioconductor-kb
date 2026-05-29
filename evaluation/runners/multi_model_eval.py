#!/usr/bin/env python3
"""Unified 5-model regulatory LLM eval orchestrator.

Scores BioMate `regulatory_llm_v6`, base Qwen3-8B, Claude (Sonnet+Opus),
GPT (4o+o3-mini), and Gemini (3.5-flash+2.5-pro) on the held-out IND §2.6
corpus using all 9 checkers from `checker_suite.py`.

Output:
  evaluation/results/regulatory_llm_5model_v1/<model>.jsonl   — per-example
  evaluation/results/regulatory_llm_5model_v1/summary.csv     — model × checker

Usage:
  # Dry-run (no API keys, no GPU — verifies wiring only):
  python -m evaluation.runners.multi_model_eval --dry-run

  # Real run (subset):
  PI_LIMIT=20 ANTHROPIC_API_KEY=... OPENAI_API_KEY=... GEMINI_API_KEY=... \
      python -m evaluation.runners.multi_model_eval

  # Real run (full 326-example test split):
  ANTHROPIC_API_KEY=... OPENAI_API_KEY=... GEMINI_API_KEY=... \
      python -m evaluation.runners.multi_model_eval

The orchestrator loads ONE local model at a time (LoRA, then base) so the
GPU never needs to fit both simultaneously. Frontier API calls run in
parallel with per-provider concurrency caps (Anthropic 4, OpenAI 8, Google 4).
Resumable: checkpoints to <model>.jsonl after every example.
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
from dataclasses import asdict
from pathlib import Path
from typing import Iterable, Optional

from .adapters import (
    AnthropicAdapter, GeminiAdapter, LocalQwenAdapter, OpenAIAdapter,
    ModelAdapter, AdapterError,
)
from .checker_suite import CHECKERS, all_checker_names, run_all
from .corpus import Example, load_corpus
from .prompts import render

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
RESULTS_DIR = REPO_ROOT / "evaluation" / "results" / "regulatory_llm_5model_v1"
LORA_PATH   = REPO_ROOT / "models" / "regulatory_llm_v6" / "lora_adapter"

PROVIDER_CONCURRENCY = {
    "anthropic": 4,
    "openai": 8,
    "gemini": 4,
}


# ---------------------------------------------------------------------------
# Model registry — name → (factory, provider)
# ---------------------------------------------------------------------------

def _registry(dry_run: bool) -> list[tuple[str, callable, str]]:
    """Order matters for local: run LoRA first so its 8B base is hot in cache;
    base Qwen reuses the same base weights without re-download."""
    return [
        ("regulatory_llm_v6",   lambda: LocalQwenAdapter(lora_path=LORA_PATH, name="regulatory_llm_v6"),  "local"),
        ("qwen3_8b_base",        lambda: LocalQwenAdapter(lora_path=None,       name="qwen3_8b_base"),     "local"),
        ("claude_sonnet_4_6",    lambda: AnthropicAdapter(model="claude-sonnet-4-6"),     "anthropic"),
        ("claude_opus_4_8",      lambda: AnthropicAdapter(model="claude-opus-4-8"),       "anthropic"),
        ("gpt_5",                lambda: OpenAIAdapter(model="gpt-5"),                    "openai"),
        ("gpt_5_mini",           lambda: OpenAIAdapter(model="gpt-5-mini"),               "openai"),
        ("gemini_3_1_pro_preview", lambda: GeminiAdapter(model="gemini-3.1-pro-preview"), "gemini"),
        ("gemini_3_5_flash",     lambda: GeminiAdapter(model="gemini-3.5-flash"),         "gemini"),
    ]


# ---------------------------------------------------------------------------
# Per-example evaluation
# ---------------------------------------------------------------------------

def _eval_example(adapter: ModelAdapter, ex: Example) -> dict:
    system, user = render(adapter.style, ex)
    t0 = time.time()
    try:
        output = adapter.generate(system, user, max_new_tokens=400)
        err: Optional[str] = None
    except Exception as e:
        output = ""
        err = f"{type(e).__name__}: {e}"
    elapsed = time.time() - t0

    results = run_all(output, ex) if output else []
    passes = sum(1 for r in results if r.passed)
    total = len(results) or 1

    return {
        "example_id": ex.id,
        "section_type": ex.section_type,
        "region": ex.region,
        "output": output,
        "output_chars": len(output),
        "elapsed_s": round(elapsed, 3),
        "error": err,
        "checker_pass_count": passes,
        "checker_total": total,
        "checkers": {r.name: {"passed": r.passed, "score": r.score, "detail": r.detail}
                     for r in results},
    }


# ---------------------------------------------------------------------------
# Per-model evaluation
# ---------------------------------------------------------------------------

def _completed_ids(out_path: Path) -> set[str]:
    if not out_path.exists():
        return set()
    seen: set[str] = set()
    with out_path.open() as f:
        for line in f:
            try:
                seen.add(json.loads(line)["example_id"])
            except Exception:
                continue
    return seen


def _eval_model(
    name: str,
    factory: callable,
    provider: str,
    corpus: list[Example],
    out_path: Path,
    resume: bool = True,
) -> None:
    done = _completed_ids(out_path) if resume else set()
    pending = [ex for ex in corpus if ex.id not in done]
    if not pending:
        print(f"[{name}] all {len(corpus)} examples already evaluated; skipping")
        return
    print(f"[{name}] starting — pending={len(pending)} done={len(done)}")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    adapter = factory()
    try:
        if provider == "local":
            # Sequential — GPU can't share generation safely
            with out_path.open("a") as out_f:
                for i, ex in enumerate(pending, 1):
                    row = _eval_example(adapter, ex)
                    out_f.write(json.dumps(row) + "\n")
                    out_f.flush()
                    if i % 10 == 0:
                        print(f"[{name}] {i}/{len(pending)} done")
        else:
            cap = PROVIDER_CONCURRENCY[provider]
            with ThreadPoolExecutor(max_workers=cap) as pool, out_path.open("a") as out_f:
                futures = {pool.submit(_eval_example, adapter, ex): ex.id for ex in pending}
                for i, fut in enumerate(as_completed(futures), 1):
                    row = fut.result()
                    out_f.write(json.dumps(row) + "\n")
                    out_f.flush()
                    if i % 10 == 0:
                        print(f"[{name}] {i}/{len(pending)} done")
    finally:
        adapter.close()


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

def _write_summary(results_dir: Path, model_names: list[str]) -> None:
    """Aggregate every <model>.jsonl found in results_dir into summary.csv.

    Walks the whole directory rather than just `model_names` so that running
    with `--models foo` doesn't clobber earlier rows for other models.
    """
    summary_path = results_dir / "summary.csv"
    checker_names = all_checker_names()
    rows = []
    found = sorted({p.stem for p in results_dir.glob("*.jsonl") if p.stem != "summary"})
    for name in found:
        path = results_dir / f"{name}.jsonl"
        if not path.exists():
            continue
        per_checker_pass: dict[str, int] = defaultdict(int)
        per_checker_total: dict[str, int] = defaultdict(int)
        n_examples = 0
        for line in path.open():
            try:
                rec = json.loads(line)
            except Exception:
                continue
            n_examples += 1
            for cn in checker_names:
                c = rec.get("checkers", {}).get(cn)
                if c is None:
                    continue
                per_checker_total[cn] += 1
                if c.get("passed"):
                    per_checker_pass[cn] += 1
        row = {"model": name, "n_examples": n_examples}
        macro = 0.0
        for cn in checker_names:
            denom = per_checker_total[cn] or 1
            rate = per_checker_pass[cn] / denom
            row[cn] = round(rate, 4)
            macro += rate
        row["macro_avg"] = round(macro / max(1, len(checker_names)), 4)
        rows.append(row)

    if not rows:
        print("[summary] no model results yet; skipping summary write")
        return
    with summary_path.open("w", newline="") as f:
        writer = csv.DictWriter(
            f, fieldnames=["model", "n_examples"] + checker_names + ["macro_avg"]
        )
        writer.writeheader()
        writer.writerows(rows)
    print(f"[summary] wrote {summary_path}")


# ---------------------------------------------------------------------------
# Main + dry-run
# ---------------------------------------------------------------------------

def _dry_run() -> int:
    """Validate wiring without touching network or GPU."""
    print("=== DRY RUN ===")
    print("[corpus] loading test split…")
    corpus = load_corpus(limit=3)
    print(f"[corpus] {len(corpus)} examples loaded (sample of 3)")
    for ex in corpus:
        print(f"  - {ex.short} prompt={ex.user_prompt[:60]!r}")

    print("[checkers] registry:")
    for name in all_checker_names():
        print(f"  - {name}")

    print("[adapters] instantiating (lazy — no network/GPU yet)…")
    for name, factory, provider in _registry(dry_run=True):
        try:
            adapter = factory()
            assert hasattr(adapter, "generate") and hasattr(adapter, "close")
            assert adapter.style in ("sft_style", "instruction_style")
            print(f"  - {name:<22} provider={provider:<10} style={adapter.style}")
        except Exception as e:
            print(f"  - {name:<22} FAILED to construct: {e}")
            return 2

    print("[checkers] running on a synthetic output for the first example…")
    synthetic = (
        "[BioMate-generated draft] The NOAEL of 15 mg/kg/day was identified per "
        "ICH M3(R2). At the 50 mg/kg high dose, hepatocellular hypertrophy was observed."
    )
    for r in run_all(synthetic, corpus[0]):
        print(f"  - {r.name:<28} passed={r.passed!s:<5} detail={r.detail}")

    print("DRY RUN OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true",
                        help="Validate wiring without network/GPU; does not score")
    parser.add_argument("--limit", type=int, default=None,
                        help="Number of corpus examples (default: full split)")
    parser.add_argument("--models", nargs="*", default=None,
                        help="Subset of model names to run (default: all)")
    parser.add_argument("--results-dir", default=str(RESULTS_DIR))
    parser.add_argument("--no-resume", action="store_true",
                        help="Re-evaluate even examples already in the JSONL")
    args = parser.parse_args(argv)

    if args.dry_run:
        return _dry_run()

    limit = args.limit or (int(os.environ["PI_LIMIT"]) if os.environ.get("PI_LIMIT") else None)
    corpus = load_corpus(limit=limit)
    print(f"[corpus] {len(corpus)} examples to score")

    registry = _registry(dry_run=False)
    if args.models:
        registry = [r for r in registry if r[0] in set(args.models)]
        if not registry:
            print("no models match --models filter; aborting")
            return 2

    results_dir = Path(args.results_dir)
    results_dir.mkdir(parents=True, exist_ok=True)

    for name, factory, provider in registry:
        out_path = results_dir / f"{name}.jsonl"
        try:
            _eval_model(name, factory, provider, corpus, out_path, resume=not args.no_resume)
        except AdapterError as e:
            print(f"[{name}] adapter error: {e} — skipping")
        except KeyboardInterrupt:
            print(f"\n[{name}] interrupted — partial results in {out_path}")
            raise

    model_names = [r[0] for r in registry]
    _write_summary(results_dir, model_names)
    return 0


if __name__ == "__main__":
    sys.exit(main())
