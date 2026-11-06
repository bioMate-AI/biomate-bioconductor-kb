#!/usr/bin/env python3
"""Run the clarification benchmark: bare LLM vs LLM + clarification knowledge (harness).

bare    = query + the slot in question only.
harness = additionally the clarification knowledge (the branch options for a fork; the fill-only-if-stated
          rule for params/inputs) — i.e. what the deployed clarification layer supplies.

Usage: OPENROUTER_API_KEY=... python3 run_clarification.py "model1,model2,..."
"""
import json, os, re, sys, urllib.request, time, concurrent.futures as cf

HERE = os.path.dirname(os.path.abspath(__file__))
ITEMS = [json.loads(l) for l in open(os.path.join(HERE, "data.jsonl"))]
KEY = os.environ.get("OPENROUTER_API_KEY", "")
import importlib.util
_sp = importlib.util.spec_from_file_location("sc", os.path.join(HERE, "score.py"))
SC = importlib.util.module_from_spec(_sp); _sp.loader.exec_module(SC)

FORK_OPTIONS = {  # the two branches a fork chooses between (the harness knowledge)
    "variant_type": "germline vs somatic variant calling", "assembly_type": "de novo vs reference-guided assembly",
    "rnaseq_type": "bulk RNA-seq vs single-cell RNA-seq", "peak_calling_type": "ChIP-seq vs ATAC-seq",
    "chip_target": "transcription factor (narrow peaks) vs histone mark (broad peaks)",
    "proteomics_type": "DDA vs DIA acquisition", "cryoem_type": "single-particle (SPA) vs tomography (cryo-ET)",
    "metagenomics_type": "16S amplicon vs shotgun metagenomics", "docking_type": "blind vs site-directed docking",
    "rnaseq_focus": "mRNA/differential-expression vs small-RNA/miRNA",
}
INSTR = ('Return ONLY JSON: {"action":"interpret"|"clarify","value":"<the value, if you can interpret it from '
         'the request>","clarify_about":"<what you would ask the user, if it must be clarified>"}. '
         'Choose "interpret" ONLY when the request clearly determines the value; otherwise "clarify". '
         'Do not over-ask when the request is clear, and do not silently guess when it is genuinely ambiguous.')

def prompt(it, mode):
    slot = {"branch": "workflow branch", "param": "parameter", "input": "input file"}[it["slot_type"]]
    base = f"User request: \"{it['query']}\"\n\nFor the {slot} \"{it['gold_target']}\", decide interpret or clarify."
    if mode == "harness":
        if it["slot_type"] == "branch" and it["gold_target"] in FORK_OPTIONS:
            base += f"\nThis {slot} is a choice between: {FORK_OPTIONS[it['gold_target']]}."
        else:
            base += "\nRule: fill the value only if it is explicitly stated or unambiguously implied; otherwise clarify."
    return base + "\n\n" + INSTR

def ask(model, it, mode):
    body = json.dumps({"model": model, "temperature": 0, "max_tokens": 2500,
                       "messages": [{"role": "user", "content": prompt(it, mode)}]}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body,
          headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    for _ in range(3):
        try:
            c = json.loads(urllib.request.urlopen(req, timeout=75).read())["choices"][0]["message"].get("content") or ""
            m = re.search(r"\{.*\}", c, re.S)
            if m:
                try: return json.loads(m.group())
                except Exception: pass
        except Exception: time.sleep(4)
    return {}

def run(model):
    res = {}
    for mode in ("bare", "harness"):
        preds = [{"id": it["id"], **ask(model, it, mode)} for it in ITEMS]
        res[mode] = SC.score(ITEMS, preds)
    b, h = res["bare"], res["harness"]
    print(f"{model:28s} bare: dec={b['decision_acc']} outcome={b['outcome']} | "
          f"harness: dec={h['decision_acc']} outcome={h['outcome']} (+{round(h['outcome']-b['outcome'],3)})", flush=True)
    return {"model": model, **{f"bare_{k}": v for k, v in b.items()}, **{f"harness_{k}": v for k, v in h.items()}}

if __name__ == "__main__":
    models = sys.argv[1].split(",") if len(sys.argv) > 1 else []
    print("CLARIFICATION BENCHMARK — interpret-or-clarify (bare vs + clarification knowledge)\n")
    rows = []
    if models and KEY:
        with cf.ThreadPoolExecutor(max_workers=4) as ex: rows = list(ex.map(run, models))
    json.dump(rows, open(os.path.join(HERE, "results_summary.json"), "w"), indent=2)
    print("\nwrote results_summary.json")
