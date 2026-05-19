"""
A/B measurement: 155-case workflow routing benchmark with vs without
prioritize_workflow_by_intent().

Baseline = raw UnifiedWorkflowSearch.search() top-1 = correct?
Treatment = same, plus prioritize_workflow_by_intent() applied.

Output: sandbox/workflow_search_v2/docs/20260519_intent_lift_results.md
"""
from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path
from typing import Dict, List

import yaml

sys.path.insert(0, str(Path("backend/lib").resolve()))
from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from sandbox.workflow_search_v2.library.workflow_intent import (  # noqa: E402
    prioritize_workflow_by_intent, load_intent_anchors,
)

EVAL_YAML = ROOT / "evaluation" / "datasets" / "cross_domain_routing" / "queries.yaml"
OUT_DOC = Path(__file__).resolve().parents[1] / "docs" / "20260519_intent_lift_results.md"


def main() -> int:
    cases = yaml.safe_load(EVAL_YAML.read_text())
    print(f"Loaded {len(cases)} routing cases")
    anchors = load_intent_anchors()
    print(f"Loaded {len(anchors)} intent anchors")

    search = UnifiedWorkflowSearch()
    bge_active = bool(getattr(search, "_bge_model", None))
    print(f"BGE: {'ACTIVE' if bge_active else 'DISABLED'}\n")

    baseline_hits = 0
    treatment_hits = 0
    by_domain: Dict[str, Dict[str, int]] = {}
    flips_to_correct: List[Dict] = []
    flips_to_wrong: List[Dict] = []
    no_change_fail: List[Dict] = []

    for c in cases:
        query = c["query"]
        correct = c["correct_workflow"]
        domain = c.get("domain", "unknown")
        try:
            raw = search.search(query, limit=10)
        except Exception:
            continue
        baseline_top1 = raw[0].name if raw else None
        treated = prioritize_workflow_by_intent(query, raw, anchors=anchors)
        treated_top1 = treated[0].name if treated else None

        b_hit = (baseline_top1 == correct)
        t_hit = (treated_top1 == correct)
        if b_hit: baseline_hits += 1
        if t_hit: treatment_hits += 1

        bd = by_domain.setdefault(domain, {"n": 0, "b": 0, "t": 0})
        bd["n"] += 1
        if b_hit: bd["b"] += 1
        if t_hit: bd["t"] += 1

        if not b_hit and t_hit:
            flips_to_correct.append({"id": c["id"], "query": query[:70], "correct": correct,
                                      "baseline_top1": baseline_top1})
        elif b_hit and not t_hit:
            flips_to_wrong.append({"id": c["id"], "query": query[:70], "correct": correct,
                                    "treated_top1": treated_top1})
        elif not b_hit and not t_hit:
            no_change_fail.append({"id": c["id"], "query": query[:70], "correct": correct,
                                    "baseline_top1": baseline_top1, "treated_top1": treated_top1})

    n = len(cases)
    print(f"=== A/B results (n={n}) ===")
    print(f"  BASELINE top-1 HIT:  {baseline_hits}/{n}  ({100*baseline_hits/n:.1f}%)")
    print(f"  TREATMENT top-1 HIT: {treatment_hits}/{n}  ({100*treatment_hits/n:.1f}%)")
    print(f"  Delta:               {treatment_hits - baseline_hits:+d}  "
          f"({100*(treatment_hits-baseline_hits)/n:+.1f}pp)")
    print(f"  Flips to correct:    {len(flips_to_correct)}")
    print(f"  Flips to wrong:      {len(flips_to_wrong)}")

    print(f"\nBy domain:")
    for d, st in sorted(by_domain.items()):
        delta = st["t"] - st["b"]
        print(f"  {d:<24} n={st['n']:>3}  baseline={st['b']:>3}  treatment={st['t']:>3}  Δ={delta:+d}")

    OUT_DOC.parent.mkdir(parents=True, exist_ok=True)
    with OUT_DOC.open("w", encoding="utf-8") as f:
        f.write("# Intent-Anchor A/B Lift Results (n=155)\n\n")
        f.write(f"**Date:** 2026-05-19\n")
        f.write(f"**Source:** `evaluation/datasets/cross_domain_routing/queries.yaml`\n")
        f.write(f"**Library:** `sandbox/workflow_search_v2/library/workflow_intent.py`\n")
        f.write(f"**Anchors:** `sandbox/workflow_search_v2/data/intent_anchors.yaml` ({len(anchors)} entries)\n")
        f.write(f"**BGE:** {'ACTIVE' if bge_active else 'DISABLED (local — same as baseline run)'}\n\n")
        f.write("## Headline\n\n")
        f.write(f"| Method | Top-1 HIT | % |\n|---|---|---|\n")
        f.write(f"| BASELINE (`UnifiedWorkflowSearch.search` raw) | {baseline_hits} / {n} | **{100*baseline_hits/n:.1f}%** |\n")
        f.write(f"| **TREATMENT (+`prioritize_workflow_by_intent`)** | {treatment_hits} / {n} | **{100*treatment_hits/n:.1f}%** |\n")
        f.write(f"| Delta | {treatment_hits - baseline_hits:+d} | **{100*(treatment_hits-baseline_hits)/n:+.1f}pp** |\n\n")

        f.write("## By domain\n\n")
        f.write("| Domain | n | baseline | treatment | Δ |\n|---|---|---|---|---|\n")
        for d, st in sorted(by_domain.items()):
            f.write(f"| {d} | {st['n']} | {st['b']} | {st['t']} | {st['t']-st['b']:+d} |\n")

        f.write(f"\n## Flips to correct ({len(flips_to_correct)})\n\n")
        for fl in flips_to_correct:
            f.write(f"- **{fl['id']}** `{fl['query']}` → was `{fl['baseline_top1']}`, now `{fl['correct']}`\n")

        f.write(f"\n## Flips to wrong ({len(flips_to_wrong)})\n\n")
        if not flips_to_wrong:
            f.write("**None.** The intent prioritizer never demoted a correct top-1 to wrong.\n")
        for fl in flips_to_wrong:
            f.write(f"- **{fl['id']}** `{fl['query']}` → was `{fl['correct']}` (correct), now `{fl['treated_top1']}`\n")

        f.write(f"\n## Still failing ({len(no_change_fail)})\n\n")
        for fl in no_change_fail[:20]:
            f.write(f"- **{fl['id']}** `{fl['query']}` — expected `{fl['correct']}`, got `{fl['baseline_top1']}`\n")
        if len(no_change_fail) > 20:
            f.write(f"\n…{len(no_change_fail) - 20} more cases.\n")

    print(f"\nWrote {OUT_DOC.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
