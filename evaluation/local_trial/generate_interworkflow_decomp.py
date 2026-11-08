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

import re
def concise_purpose(w):
    d=(w.get("description") or "").strip()
    if d:
        clause=re.split(r"[.;\n]", d)[0].strip()
        if clause: return clause[:80]
    return f"{w['domain']} analysis"

def gen(_):
    k=random.randint(2,3)
    # mostly a sequential same-domain chain; sometimes parallel cross-domain
    if random.random()<0.6:
        cand=[d for d in bydom if len(bydom[d])>=k]
        if not cand: return None
        dom=random.choice(cand); picks=random.sample(bydom[dom],k); parallel=False
    else:
        cand=[d for d in bydom if bydom[d]]
        if len(cand)<k: return None
        doms=random.sample(cand,k); picks=[random.choice(bydom[d]) for d in doms]; parallel=True
    # committee fix: generate one aligned sub-request PER workflow (from ITS description) so each query
    # branch corresponds to its workflow (was: one blob -> branch<->workflow drift, e.g. phenomis/
    # metabolomics gold for a scRNA-seq branch). sub_task = the real purpose, not generic "{domain} analysis".
    goals="\n".join(f"{i+1}. {(w['description'] or w['name'])[:120]}" for i,w in enumerate(picks))
    raw=_call(f"For EACH of these {k} analysis goals, write a short natural sub-request in a researcher's own "
              f"words (their data + what they want), WITHOUT naming any tool/workflow, faithful to its goal:\n"
              f"{goals}\n\nReply ONLY a JSON list of {k} strings, in the SAME order as the goals.")
    if not raw: return None
    m=re.search(r"\[.*\]", raw, re.S)
    if not m: return None
    try: subreqs=json.loads(m.group(0))
    except: return None
    if not isinstance(subreqs,list) or len(subreqs)!=k or any(not isinstance(s,str) or len(s.strip())<15 for s in subreqs):
        return None                                   # alignment/format guard: must be k faithful branches
    conns=(["", "Separately, ", "Also, "] if parallel else ["First, ", "Then, ", "Finally, "])
    q=" ".join((conns[i] if i<len(conns) else "")+s.strip() for i,s in enumerate(subreqs))
    gold=[]
    for i,w in enumerate(picks):
        deps=[] if parallel else ([i] if i>0 else [])   # sequential chain: order i+1 depends on order i
        gold.append({"sub_task":concise_purpose(w),"workflow":w["name"],"order":i+1,"depends_on":deps})
    return {"messages":[{"role":"user","content":f"{INSTR}\n\nINPUT:\n{q}"},{"role":"assistant","content":json.dumps(gold)}],
            "n_wf":k,"parallel":parallel}

N=int(sys.argv[1]) if len(sys.argv)>1 else 300
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, range(N)):
        if e: out.append(e)
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/interworkflow_decomp_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"INTER-WORKFLOW DECOMP: {len(out)} ex | parallel={sum(e['parallel'] for e in out)}, sequential={sum(1-e['parallel'] for e in out)}")
