"""Autofix data in the EXACT harness label space (10 categories) + real error logs, so training
matches the RealBio autofix metric. Grounded in workflows.real_exec_err; independent-auditor gated."""
import json, os, re, random, sqlite3, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(47); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
CATS=['cloud_storage_error','container_error','data_format_error','dependency_mismatch','genome_mismatch',
 'missing_input','output_assertion_error','param_scope_error','param_type_error','resource_failure']
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
FAIL={"exec_error","timeout","fixture_failed","ran_empty_output","skip_input_type"}
rows=[dict(r) for r in c.execute("select name,domain,description,real_exec_status,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>25")]
rows=[r for r in rows if (r["real_exec_status"] in FAIL) or ("error" in (r["real_exec_err"] or "").lower())]
def _call(p):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":120,"reasoning_effort":"low"}).encode()
    last=None
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception as e: last=e; time.sleep(1.5*(a+1))
    raise last
def gen(r):
    err=(r["real_exec_err"] or "")[:1000]
    p=(f"Classify this real pipeline failure into EXACTLY ONE category from this list and reply with only that token:\n"
       f"{CATS}\nWorkflow: {r['name']}\nERROR LOG:\n{err}")
    try:
        out=_call(p).strip().strip('".,'); cat=next((x for x in CATS if x in out), None)
        if not cat: return None
        return {"workflow":r["name"],"domain":r["domain"],"description":(r["description"] or "")[:200],"error_log":err,"category":cat}
    except Exception: return None
N=int(sys.argv[1]) if len(sys.argv)>1 else 400
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, random.sample(rows,min(N,len(rows)))):
        if e: out.append(e)
import collections
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/autofix_harness_raw.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"GENERATED {len(out)} autofix (harness 10-cat) | dist: {dict(collections.Counter(e['category'] for e in out))}")
