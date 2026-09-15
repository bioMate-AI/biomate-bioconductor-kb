"""INDEPENDENT auditor for multi-intent items (different model from generator)."""
import json, os, re, urllib.request
from concurrent.futures import ThreadPoolExecutor
REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; AUD="gpt-5.6-terra"
INTENTS=["workflow_generation","workflow_modification","visualization","tool_search","troubleshooting",
 "research_question","database_lookup","genomics_knowledge","clinical_genomics","experiment_design",
 "data_interpretation","protocol_guidance","methods_writing","teaching_explanation","general_question",
 "benchmark_query","dataset_inquiry","cost_estimation","regulatory_compliance"]
def audit(e):
    prompt=("Independent auditor for an intent-classification training set. Given a user query and its "
      f"proposed intent label (from {INTENTS}), reply ONLY JSON: "
      '{"realistic":0-1,"label_correct":0-1,"non_circular":0-1,"pass":true/false,"reason":"..."}\n'
      "label_correct=1 only if the proposed intent is the single best BioMate intent for this query. "
      "pass=true only if realistic AND label_correct AND non_circular.\n\n"
      f"QUERY: {e['query']}\nPROPOSED_INTENT: {e['intent']}")
    body=json.dumps({"model":AUD,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":4000,"reasoning_effort":"low"}).encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=90))
        m=re.search(r"\{.*\}", d["choices"][0]["message"]["content"], re.S); v=json.loads(m.group(0)) if m else {"pass":False,"reason":"no json"}
        return {**e,"audit":v}
    except Exception as ex: return {**e,"audit":{"pass":False,"reason":f"err {ex}"}}
items=[json.loads(l) for l in open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/generated_intent_raw.jsonl") if l.strip()]
res=[]
with ThreadPoolExecutor(max_workers=8) as ex:
    for r in ex.map(audit, items): res.append(r)
p=[r for r in res if r["audit"].get("pass")]
from collections import Counter
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/intent_pass.jsonl","w").write("\n".join(json.dumps({k:v for k,v in r.items() if k!='audit'}) for r in p))
print(f"AUDITED {len(res)} intent items | PASS {len(p)} ({len(p)*100//max(len(res),1)}%) | by intent: {dict(Counter(r['intent'] for r in p))}")
