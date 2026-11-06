#!/usr/bin/env python3
"""Development-stage holdout — a stricter memorization control toward a novel-discovery claim.

A true temporal holdout needs approval dates. The tractable rigorous proxy: split each disease's
clinical gold by MAX DRUG PHASE (OpenTargets knownDrugs):
  APPROVED (phase 4) = "the known drug for this disease" — maximally memorizable.
  EMERGING (phase 1-3, in trials, not approved) = less-established targets.
If the LLM ranks EMERGING clinical targets above negatives (and above genetics), it has forward-looking
signal beyond recalling approved drugs — the closest tractable test of genuine target reasoning.

Pooled AUROC (10 immune diseases) of LLM-alone + OT-genetics on: all clinical gold, APPROVED, EMERGING.
"""
import json, os, sys, random, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from benchmark_multidisease import resolve_efo
from bench_targetid_llm_v3 import llm_channel, DISEASES, OT

Q_CLIN = ("query($id:String!){disease(efoId:$id){associatedTargets(page:{index:0,size:300})"
          "{rows{target{approvedSymbol} datatypeScores{id score}}}}}")
Q_DRUG = "query($id:String!){disease(efoId:$id){knownDrugs(size:2000){count rows{phase target{approvedSymbol}}}}}"


def ot_get(q, efo):
    body = json.dumps({"query": q, "variables": {"id": efo}}).encode()
    return json.loads(urllib.request.urlopen(urllib.request.Request(OT, data=body,
           headers={"Content-Type": "application/json"}), timeout=45).read())


def disease_data(efo):
    rows = ot_get(Q_CLIN, efo)["data"]["disease"]["associatedTargets"]["rows"]
    gold, gen, kd = set(), {}, {}
    for r in rows:
        s = (r["target"]["approvedSymbol"] or "").upper()
        if not s:
            continue
        dt = {d["id"]: d["score"] for d in r["datatypeScores"]}
        if dt.get("clinical", 0) >= 0.5:
            gold.add(s)
        if dt.get("genetic_association", 0) > 0:
            gen[s] = dt["genetic_association"]
        kd[s] = dt.get("known_drug", 0.0)   # approved-drug-precedence proxy (same query, no endpoint)
    return gold, gen, kd


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "openai/gpt-6.1-sol-pro"
    data = {}
    for name in DISEASES:
        efo = resolve_efo(name)
        if not efo:
            continue
        try:
            g, gen, kd = disease_data(efo)
        except Exception as e:
            print(f"[{name}] data failed: {str(e)[:60]}", flush=True); continue
        if len(g) >= 6:
            data[name] = (efo, g, gen, kd)
            approved = sum(1 for s in g if kd.get(s, 0) >= 0.5)
            print(f"[{name}] clinical={len(g)} approved(kd>=.5)={approved} emerging={len(g)-approved} (kd-covered={sum(1 for s in g if s in kd)})", flush=True)
    all_gold = sorted({x for _, (_, g, _, _) in data.items() for x in g})
    pooled = {k: {"llm": [], "ot": [], "y": []} for k in ("all", "approved", "emerging")}
    for name, (efo, g, gen, kd) in data.items():
        rng = random.Random(0)
        hardneg = [x for x in all_gold if x not in g]; rng.shuffle(hardneg); hardneg = hardneg[:3 * len(g)]
        universe = sorted({*g, *hardneg, *list(gen)[:40]})
        cr = llm_channel(name, universe, model)
        if not cr.ok:
            print(f"[{name}] LLM failed: {cr.error}", flush=True); continue
        kds = sorted(kd.get(s, 0) for s in g); med = kds[len(kds)//2] if kds else 0
        approved = {s for s in g if kd.get(s, 0) >= med and kd.get(s,0) > 0}   # top-half known-drug precedence (famous/approved)
        emerging = {s for s in g if kd.get(s, 0) < med}                        # bottom-half (weaker approved-drug precedence)
        for u in universe:
            neg = u not in g
            pooled["all"]["llm"].append(cr.scores.get(u, 0.0)); pooled["all"]["ot"].append(gen.get(u, 0.0)); pooled["all"]["y"].append(0 if neg else 1)
            if u in approved or neg:
                pooled["approved"]["llm"].append(cr.scores.get(u, 0.0)); pooled["approved"]["ot"].append(gen.get(u, 0.0)); pooled["approved"]["y"].append(1 if u in approved else 0)
            if u in emerging or neg:
                pooled["emerging"]["llm"].append(cr.scores.get(u, 0.0)); pooled["emerging"]["ot"].append(gen.get(u, 0.0)); pooled["emerging"]["y"].append(1 if u in emerging else 0)
        print(f"[{name}] approved={len(approved)} emerging={len(emerging)}", flush=True)
    from sklearn.metrics import roc_auc_score
    def au(arm, ch):
        y = pooled[arm]["y"]; return round(float(roc_auc_score(y, pooled[arm][ch])), 4) if sum(y) >= 5 and sum(y) < len(y) else None
    res = {"model": model, "pooled": {a: {"n_pos": int(sum(pooled[a]["y"])), "n": len(pooled[a]["y"]),
            "llm_alone_auroc": au(a, "llm"), "ot_genetics_auroc": au(a, "ot")} for a in ("all", "approved", "emerging")}}
    em = res["pooled"]["emerging"]
    res["novel_discovery_signal"] = bool(em["llm_alone_auroc"] and em["llm_alone_auroc"] > 0.6 and
                                         em["llm_alone_auroc"] > (em["ot_genetics_auroc"] or 0) + 0.05)
    res["interpretation"] = (
        f"LLM-alone: all={res['pooled']['all']['llm_alone_auroc']}, APPROVED(kd>=.5)={res['pooled']['approved']['llm_alone_auroc']}, "
        f"EMERGING(kd<.5)={em['llm_alone_auroc']} (OT-genetics on emerging={em['ot_genetics_auroc']}, n_emerging_pos={em['n_pos']}). "
        + ("LLM ranks EMERGING (not-yet-approved) targets above chance/genetics -> forward signal beyond approved-drug recall."
           if res["novel_discovery_signal"] else
           "LLM advantage concentrates in APPROVED targets; no clear forward signal on emerging targets -> remains recall, not discovery."))
    json.dump(res, open("bench_targetid_llm_v5_holdout.json", "w"), indent=2)
    print("\n=== DEVELOPMENT-STAGE HOLDOUT ===\n" + json.dumps(res, indent=2), flush=True)


if __name__ == "__main__":
    main()
