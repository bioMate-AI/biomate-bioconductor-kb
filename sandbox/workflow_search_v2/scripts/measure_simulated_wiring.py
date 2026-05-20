"""
Simulated production wiring measurement for workflow_intent.

Calls UnifiedWorkflowSearch.search() directly, then applies
prioritize_workflow_by_intent — exactly what the wiring patch would do
in ai_assistant.search_ranked. Measures utility + latency without
modifying any production file.
"""
from __future__ import annotations

import statistics
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

import yaml

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "backend" / "lib"))

from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch  # noqa: E402
from sandbox.workflow_search_v2.library.workflow_intent import (  # noqa: E402
    prioritize_workflow_by_intent, load_intent_anchors,
)

EVAL_YAML = ROOT / "evaluation/datasets/cross_domain_routing/queries.yaml"
OUT = Path(__file__).resolve().parents[1] / "output" / "simulated_wiring_ab.md"
OUT.parent.mkdir(parents=True, exist_ok=True)


def main() -> int:
    cases = yaml.safe_load(EVAL_YAML.read_text())
    search = UnifiedWorkflowSearch()
    bge = bool(getattr(search, "_bge_model", None))

    # Warm intent YAML cache
    anchors = load_intent_anchors()

    # Warm-up: run a few queries to amortize SQLite + LLM-cache startup
    for c in cases[:3]:
        search.search(c["query"], limit=10)

    print(f"Loaded {len(cases)} cases × 2 (baseline + treatment) — BGE: "
          f"{'on' if bge else 'off'}")
    print(f"Anchors loaded: {len(anchors)}\n")

    baseline_hits = 0
    treatment_hits = 0
    baseline_times = []
    treatment_times = []   # treatment = baseline search + prioritize overhead

    for c in cases:
        # Baseline: just the search call
        t0 = time.perf_counter()
        raw = search.search(c["query"], limit=10)
        baseline_elapsed = (time.perf_counter() - t0) * 1000
        baseline_times.append(baseline_elapsed)

        # Treatment: search + prioritize_by_intent overhead
        t0 = time.perf_counter()
        raw_t = search.search(c["query"], limit=10)
        treated = prioritize_workflow_by_intent(c["query"], raw_t,
                                                  inject_canonical=True,
                                                  anchors=anchors)
        treatment_elapsed = (time.perf_counter() - t0) * 1000
        treatment_times.append(treatment_elapsed)

        if raw and raw[0].name == c["correct_workflow"]:
            baseline_hits += 1
        if treated and treated[0].name == c["correct_workflow"]:
            treatment_hits += 1

    # Prioritize-only overhead = treatment - baseline (per query, then aggregate)
    overhead_ms = [t - b for t, b in zip(treatment_times, baseline_times)]
    overhead_sorted = sorted(overhead_ms)

    print(f"=== Utility (n={len(cases)}) ===")
    print(f"  Baseline top-1:  {baseline_hits}/{len(cases)} ({100*baseline_hits/len(cases):.1f}%)")
    print(f"  Treatment top-1: {treatment_hits}/{len(cases)} ({100*treatment_hits/len(cases):.1f}%)")
    print(f"  Δ utility:       +{treatment_hits-baseline_hits} hits "
          f"({100*(treatment_hits-baseline_hits)/len(cases):+.1f}pp)")

    print(f"\n=== Latency (full search call) ===")
    print(f"  Baseline:  mean={statistics.mean(baseline_times):.1f}ms  "
          f"p95={sorted(baseline_times)[int(0.95*len(baseline_times))]:.1f}ms")
    print(f"  Treatment: mean={statistics.mean(treatment_times):.1f}ms  "
          f"p95={sorted(treatment_times)[int(0.95*len(treatment_times))]:.1f}ms")

    print(f"\n=== Prioritize-only overhead (per query) ===")
    print(f"  mean: {statistics.mean(overhead_ms):.3f}ms")
    print(f"  p50:  {statistics.median(overhead_ms):.3f}ms")
    print(f"  p95:  {overhead_sorted[int(0.95*len(overhead_sorted))]:.3f}ms")
    print(f"  p99:  {overhead_sorted[min(int(0.99*len(overhead_sorted)), len(overhead_sorted)-1)]:.3f}ms")

    with OUT.open("w", encoding="utf-8") as f:
        f.write("# workflow_intent Simulated Wiring A/B\n\n")
        f.write(f"**Date:** 2026-05-20\n")
        f.write(f"**Eval:** `evaluation/datasets/cross_domain_routing/queries.yaml` (n={len(cases)})\n")
        f.write(f"**BGE dense retrieval:** {'ACTIVE' if bge else 'DISABLED (local)'}\n")
        f.write(f"**Approach:** call UnifiedWorkflowSearch.search() directly, then apply "
                f"prioritize_workflow_by_intent — same as wiring patch would do "
                f"in ai_assistant.search_ranked. No production modifications.\n\n")
        f.write("## Utility\n\n")
        f.write("| Metric | Baseline | Treatment | Δ |\n|---|---|---|---|\n")
        f.write(f"| Top-1 hit rate | {baseline_hits}/{len(cases)} "
                f"({100*baseline_hits/len(cases):.1f}%) | "
                f"{treatment_hits}/{len(cases)} ({100*treatment_hits/len(cases):.1f}%) | "
                f"**+{treatment_hits-baseline_hits} hits "
                f"({100*(treatment_hits-baseline_hits)/len(cases):+.1f}pp)** |\n\n")
        f.write("## Time cost\n\n")
        f.write("### Full call latency (search + maybe-prioritize)\n\n")
        f.write("| Metric | Baseline | Treatment | Δ |\n|---|---|---|---|\n")
        for label, fn in [("mean", statistics.mean), ("p95", lambda x: sorted(x)[int(0.95*len(x))])]:
            b = fn(baseline_times); t = fn(treatment_times)
            f.write(f"| {label} | {b:.1f}ms | {t:.1f}ms | {t-b:+.2f}ms |\n")
        f.write("\n### Prioritize-only overhead\n\n")
        f.write("| Metric | Value |\n|---|---|\n")
        f.write(f"| mean | {statistics.mean(overhead_ms):.3f}ms |\n")
        f.write(f"| p50 | {statistics.median(overhead_ms):.3f}ms |\n")
        f.write(f"| p95 | {overhead_sorted[int(0.95*len(overhead_sorted))]:.3f}ms |\n")
        f.write(f"| p99 | {overhead_sorted[min(int(0.99*len(overhead_sorted)), len(overhead_sorted)-1)]:.3f}ms |\n")
    print(f"\nWrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
