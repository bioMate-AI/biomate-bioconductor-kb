#!/usr/bin/env python3
"""Run intent_interpretation + task_decomposition against any OpenAI-compatible endpoint (frontier API
or a local vLLM base). Writes results/<model>/<task>.jsonl in the format score.py expects. No openai dep."""
import json, os, re, sys, time, urllib.request
PE="/Users/kky/biomate-review/evaluation/datasets/public_export"
ENDPOINT=os.environ.get("ENDPOINT","https://api.openai.com/v1")
MODEL=os.environ.get("MODEL","gpt-4.1")
KEY=os.environ.get("API_KEY", os.environ.get("OPENAI_API_KEY",""))
THINK=os.environ.get("THINK","0")=="1"
OUTDIR=os.environ.get("OUTDIR", f"{PE}/results/{MODEL.replace('/','_')}")
HERE=os.environ.get("DATA_DIR", PE)   # on the box, data dir may be local copy

INTENT_LABELS=sorted({json.loads(l)["intent"] for l in open(f"{HERE}/intent_interpretation/data.jsonl")})
INTENT_INSTR=("Classify this BioMate user request into exactly one INTENT (capability) label from the list.")
DECOMP_INSTR=("Decompose this request into an ordered plan of sub-tasks. Reply ONLY a JSON list of "
    "{\"sub_task\": ..., \"order\": N, \"depends_on\": [prerequisite orders]} — INDEPENDENT sub-tasks have "
    "empty depends_on (they can run in parallel); a sub-task that needs an earlier one's output lists that "
    "order in depends_on.")

def call(prompt, maxtok):
    body={"model":MODEL,"messages":[{"role":"user","content":prompt}],"temperature":0,"max_tokens":maxtok}
    if ENDPOINT.startswith("http://"):  # local vLLM: pass thinking toggle
        body["chat_template_kwargs"]={"enable_thinking":THINK}
    hdr={"Content-Type":"application/json"}
    if KEY: hdr["Authorization"]=f"Bearer {KEY}"
    data=json.dumps(body).encode()
    for a in range(3):
        try:
            r=urllib.request.urlopen(urllib.request.Request(ENDPOINT.rstrip('/')+"/chat/completions",data,hdr),timeout=120)
            return json.load(r)["choices"][0]["message"]["content"] or ""
        except Exception as e:
            if a==2: print("FAIL",e,flush=True); return ""
            time.sleep(4)

def strip_think(t):
    t=re.sub(r"<think>.*?</think>","",t,flags=re.S); t=re.sub(r"^.*</think>","",t,flags=re.S); return t

def run_intent():
    labset={l.lower():l for l in INTENT_LABELS}
    rows=[json.loads(l) for l in open(f"{HERE}/intent_interpretation/data.jsonl")]
    out=[]
    for r in rows:
        p=f"{INTENT_INSTR}\nRespond with EXACTLY ONE option from this list and nothing else:\n{', '.join(INTENT_LABELS)}\n\nINPUT:\n{r['query']}"
        t=strip_think(call(p,200)).strip().lower()
        pred=next((labset[l] for l in sorted(labset,key=len,reverse=True) if l in t), (t.split()[0] if t else ""))
        out.append({"id":r["id"],"prediction":pred})
    return out

def run_decomp():
    rows=[json.loads(l) for l in open(f"{HERE}/task_decomposition/data.jsonl")]
    out=[]
    for r in rows:
        p=f"{DECOMP_INSTR}\n\nINPUT:\n{r['query']}"
        t=strip_think(call(p,1500))
        m=re.search(r"\[.*\]", t, re.S)
        try: plan=json.loads(m.group()) if m else []
        except Exception: plan=[]
        out.append({"id":r["id"],"prediction":plan})
    return out

if __name__=="__main__":
    os.makedirs(OUTDIR,exist_ok=True)
    for task,fn in (("intent_interpretation",run_intent),("task_decomposition",run_decomp)):
        res=fn()
        with open(f"{OUTDIR}/{task}.jsonl","w") as f:
            for rec in res: f.write(json.dumps(rec)+"\n")
        print(f"wrote {OUTDIR}/{task}.jsonl ({len(res)})",flush=True)
