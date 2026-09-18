"""Inter-workflow decomposition SFT: cross-domain / multi-goal user queries -> an ordered DAG of
DISTINCT WORKFLOWS (not intra-workflow steps). Fills the committee-flagged gap: real queries like
"run scRNA-seq QC, then trajectory analysis, and correlate with this ATAC-seq" chain independent
workflows. Ground: sample 2-3 real workflows; generate a compound query; gold = workflow-level DAG."""
import sqlite3, json, os, sys, time, random, urllib.request, collections
from concurrent.futures import ThreadPoolExecutor
random.seed(83); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
wf=[dict(r) for r in c.execute("select name,domain,description from workflows where description is not null and length(description)>40")]
bydom=collections.defaultdict(list)
for w in wf: bydom[w["domain"] or "general"].append(w)

def _call(p):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":800,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None

INSTR=("Decompose this multi-part request into an ordered plan of WORKFLOWS. Reply ONLY a JSON list of "
       "{sub_task, workflow, order, depends_on} (depends_on lists prerequisite orders; independent parts "
       "may run in parallel with empty depends_on).")

def gen(_):
    k=random.randint(2,3)
    # mostly a sequential same-domain chain; sometimes parallel cross-domain
    if random.random()<0.6:
        dom=random.choice([d for d in bydom if len(bydom[d])>=k]); picks=random.sample(bydom[dom],k); parallel=False
    else:
        doms=random.sample([d for d in bydom if bydom[d]],k); picks=[random.choice(bydom[d]) for d in doms]; parallel=True
    descs="; ".join(f"({i+1}) {w['name']}: {(w['description'] or '')[:90]}" for i,w in enumerate(picks))
    q=_call(f"A researcher wants to accomplish these {k} analysis goals: {descs}. Write ONE realistic compound "
            f"request describing their data and ALL {k} goals in their own words, WITHOUT naming the workflows. "
            f"Reply with only the request.")
    if not q or len(q)<25: return None
    gold=[]
    for i,w in enumerate(picks):
        deps=[] if parallel else ([i] if i>0 else [])
        gold.append({"sub_task":f"{w['domain']} analysis","workflow":w["name"],"order":i+1,"depends_on":deps})
    return {"messages":[{"role":"user","content":f"{INSTR}\n\nINPUT:\n{q}"},{"role":"assistant","content":json.dumps(gold)}],
            "n_wf":k,"parallel":parallel}

N=int(sys.argv[1]) if len(sys.argv)>1 else 300
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, range(N)):
        if e: out.append(e)
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/interworkflow_decomp_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"INTER-WORKFLOW DECOMP: {len(out)} ex | parallel={sum(e['parallel'] for e in out)}, sequential={sum(1-e['parallel'] for e in out)}")
