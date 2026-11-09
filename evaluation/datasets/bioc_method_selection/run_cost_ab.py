#!/usr/bin/env python3
"""Invoice-grade LLM $/task A/B: for each (model, bioc item) call OpenRouter, then GET /generation?id=
to read the ACTUAL CHARGED cost (not tokens x list price). Sum -> real $/task per frontier model.
The on-prem 9B is $0 marginal API; its amortized $/task = GPU $/h / tasks-per-hour (computed separately).
Env: OPENROUTER_API_KEY (falls back to the saved key file). Usage: python3 run_cost_ab.py [models...]
"""
import json, os, re, sys, time, urllib.request
HERE=os.path.dirname(os.path.abspath(__file__))
KEY=os.environ.get("OPENROUTER_API_KEY","") or open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
OR="https://openrouter.ai/api/v1/chat/completions"
GEN="https://openrouter.ai/api/v1/generation?id="
MODELS=sys.argv[1:] or ["anthropic/claude-opus-5","openai/gpt-5.6","google/gemini-3.1-pro-preview","deepseek/deepseek-v4-pro"]
rows=[json.loads(l) for l in open(f"{HERE}/data.jsonl")]
def hdr(): return {"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}
def call_cost(model,prompt):
    """Return (actual_charged_usd, prompt_tok, completion_tok) from inline usage.cost — invoice-grade."""
    body=json.dumps({"model":model,"messages":[{"role":"user","content":prompt}],"temperature":0,
                     "max_tokens":256,"usage":{"include":True}}).encode()
    for a in range(3):
        try:
            d=json.loads(urllib.request.urlopen(urllib.request.Request(OR,body,hdr()),timeout=120).read().decode().lstrip())
            u=d.get("usage") or {}
            if "cost" not in u: return None
            return float(u.get("cost") or 0.0), int(u.get("prompt_tokens") or 0), int(u.get("completion_tokens") or 0)
        except Exception:
            if a==2: return None
            time.sleep(4)
    return None
INSTR=("Select the single correct bioinformatics method. Candidates: %s\nRespond with ONLY the exact name.\nANALYSIS:\n%s")
out={}
for model in MODELS:
    tot=0.0; n=0; tp=tc=0
    for r in rows:
        c=call_cost(model, INSTR%(", ".join(r["candidates"]), r["query"]))
        if c is None: continue
        cost,p,co=c; tot+=cost; tp+=p; tc+=co; n+=1
    out[model]={"n":n,"total_usd":round(tot,5),"usd_per_task":round(tot/max(n,1),6),
                "avg_prompt_tok":round(tp/max(n,1)),"avg_completion_tok":round(tc/max(n,1))}
    print(json.dumps({model:out[model]}),flush=True)
json.dump(out, open(f"{HERE}/results/cost_ab_frontier.json","w"), indent=2)
print("DONE",flush=True)
