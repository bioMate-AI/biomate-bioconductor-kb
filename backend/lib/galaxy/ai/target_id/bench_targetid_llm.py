#!/usr/bin/env python3
"""Does the LLM-reasoned channel CONTRIBUTE to target-ID? (the test never run)

The multi-disease benchmark only ever fed OpenTargets + STRING. The system HAS an
LLMReasonedChannel (frontier-LLM scores candidate targets from its own literature/clinical
knowledge) but it was off-by-default, down-weighted, and benchmarked-around. This runs the
honest with-vs-without comparison on the curated gold, reusing run_demonstration (HarmonicSum
fusion + per-channel arms + permutation null).

Per disease, four arms compared on the gold:
  OT-alone          (genetics_ot channel)         — the strong existing baseline
  system NO-LLM     (OT + STRING, harmonic fusion) — current product
  system WITH-LLM   (OT + STRING + LLM, fusion)    — does the LLM channel earn lift?
  LLM-alone         (llm_reasoned channel)         — what the LLM knows by itself

HONESTY: LLM-alone high can be MEMORIZATION (the LLM read the same literature the gold derives
from) rather than complementary signal. The product-relevant question is whether WITH-LLM beats
NO-LLM *and* OT-alone (the LLM adding target knowledge OT genetics lacks); LLM-alone is reported
with that caveat, not as a clean capability number.

Usage: PYTHONPATH=<repo>/backend/lib python3 bench_targetid_llm.py <gold.json> [n_diseases] [model]
"""
import json, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from galaxy.ai.target_id.data_channels import OpenTargetsGeneticsChannel
from galaxy.ai.target_id.network_channels import StringPpiChannel
from galaxy.ai.target_id.channels import LLMReasonedChannel
from galaxy.ai.target_id.demonstration import run_demonstration
from benchmark_multidisease import resolve_efo

OR_KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()


class OpenRouterLLM:
    """Duck-typed .generate(prompt, **kwargs) -> str via OpenRouter (urllib; no openai dep)."""
    def __init__(self, model="deepseek/deepseek-v4-pro"):
        self.model = model

    def generate(self, prompt, max_tokens=1500, temperature=0.0, **kw):
        body = json.dumps({"model": self.model, "temperature": temperature, "max_tokens": max_tokens,
                           "messages": [{"role": "user", "content": prompt}]}).encode()
        req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
                                     headers={"Authorization": f"Bearer {OR_KEY}", "Content-Type": "application/json"})
        r = json.loads(urllib.request.urlopen(req, timeout=180).read())
        return r["choices"][0]["message"]["content"]


def arm(res, key):
    a = (res["arms"].get(key) or {})
    return a.get("auroc")


def bench(name, gold_genes, llm, top_k=20):
    efo = resolve_efo(name)
    if not efo:
        return {"disease": name, "error": "no EFO"}
    cr_ot = OpenTargetsGeneticsChannel(default_disease_id=efo, size=200).run({})
    if not cr_ot.ok or not cr_ot.scores:
        return {"disease": name, "efo": efo, "error": "OT failed"}
    cand = [t for t, _ in sorted(cr_ot.scores.items(), key=lambda kv: -kv[1])]
    cr_string = StringPpiChannel(agg="max", limit=50).run({"seed_genes": cand[:top_k]})
    if cr_string.ok:  # corroborate-only (the fair mode; expansion hurt in the prior bench)
        cr_string.scores = {t: s for t, s in cr_string.scores.items() if t in cr_ot.scores}
    cr_llm = LLMReasonedChannel(llm).run({"query": f"drug targets for {name}", "candidate_targets": cand[:50]})
    base = [cr_ot] + ([cr_string] if cr_string.ok and cr_string.scores else [])
    resA = run_demonstration(base, gold=gold_genes, n_perm=300)
    resB = run_demonstration(base + ([cr_llm] if cr_llm.ok else []), gold=gold_genes, n_perm=300)
    return {
        "disease": name, "efo": efo, "llm_ok": cr_llm.ok, "llm_err": cr_llm.error if not cr_llm.ok else None,
        "n_llm_scores": len(cr_llm.scores) if cr_llm.ok else 0,
        "ot_alone": arm(resA, "channel:genetics_ot"),
        "string_alone": arm(resA, "channel:ppi_string"),
        "system_noLLM": resA["system_auroc"],
        "system_withLLM": resB["system_auroc"],
        "llm_alone": arm(resB, "channel:llm_reasoned"),
        "null_bar": resB["null_bar_auroc_p95"],
    }


def main():
    gold_path = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    model = sys.argv[3] if len(sys.argv) > 3 else "deepseek/deepseek-v4-pro"
    gold = json.load(open(gold_path))
    g = gold.get("target_id_gold_disgenet") or gold.get("gold") or gold
    diseases = list(g.items())[:n]
    llm = OpenRouterLLM(model=model)
    print(f"LLM target-ID contribution bench: {len(diseases)} diseases, model={model}", flush=True)
    rows = []
    for name, genes in diseases:
        try:
            r = bench(name, genes, llm)
        except Exception as e:
            r = {"disease": name, "error": f"{type(e).__name__}: {str(e)[:120]}"}
        rows.append(r)
        print(json.dumps(r), flush=True)
    ok = [r for r in rows if "error" not in r and r.get("system_withLLM") is not None and r.get("ot_alone") is not None]
    import statistics as st
    summ = {"n_ok": len(ok), "model": model, "rows": rows}
    if ok:
        def mean(k):
            v = [r[k] for r in ok if r.get(k) is not None]
            return round(st.mean(v), 4) if v else None
        summ.update({
            "mean_ot_alone": mean("ot_alone"), "mean_system_noLLM": mean("system_noLLM"),
            "mean_system_withLLM": mean("system_withLLM"), "mean_llm_alone": mean("llm_alone"),
            "withLLM_beats_noLLM": f"{sum(1 for r in ok if (r.get('system_withLLM') or 0) > (r.get('system_noLLM') or 0) + 1e-9)}/{len(ok)}",
            "withLLM_beats_OTalone": f"{sum(1 for r in ok if (r.get('system_withLLM') or 0) > (r.get('ot_alone') or 0) + 1e-9)}/{len(ok)}",
            "llm_alone_beats_OTalone": f"{sum(1 for r in ok if (r.get('llm_alone') or 0) > (r.get('ot_alone') or 0) + 1e-9)}/{len(ok)}",
        })
        print("\n=== SUMMARY ===")
        print(json.dumps({k: v for k, v in summ.items() if k != "rows"}, indent=2), flush=True)
    out = "bench_targetid_llm_" + os.path.basename(gold_path).replace(".json", "") + ".json"
    json.dump(summ, open(out, "w"), indent=2)
    print("wrote", out, flush=True)


if __name__ == "__main__":
    main()
