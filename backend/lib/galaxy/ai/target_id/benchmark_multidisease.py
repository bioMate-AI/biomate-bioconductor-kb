#!/usr/bin/env python3
"""Multi-disease contribution benchmark for the evidence-fusion target-ID system.

THE honest question (same rigor that sank the base): does the FUSION beat OpenTargets-ALONE,
robustly across diseases, past the permutation null? Channels are INDEPENDENT of the gold:
  - genetics_ot : OpenTargets association (live GraphQL)
  - ppi_string  : STRING-PPI proximity to the OT top-k hits (live)   [the corroboration channel]
Gold = curated DisGeNET-derived approved/associated targets per disease (gold_targets_*.json).
Arbiter = HarmonicSumArbiter (the system). Scored by run_demonstration: system vs each single
channel vs null (AUROC/AP/prec@k). Aggregate = system-vs-OT-alone per disease + pooled + win count.

Usage: PYTHONPATH=<repo>/backend/lib python3 bench_targetid_multidisease.py <gold.json> [n_diseases] [top_k_seeds]
Live APIs; fails soft per disease. 3.9-safe except f-strings.
"""
import json, sys, time, urllib.request
from galaxy.ai.target_id import OpenTargetsGeneticsChannel, StringPpiChannel, run_demonstration

OT_GQL = "https://api.platform.opentargets.org/api/v4/graphql"
_efo_cache = {}


def resolve_efo(name):
    if name in _efo_cache:
        return _efo_cache[name]
    q = ('query($s:String!){search(queryString:$s,entityNames:["disease"],page:{index:0,size:1})'
         '{hits{id name}}}')
    try:
        req = urllib.request.Request(OT_GQL, data=json.dumps({"query": q, "variables": {"s": name}}).encode(),
                                     headers={"Content-Type": "application/json"})
        hits = json.loads(urllib.request.urlopen(req, timeout=25).read())["data"]["search"]["hits"]
        efo = hits[0]["id"] if hits else None
    except Exception as e:
        efo = None
    _efo_cache[name] = efo
    return efo


CORROBORATE = "--corroborate" in sys.argv  # STRING re-ranks OT's OWN candidates only (no universe expansion)


def bench_disease(name, gold_genes, top_k=20):
    efo = resolve_efo(name)
    if not efo:
        return {"disease": name, "error": "no EFO"}
    cr_ot = OpenTargetsGeneticsChannel(default_disease_id=efo, size=200).run({})
    if not cr_ot.ok:
        return {"disease": name, "efo": efo, "error": "OT: " + str(cr_ot.error)}
    seeds = [t for t, _ in sorted(cr_ot.scores.items(), key=lambda kv: -kv[1])[:top_k]]
    cr_string = StringPpiChannel(agg="max", limit=50).run({"seed_genes": seeds})
    if CORROBORATE and cr_string.ok:
        # fair test: keep STRING only on OT's candidates (corroboration, not expansion with PPI neighbors)
        cr_string.scores = {t: s for t, s in cr_string.scores.items() if t in cr_ot.scores}
        if not cr_string.scores:
            cr_string.error = "no overlap with OT candidates"
    channel_results = [cr_ot] + ([cr_string] if cr_string.ok and cr_string.scores else [])
    res = run_demonstration(channel_results, gold=gold_genes, k_list=(10, 20, 50), n_perm=300)
    arms = res["arms"]
    return {
        "disease": name, "efo": efo,
        "n_gold_in_universe": res["n_gold_in_universe"], "universe": res["universe_size"],
        "channels": res["channels"],
        "system_auroc": res["system_auroc"],
        "ot_alone_auroc": (arms.get("channel:genetics_ot") or {}).get("auroc"),
        "string_alone_auroc": (arms.get("channel:ppi_string") or {}).get("auroc"),
        "null_bar": res["null_bar_auroc_p95"],
        "system_prec20": (arms.get("system") or {}).get("prec_at_k", {}).get(20),
        "ot_prec20": (arms.get("channel:genetics_ot") or {}).get("prec_at_k", {}).get(20),
        "pass_P1": res["pass_P1_system_beats_singles_and_null"],
    }


def main():
    gold_path = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 999
    top_k = int(sys.argv[3]) if len(sys.argv) > 3 else 20
    gold = json.load(open(gold_path))
    g = gold.get("target_id_gold_disgenet") or gold.get("gold") or gold
    diseases = [(k, v) for k, v in g.items() if isinstance(v, list) and v][:n]
    print("benchmarking %d diseases from %s" % (len(diseases), gold_path), flush=True)
    rows = []
    for name, genes in diseases:
        try:
            r = bench_disease(name, genes, top_k=top_k)
        except Exception as e:
            r = {"disease": name, "error": "%s: %s" % (type(e).__name__, e)}
        rows.append(r)
        if "error" in r:
            print("  %-42s ERROR %s" % (name[:42], r["error"]), flush=True)
        else:
            delta = (r["system_auroc"] or 0) - (r["ot_alone_auroc"] or 0)
            print("  %-42s sys=%.3f ot=%.3f d=%+.3f null=%.3f P1=%s ch=%s"
                  % (name[:42], r["system_auroc"] or 0, r["ot_alone_auroc"] or 0, delta,
                     r["null_bar"] or 0, r["pass_P1"], "+".join(r["channels"])), flush=True)
        time.sleep(0.3)
    ok = [r for r in rows if "error" not in r and r["system_auroc"] is not None and r["ot_alone_auroc"] is not None]
    both_ch = [r for r in ok if len(r["channels"]) >= 2]
    import statistics as st
    print("\n==== AGGREGATE (diseases with BOTH channels: %d/%d) ====" % (len(both_ch), len(ok)))
    if both_ch:
        sys_m = st.mean(r["system_auroc"] for r in both_ch)
        ot_m = st.mean(r["ot_alone_auroc"] for r in both_ch)
        wins = sum(1 for r in both_ch if r["system_auroc"] > r["ot_alone_auroc"] + 1e-9)
        beats_null = sum(1 for r in both_ch if r["null_bar"] and r["system_auroc"] > r["null_bar"])
        print("mean system AUROC %.4f vs mean OT-alone %.4f  (delta %+.4f)" % (sys_m, ot_m, sys_m - ot_m))
        print("fusion > OT-alone in %d/%d diseases; system > null in %d/%d; pass_P1 %d/%d"
              % (wins, len(both_ch), beats_null, len(both_ch),
                 sum(1 for r in both_ch if r["pass_P1"]), len(both_ch)))
    out = gold_path.rsplit("/", 1)[-1].replace(".json", "") + "_bench.json"
    json.dump(rows, open("/tmp/" + out, "w"), indent=2)
    print("wrote /tmp/" + out)


if __name__ == "__main__":
    main()
