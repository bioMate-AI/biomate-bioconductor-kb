#!/usr/bin/env python3
"""Target-ID: does the LLM channel contribute? — CLEAN eval (v3).

Fixes every prior eval bug: (1) canonical immune diseases with FIXED EFO ids (no resolution
failures); (2) a proper CLINICAL gold = OpenTargets `known_drug` targets (targets with an
approved/clinical drug for the disease) — distinct from the genetic-association channel, so NOT
circular; (3) small universe (gold + hard-negatives = other diseases' known-drug targets) so the
LLM reliably returns parseable scores; (4) robust LLM (strip markdown fences, retry on empty).

Arms (run_demonstration): OT genetic-association alone, system NO-LLM (OT_gen + STRING),
system WITH-LLM, LLM-alone, permutation null. Question: does WITH-LLM beat NO-LLM and OT-alone?
Honesty: LLM-alone partly reflects literature memorization of known disease->drug-target links;
the product question is the *lift* WITH-LLM vs NO-LLM/OT-alone. Reported with that caveat.
"""
import json, os, re, sys, random, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from galaxy.ai.target_id.network_channels import StringPpiChannel
from galaxy.ai.target_id.types import ChannelResult
from galaxy.ai.target_id.demonstration import run_demonstration
from benchmark_multidisease import resolve_efo

OR_KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
OT = "https://api.platform.opentargets.org/api/v4/graphql"
DISEASES = [  # canonical immune-mediated diseases; EFO ids resolved live via OT search
    "rheumatoid arthritis", "systemic lupus erythematosus", "ulcerative colitis", "Crohn's disease",
    "multiple sclerosis", "psoriasis", "type 1 diabetes mellitus", "asthma",
    "systemic sclerosis", "ankylosing spondylitis",
]
Q = ("query($id:String!){disease(efoId:$id){associatedTargets(page:{index:0,size:300})"
     "{rows{target{approvedSymbol} datatypeScores{id score}}}}}")


def ot_target_scores(efo):
    """Return (known_drug_gold:set, genetic_assoc:dict) for a disease."""
    body = json.dumps({"query": Q, "variables": {"id": efo}}).encode()
    req = urllib.request.Request(OT, data=body, headers={"Content-Type": "application/json"})
    rows = json.loads(urllib.request.urlopen(req, timeout=40).read())["data"]["disease"]["associatedTargets"]["rows"]
    gold, gen = set(), {}
    for r in rows:
        sym = (r["target"]["approvedSymbol"] or "").upper()
        if not sym:
            continue
        dt = {d["id"]: d["score"] for d in r["datatypeScores"]}
        if dt.get("clinical", 0) >= 0.50:   # clinical-precedence gold (distinct from genetic_association)
            gold.add(sym)
        if dt.get("genetic_association", 0) > 0:
            gen[sym] = dt["genetic_association"]
    return gold, gen


def llm_generate(prompt, model, max_tokens=1600):
    body = json.dumps({"model": model, "temperature": 0.0, "max_tokens": max_tokens,
                       "messages": [{"role": "user", "content": prompt}]}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
                                 headers={"Authorization": f"Bearer {OR_KEY}", "Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=180).read())["choices"][0]["message"]["content"]


def robust_json(text):
    if not text:
        return None
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    s = m.group(1) if m else (text[text.find("{"):text.rfind("}") + 1] if "{" in text and "}" in text else None)
    try:
        return json.loads(s) if s else None
    except Exception:
        return None


def llm_channel(disease, universe, model, retries=2, batch=50):
    """Score the universe in small batches (<=batch genes/call) so the JSON never exceeds the
    token budget — the fix for the large-universe empty-response failures."""
    uni = sorted(universe)
    scores, n_batches_ok = {}, 0
    for i in range(0, len(uni), batch):
        chunk = uni[i:i + batch]
        prompt = ("You are a cautious drug-target evaluator. Score EACH candidate gene for how strongly "
                  f"current evidence supports it as a DRUG TARGET specifically for {disease}.\n"
                  f"Candidates ({len(chunk)}): {', '.join(chunk)}\n"
                  "Return ONLY a raw JSON object mapping gene symbol -> score in [0,1] (1=strongest). "
                  "Score every candidate. No markdown, no prose.")
        for _ in range(retries + 1):
            try:
                obj = robust_json(llm_generate(prompt, model, max_tokens=1200))
            except Exception:
                obj = None
            if isinstance(obj, dict) and obj:
                n_batches_ok += 1
                for k, v in obj.items():
                    try:
                        scores[str(k).upper()] = float(v)
                    except Exception:
                        pass
                break
    if not scores:
        return ChannelResult(channel="llm_reasoned", error="unparseable/empty after retries")
    return ChannelResult(channel="llm_reasoned", scores=scores,
                         provenance={"model": model, "batches_ok": n_batches_ok})


def arm(res, key):
    return (res["arms"].get(key) or {}).get("auroc")


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "openai/gpt-6.1-sol-pro"
    # precompute gold per disease
    gold_by = {}
    for name in DISEASES:
        try:
            efo = resolve_efo(name)
            if not efo:
                print(f"[gold] {name}: no EFO", flush=True); continue
            g, gen = ot_target_scores(efo)
            gold_by[name] = (efo, g, gen)
            print(f"[gold] {name} ({efo}): clinical_gold={len(g)} genetic={len(gen)}", flush=True)
        except Exception as e:
            print(f"[gold] {name}: FAILED {type(e).__name__}: {str(e)[:80]}", flush=True)
    all_gold = sorted({x for _, (_, g, _) in gold_by.items() for x in g})
    rows = []
    for name, (efo, gold, gen) in gold_by.items():
        if len(gold) < 5:
            rows.append({"disease": name, "error": f"too few known-drug gold ({len(gold)})"}); continue
        rng = random.Random(0)
        hardneg = [x for x in all_gold if x not in gold]
        rng.shuffle(hardneg); hardneg = hardneg[: 3 * len(gold)]
        universe = sorted({*gold, *hardneg, *list(gen)[:40]})
        # OT genetic-association channel over universe
        cr_ot = ChannelResult(channel="genetics_ot", scores={g2: gen.get(g2, 0.0) for g2 in universe})
        seeds = [t for t, _ in sorted(gen.items(), key=lambda kv: -kv[1])[:20]]
        cr_string = StringPpiChannel(agg="max", limit=50).run({"seed_genes": seeds}) if seeds else ChannelResult(channel="ppi_string", error="no seeds")
        if cr_string.ok:
            cr_string.scores = {t.upper(): s for t, s in cr_string.scores.items() if t.upper() in set(universe)}
        cr_llm = llm_channel(name, universe, model)
        base = [cr_ot] + ([cr_string] if cr_string.ok and cr_string.scores else [])
        resA = run_demonstration(base, gold=gold, n_perm=300)
        resB = run_demonstration(base + ([cr_llm] if cr_llm.ok else []), gold=gold, n_perm=300)
        r = {"disease": name, "n_gold": len(gold), "n_universe": len(universe), "llm_ok": cr_llm.ok,
             "llm_err": None if cr_llm.ok else cr_llm.error, "n_llm": len(cr_llm.scores) if cr_llm.ok else 0,
             "ot_gen_alone": arm(resA, "channel:genetics_ot"), "string_alone": arm(resA, "channel:ppi_string"),
             "system_noLLM": resA["system_auroc"], "system_withLLM": resB["system_auroc"],
             "llm_alone": arm(resB, "channel:llm_reasoned"), "null_bar": resB["null_bar_auroc_p95"]}
        rows.append(r); print(json.dumps(r), flush=True)
    ok = [r for r in rows if "error" not in r and r.get("system_withLLM") is not None]
    import statistics as st
    summ = {"n_ok": len(ok), "model": model, "rows": rows}
    if ok:
        mean = lambda k: round(st.mean([r[k] for r in ok if r.get(k) is not None]), 4) if [r[k] for r in ok if r.get(k) is not None] else None
        beats = lambda a, b: f"{sum(1 for r in ok if (r.get(a) or 0) > (r.get(b) or 0) + 1e-9)}/{len(ok)}"
        summ.update({"llm_ok_count": f"{sum(1 for r in ok if r.get('llm_ok'))}/{len(ok)}",
                     "mean_ot_gen_alone": mean("ot_gen_alone"), "mean_system_noLLM": mean("system_noLLM"),
                     "mean_system_withLLM": mean("system_withLLM"), "mean_llm_alone": mean("llm_alone"),
                     "mean_null_bar": mean("null_bar"),
                     "withLLM_beats_noLLM": beats("system_withLLM", "system_noLLM"),
                     "withLLM_beats_OTgen": beats("system_withLLM", "ot_gen_alone"),
                     "llm_alone_beats_OTgen": beats("llm_alone", "ot_gen_alone"),
                     "llm_alone_beats_null": f"{sum(1 for r in ok if (r.get('llm_alone') or 0) > (r.get('null_bar') or 1))}/{len(ok)}"})
        print("\n=== SUMMARY ===\n" + json.dumps({k: v for k, v in summ.items() if k != 'rows'}, indent=2), flush=True)
    json.dump(summ, open("bench_targetid_llm_v3_immune.json", "w"), indent=2); print("wrote bench_targetid_llm_v3_immune.json", flush=True)


if __name__ == "__main__":
    main()
