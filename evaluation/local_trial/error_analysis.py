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


def _lit(x):
    import ast
    if isinstance(x, (dict, list)):
        return x
    try:
        return ast.literal_eval(x)
    except Exception:
        return {} if "{" in str(x) else []


def param_owner_analysis(gt):
    """param_prefill owner split. must_not_fill_violation = the model filled a FORBIDDEN param
    (unambiguous model over-fill → trainable; the failure that WORSENED with SFT, 34→61).
    value_or_missing = expected key missing/other — flagged (needs alias-aware check), NOT auto-gold."""
    rows, cand = [], []
    for model in ("sft", "base"):
        preds = _preds(model, "param_prefill.jsonl")
        if not preds:
            continue
        b = {"n": 0, "correct_restraint": 0, "must_not_fill_violation": 0, "value_or_missing": 0}
        for i, r in gt.items():
            if i not in preds:
                continue
            b["n"] += 1
            pred = preds[i]
            pred_keys = set(pred.keys()) if isinstance(pred, dict) else set(_lit(pred).keys() if isinstance(_lit(pred), dict) else [])
            forbidden = set(_lit(r.get("must_not_fill")) or [])
            expected = set((_lit(r.get("expected_params")) or {}).keys())
            viol = pred_keys & forbidden
            if viol:
                b["must_not_fill_violation"] += 1
                if model == "sft":
                    cand.append({"task": "param_prefill", "owner": "model(must_not_fill_overfill)",
                                 "src_model": model, "id": i, "prompt": r.get("user_query"),
                                 "gold": r.get("expected_params"), "must_not_fill": r.get("must_not_fill"),
                                 "overfilled": sorted(viol)})
            elif not expected <= pred_keys:
                b["value_or_missing"] += 1
            else:
                b["correct_restraint"] += 1
        rows.append((model, b))
    return rows, cand


def autofix_owner_analysis(gt):
    """autofix = error-log → fix category; pure model reasoning (no harness lever). Wrong category
    = model-owned → trainable."""
    rows, cand = [], []
    for model in ("sft", "base"):
        preds = _preds(model, "autofix_benchmark.jsonl")
        if not preds:
            continue
        b = {"n": 0, "correct": 0, "model_error": 0}
        for i, r in gt.items():
            if i not in preds:
                continue
            b["n"] += 1
            p = preds[i]
            pv = _norm(p.get("category") if isinstance(p, dict) else p)
            gold = {_norm(r.get("category")), _norm(r.get("expected_fix"))}
            if pv in gold:
                b["correct"] += 1
            else:
                b["model_error"] += 1
                if model == "sft":
                    cand.append({"task": "autofix", "owner": "model", "src_model": model, "id": i,
                                 "prompt": (r.get("error_log") or r.get("description")),
                                 "gold": r.get("category")})
        rows.append((model, b))
    return rows, cand


def main():
    gt = S.load("cross_domain_routing")
    rows, cand = routing_owner_analysis(gt)
    print("=== routing error analysis — owner buckets (bare vs +harness) ===")
    print(f"{'model':30} {'n':>4} {'correct':>8} {'harness_fix':>12} {'model/data':>11}")
    for model, b in rows:
        print(f"{model:30} {b['n']:>4} {b['correct']:>8} {b['harness_fixable']:>12} {b['model_or_data']:>11}")

    # param_prefill
    prows, pcand = param_owner_analysis(S.load("param_prefill"))
    print("\n=== param_prefill — owner buckets ===")
    print(f"{'model':8} {'n':>4} {'ok_restraint':>12} {'MUSTNOTFILL_viol':>16} {'value/missing':>13}")
    for model, b in prows:
        print(f"{model:8} {b['n']:>4} {b['correct_restraint']:>12} {b['must_not_fill_violation']:>16} {b['value_or_missing']:>13}")
    cand += pcand

    # autofix
    arows, acand = autofix_owner_analysis(S.load("autofix_benchmark"))
    print("\n=== autofix — owner buckets (pure model reasoning) ===")
    print(f"{'model':8} {'n':>4} {'correct':>8} {'model_error':>12}")
    for model, b in arows:
        print(f"{model:8} {b['n']:>4} {b['correct']:>8} {b['model_error']:>12}")
    cand += acand
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
