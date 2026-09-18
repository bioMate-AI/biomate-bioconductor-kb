"""Decomposition SFT (T01/T09): user request -> ordered sub-task DAG. Grounded in workflows.step_metadata
(the real ordered steps ARE the gold decomposition). Generator writes a realistic overall-goal query
(not naming steps); gold = ordered sub-tasks with deps. Harness-format completion = JSON list."""
import sqlite3,json,os,re,random,sys,time,urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(61); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
rows=[]
for r in c.execute("select name,domain,step_metadata from workflows where step_metadata is not null and length(step_metadata)>60"):
    try: s=json.loads(r["step_metadata"])
    except: continue
    steps=[x.get("step") for x in s if isinstance(x,dict) and x.get("step")]
    if 3<=len(steps)<=10: rows.append((r["name"],r["domain"],steps))
def _call(p):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":300,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None
INSTR="Decompose this analysis request into ordered sub-tasks. Reply ONLY a JSON list of {sub_task, order, depends_on}."
def gen(item):
    name,dom,steps=item
    q=_call(f"A {dom} analysis performs these steps in order: {steps}. Write ONE realistic user request describing the OVERALL goal/data in a researcher's words, WITHOUT listing the steps. Reply with only the request.")
    if not q or len(q)<20: return None
    gold=[{"sub_task":s,"order":i+1,"depends_on":([i] if i>0 else [])} for i,s in enumerate(steps)]
    prompt=f"{INSTR}\n\nINPUT:\n{q}"
    return {"messages":[{"role":"user","content":prompt},{"role":"assistant","content":json.dumps(gold)}],"workflow":name}
N=int(sys.argv[1]) if len(sys.argv)>1 else 400
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, random.sample(rows,min(N,len(rows)))):
        if e: out.append(e)
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/decomposition_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"DECOMPOSITION: {len(out)} examples (grounded in step_metadata)")
