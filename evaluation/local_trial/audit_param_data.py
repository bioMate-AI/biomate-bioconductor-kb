"""INDEPENDENT auditor (T06). Deterministic: gold values must be schema-valid (enum membership).
LLM (different model): does the query imply EXACTLY gold_params, realistically, without naming keys,
and NOT imply the distractor params (restraint)? Only PASS -> param_pass.jsonl."""
import json, os, re, urllib.request
from concurrent.futures import ThreadPoolExecutor
REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; AUD="gpt-5.6-terra"
def schema_valid(e):
    byname={p["name"]:p for p in e["schema_params"]}
    for k,v in e["gold_params"].items():
        p=byname.get(k)
        if not p: return False
        av=p.get("allowed_values") or []
        if av and v not in av: return False
    return True
def audit(e):
    if not schema_valid(e): return {**e,"audit":{"pass":False,"reason":"gold not schema-valid"}}
    keys=[p["name"] for p in e["schema_params"]]
    prompt=("Independent auditor for a parameter-extraction training item. Given a user QUERY, the "
      "candidate parameter SCHEMA, and the PROPOSED gold extraction, reply ONLY JSON: "
      '{"realistic":0-1,"implies_exactly_gold":0-1,"non_circular":0-1,"restraint_ok":0-1,"pass":true/false,"reason":"..."}\n'
      "implies_exactly_gold=1 iff the query clearly implies each gold key=value. non_circular=1 iff the query "
      "does NOT name the parameter keys verbatim. restraint_ok=1 iff the query does NOT imply any non-gold "
      "schema key. pass=true iff all four hold.\n\n"
      f"QUERY: {e['query']}\nSCHEMA KEYS: {keys}\nPROPOSED GOLD: {json.dumps(e['gold_params'])}")
    body=json.dumps({"model":AUD,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":4000,"reasoning_effort":"low"}).encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=90))
        m=re.search(r"\{.*\}", d["choices"][0]["message"]["content"], re.S); v=json.loads(m.group(0)) if m else {"pass":False,"reason":"no json"}
        return {**e,"audit":v}
    except Exception as ex: return {**e,"audit":{"pass":False,"reason":f"err {ex}"}}
D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
items=[json.loads(l) for l in open(f"{D}/param_generated_raw.jsonl") if l.strip()]
res=[]
with ThreadPoolExecutor(max_workers=8) as ex:
    for r in ex.map(audit, items): res.append(r)
p=[r for r in res if r["audit"].get("pass")]
open(f"{D}/param_pass.jsonl","w").write("\n".join(json.dumps({k:v for k,v in r.items() if k!='audit'}) for r in p))
import collections
print(f"AUDITED {len(res)} param items | PASS {len(p)} ({len(p)*100//max(len(res),1)}%) | domains: {dict(collections.Counter(r['domain'] for r in p))}")
