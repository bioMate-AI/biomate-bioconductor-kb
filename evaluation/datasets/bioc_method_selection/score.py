#!/usr/bin/env python3
"""Score the Bioconductor method-selection benchmark.
Predictions file: JSONL of {"id":..., "prediction": "<method name>"}.
Metrics: top-1 accuracy; invalid-regime failure rate (picked a correctness-failure method, e.g. ORA on
ranked data); wrong-but-real rate; hallucination rate (method not among candidates / not a real workflow).
Usage: python3 score.py data.jsonl predictions.jsonl
"""
import json, sys
def norm(s): return str(s).strip().lower() if s is not None else ""
def main():
    gold={json.loads(l)["id"]:json.loads(l) for l in open(sys.argv[1])}
    preds={json.loads(l)["id"]:json.loads(l).get("prediction") for l in open(sys.argv[2])}
    n=correct=invalid=wrong_real=hallu=0
    for i,r in gold.items():
        if i not in preds: continue
        n+=1; p=norm(preds[i])
        g={norm(r["correct_method"])}|{norm(a) for a in r.get("acceptable_alts",[])}
        cands={norm(c) for c in r["candidates"]}
        inv={norm(x) for x in r.get("invalid_picks",[])}
        if p in g: correct+=1
        elif p in inv: invalid+=1
        elif p in cands: wrong_real+=1
        else: hallu+=1
    print(json.dumps({
        "benchmark":"bioc_method_selection","scored":n,
        "top1_accuracy":round(correct/max(n,1),4),
        "invalid_regime_failure_rate":round(invalid/max(n,1),4),
        "wrong_but_real_rate":round(wrong_real/max(n,1),4),
        "hallucination_rate":round(hallu/max(n,1),4),
        "note":"invalid_regime = picked a method that is a correctness failure for the context (e.g. ORA on a ranked statistic)"
    },indent=2))
if __name__=="__main__": raise SystemExit(main())
