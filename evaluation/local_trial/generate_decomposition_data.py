"""Decomposition SFT (T01/T09) — HIERARCHICAL phase->step DAG (not flat-linear).
Grounded in workflows.step_metadata which carries {step, phase} per step. Gold preserves the
phase grouping and models a DAG: within a phase steps chain sequentially; the first step of a phase
depends on the last step of the previous phase (cross-phase edge). Generator writes a realistic
overall-goal query (not naming steps); the phase->step DAG is the gold decomposition.
(Inter-workflow decomposition — chaining independent workflows — is a separate generator fed by
chain_composer patterns; this one covers intra-workflow phase/step structure faithfully.)"""
import sqlite3, json, os, sys, time, random, urllib.request, collections
from concurrent.futures import ThreadPoolExecutor
random.seed(61); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
rows=[]
for r in c.execute("select name,domain,step_metadata from workflows where step_metadata is not null and length(step_metadata)>60"):
    try: s=json.loads(r["step_metadata"])
    except: continue
    steps=[(x.get("step"), x.get("phase") or "Analysis") for x in s if isinstance(x,dict) and x.get("step")]
    if 3<=len(steps)<=12: rows.append((r["name"], r["domain"], steps))

def build_dag(steps):
    """Hierarchical phase->step DAG: {sub_task,phase,order,depends_on}. Each step depends on its true
    immediate predecessor: intra-phase -> previous step; first-of-phase -> last step of the phase that
    just ended (committee-audit fix: old code updated last-of-prev-phase AFTER computing deps -> first
    step of a new phase wrongly got deps=[] and later steps pointed at the wrong phase's step)."""
    gold=[]; prev_order=None; prev_phase=None; last_order_prev_phase=None
    for i,(name,phase) in enumerate(steps):
        order=i+1
        if phase!=prev_phase and prev_phase is not None:
            last_order_prev_phase=prev_order          # close the phase that just ended, BEFORE using it
        if phase!=prev_phase:
            deps=[last_order_prev_phase] if last_order_prev_phase is not None else []
        else:
            deps=[prev_order]                          # intra-phase sequential
        gold.append({"sub_task":name,"phase":phase,"order":order,"depends_on":deps})
        prev_order=order; prev_phase=phase
    return gold

def _call(p):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":300,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None

INSTR=("Decompose this analysis request into an ordered plan of PHASES and STEPS. Reply ONLY a JSON list "
       "of {sub_task, phase, order, depends_on} (depends_on lists prerequisite step orders; steps in the "
       "same phase run in sequence, and a phase begins after the prior phase completes).")

def gen(item):
    name,dom,steps=item
    phases=list(dict.fromkeys(p for _,p in steps))
    q=_call(f"A {dom} analysis has these phases {phases} with steps {[s for s,_ in steps]}. Write ONE realistic "
            f"user request describing the OVERALL goal/data in a researcher's words, WITHOUT listing the "
            f"steps or phases. Reply with only the request.")
    if not q or len(q)<20: return None
    gold=build_dag(steps)
    return {"messages":[{"role":"user","content":f"{INSTR}\n\nINPUT:\n{q}"},
                        {"role":"assistant","content":json.dumps(gold)}],"workflow":name,"n_phases":len(phases)}

N=int(sys.argv[1]) if len(sys.argv)>1 else 400
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, random.sample(rows,min(N,len(rows)))):
        if e: out.append(e)
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/decomposition_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"DECOMPOSITION (phase->step DAG): {len(out)} ex | phase-count dist: {dict(collections.Counter(e['n_phases'] for e in out))}")
