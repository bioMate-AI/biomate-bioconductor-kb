"""MULTI-INTENT generator: produces intent-classification training items across BioMate's
non-workflow intent categories, grounded in REAL DB sources. Emits {query, intent[, ...]}.
Auditor (audit_intent_data.py) checks realistic + correct intent label."""
import json, os, re, random, sqlite3, urllib.request, sys
from concurrent.futures import ThreadPoolExecutor
random.seed(41); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
# grounding pools
errs=[dict(r) for r in c.execute("select name,domain,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>30 limit 400")]
tools=[dict(r) for r in c.execute("select name,category,description,scientific_context from tools where scientific_context is not null and length(scientific_context)>60 limit 1500")]
LIVE_DBS=["GWAS Catalog","OMIM","Open Targets","ClinVar","Ensembl","mygene.info","Monarch"]
def call(prompt):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":500,"reasoning_effort":"low"}).encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
        return d["choices"][0]["message"]["content"].strip().strip('"')
    except Exception: return None
def gen_trouble(r):
    q=call(f"Write ONE realistic user message asking for help with a FAILED bioinformatics run, grounded in this real error. Describe symptoms in the user's words; do not just paste the error verbatim. Domain: {r['domain']}. Error: {(r['real_exec_err'] or '')[:300]}. Reply with only the message.")
    return {"query":q,"intent":"troubleshooting","grounding":r["name"]} if q and len(q)>20 else None
def gen_dblookup(_):
    db=random.choice(LIVE_DBS)
    q=call(f"Write ONE realistic user question that requires a LIVE lookup in {db} (a specific gene/variant/disease association or record) — the kind that needs real-time database access, not a workflow. Reply with only the question.")
    return {"query":q,"intent":"database_lookup","grounding":db} if q and len(q)>15 else None
def gen_teach(r):
    q=call(f"Write ONE realistic user question asking to EXPLAIN a concept/method (teaching, no data to run), related to the tool '{r['name']}' ({r['category']}). Reply with only the question.")
    return {"query":q,"intent":"teaching_explanation","grounding":r["name"]} if q and len(q)>15 else None
def gen_general(r):
    q=call(f"Write ONE short general question a user might ask BioMate (capabilities, definitions, quick facts) loosely related to {r['category']}. Reply with only the question.")
    return {"query":q,"intent":"general_question","grounding":r["category"]} if q and len(q)>12 else None
def gen_expdesign(r):
    q=call(f"Write ONE realistic user request asking for help DESIGNING an experiment/study (not running a pipeline) in the area of {r['category']}. Reply with only the request.")
    return {"query":q,"intent":"experiment_design","grounding":r["category"]} if q and len(q)>20 else None
N=int(sys.argv[1]) if len(sys.argv)>1 else 40
jobs=[]
for r in random.sample(errs,min(N,len(errs))): jobs.append((gen_trouble,r))
for _ in range(N): jobs.append((gen_dblookup,None))
for r in random.sample(tools,min(N,len(tools))): jobs.append((gen_teach,r))
for r in random.sample(tools,min(N,len(tools))): jobs.append((gen_general,r))
for r in random.sample(tools,min(N,len(tools))): jobs.append((gen_expdesign,r))
out=[]
with ThreadPoolExecutor(max_workers=12) as ex:
    for e in ex.map(lambda jr: jr[0](jr[1]), jobs):
        if e: out.append(e)
from collections import Counter
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/generated_intent_raw.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print("GENERATED",len(out),"multi-intent items:",dict(Counter(e["intent"] for e in out)))
