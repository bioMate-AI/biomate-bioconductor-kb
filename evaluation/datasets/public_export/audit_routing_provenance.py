#!/usr/bin/env python3
"""Transparency audit for the routing_harness leaderboard column.

Found 2026-10-26 (docs/20261025_BENCHMARK_ERROR_ANALYSIS_ROOTCAUSE.md): the routing_harness cells are NOT
uniformly comparable. The leaderboard uses each model's `cross_domain_routing_catalog_described.jsonl` when
present (the rich, production-faithful menu), else falls back to `cross_domain_routing_catalog.jsonl` (the
legacy NAMES-ONLY menu). So some models are scored under a richer condition than others. Separately, a few
catalog files contain EMPTY predictions (model returned no content — a harness/refusal artifact), which score
as wrong and understate those cells.

This script prints, per model, which file fed its routing_harness cell, the empty-prediction count, the
scored accuracy, and the accuracy with empties treated as abstentions (excluded from the denominator). Use it
to see which cells are (a) on the legacy names-only menu and (b) empties-contaminated — i.e. which must be
re-run under a uniform, empties-aware harness before the leaderboard is publishable.

Usage: python3 audit_routing_provenance.py
"""
import json, os, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("score", os.path.join(HERE, "score.py"))
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)


def main():
    gt = S.load("cross_domain_routing")
    R = os.path.join(HERE, "results")
    models = sorted(d for d in os.listdir(R) if os.path.isdir(os.path.join(R, d)))
    print(f"{'model':30s} {'menu':10s} {'n':>4} {'empty':>6} {'acc':>6} {'acc(excl.empty)':>16}")
    n_catalog = n_contam = 0
    for m in models:
        desc = os.path.join(R, m, "cross_domain_routing_catalog_described.jsonl")
        cat = os.path.join(R, m, "cross_domain_routing_catalog.jsonl")
        path, tag = (desc, "described") if os.path.exists(desc) else ((cat, "catalog") if os.path.exists(cat) else (None, None))
        if not path:
            continue
        preds = {r["id"]: r.get("prediction") for r in (json.loads(l) for l in open(path) if l.strip())}
        empty = [i for i, p in preds.items() if not (p if isinstance(p, str) else "")]
        acc = S.score_routing(gt, preds)["accuracy"]
        ne = {i: p for i, p in preds.items() if i not in empty}
        acc_ne = S.score_routing(gt, ne)["accuracy"] if ne else None
        if tag == "catalog":
            n_catalog += 1
        flag = ""
        if empty:
            n_contam += 1; flag = f"  <-- {len(empty)} empty (understated)"
        print(f"{m:30s} {tag:10s} {len(preds):>4} {len(empty):>6} {acc:>6.3f} "
              f"{(round(acc_ne,3) if acc_ne is not None else '-')!s:>16}{flag}")
    print(f"\nSUMMARY: {n_catalog} models on the legacy NAMES-ONLY menu (not apples-to-apples with the "
          f"'described' models); {n_contam} cells empties-contaminated. Both must be fixed by a uniform, "
          f"empties-aware re-run before publishing the routing_harness column.")


if __name__ == "__main__":
    main()
