"""Execution-trace diagnosis+fix SFT (committee gap): real error logs -> full {category, root_cause,
fix} trajectory, grounded in workflows.real_exec_err + workflow context. Richer than autofix
(category-only). Feeds diagnosis SFT + is the reward signal source for grounded RL."""
import sqlite3, json, os, re, sys, time, random, urllib.request, collections
from concurrent.futures import ThreadPoolExecutor
random.seed(103); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
CATS=['cloud_storage_error','container_error','data_format_error','dependency_mismatch','genome_mismatch',
 'missing_input','output_assertion_error','param_scope_error','param_type_error','resource_failure']
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
FAIL={"exec_error","timeout","fixture_failed","ran_empty_output","skip_input_type"}
rows=[dict(r) for r in c.execute("select name,domain,description,real_exec_status,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>40")]
def informative(log):
    low=(log or "").lower()
    return len(log)>=40 and any(k in low for k in ["error","not found","failed","no such","missing","cannot","exception","fatal","traceback","undefined","unable","invalid","denied","exceeded"])
rows=[r for r in rows if (r["real_exec_status"] in FAIL or "error" in (r["real_exec_err"] or "").lower()) and informative(r["real_exec_err"])]
INSTR=("You are BioMate. A workflow run failed. From the error log, produce a diagnosis as JSON "
       f'{{"category": one of {CATS}, "root_cause": grounded in the log, "fix": a concrete corrective action}}.')
def _call(p):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":700,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None
def gen(r):
    err=(r["real_exec_err"] or "")[:1000]; desc=(r.get("description") or "")[:150]
    out=_call(f"Workflow '{r['name']}' ({r['domain']}): {desc}\nERROR LOG:\n{err}\n\n{INSTR} Reply ONLY the JSON.")
    if not out: return None
    m=re.search(r"\{.*\}", out, re.S)
    if not m: return None
    try: v=json.loads(m.group(0))
    except: return None
    if v.get("category") not in CATS or len(str(v.get("root_cause","")))<10 or len(str(v.get("fix","")))<10: return None
    prompt=f"{INSTR}\n\nWorkflow: {r['name']}\nERROR LOG:\n{err}"
    return {"messages":[{"role":"user","content":prompt},{"role":"assistant","content":json.dumps({k:v[k] for k in ('category','root_cause','fix')})}],"category":v["category"]}
N=int(sys.argv[1]) if len(sys.argv)>1 else 500
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, random.sample(rows,min(N,len(rows)))):
        if e: out.append(e)
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/diagnosis_fix_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"DIAGNOSIS+FIX: {len(out)} ex | cats: {dict(collections.Counter(e['category'] for e in out))}")
