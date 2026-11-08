#!/usr/bin/env python3
"""Run the bioc_method_selection matrix via OpenRouter: {bare, kb} x {models}.
bare = candidate method NAMES only (model's own knowledge).
kb   = each candidate annotated with its KB description[:200] + input_types (the harness-retrieval analog).
Writes results/<model>_<cond>.jsonl of {id, prediction}. Score with score.py afterward.

Env: OPENROUTER_API_KEY. Usage: python3 run_bioc_matrix.py [model1 model2 ...]
"""
import json, os, re, sys, time, sqlite3, urllib.request
HERE=os.path.dirname(os.path.abspath(__file__))
DB=os.path.join(HERE,"..","..","..","backend","database","galaxy_ai_tools.db")
KEY=os.environ.get("OPENROUTER_API_KEY","")
BASE="https://openrouter.ai/api/v1/chat/completions"
MODELS=sys.argv[1:] or ["anthropic/claude-opus-5","openai/gpt-5.6","google/gemini-3.1-pro-preview","qwen/qwen3.8-max"]
INSTR=("You are selecting the single correct bioinformatics method for the described analysis. "
       "Choose EXACTLY ONE option from the candidate list and respond with ONLY that exact name, nothing else.")
rows=[json.loads(l) for l in open(os.path.join(HERE,"data.jsonl"))]

# KB descriptions for candidates (desc[:200] + input_types) from the workflows table
con=sqlite3.connect(DB); meta={}
for nm,d,it in con.execute("SELECT name, COALESCE(NULLIF(TRIM(description),''),annotation,''), COALESCE(input_types,'') FROM workflows"):
    if nm not in meta: meta[nm]=(d,it)
def kb_line(c):
    d,it=meta.get(c,("",""))
    d=(d or "")[:200].replace("\n"," ").strip()
    return f"{c} — {d}" + (f"  [input: {it}]" if it and it not in ("[]","") else "")

def build_prompt(r, cond):
    if cond=="kb":
        menu="\n".join(kb_line(c) for c in r["candidates"])
        return f"{INSTR}\nEach candidate is 'name — description [input: types]'.\n{menu}\n\nANALYSIS:\n{r['query']}"
    menu=", ".join(r["candidates"])
    return f"{INSTR}\nCandidates: {menu}\n\nANALYSIS:\n{r['query']}"

def call(model, prompt):
    body=json.dumps({"model":model,"messages":[{"role":"user","content":prompt}],
                     "temperature":0,"max_tokens":600}).encode()
    hdr={"Authorization":f"Bearer {KEY}","Content-Type":"application/json",
         "HTTP-Referer":"https://biomate.ai","X-Title":"biomate-bioc-selection"}
    for a in range(3):
        try:
            r=urllib.request.urlopen(urllib.request.Request(BASE,body,hdr),timeout=120)
            return json.load(r)["choices"][0]["message"]["content"] or ""
        except Exception as e:
            if a==2: print(f"  FAIL {model}: {e}",flush=True); return ""
            time.sleep(4)

def parse(text, cands):
    t=re.sub(r"<think>.*?</think>","",text or "",flags=re.S).strip().lower()
    for c in sorted(cands,key=len,reverse=True):
        if c.lower() in t: return c
    return t.split()[0] if t else ""

if not KEY: sys.exit("ERROR: set OPENROUTER_API_KEY")
os.makedirs(os.path.join(HERE,"results"),exist_ok=True)
for model in MODELS:
    for cond in ("bare","kb"):
        out=os.path.join(HERE,"results",f"{model.replace('/','_')}_{cond}.jsonl")
        with open(out,"w") as f:
            for r in rows:
                pred=parse(call(model,build_prompt(r,cond)), r["candidates"])
                f.write(json.dumps({"id":r["id"],"prediction":pred})+"\n"); f.flush()
        print(f"wrote {out}",flush=True)
print("DONE",flush=True)
