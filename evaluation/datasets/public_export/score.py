#!/usr/bin/env python3
"""Objective scorer for RealBio Benchmark — real-world bioinformatics-agent benchmarks — no LLM judge.

Any system runs a benchmark, writes predictions as JSONL ({"id": ..., "prediction": ...}),
and is scored here against the published ground truth. Same items, same metric, for every system.

Usage:  python3 score.py <benchmark> <predictions.jsonl>
        python3 score.py cross_domain_routing my_system_preds.jsonl

Prediction formats expected per benchmark (see each README.md):
  cross_domain_routing  prediction = domain string
  workflow_generation   prediction = category string (A) OR list of tools (B)
  protocol_thresholds   prediction = "PASS" | "FAIL"
  param_prefill         prediction = {param: value, ...}
  boin_benchmark        prediction = dose-decision string (matched to 'reference')
  pbpk_benchmark        prediction = numeric PK value (matched within-2-fold to 'reference')
  drug_discovery_e2e    prediction = predicted ligand id order (list)
  autofix_benchmark     prediction = fix category string (or {"category":.., "fix":..}); primary = category accuracy
"""
import json, sys, os, re

HERE = os.path.dirname(os.path.abspath(__file__))

def load(name):
    gt = {r["id"]: r for r in (json.loads(l) for l in open(os.path.join(HERE, name, "data.jsonl")))}
    return gt

def load_preds(path):
    return {r["id"]: r.get("prediction") for r in (json.loads(l) for l in open(path))}

def norm(s):
    return re.sub(r"\s+", " ", str(s).strip().lower())

def wilson(k, n, z=1.96):
    """95% Wilson score interval for a proportion — the interval to report for accuracy."""
    if not n: return [None, None]
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5) / d
    return [round(max(0, c - h), 4), round(min(1, c + h), 4)]

def acc(gt, preds, key):
    n = hit = 0
    for i, r in gt.items():
        if i not in preds: continue
        n += 1
        if norm(preds[i]) == norm(r.get(key)): hit += 1
    return {"scored": n, "correct": hit, "accuracy": round(hit / n, 4) if n else None,
            "ci95": wilson(hit, n), "note": f"exact match on '{key}'"}

def score_routing(gt, preds):
    """Match the correct WORKFLOW; credit acceptable_alts."""
    n = hit = 0
    for i, r in gt.items():
        if i not in preds: continue
        n += 1
        gold = {norm(r.get("correct_workflow"))} | {norm(a) for a in (r.get("acceptable_alts") or [])}
        if norm(preds[i]) in gold: hit += 1
    return {"scored": n, "correct": hit, "accuracy": round(hit / n, 4) if n else None, "ci95": wilson(hit, n),
            "note": "exact match on correct_workflow (acceptable_alts credited)"}
def score_protocol(gt, preds):    return acc(gt, preds, "expected_correct_action")  # PASS/FAIL
def score_boin(gt, preds):
    import ast
    n = hit = skipped = 0
    for i, r in gt.items():
        if i not in preds: continue
        try:
            ref = r["reference"]; ref = ast.literal_eval(ref) if isinstance(ref, str) else ref
            gt_val = ref.get("true_MTD_mg")
        except Exception:
            gt_val = None
        if gt_val is None:        # no ground truth -> item is unscorable, exclude from denominator
            skipped += 1; continue
        n += 1
        try:
            if abs(float(preds[i]) - float(gt_val)) < 1e-6: hit += 1
        except Exception:
            pass  # prediction unparseable/wrong but GT exists -> counts against n
    return {"scored": n, "correct": hit, "accuracy": round(hit / n, 4) if n else None,
            "ci95": wilson(hit, n), "skipped_no_gt": skipped,
            "note": "exact match on true_MTD_mg; items with null true_MTD_mg excluded (unscorable)"}

def score_workflow_gen(gt, preds):
    n = hit = 0
    for i, r in gt.items():
        if i not in preds: continue
        n += 1; p = preds[i]
        if "expected_category" in r:
            if norm(p) == norm(r["expected_category"]): hit += 1
        elif "key_tools" in r:  # partition B: tool-set recall >= 0.5 counts
            want = {norm(t) for t in r["key_tools"]}
            got = {norm(t) for t in (p if isinstance(p, list) else [p])}
            if want and len(want & got) / len(want) >= 0.5: hit += 1
    return {"scored": n, "correct": hit, "accuracy": round(hit / n, 4) if n else None, "ci95": wilson(hit, n),
            "note": "A: category exact; B: >=50% key-tool recall"}

def score_param_prefill(gt, preds):
    tp = fp = fn = viol = n = 0
    for i, r in gt.items():
        if i not in preds: continue
        n += 1
        want = r.get("expected_params", {}) or {}
        got = preds[i] if isinstance(preds[i], dict) else {}
        for k, v in want.items():
            if k in got and norm(got[k]) == norm(v): tp += 1
            else: fn += 1
        for k in got:
            if k not in want: fp += 1
        for k in (r.get("must_not_fill") or []):
            if k in got: viol += 1
    prec = tp / (tp + fp) if tp + fp else 0
    rec = tp / (tp + fn) if tp + fn else 0
    f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0
    return {"scored": n, "param_precision": round(prec, 4), "param_recall": round(rec, 4),
            "param_f1": round(f1, 4), "must_not_fill_violations": viol,
            "note": "key+value exact match; must_not_fill is a hard penalty to report separately"}

def score_pbpk(gt, preds):
    n = ok = 0
    for i, r in gt.items():
        if i not in preds: continue
        try:
            ref = float(re.search(r"[-+]?\d*\.?\d+", str(r["reference"])).group())
            p = float(preds[i])
        except Exception:
            continue
        n += 1
        if ref > 0 and 0.5 <= p / ref <= 2.0: ok += 1
    return {"scored": n, "within_2fold": round(ok / n, 4) if n else None, "ci95": wilson(ok, n),
            "note": "fraction of PK predictions within 2-fold of published reference"}

def score_drug_disc(gt, preds):
    def spearman(a, b):
        ra = {v: k for k, v in enumerate(a)}; rb = {v: k for k, v in enumerate(b)}
        common = [x for x in a if x in rb]
        if len(common) < 2: return None
        d2 = sum((ra[x] - rb[x]) ** 2 for x in common); nn = len(common)
        return 1 - 6 * d2 / (nn * (nn * nn - 1))
    vals = []
    for i, r in gt.items():
        if i not in preds: continue
        gold = [str(x) for x in r.get("ligand_rank_order", [])]
        pred = [str(x) for x in (preds[i] or [])]
        rho = spearman(gold, pred)
        if rho is not None: vals.append(rho)
    return {"scored": len(vals), "mean_spearman_rank": round(sum(vals) / len(vals), 4) if vals else None,
            "note": "mean Spearman rank correlation of predicted vs experimental affinity order"}

def score_autofix(gt, preds):
    """Primary: exact match on the 10-class fix CATEGORY (objective, no judge).
    Secondary (optional): token overlap vs the free-text expected_fix, if the prediction
    supplies a 'fix'. prediction may be a category string, or {"category":..., "fix":...}."""
    n = cat_hit = ov_n = 0; ov = 0.0
    for i, r in gt.items():
        if i not in preds: continue
        n += 1; p = preds[i]
        pred_cat = p.get("category") if isinstance(p, dict) else p
        if norm(pred_cat) == norm(r.get("category")): cat_hit += 1
        pred_fix = p.get("fix") if isinstance(p, dict) else None
        if pred_fix is not None:
            want = set(norm(r.get("expected_fix")).split()); got = set(norm(pred_fix).split())
            ov += len(want & got) / len(want) if want else 0; ov_n += 1
    out = {"scored": n, "fix_category_accuracy": round(cat_hit / n, 4) if n else None, "ci95": wilson(cat_hit, n),
           "note": "primary: exact match on fix category (10 objective classes)"}
    if ov_n:
        out["mean_fix_token_overlap"] = round(ov / ov_n, 4)
        out["secondary_note"] = "indicative only: token overlap on the free-text fix"
    return out

def _nearest_option(ans_n, options):
    """Map a free-text / near-verbatim answer to the option it best matches (token overlap),
    so a bare LLM that writes prose still scores against the option set."""
    best, best_score = None, -1
    for o in options:
        toks = set(re.findall(r"[a-z0-9]{3,}", norm(o)))
        s = (sum(1 for w in toks if w in ans_n) / len(toks)) if toks else 0.0
        if s > best_score:
            best, best_score = o, s
    return best if best_score > 0 else ""


def score_litqa2(gt, preds):
    """LitQA2 MCQ. prediction = {"answer": <chosen option or free text>}. Report accuracy
    (correct/all), precision (correct/answered), and coverage (answered/all) — abstaining via
    the 'Insufficient information' option is NOT wrong, so a system that abstains instead of
    guessing keeps high precision at lower coverage. Pair with citation_veracity.py for the
    confabulation axis (accuracy alone can't see fabricated evidence)."""
    n = correct = answered = 0
    for i, r in gt.items():
        if i not in preds:
            continue
        n += 1
        p = preds[i]
        raw = p.get("answer", "") if isinstance(p, dict) else str(p or "")
        options = r.get("options") or []
        chosen = _nearest_option(norm(raw), options) if options else raw
        ans_n, ideal_n, uns_n = norm(chosen), norm(r.get("ideal")), norm(r.get("unsure_option", ""))
        if ans_n and ans_n != uns_n:
            answered += 1
        if ans_n and ans_n == ideal_n:
            correct += 1
    return {"scored": n, "correct": correct,
            "accuracy": round(correct / n, 4) if n else None, "ci95": wilson(correct, n),
            "answered": answered,
            "precision": round(correct / answered, 4) if answered else None,
            "coverage": round(answered / n, 4) if n else None,
            "note": "LitQA2 MCQ: accuracy=correct/all, precision=correct/answered, coverage=answered/all"}

SCORERS = {
    "cross_domain_routing": score_routing, "protocol_thresholds": score_protocol,
    "boin_benchmark": score_boin, "workflow_generation": score_workflow_gen,
    "param_prefill": score_param_prefill, "pbpk_benchmark": score_pbpk,
    "drug_discovery_e2e": score_drug_disc, "autofix_benchmark": score_autofix,
    "litqa2": score_litqa2,
}

if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in SCORERS:
        print("usage: python3 score.py <benchmark> <predictions.jsonl>")
        print("benchmarks:", ", ".join(SCORERS)); sys.exit(1)
    name, pred_path = sys.argv[1], sys.argv[2]
    result = SCORERS[name](load(name), load_preds(pred_path))
    print(json.dumps({"benchmark": name, **result}, indent=2))
