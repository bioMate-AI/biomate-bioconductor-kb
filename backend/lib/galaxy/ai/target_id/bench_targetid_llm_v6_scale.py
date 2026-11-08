#!/usr/bin/env python3
"""Scale the POSITIVE target-ID result across many immune diseases, with statistics.

v3 showed the LLM-reasoned channel lifts the fused system 9/10 on 10 canonical diseases. v6 scales
to a broad immune-disease panel and reports proper cross-disease statistics so the positive is robust:
  - per-disease: OT-genetics alone, system (OT+STRING) NO-LLM, system WITH-LLM, LLM-alone, perm null
  - cross-disease: Wilcoxon signed-rank on (withLLM - noLLM) deltas; mean delta + bootstrap 95% CI;
    win-count k/N + binomial test vs 0.5; same for withLLM vs OT-alone and LLM-alone vs null.
Clinical-precedence gold (OT `clinical` >= 0.5), distinct from the genetic_association channel.
"""
import json, os, sys, random
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from benchmark_multidisease import resolve_efo
from bench_targetid_llm_v3 import ot_target_scores, llm_channel
from galaxy.ai.target_id.network_channels import StringPpiChannel
from galaxy.ai.target_id.types import ChannelResult
from galaxy.ai.target_id.demonstration import run_demonstration

DISEASES = [  # broad immune-mediated panel (resolved live; kept if >=6 clinical-gold targets)
    "rheumatoid arthritis", "systemic lupus erythematosus", "ulcerative colitis", "Crohn's disease",
    "multiple sclerosis", "psoriasis", "type 1 diabetes mellitus", "asthma", "systemic sclerosis",
    "ankylosing spondylitis", "psoriatic arthritis", "atopic dermatitis", "Sjogren syndrome",
    "Behcet disease", "Graves disease", "Hashimoto thyroiditis", "vitiligo", "alopecia areata",
    "celiac disease", "primary biliary cholangitis", "autoimmune hepatitis", "myasthenia gravis",
    "sarcoidosis", "giant cell arteritis", "juvenile idiopathic arthritis", "pemphigus vulgaris",
    "hidradenitis suppurativa", "polymyalgia rheumatica", "uveitis", "inflammatory bowel disease",
]


def arm(res, key):
    return (res["arms"].get(key) or {}).get("auroc")


def bench_disease(name, all_gold, model):
    efo = resolve_efo(name)
    if not efo:
        return {"disease": name, "error": "no EFO"}
    try:
        gold, gen = ot_target_scores(efo)
    except Exception as e:
        return {"disease": name, "error": f"OT: {str(e)[:60]}"}
    if len(gold) < 6:
        return {"disease": name, "error": f"too few clinical gold ({len(gold)})"}
    rng = random.Random(0)
    hardneg = [x for x in all_gold if x not in gold]; rng.shuffle(hardneg); hardneg = hardneg[: 3 * len(gold)]
    universe = sorted({*gold, *hardneg, *list(gen)[:40]})
    cr_ot = ChannelResult(channel="genetics_ot", scores={g: gen.get(g, 0.0) for g in universe})
    seeds = [t for t, _ in sorted(gen.items(), key=lambda kv: -kv[1])[:20]]
    cr_string = StringPpiChannel(agg="max", limit=50).run({"seed_genes": seeds}) if seeds else ChannelResult(channel="ppi_string", error="no seeds")
    if cr_string.ok:
        cr_string.scores = {t.upper(): s for t, s in cr_string.scores.items() if t.upper() in set(universe)}
    cr_llm = llm_channel(name, universe, model)
    base = [cr_ot] + ([cr_string] if cr_string.ok and cr_string.scores else [])
    resA = run_demonstration(base, gold=gold, n_perm=300)
    resB = run_demonstration(base + ([cr_llm] if cr_llm.ok else []), gold=gold, n_perm=300)
    return {"disease": name, "n_gold": len(gold), "n_universe": len(universe), "llm_ok": cr_llm.ok,
            "ot_gen_alone": arm(resA, "channel:genetics_ot"), "system_noLLM": resA["system_auroc"],
            "system_withLLM": resB["system_auroc"], "llm_alone": arm(resB, "channel:llm_reasoned"),
            "null_bar": resB["null_bar_auroc_p95"]}


def bootstrap_ci(x, n=5000, seed=0):
    rng = np.random.RandomState(seed); x = np.asarray(x, float)
    bs = [np.mean(rng.choice(x, len(x), replace=True)) for _ in range(n)]
    return round(float(np.percentile(bs, 2.5)), 4), round(float(np.percentile(bs, 97.5)), 4)


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "openai/gpt-6.1-sol-pro"
    # pass 1: gather gold per disease (for the hard-negative pool)
    gold_by = {}
    for name in DISEASES:
        efo = resolve_efo(name)
        if not efo:
            print(f"[skip] {name}: no EFO", flush=True); continue
        try:
            g, _ = ot_target_scores(efo)
        except Exception:
            continue
        if len(g) >= 6:
            gold_by[name] = g
            print(f"[gold] {name}: {len(g)}", flush=True)
    all_gold = sorted({x for g in gold_by.values() for x in g})
    print(f"=== {len(gold_by)} diseases qualify; hard-neg pool {len(all_gold)} ===", flush=True)
    # pass 2: benchmark
    rows = []
    for name in gold_by:
        try:
            r = bench_disease(name, all_gold, model)
        except Exception as e:
            r = {"disease": name, "error": f"{type(e).__name__}: {str(e)[:100]}"}
        rows.append(r); print(json.dumps({k: r.get(k) for k in ('disease', 'system_noLLM', 'system_withLLM', 'llm_alone', 'ot_gen_alone', 'null_bar')}), flush=True)
    ok = [r for r in rows if "error" not in r and r.get("system_withLLM") is not None and r.get("llm_ok")]
    import scipy.stats as ss
    res = {"model": model, "n_diseases_ok": len(ok), "rows": rows}
    if len(ok) >= 6:
        d_wo = np.array([r["system_withLLM"] - r["system_noLLM"] for r in ok])
        d_ot = np.array([r["system_withLLM"] - r["ot_gen_alone"] for r in ok])
        d_ln = np.array([r["llm_alone"] - r["null_bar"] for r in ok])
        def summ(d, label):
            wins = int((d > 0).sum()); n = len(d)
            return {"mean_delta": round(float(d.mean()), 4), "bootstrap95_CI": bootstrap_ci(d),
                    "wins": f"{wins}/{n}", "binom_p_vs_0.5": round(float(ss.binomtest(wins, n, 0.5).pvalue), 5),
                    "wilcoxon_p": round(float(ss.wilcoxon(d).pvalue), 5) if len(set(d)) > 1 else None}
        res["withLLM_vs_noLLM"] = summ(d_wo, "wo")
        res["withLLM_vs_OTgenetics"] = summ(d_ot, "ot")
        res["LLMalone_vs_null"] = summ(d_ln, "ln")
        res["means"] = {"ot_gen": round(float(np.mean([r["ot_gen_alone"] for r in ok])), 4),
                        "system_noLLM": round(float(np.mean([r["system_noLLM"] for r in ok])), 4),
                        "system_withLLM": round(float(np.mean([r["system_withLLM"] for r in ok])), 4),
                        "llm_alone": round(float(np.mean([r["llm_alone"] for r in ok])), 4),
                        "null": round(float(np.mean([r["null_bar"] for r in ok])), 4)}
        res["POSITIVE"] = bool(res["withLLM_vs_noLLM"]["mean_delta"] > 0 and res["withLLM_vs_noLLM"]["wilcoxon_p"] and res["withLLM_vs_noLLM"]["wilcoxon_p"] < 0.05)
        print("\n=== SCALED POSITIVE ===\n" + json.dumps({k: v for k, v in res.items() if k != "rows"}, indent=2), flush=True)
    json.dump(res, open("bench_targetid_llm_v6_scale.json", "w"), indent=2)
    print("wrote bench_targetid_llm_v6_scale.json", flush=True)


if __name__ == "__main__":
    main()
