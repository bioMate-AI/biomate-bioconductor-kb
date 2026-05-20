"""
A/B measurement: memory recall with vs without prioritize_memory_by_intent.

Baseline simulates the current auto-memory recall behavior by scoring each
memory file's basename + first 300 chars of content against the query
(token overlap with stopwords removed — a generous approximation of what
fuzzy keyword search would do).

Treatment applies the memory adapter on top of the baseline ranking. The
adapter is opt-in via inject_canonical=True (default for memory recall
because the canonical file often doesn't rank well in pure lexical search).

Output: top-1 hit rates side by side, plus per-query flips.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import yaml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from sandbox.intent_retrieval_v3.adapters.memory import (  # noqa: E402
    prioritize_memory_by_intent,
)
from sandbox.intent_retrieval_v3.core.yaml_loader import reset_loader_cache  # noqa: E402

MEM_DIR = Path.home() / ".claude/projects/-home-yzhang-biomate/memory"
EVAL_YAML = Path(__file__).resolve().parents[1] / "data" / "memory_eval_set.yaml"
OUT_DOC = Path(__file__).resolve().parents[1] / "docs" / "20260519_memory_lift_results.md"

_STOP = {"the", "a", "an", "and", "or", "of", "in", "on", "at", "to", "for",
         "with", "what", "show", "tell", "me", "is", "are", "was", "were",
         "about", "remind", "summarize", "from", "by", "be", "do", "did",
         "have", "has", "had", "this", "that", "these", "those", "our",
         "we", "us", "i", "my", "your"}


def _tokens(s: str) -> set:
    return {t for t in re.findall(r"[a-zA-Z][a-zA-Z0-9]+", s.lower())
            if len(t) >= 3 and t not in _STOP}


def baseline_search(query: str, memory_files: List[Path], limit: int = 10
                      ) -> List[str]:
    """Approximate auto-memory's fuzzy match by scoring each file on token
    overlap between query and (basename + first 300 chars of content).
    Returns ranked list of basenames."""
    q_toks = _tokens(query)
    scored: List[Tuple[float, str]] = []
    for f in memory_files:
        name_toks = _tokens(f.stem)
        try:
            head = f.read_text(encoding="utf-8")[:300]
        except Exception:
            head = ""
        head_toks = _tokens(head)
        # Token overlap with name-tokens weighted more strongly than head-tokens
        score = 3.0 * len(q_toks & name_toks) + 1.0 * len(q_toks & head_toks)
        if score > 0:
            scored.append((score, f.name))
    scored.sort(key=lambda x: -x[0])
    return [n for _, n in scored[:limit]]


def main() -> int:
    if not MEM_DIR.exists():
        print(f"ERROR: memory dir not found at {MEM_DIR}", file=sys.stderr)
        return 1
    cases = yaml.safe_load(EVAL_YAML.read_text())
    files = sorted(p for p in MEM_DIR.glob("*.md") if p.is_file())
    print(f"Loaded {len(cases)} eval cases against {len(files)} memory files\n")

    reset_loader_cache()

    n = len(cases)
    b_top1 = t_top1 = 0
    b_top3 = t_top3 = 0
    flips_correct: List[Dict] = []
    flips_wrong: List[Dict] = []
    no_change: List[Dict] = []

    for c in cases:
        baseline = baseline_search(c["query"], files, limit=10)
        treated = prioritize_memory_by_intent(c["query"], baseline,
                                                inject_canonical=True)
        b_t1 = (baseline[0] == c["expected"]) if baseline else False
        t_t1 = (treated[0] == c["expected"]) if treated else False
        b_t3 = c["expected"] in baseline[:3]
        t_t3 = c["expected"] in treated[:3]
        if b_t1: b_top1 += 1
        if t_t1: t_top1 += 1
        if b_t3: b_top3 += 1
        if t_t3: t_top3 += 1

        if not b_t1 and t_t1:
            flips_correct.append({"id": c["id"], "query": c["query"],
                                    "expected": c["expected"],
                                    "baseline": baseline[:3]})
        elif b_t1 and not t_t1:
            flips_wrong.append({"id": c["id"], "query": c["query"],
                                 "expected": c["expected"],
                                 "treated": treated[:3]})
        elif not b_t1 and not t_t1:
            no_change.append({"id": c["id"], "query": c["query"],
                              "expected": c["expected"],
                              "baseline": baseline[:3], "treated": treated[:3]})

    print(f"=== Memory recall A/B (n={n}) ===")
    print(f"  BASELINE top-1: {b_top1}/{n} ({100*b_top1/n:.1f}%)  top-3: {b_top3}/{n} ({100*b_top3/n:.1f}%)")
    print(f"  TREATMENT top-1: {t_top1}/{n} ({100*t_top1/n:.1f}%)  top-3: {t_top3}/{n} ({100*t_top3/n:.1f}%)")
    print(f"  Top-1 Δ: {t_top1 - b_top1:+d}  ({100*(t_top1-b_top1)/n:+.1f}pp)")
    print(f"  Flips to correct: {len(flips_correct)}")
    print(f"  Flips to wrong:   {len(flips_wrong)}")

    OUT_DOC.parent.mkdir(parents=True, exist_ok=True)
    with OUT_DOC.open("w", encoding="utf-8") as f:
        f.write("# Memory-Recall A/B Lift Results (n=20)\n\n")
        f.write(f"**Date:** 2026-05-19\n")
        f.write(f"**Source:** sandbox/intent_retrieval_v3/data/memory_eval_set.yaml\n")
        f.write(f"**Library:** sandbox/intent_retrieval_v3/adapters/memory.py\n")
        f.write(f"**Intents:** sandbox/intent_retrieval_v3/data/memory_intents.yaml (8 entries)\n")
        f.write(f"**Memory files indexed:** {len(files)}\n\n")
        f.write("## Headline\n\n")
        f.write("| Method | Top-1 | Top-3 |\n|---|---|---|\n")
        f.write(f"| BASELINE (lexical overlap) | {b_top1}/{n} ({100*b_top1/n:.1f}%) | "
                f"{b_top3}/{n} ({100*b_top3/n:.1f}%) |\n")
        f.write(f"| **TREATMENT (+ memory adapter)** | "
                f"**{t_top1}/{n} ({100*t_top1/n:.1f}%)** | "
                f"**{t_top3}/{n} ({100*t_top3/n:.1f}%)** |\n")
        f.write(f"| Δ top-1 | **{t_top1 - b_top1:+d}** ({100*(t_top1-b_top1)/n:+.1f}pp) | "
                f"{t_top3 - b_top3:+d} ({100*(t_top3-b_top3)/n:+.1f}pp) |\n\n")

        f.write(f"## Flips to correct ({len(flips_correct)})\n\n")
        for fl in flips_correct:
            f.write(f"- **{fl['id']}** `{fl['query'][:70]}`\n")
            f.write(f"  - expected: `{fl['expected']}`\n")
            f.write(f"  - baseline top-3: `{fl['baseline']}`\n")

        f.write(f"\n## Flips to wrong ({len(flips_wrong)})\n\n")
        if not flips_wrong:
            f.write("**None.** Memory adapter never demoted a correct top-1.\n")
        for fl in flips_wrong:
            f.write(f"- **{fl['id']}** `{fl['query'][:70]}`\n")
            f.write(f"  - expected: `{fl['expected']}`\n")
            f.write(f"  - treated top-3: `{fl['treated']}`\n")

        f.write(f"\n## Still failing ({len(no_change)})\n\n")
        for fl in no_change:
            f.write(f"- **{fl['id']}** `{fl['query'][:70]}`\n")
            f.write(f"  - expected: `{fl['expected']}`\n")
            f.write(f"  - baseline top-3: `{fl['baseline']}`\n")
            f.write(f"  - treated top-3: `{fl['treated']}`\n")

    print(f"\nWrote {OUT_DOC.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
