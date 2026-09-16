"""GENERATOR (T18 diagnosis): ground in REAL workflow error logs (workflows.real_exec_err).
Generator classifies the real error -> {category, root_cause, fix}; auditor verifies faithfulness."""
import json, os, re, random, sqlite3, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(__file__)); from diag_prompt import TAXONOMY
random.seed(43); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
FAIL={"exec_error","timeout","fixture_failed","ran_empty_output","skip_input_type"}
rows=[dict(r) for r in c.execute("select name,domain,real_exec_status,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>25")]
rows=[r for r in rows if (r["real_exec_status"] in FAIL) or ("error" in (r["real_exec_err"] or "").lower())]
def _call(prompt):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":400,"reasoning_effort":"low"}).encode()
    last=None
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=90))
            return d["choices"][0]["message"]["content"].strip()
        except Exception as e: last=e; time.sleep(1.5*(a+1))
    raise last
def gen(r):
    err=(r["real_exec_err"] or "")[:1000]
    prompt=(f"A run of workflow '{r['name']}' (domain {r['domain']}) failed. Classify the failure into exactly "
            f"one category from {TAXONOMY}, give the root cause grounded ONLY in this log, and a concrete fix. "
            f'Reply ONLY JSON {{"category","root_cause","fix"}}.\nERROR LOG:\n{err}')
    try:
        m=re.search(r"\{.*\}", _call(prompt), re.S)
        if not m: return None
        v=json.loads(m.group(0))
        if v.get("category") not in TAXONOMY: return None
        return {"workflow":r["name"],"domain":r["domain"],"status":r["real_exec_status"],"error_log":err,
                "category":v["category"],"root_cause":v.get("root_cause",""),"fix":v.get("fix","")}
    except Exception: return None
N=int(sys.argv[1]) if len(sys.argv)>1 else 300
sample=random.sample(rows,min(N,len(rows)))
out=[]
with ThreadPoolExecutor(max_workers=12) as ex:
    for e in ex.map(gen, sample):
        if e: out.append(e)
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/diag_generated_raw.jsonl","w").write("\n".join(json.dumps(e) for e in out))
import collections
print(f"GENERATED {len(out)} diag episodes | categories: {dict(collections.Counter(e['category'] for e in out))}")
