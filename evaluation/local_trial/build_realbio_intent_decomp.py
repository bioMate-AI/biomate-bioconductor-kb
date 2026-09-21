"""Build two new RealBio benchmark tasks:
  1) intent_interpretation — classify a request into BioMate's capability intent (label-constrained).
  2) task_decomposition — decompose a multi-part request into a subtask DAG; scored on subtask coverage
     AND parallel/sequential STRUCTURE correctness (balanced parallel/sequential/mixed, grounded in WKG).
Emits data.jsonl into evaluation/datasets/public_export/{intent_interpretation,task_decomposition}/.
Structure/ground-truth is deterministic (we construct the DAG); the LLM only writes the natural query."""
import sqlite3, json, os, re, sys, time, random, urllib.request, collections
from concurrent.futures import ThreadPoolExecutor
random.seed(1234); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
PUB=f"{REPO}/evaluation/datasets/public_export"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
wf=[dict(r) for r in c.execute("select name,domain,description from workflows where description is not null and length(description)>40")]
bydom=collections.defaultdict(list)
for w in wf: bydom[w["domain"] or "general"].append(w)

# BioMate capability intent taxonomy (mapped to the MCP tool surface)
INTENTS={
 "route_and_run_workflow":"pick and run the right bioinformatics workflow for an analysis",
 "extract_parameters":"specify/override parameters for a workflow run",
 "decompose_multi_step":"a multi-goal request needing several workflows/steps planned",
 "fetch_public_data":"download/fetch a public dataset or accession",
 "resolve_accession":"identify/resolve a specific accession or ID (GEO/SRA/PDB/UniProt...)",
 "analyze_results":"interpret/summarize results or outputs of a completed run",
 "explain_error":"diagnose why a run failed / what an error means",
 "search_literature":"find papers/methods/references",
 "get_workflow_spec":"ask what a workflow does / its inputs-outputs/steps",
 "run_instrument_protocol":"run or configure an instrument protocol / QC",
 "browse_or_preview_data":"browse, preview, or inspect a file/dataset",
 "export_report":"generate/download a report or compliance package",
}

def _call(p, mx=500):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":mx,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",
              data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None

# ---------- intent_interpretation ----------
def gen_intent(args):
    label,desc,i=args
    q=_call(f"Write ONE realistic BioMate user request whose intent is: {desc}. A researcher's own words, "
            f"specific (mention real data/analysis where natural), do NOT name the intent. Reply only the request.")
    if not q or len(q)<15: return None
    return {"id":f"intent_{label}_{i}","query":q.strip(),"intent":label}

# ---------- task_decomposition (balanced structure) ----------
INSTR_DECOMP=("Decompose this request into an ordered plan of sub-tasks. Reply ONLY a JSON list of "
              "{\"sub_task\": ..., \"order\": N, \"depends_on\": [prerequisite orders]} — independent "
              "sub-tasks have empty depends_on (they can run in parallel).")
def compound_query(picks, structure):
    goals="; ".join(f"({i+1}) {w['domain']}: {(w['description'] or '')[:80]}" for i,w in enumerate(picks))
    hint={"parallel":"these are INDEPENDENT goals on possibly different data",
          "sequential":"each goal uses the OUTPUT of the previous one",
          "mixed":"some goals are independent and some depend on earlier ones"}[structure]
    q=_call(f"A researcher wants to accomplish these goals ({hint}): {goals}. Write ONE natural compound "
            f"request describing their data and ALL goals in their own words, WITHOUT naming any workflow. Reply only the request.")
    return q
def gen_decomp(args):
    structure,i=args; k=random.randint(2,4)
    if structure=="parallel":
        doms=random.sample([d for d in bydom if bydom[d]],min(k,len(bydom))); picks=[random.choice(bydom[d]) for d in doms]
        gold=[{"sub_task":f"{w['domain']} analysis","order":j+1,"depends_on":[]} for j,w in enumerate(picks)]
    elif structure=="sequential":
        dom=random.choice([d for d in bydom if len(bydom[d])>=k]); picks=random.sample(bydom[dom],k)
        gold=[{"sub_task":f"{w['domain']} step","order":j+1,"depends_on":([j] if j>0 else [])} for j,w in enumerate(picks)]
    else:  # mixed: two independent branches, each internally sequential
        doms=random.sample([d for d in bydom if len(bydom[d])>=2],2); picks=[]; gold=[]; o=0
        for d in doms:
            a,b=random.sample(bydom[d],2); picks+=[a,b]
            gold.append({"sub_task":f"{d} prep","order":o+1,"depends_on":[]})
            gold.append({"sub_task":f"{d} analysis","order":o+2,"depends_on":[o+1]}); o+=2
    q=compound_query(picks,structure)
    if not q or len(q)<25: return None
    return {"id":f"decomp_{structure}_{i}","query":q.strip(),"structure":structure,"gold_subtasks":gold,"instr":INSTR_DECOMP}

def main():
    N_INT=int(sys.argv[1]) if len(sys.argv)>1 else 12    # per intent label
    N_DEC=int(sys.argv[2]) if len(sys.argv)>2 else 45    # per structure
    # intent
    tasks=[(lab,desc,i) for lab,desc in INTENTS.items() for i in range(N_INT)]
    intent=[];
    with ThreadPoolExecutor(max_workers=12) as ex:
        for e in ex.map(gen_intent, tasks):
            if e: intent.append(e)
    os.makedirs(f"{PUB}/intent_interpretation",exist_ok=True)
    open(f"{PUB}/intent_interpretation/data.jsonl","w").write("\n".join(json.dumps(e) for e in intent))
    print(f"intent_interpretation: {len(intent)} across {len(INTENTS)} labels")
    # decomposition (balanced)
    dtasks=[(s,i) for s in ("parallel","sequential","mixed") for i in range(N_DEC)]
    dec=[]
    with ThreadPoolExecutor(max_workers=12) as ex:
        for e in ex.map(gen_decomp, dtasks):
            if e: dec.append(e)
    os.makedirs(f"{PUB}/task_decomposition",exist_ok=True)
    open(f"{PUB}/task_decomposition/data.jsonl","w").write("\n".join(json.dumps(e) for e in dec))
    print(f"task_decomposition: {len(dec)} | structures={dict(collections.Counter(d['structure'] for d in dec))}")

if __name__=="__main__": raise SystemExit(main())
