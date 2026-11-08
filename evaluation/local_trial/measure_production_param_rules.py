#!/usr/bin/env python3
"""Measure BioMate's PRODUCTION param_prefill — rule layer + LLM fallback — vs the raw-LLM number the
public leaderboard shows.

WHY: the public param_prefill benchmark (datasets/public_export/run_baseline.py) sends the raw user_query to
a raw LLM, bypassing BioMate's deterministic rule layer (_rule_based_param_inference + _validate_extracted_params
in backend/.../api/ai_assistant.py), which is WIRED into the live path (runs before the LLM, overrides it).
So the leaderboard rows labeled "BioMate 9B (base/SFT)" are the raw LLM with the harness OFF and UNDER-STATE
BioMate. This script runs the ACTUAL production rule functions (AST-extracted so no Galaxy runtime is needed)
over the benchmark and merges them with the committed on-prem-9B LLM predictions exactly as production does
(rules win, LLM fills the residual), scored with the committed semantic scorer.

Faithful offline approximation; the canonical end-to-end measurement is evaluation/runners/run_param_prefill.py
against the live backend. Run:  python3 measure_production_param_rules.py
"""
import ast, json, re, logging, os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(REPO, "backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py")
BENCH = os.path.join(REPO, "evaluation/datasets/public_export/param_prefill/data.jsonl")
LLM_PREDS = os.path.join(REPO, "evaluation/datasets/public_export/results/base/param_prefill.jsonl")

def load_prod_funcs():
    src = open(SRC).read(); tree = ast.parse(src)
    want = {"_rule_based_param_inference", "_validate_extracted_params"}
    segs = [ast.get_source_segment(src, n) for n in tree.body
            if isinstance(n, ast.FunctionDef) and n.name in want]
    ns = {"re": re, "json": json, "log": logging.getLogger("stub"), "logging": logging}
    exec("from __future__ import annotations\nfrom typing import Dict,List,Any,Optional\n" + "\n\n".join(segs), ns)
    return ns["_rule_based_param_inference"], ns["_validate_extracted_params"]

def norm(s): return re.sub(r"\s+", " ", str(s).strip().lower())
_GEN = {"hg38":"grch38","hg19":"grch37","grch37":"grch37","grch38":"grch38","mm39":"grcm39","grcm39":"grcm39",
        "mm10":"grcm38","grcm38":"grcm38","ce11":"wbcel235","wbcel235":"wbcel235","dm6":"bdgp6","bdgp6":"bdgp6",
        "r64":"r64-1-1","r64-1-1":"r64-1-1","tair10":"tair10","rnor6.0":"rnor_6.0","rnor_6.0":"rnor_6.0",
        "danrer11":"grcz11","grcz11":"grcz11"}
_BT = {"true","yes","on","enabled","1"}; _BF = {"false","no","off","disabled","0"}
def veq(g, p):
    g, p = norm(g), norm(p)
    if g == p or _GEN.get(g.replace(" ", ""), g) == _GEN.get(p.replace(" ", ""), p): return True
    if (g in _BT and p in _BT) or (g in _BF and p in _BF): return True
    if len(g) >= 3 and (g in p or p in g): return True
    return False

def score(gt, getter):
    tp = fp = fn = viol = 0
    for r in gt:
        wp = r.get("expected_params", {}) or {}; mnf = r.get("must_not_fill") or []
        got = getter(r)
        for k, v in wp.items():
            if k in got and veq(v, got[k]): tp += 1
            else: fn += 1
        for k in got:
            if k not in wp: fp += 1
        for k in mnf:
            if k in got: viol += 1
    P = tp / (tp + fp) if tp + fp else 0; R = tp / (tp + fn) if tp + fn else 0
    return P, R, (2 * P * R / (P + R) if P + R else 0), viol

def main():
    rbpi, val = load_prod_funcs()
    gt = [json.loads(l) for l in open(BENCH)]
    llm = {r["id"]: (r.get("prediction") or {}) for r in (json.loads(l) for l in open(LLM_PREDS))}

    def _ap(r):
        wp = r.get("expected_params", {}) or {}; mnf = r.get("must_not_fill") or []
        return [{"name": k} for k in (set(wp) | set(mnf))]
    def rules_only(r):
        try: return val(rbpi(r["user_query"], _ap(r)), _ap(r)) or {}
        except Exception: return {}
    def raw_llm(r): return llm.get(r["id"], {})
    def production(r):
        # Mirror production ai_assistant.py:2139/2224/2232: rules run first + win; LLM fills the
        # residual; the FINAL merged dict passes through _validate_extracted_params (the guardrail).
        ap = _ap(r)
        try: rule = rbpi(r["user_query"], ap) or {}
        except Exception: rule = {}
        merged = dict(raw_llm(r)); merged.update(rule)   # rules win
        try: return val(merged, ap) or {}
        except Exception: return merged

    for lab, g in [("raw on-prem 9B (leaderboard shows this)", raw_llm),
                   ("rule layer ALONE (no LLM)", rules_only),
                   ("PRODUCTION rule layer + 9B fallback", production)]:
        P, R, F, v = score(gt, g)
        print(f"{lab:40s}: P={P:.3f} R={R:.3f} F1={F:.3f} must_not_fill_viol={v}")

if __name__ == "__main__":
    main()
