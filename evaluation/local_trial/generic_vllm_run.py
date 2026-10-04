#!/usr/bin/env python3
"""Generic box-side runner: read a prompts file [{id,task,prompt,maxtok}], call local vLLM (no-think),
write {id,task,raw} lines. All parsing/scoring happens locally afterward."""
import json, sys, time, urllib.request
PROMPTS=sys.argv[1]; OUT=sys.argv[2]; ENDPOINT=sys.argv[3] if len(sys.argv)>3 else "http://localhost:8000/v1"
MODEL=sys.argv[4] if len(sys.argv)>4 else "base"
items=json.load(open(PROMPTS))["items"]
def call(prompt,maxtok):
    body=json.dumps({"model":MODEL,"messages":[{"role":"user","content":prompt}],"temperature":0,
                     "max_tokens":maxtok,"chat_template_kwargs":{"enable_thinking":False}}).encode()
    for a in range(3):
        try:
            r=urllib.request.urlopen(urllib.request.Request(ENDPOINT.rstrip('/')+"/chat/completions",body,
                {"Content-Type":"application/json","Authorization":"Bearer x"}),timeout=180)
            return json.load(r)["choices"][0]["message"]["content"] or ""
        except Exception as e:
            if a==2: return ""
            time.sleep(3)
with open(OUT,"w") as f:
    for i,it in enumerate(items):
        raw=call(it["prompt"], it.get("maxtok",200))
        f.write(json.dumps({"id":it["id"],"task":it["task"],"raw":raw})+"\n"); f.flush()
        if i%50==0: print(f"{i}/{len(items)} done",flush=True)
print("DONE",flush=True)
