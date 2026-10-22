#!/usr/bin/env python3
"""
error_analysis.py  (READ-ONLY; offline)
---------------------------------------
Benchmark error analysis that buckets each failure by OWNER, so only MODEL-owned errors become
SFT/GRPO gold — the disciplined bridge from benchmark results to a better LLM (per the session's
diagnosis: most "errors" are harness/data/eval, not the model).

Routing is the clean case: the same items are scored BARE and +HARNESS(catalog), so:
  correct_bare       — already right, no action
  HARNESS_FIXABLE    — bare-wrong but catalog-right  → a HARNESS lever (retrieval), NOT a training target
  MODEL_OR_DATA      — bare-wrong AND catalog-wrong   → training candidate (model couldn't route even with
                       the candidate list) — caveat: if the gold workflow isn't in the catalog it's a DATA gap
Only MODEL_OR_DATA items are emitted as gold candidates (query → correct_workflow).

Focus: the on-prem models we would actually improve (sft, base). Run:
    python3 evaluation/local_trial/error_analysis.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
_PE = _REPO / "evaluation" / "datasets" / "public_export"
sys.path.insert(0, str(_PE))
import score as S  # noqa: E402

_norm = getattr(S, "norm", lambda x: str(x or "").strip().lower())
MODELS = ["sft", "base", "deepseek_deepseek-v4-pro"]  # on-prem first; a frontier for contrast
OUT = Path(__file__).resolve().parent / "error_analysis_gold_candidates.jsonl"


def _preds(model, fname):
    p = _PE / "results" / model / fname
    return S.load_preds(str(p)) if p.exists() else None


def routing_owner_analysis(gt):
    rows = []
    gold_candidates = []
    for model in MODELS:
        bare = _preds(model, "cross_domain_routing_bare.jsonl")
        cat = _preds(model, "cross_domain_routing_catalog.jsonl") \
            or _preds(model, "cross_domain_routing_catalog_described.jsonl")
        if not bare:
            continue
        b = {"correct": 0, "harness_fixable": 0, "model_or_data": 0, "n": 0}
        for i, r in gt.items():
            if i not in bare:
                continue
            gold = {_norm(r.get("correct_workflow"))} | {_norm(a) for a in (r.get("acceptable_alts") or [])}
            b["n"] += 1
            bare_ok = _norm(bare[i]) in gold
            cat_ok = (cat is not None and i in cat and _norm(cat[i]) in gold)
            if bare_ok:
                b["correct"] += 1
            elif cat_ok:
                b["harness_fixable"] += 1
            else:
                b["model_or_data"] += 1
                if model in ("sft", "base"):  # emit training candidates from the on-prem models
                    gold_candidates.append({
                        "task": "cross_domain_routing", "owner": "model_or_data", "src_model": model,
                        "id": i, "prompt": r.get("query"), "gold": r.get("correct_workflow"),
                        "bare_pred": bare[i], "catalog_pred": (cat.get(i) if cat else None),
                    })
        rows.append((model, b))
    return rows, gold_candidates


def main():
    gt = S.load("cross_domain_routing")
    rows, cand = routing_owner_analysis(gt)
    print("=== routing error analysis — owner buckets (bare vs +harness) ===")
    print(f"{'model':30} {'n':>4} {'correct':>8} {'harness_fix':>12} {'model/data':>11}")
    for model, b in rows:
        print(f"{model:30} {b['n']:>4} {b['correct']:>8} {b['harness_fixable']:>12} {b['model_or_data']:>11}")
    # dedupe gold candidates by (id) across on-prem models, keep sft's if present
    seen, uniq = set(), []
    for c in sorted(cand, key=lambda x: (x["src_model"] != "sft", x["id"])):
        if c["id"] in seen:
            continue
        seen.add(c["id"]); uniq.append(c)
    with OUT.open("w") as f:
        for c in uniq:
            f.write(json.dumps(c) + "\n")
    print(f"\nMODEL-owned routing failures (on-prem) → {len(uniq)} SFT/GRPO gold candidates: {OUT.name}")
    print("Reading: harness_fixable = fix via retrieval, NOT training; model/data = train (minus the")
    print("subset whose gold workflow isn't in the catalog = a DATA gap). Same method extends to")
    print("param_prefill (must_not_fill over-fill = model), autofix, etc. — all offline, clean evals only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
