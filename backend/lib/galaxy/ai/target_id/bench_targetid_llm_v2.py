#!/usr/bin/env python3
"""Target-ID: does the LLM channel contribute? — CORRECTED eval (v2).

v1 bugs (both manufactured a false null): (a) candidate universe = OpenTargets' own hits, so
gold targets scored 0 -> every arm at chance; (b) LLM JSON wrapped in markdown fences -> parser
dropped 50% of LLM answers. v2 fixes both:
  * robust JSON extraction (strip fences / grab first {...}).
  * VALID universe per disease: positives = this disease's gold; hard-negatives = a sample of OTHER
    diseases' real gold targets (+ OT's genetic candidates). Every channel scores the SAME universe.
    The task is genuine DISEASE-SPECIFIC target ranking (rank this disease's targets above real
    targets of other diseases) — not trivial, and OT/STRING/LLM all compete on the same set.
Arms (via run_demonstration): OT-alone, system NO-LLM (OT+STRING), system WITH-LLM, LLM-alone, null.
Honesty: LLM-alone may partly reflect literature memorization of known disease->target links; the
product question is whether WITH-LLM beats NO-LLM and OT-alone. Reported with that caveat.
"""
import json, os, re, sys, random, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from galaxy.ai.target_id.data_channels import OpenTargetsGeneticsChannel
from galaxy.ai.target_id.network_channels import StringPpiChannel
from galaxy.ai.target_id.types import ChannelResult
from galaxy.ai.target_id.demonstration import run_demonstration
from benchmark_multidisease import resolve_efo

OR_KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()


def llm_generate(prompt, model, max_tokens=2000):
    body = json.dumps({"model": model, "temperature": 0.0, "max_tokens": max_tokens,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
                                 headers={"Authorization": f"Bearer {OR_KEY}", "Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=180).read())["choices"][0]["message"]["content"]


def robust_json(text):
    if not text:
        return None
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    s = m.group(1) if m else None
    if s is None:
        i, j = text.find("{"), text.rfind("}")
        s = text[i:j + 1] if i >= 0 and j > i else None
    if s is None:
        return None
    try:
        return json.loads(s)
    except Exception:
        return None


def llm_channel(disease, universe, model):
    """Score the FULL universe for disease relevance. Robust parse. Returns ChannelResult."""
    cand = ", ".join(sorted(universe))
    prompt = ("You are a cautious target-biology evaluator. Score EACH candidate gene for how strongly "
              f"current evidence supports it as a DRUG TARGET specifically for: {disease}.\n"
              f"Candidates: {cand}\n"
              "Return ONLY a raw JSON object (no markdown, no prose) mapping gene symbol -> score in [0,1] "
              "(1=strongest disease-specific target evidence). Score every candidate.")
    try:
        raw = llm_generate(prompt, model)
    except Exception as e:
        return ChannelResult(channel="llm_reasoned", error=f"llm call failed: {type(e).__name__}: {str(e)[:80]}")
    obj = robust_json(raw)
    if not isinstance(obj, dict):
        return ChannelResult(channel="llm_reasoned", error="unparseable: " + repr((raw or "")[:80]))
    scores = {}
    for k, v in obj.items():
        try:
            scores[str(k).upper()] = float(v)
        except Exception:
            continue
    if not scores:
        return ChannelResult(channel="llm_reasoned", error="no numeric scores")
    return ChannelResult(channel="llm_reasoned", scores=scores, provenance={"source": "llm_reasoned", "model": model})


def arm(res, key):
    return (res["arms"].get(key) or {}).get("auroc")


def bench(name, pos_genes, other_pool, model, top_k=20, n_hardneg_mult=3, max_universe=250):
    efo = resolve_efo(name)
    if not efo:
        return {"disease": name, "error": "no EFO"}
    pos = sorted({g.upper() for g in pos_genes if g and g.isalnum()})
    if len(pos) < 5:
        return {"disease": name, "error": f"too few gold ({len(pos)})"}
    cr_ot = OpenTargetsGeneticsChannel(default_disease_id=efo, size=200).run({})
    ot_cand = [t.upper() for t, _ in sorted(cr_ot.scores.items(), key=lambda kv: -kv[1])[:100]] if cr_ot.ok else []
    # hard negatives = other diseases' gold targets NOT in this disease's gold
    rng = random.Random(0)
    hardneg_pool = [g for g in other_pool if g.upper() not in set(pos)]
    rng.shuffle(hardneg_pool)
    hardneg = [g.upper() for g in hardneg_pool[: n_hardneg_mult * len(pos)]]
    universe = list({*pos, *hardneg, *ot_cand})
    if len(universe) > max_universe:
        # keep all pos + fill to cap with negatives
        negs = [g for g in universe if g not in set(pos)]
        rng.shuffle(negs)
        universe = list({*pos, *negs[: max_universe - len(pos)]})
    seeds = ot_cand[:top_k]
    cr_string = StringPpiChannel(agg="max", limit=50).run({"seed_genes": seeds}) if seeds else ChannelResult(channel="ppi_string", error="no seeds")
    if cr_string.ok:
        cr_string.scores = {t.upper(): s for t, s in cr_string.scores.items() if t.upper() in set(universe)}
    cr_llm = llm_channel(name, universe, model)
    base = ([cr_ot] if cr_ot.ok and cr_ot.scores else []) + ([cr_string] if cr_string.ok and cr_string.scores else [])
    resA = run_demonstration(base, gold=pos, n_perm=300)
    resB = run_demonstration(base + ([cr_llm] if cr_llm.ok else []), gold=pos, n_perm=300)
    return {"disease": name, "efo": efo, "n_pos": len(pos), "n_universe": len(universe),
            "llm_ok": cr_llm.ok, "llm_err": None if cr_llm.ok else cr_llm.error, "n_llm": len(cr_llm.scores) if cr_llm.ok else 0,
            "ot_alone": arm(resA, "channel:genetics_ot"), "string_alone": arm(resA, "channel:ppi_string"),
            "system_noLLM": resA["system_auroc"], "system_withLLM": resB["system_auroc"],
            "llm_alone": arm(resB, "channel:llm_reasoned"), "null_bar": resB["null_bar_auroc_p95"]}


def main():
    gold_path = sys.argv[1]; n = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    model = sys.argv[3] if len(sys.argv) > 3 else "deepseek/deepseek-v4-pro"
    gold = json.load(open(gold_path))
    g = gold.get("target_id_gold_disgenet") or gold.get("gold") or gold
    items = [(k, v) for k, v in g.items() if isinstance(v, (list, tuple)) and len(v) >= 5][:n]
    other_pool = sorted({x for k, v in g.items() if isinstance(v, (list, tuple)) for x in v})
    print(f"v2 LLM target-ID bench: {len(items)} diseases, model={model}, hard-neg pool={len(other_pool)}", flush=True)
    rows = []
    for name, genes in items:
        try:
            r = bench(name, genes, [x for x in other_pool if x not in set(genes)], model)
        except Exception as e:
            r = {"disease": name, "error": f"{type(e).__name__}: {str(e)[:120]}"}
        rows.append(r); print(json.dumps(r), flush=True)
    ok = [r for r in rows if "error" not in r and r.get("system_withLLM") is not None]
    import statistics as st
    summ = {"n_ok": len(ok), "model": model, "rows": rows}
    if ok:
        mean = lambda k: round(st.mean([r[k] for r in ok if r.get(k) is not None]), 4) if [r[k] for r in ok if r.get(k) is not None] else None
        beats = lambda a, b: f"{sum(1 for r in ok if (r.get(a) or 0) > (r.get(b) or 0) + 1e-9)}/{len(ok)}"
        summ.update({"mean_ot_alone": mean("ot_alone"), "mean_system_noLLM": mean("system_noLLM"),
                     "mean_system_withLLM": mean("system_withLLM"), "mean_llm_alone": mean("llm_alone"),
                     "mean_null_bar": mean("null_bar"), "llm_ok_count": f"{sum(1 for r in ok if r.get('llm_ok'))}/{len(ok)}",
                     "withLLM_beats_noLLM": beats("system_withLLM", "system_noLLM"),
                     "withLLM_beats_OTalone": beats("system_withLLM", "ot_alone"),
                     "llm_alone_beats_OTalone": beats("llm_alone", "ot_alone"),
                     "llm_alone_beats_null": f"{sum(1 for r in ok if (r.get('llm_alone') or 0) > (r.get('null_bar') or 1))}/{len(ok)}"})
        print("\n=== SUMMARY ===\n" + json.dumps({k: v for k, v in summ.items() if k != "rows"}, indent=2), flush=True)
    out = "bench_targetid_llm_v2_" + os.path.basename(gold_path).replace(".json", "") + ".json"
    json.dump(summ, open(out, "w"), indent=2); print("wrote", out, flush=True)


if __name__ == "__main__":
    main()
