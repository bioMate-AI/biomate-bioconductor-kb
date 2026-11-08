"""INDEPENDENT AUDITOR: a DIFFERENT model from the generator scores each generated routing
item on a quality rubric and PASS/FAILs it. Only passed items enter training.
Rubric: grounded/realistic, unambiguous->correct, non-circular (no name echo),
valid candidates (correct present + plausible distractors + >=1 hard negative)."""
import json, os, re, urllib.request
from concurrent.futures import ThreadPoolExecutor
REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; AUD_MODEL="gpt-5.6-terra"
def audit(e):
    prompt=("You are an INDEPENDENT data-quality auditor for a workflow-routing training set. "
      "Judge this item and reply with ONLY a JSON object: "
      '{"grounded_realistic":0-1,"unambiguous":0-1,"non_circular":0-1,"valid_candidates":0-1,"pass":true/false,"reason":"..."}\n'
      "Criteria: grounded_realistic=reads like a real user describing their data+goal (not a workflow blurb); "
      "unambiguous=the request should route to correct_workflow and not equally to a distractor; "
      "non_circular=does NOT name or paraphrase the correct workflow; "
      "valid_candidates=correct_workflow is in candidates, distractors are plausible, >=1 is a confusable hard negative. "
      "pass=true only if all four are acceptable.\n\n"
      f"QUERY: {e['query']}\nCORRECT_WORKFLOW: {e['correct_workflow']}\nCANDIDATES: {e['candidates']}\nDOMAIN: {e.get('domain')}")
    body=json.dumps({"model":AUD_MODEL,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":4000,"reasoning_effort":"low"}).encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=90))
        txt=d["choices"][0]["message"]["content"]
        m=re.search(r"\{.*\}", txt, re.S); v=json.loads(m.group(0)) if m else {"pass":False,"reason":"no json"}
        return {**e,"audit":v}
    except Exception as ex: return {**e,"audit":{"pass":False,"reason":f"err {ex}"}}
src=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/generated_raw.jsonl"
items=[json.loads(l) for l in open(src) if l.strip()]
res=[]
with ThreadPoolExecutor(max_workers=8) as ex:
    for r in ex.map(audit, items): res.append(r)
passed=[r for r in res if r["audit"].get("pass")]
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/audited_all.jsonl","w").write("\n".join(json.dumps(r) for r in res))
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/audited_pass.jsonl","w").write("\n".join(json.dumps({k:v for k,v in r.items() if k!='audit'}) for r in passed))
print(f"AUDITED {len(res)} | PASS {len(passed)} ({len(passed)*100//max(len(res),1)}%) | generator=gpt-5-mini auditor={AUD_MODEL}")
print("--- 2 PASS examples ---")
for r in passed[:2]: print(" Q:",r["query"][:110]," -> ",r["correct_workflow"],"| reason:",r["audit"].get("reason","")[:80])
print("--- 2 FAIL examples ---")
for r in [x for x in res if not x["audit"].get("pass")][:2]: print(" Q:",r["query"][:90]," | FAIL:",r["audit"].get("reason","")[:100])
