"""INDEPENDENT auditor (T18): is the category correct for this real error, is root_cause faithful
to the log (not hallucinated), is the fix plausible? Only PASS -> diag_pass.jsonl."""
import json, os, re, urllib.request
from concurrent.futures import ThreadPoolExecutor
import sys; sys.path.insert(0, os.path.dirname(__file__)); from diag_prompt import TAXONOMY
REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; AUD="gpt-5.6-terra"
def audit(e):
    prompt=("Independent auditor for a failure-diagnosis training item. Given a real ERROR LOG and a proposed "
      f"diagnosis (category from {TAXONOMY}, root_cause, fix), reply ONLY JSON: "
      '{"category_correct":0-1,"root_cause_faithful":0-1,"fix_plausible":0-1,"pass":true/false,"reason":"..."}\n'
      "root_cause_faithful=1 iff the root cause is supported by the log (not invented). pass=true iff all three hold.\n\n"
      f"ERROR LOG:\n{e['error_log'][:900]}\nPROPOSED: category={e['category']} | root_cause={e['root_cause']} | fix={e['fix']}")
    body=json.dumps({"model":AUD,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":3500,"reasoning_effort":"low"}).encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=90))
        m=re.search(r"\{.*\}", d["choices"][0]["message"]["content"], re.S); v=json.loads(m.group(0)) if m else {"pass":False}
        return {**e,"audit":v}
    except Exception as ex: return {**e,"audit":{"pass":False,"reason":str(ex)}}
D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
items=[json.loads(l) for l in open(f"{D}/diag_generated_raw.jsonl") if l.strip()]
res=[]
with ThreadPoolExecutor(max_workers=8) as ex:
    for r in ex.map(audit, items): res.append(r)
p=[r for r in res if r["audit"].get("pass")]
open(f"{D}/diag_pass.jsonl","w").write("\n".join(json.dumps({k:v for k,v in r.items() if k!='audit'}) for r in p))
import collections
print(f"AUDITED {len(res)} diag | PASS {len(p)} ({len(p)*100//max(len(res),1)}%) | cats: {dict(collections.Counter(r['category'] for r in p))}")
