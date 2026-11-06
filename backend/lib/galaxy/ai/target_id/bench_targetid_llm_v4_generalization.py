#!/usr/bin/env python3
"""Memorization control for the LLM target-ID result (v3 showed LLM lifts 9/10 immune diseases).

Concern: LLM-alone high on a clinical-precedence gold may be the model RECALLING famous approved
targets rather than reasoning over evidence. Two controls:

(C1) DISEASE-SPECIFICITY (already inherent in v3): hard-negatives are OTHER diseases' clinical targets,
     so a high AUROC means the LLM ranks THIS disease's targets above other diseases' targets — not just
     scoring generically-famous immune genes. Re-reported here.
(C2) LITERATURE-PROMINENCE STRATIFICATION (the new control): split each disease's clinical gold by OT
     `literature` datatype score into HIGH-lit (famous, easily memorized) vs LOW-lit (clinically relevant
     but not heavily published). If the LLM still ranks LOW-lit clinical targets above hard-negatives
     (pooled across diseases for power), the signal is not pure fame recall.

Pooled AUROC of LLM-alone and OT-genetics on: all clinical gold, HIGH-lit gold, LOW-lit gold.
"""
import json, os, re, sys, random, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from benchmark_multidisease import resolve_efo
from bench_targetid_llm_v3 import llm_channel, DISEASES, OT

Q = ("query($id:String!){disease(efoId:$id){associatedTargets(page:{index:0,size:300})"
     "{rows{target{approvedSymbol} datatypeScores{id score}}}}}")


def ot_scores(efo):
    body = json.dumps({"query": Q, "variables": {"id": efo}}).encode()
    rows = json.loads(urllib.request.urlopen(urllib.request.Request(OT, data=body,
           headers={"Content-Type": "application/json"}), timeout=40).read())["data"]["disease"]["associatedTargets"]["rows"]
    gold, gen, lit = set(), {}, {}
    for r in rows:
        s = (r["target"]["approvedSymbol"] or "").upper()
        if not s:
            continue
        dt = {d["id"]: d["score"] for d in r["datatypeScores"]}
        if dt.get("clinical", 0) >= 0.5:
            gold.add(s)
        if dt.get("genetic_association", 0) > 0:
            gen[s] = dt["genetic_association"]
        lit[s] = dt.get("literature", 0.0)
    return gold, gen, lit


def auroc(scores, pos, universe):
    try:
        from sklearn.metrics import roc_auc_score
    except Exception:
        return None
    y = [1 if u in pos else 0 for u in universe]
    if sum(y) < 3 or sum(y) == len(y):
        return None
    s = [scores.get(u, 0.0) for u in universe]
    return round(float(roc_auc_score(y, s)), 4)


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "openai/gpt-6.1-sol-pro"
    data = {}
    for name in DISEASES:
        efo = resolve_efo(name)
        if not efo:
            continue
        g, gen, lit = ot_scores(efo)
        if len(g) < 6:
            continue
        rng = random.Random(0)
        all_gold_other = []  # filled below
        data[name] = {"efo": efo, "gold": g, "gen": gen, "lit": lit}
        print(f"[{name}] clinical={len(g)}", flush=True)
    all_gold = sorted({x for d in data.values() for x in d["gold"]})
    # pooled arms over all diseases
    pooled = {"all": {"llm": [], "ot": [], "y": []}, "hi": {"llm": [], "ot": [], "y": []}, "lo": {"llm": [], "ot": [], "y": []}}
    for name, d in data.items():
        g, gen, lit = d["gold"], d["gen"], d["lit"]
        rng = random.Random(0)
        hardneg = [x for x in all_gold if x not in g]
        rng.shuffle(hardneg); hardneg = hardneg[: 3 * len(g)]
        universe = sorted({*g, *hardneg, *list(gen)[:40]})
        cr = llm_channel(name, universe, model)
        if not cr.ok:
            print(f"[{name}] LLM failed: {cr.error}", flush=True); continue
        lit_pos = sorted(g, key=lambda x: lit.get(x, 0))
        med = sorted(lit.get(x, 0) for x in g)[len(g) // 2]
        hi = {x for x in g if lit.get(x, 0) >= med}
        lo = {x for x in g if lit.get(x, 0) < med}
        for u in universe:
            lbl_all = 1 if u in g else 0
            pooled["all"]["llm"].append(cr.scores.get(u, 0.0)); pooled["all"]["ot"].append(gen.get(u, 0.0)); pooled["all"]["y"].append(lbl_all)
            # HIGH-lit arm: positives = hi, negatives = hardneg (exclude lo golds from universe)
            if u in hi or u not in g:
                pooled["hi"]["llm"].append(cr.scores.get(u, 0.0)); pooled["hi"]["ot"].append(gen.get(u, 0.0)); pooled["hi"]["y"].append(1 if u in hi else 0)
            if u in lo or u not in g:
                pooled["lo"]["llm"].append(cr.scores.get(u, 0.0)); pooled["lo"]["ot"].append(gen.get(u, 0.0)); pooled["lo"]["y"].append(1 if u in lo else 0)
        print(f"[{name}] gold={len(g)} hi-lit={len(hi)} lo-lit={len(lo)} median_lit={med:.2f}", flush=True)

    from sklearn.metrics import roc_auc_score
    def pooled_auroc(arm, chan):
        y = pooled[arm]["y"]; s = pooled[arm][chan]
        if sum(y) < 5:
            return None
        return round(float(roc_auc_score(y, s)), 4)
    res = {"model": model, "pooled": {}}
    for arm in ("all", "hi", "lo"):
        res["pooled"][arm] = {"n_pos": int(sum(pooled[arm]["y"])), "n": len(pooled[arm]["y"]),
                              "llm_alone_auroc": pooled_auroc(arm, "llm"), "ot_genetics_auroc": pooled_auroc(arm, "ot")}
    lo, hi = res["pooled"]["lo"], res["pooled"]["hi"]
    res["memorization_control_pass"] = bool(lo["llm_alone_auroc"] and lo["llm_alone_auroc"] > 0.6 and
                                            lo["llm_alone_auroc"] > (lo["ot_genetics_auroc"] or 0) + 0.05)
    res["interpretation"] = (
        f"LLM-alone pooled AUROC: all={res['pooled']['all']['llm_alone_auroc']}, "
        f"HIGH-lit(famous)={hi['llm_alone_auroc']}, LOW-lit(less-published)={lo['llm_alone_auroc']} "
        f"(OT-genetics on low-lit={lo['ot_genetics_auroc']}). "
        + ("LLM ranks LOW-literature clinical targets well above genetics/chance -> signal is NOT pure fame recall."
           if res["memorization_control_pass"] else
           "LLM advantage concentrates in famous (high-lit) targets -> substantially memorization; discount."))
    json.dump(res, open("bench_targetid_llm_v4_generalization.json", "w"), indent=2)
    print("\n=== MEMORIZATION CONTROL ===\n" + json.dumps(res, indent=2), flush=True)


if __name__ == "__main__":
    main()
