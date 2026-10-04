#!/usr/bin/env python3
"""Box-side: run precomputed routing prompts (names + described) against a local vLLM endpoint.
Parses prediction with the same longest-label-substring rule as run_baseline.parse_cls.
Writes predictions.jsonl: {id, names_prediction, described_prediction}."""
import json, sys, time, urllib.request
PROMPTS=sys.argv[1]; OUT=sys.argv[2]; ENDPOINT=sys.argv[3] if len(sys.argv)>3 else "http://localhost:8000/v1"
MODEL=sys.argv[4] if len(sys.argv)>4 else "base"
d=json.load(open(PROMPTS)); labs=d["labels"]; items=d["items"]
labset={l.lower():l for l in labs}
import re
def parse_cls(text):
    t=(text or "")
    t=re.sub(r"<think>.*?</think>","",t,flags=re.S)   # strip reasoning block if any leaked
    t=re.sub(r"^.*</think>","",t,flags=re.S)           # or an unclosed-then-closed think
    t=t.strip().lower()
    for l in sorted(labset,key=len,reverse=True):
        if l in t: return labset[l]
    return t.split()[0] if t else ""
def call(prompt):
    # Base is a Qwen3 reasoning model — DISABLE thinking for this pick-from-menu classification (CoT isn't
    # needed to read a described menu, and thinking blew up latency to ~35s/call). chat_template_kwargs is
    # the clean switch; cap tokens as a safety bound. parse_cls still strips any leaked <think> block.
    body=json.dumps({"model":MODEL,"messages":[{"role":"user","content":prompt}],
                     "max_tokens":200,"temperature":0,
                     "chat_template_kwargs":{"enable_thinking":False}}).encode()
    for attempt in range(3):
        try:
            r=urllib.request.urlopen(urllib.request.Request(ENDPOINT.rstrip("/")+"/chat/completions",body,
                {"Content-Type":"application/json","Authorization":"Bearer x"}),timeout=120)
            return json.load(r)["choices"][0]["message"]["content"]
        except Exception as e:
            if attempt==2: return ""
            time.sleep(3)
with open(OUT,"w") as f:
    for i,it in enumerate(items):
        npred=parse_cls(call(it["names_prompt"]))
        dpred=parse_cls(call(it["described_prompt"]))
        f.write(json.dumps({"id":it["id"],"names_prediction":npred,"described_prediction":dpred})+"\n"); f.flush()
        if i%25==0: print(f"{i}/{len(items)} done",flush=True)
print("DONE",flush=True)
