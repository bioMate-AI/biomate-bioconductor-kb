"""
Memory recall A/B with HELD-OUT subset reporting.

Splits the eval set into:
  - 'covered': queries the intent_anchors YAML has entries for
  - 'heldout': queries the YAML doesn't cover

Reports baseline / treatment top-1 separately for each subset. The honest
test is whether the adapter (a) lifts the covered set without harming the
held-out set, and (b) doesn't introduce false positives on held-out queries.

Output: sandbox/intent_retrieval_v3/docs/20260520_memory_heldout_results.md
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import yaml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from sandbox.intent_retrieval_v3.adapters.memory import prioritize_memory_by_intent  # noqa: E402
from sandbox.intent_retrieval_v3.core.yaml_loader import reset_loader_cache  # noqa: E402

MEM_DIR = Path.home() / ".claude/projects/-home-yzhang-biomate/memory"
EVAL_YAML = Path(__file__).resolve().parents[1] / "data" / "memory_eval_set_v2.yaml"
OUT_DOC = Path(__file__).resolve().parents[1] / "docs" / "20260520_memory_heldout_results.md"

_STOP = {"the", "a", "an", "and", "or", "of", "in", "on", "at", "to", "for",
         "with", "what", "show", "tell", "me", "is", "are", "was", "were",
         "about", "remind", "summarize", "from", "by", "be", "do", "did",
         "have", "has", "had", "this", "that", "these", "those", "our",
         "we", "us", "i", "my", "your"}


def _tokens(s: str) -> set:
    return {t for t in re.findall(r"[a-zA-Z][a-zA-Z0-9]+", s.lower())
            if len(t) >= 3 and t not in _STOP}


def baseline_search(query: str, files: List[Path], limit: int = 10) -> List[str]:
    q = _tokens(query)
    scored: List[Tuple[float, str]] = []
    for f in files:
        n = _tokens(f.stem)
        try: head = f.read_text(encoding="utf-8")[:300]
        except Exception: head = ""
        h = _tokens(head)
        s = 3.0 * len(q & n) + 1.0 * len(q & h)
        if s > 0: scored.append((s, f.name))
    scored.sort(key=lambda x: -x[0])
    return [n for _, n in scored[:limit]]


def main() -> int:
    cases = yaml.safe_load(EVAL_YAML.read_text())
    files = sorted(p for p in MEM_DIR.glob("*.md") if p.is_file())
    print(f"Loaded {len(cases)} eval cases against {len(files)} memory files")
    reset_loader_cache()

    # Bucket by set
    sets = {"covered": [], "heldout": []}
    for c in cases:
        sets.setdefault(c.get("set", "unknown"), []).append(c)

    results: Dict[str, Dict] = {}
    flips_correct: Dict[str, List] = {"covered": [], "heldout": []}
    flips_wrong: Dict[str, List] = {"covered": [], "heldout": []}

    for set_name, set_cases in sets.items():
        n = len(set_cases)
        b1 = t1 = b3 = t3 = 0
        for c in set_cases:
            baseline = baseline_search(c["query"], files, limit=10)
            treated = prioritize_memory_by_intent(c["query"], baseline,
                                                    inject_canonical=True)
            b_t1 = baseline and baseline[0] == c["expected"]
            t_t1 = treated and treated[0] == c["expected"]
            if b_t1: b1 += 1
            if t_t1: t1 += 1
            if c["expected"] in baseline[:3]: b3 += 1
            if c["expected"] in treated[:3]: t3 += 1
            if not b_t1 and t_t1:
                flips_correct[set_name].append({"id": c["id"], "query": c["query"],
                                                  "expected": c["expected"],
                                                  "baseline_top1": baseline[0] if baseline else None})
            elif b_t1 and not t_t1:
                flips_wrong[set_name].append({"id": c["id"], "query": c["query"],
                                                "expected": c["expected"],
                                                "treated_top1": treated[0]})
        results[set_name] = dict(n=n, b1=b1, t1=t1, b3=b3, t3=t3)

    # ── Print ─────────────────────────────────────────────────────────
    print(f"\n=== Memory recall A/B (n={len(cases)}, split by intent-coverage) ===")
    print(f"{'subset':<10} {'n':>3}  baseline_top1  treatment_top1   Δ")
    print("-" * 65)
    for k in ("covered", "heldout"):
        r = results.get(k);
        if not r: continue
        d = r["t1"] - r["b1"]
        print(f"  {k:<8} {r['n']:>3}    {r['b1']}/{r['n']} ({100*r['b1']/r['n']:.0f}%)        "
              f"{r['t1']}/{r['n']} ({100*r['t1']/r['n']:.0f}%)         {d:+d}")
    # Combined
    cb = sum(r["b1"] for r in results.values()); ct = sum(r["t1"] for r in results.values())
    cn = sum(r["n"] for r in results.values())
    print(f"  {'TOTAL':<8} {cn:>3}    {cb}/{cn} ({100*cb/cn:.0f}%)        "
          f"{ct}/{cn} ({100*ct/cn:.0f}%)         {ct-cb:+d}")
    print(f"\n  False positives: covered={len(flips_wrong['covered'])} "
          f"heldout={len(flips_wrong['heldout'])}")

    # ── Write markdown ────────────────────────────────────────────────
    OUT_DOC.parent.mkdir(parents=True, exist_ok=True)
    with OUT_DOC.open("w", encoding="utf-8") as f:
        f.write("# Memory-Recall A/B — Held-Out Subset Honest Measurement\n\n")
        f.write("**Date:** 2026-05-20\n")
        f.write(f"**Source:** `sandbox/intent_retrieval_v3/data/memory_eval_set_v2.yaml` (n=50)\n")
        f.write(f"**Library:** `sandbox/intent_retrieval_v3/adapters/memory.py`\n")
        f.write(f"**Intents:** `sandbox/intent_retrieval_v3/data/memory_intents.yaml` (10 entries)\n")
        f.write(f"**Memory files indexed:** {len(files)}\n\n")
        f.write("## Why this run exists\n\n")
        f.write("The earlier 20-case A/B (`20260519_memory_lift_results.md`) hit "
                "100% top-1 after 2 alias entries were added to close 2 specific misses. "
                "That risks overfitting. This run splits the eval into a **covered** "
                "subset (20 queries the intent YAML has entries for) and a **held-out** "
                "subset (30 queries with NO intent entries). Honest measurement of "
                "whether the adapter helps queries it wasn't curated for.\n\n")
        f.write("## Headline\n\n")
        f.write("| Subset | n | BASELINE top-1 | TREATMENT top-1 | Δ |\n|---|---|---|---|---|\n")
        for k in ("covered", "heldout"):
            r = results.get(k)
            if not r: continue
            d = r["t1"] - r["b1"]
            f.write(f"| {k} | {r['n']} | {r['b1']}/{r['n']} ({100*r['b1']/r['n']:.0f}%) | "
                    f"{r['t1']}/{r['n']} ({100*r['t1']/r['n']:.0f}%) | {d:+d} |\n")
        f.write(f"| **TOTAL** | {cn} | {cb}/{cn} ({100*cb/cn:.0f}%) | "
                f"{ct}/{cn} ({100*ct/cn:.0f}%) | **{ct-cb:+d}** |\n\n")

        f.write("## Critical: false positives by subset\n\n")
        f.write("| Subset | Flips to correct | Flips to wrong |\n|---|---|---|\n")
        for k in ("covered", "heldout"):
            fc = len(flips_correct[k]); fw = len(flips_wrong[k])
            f.write(f"| {k} | {fc} | {fw} |\n")
        f.write("\n")

        for k in ("covered", "heldout"):
            if flips_wrong[k]:
                f.write(f"## Flips to wrong on '{k}' subset\n\n")
                for fl in flips_wrong[k]:
                    f.write(f"- **{fl['id']}** `{fl['query'][:70]}`\n")
                    f.write(f"  - expected: `{fl['expected']}`\n")
                    f.write(f"  - treated top-1: `{fl['treated_top1']}`\n")
                f.write("\n")

        f.write("## Interpretation\n\n")
        if results.get("heldout"):
            r = results["heldout"]; d = r["t1"] - r["b1"]; n = r["n"]
            fw = len(flips_wrong["heldout"])
            if fw == 0 and d >= 0:
                f.write(f"✅ **Safe on held-out**: {fw} false positives on {n} queries "
                        f"the YAML doesn't cover. Adapter does no harm on uncovered "
                        f"queries; lift on those is {d:+d}/{n}.\n\n")
            elif fw > 0:
                f.write(f"⚠️  **{fw} false positives on held-out** — intent triggers fired "
                        f"for queries the YAML wasn't designed for. Investigate the "
                        f"trigger terms (probably too broad).\n\n")
            else:
                f.write(f"Marginal: held-out delta {d:+d}, no false positives. "
                        f"Library is safe but only the covered subset benefits.\n\n")

        f.write("## Architectural conclusion\n\n")
        f.write("The framework + memory adapter is **production-safe** only if the "
                "held-out false-positive count stays at 0. The lift comes from curating "
                "intent entries for known query patterns — and the adapter's value is "
                "bounded by how well the YAML covers real user queries. This is the "
                "data-not-schema tradeoff: cheap to extend, fast feedback loop, but "
                "no magic generalization to queries you didn't anticipate.\n")
    print(f"\nWrote {OUT_DOC.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
