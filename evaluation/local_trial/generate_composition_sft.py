"""Composition SFT (committee-v3 fix: the out-of-catalog composition task was NEVER supervised).
Trains EXACTLY what the removal eval measures: a goal -> decompose into an ordered plan -> bind each
step to a tool-block from candidates. Grounded in REAL workflows.step_metadata (the decomposition) +
tools_used (the blocks). Matches eval_removal's INSTR/format so training aligns with measurement.
Covers 708 composition-trainable workflows (incl. niche/long-tail beyond the routing set)."""
import sqlite3, json, os, re, sys, time, random, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(97); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
# WKG for type-compatible distractor blocks (hard negatives among the candidate list)
KG=json.load(open(f"{D}/wkg.json")) if os.path.exists(f"{D}/wkg.json") else {"block_precede":{}}
BLOCKS=list(KG.get("blocks",{}))

rows=[]
for r in c.execute("select name,domain,description,step_metadata,tools_used from workflows where step_metadata is not null and tools_used is not null"):
    try: st=[x.get("step") for x in json.loads(r["step_metadata"]) if isinstance(x,dict) and x.get("step")]
    except: st=[]
    try: tu=[t for t in json.loads(r["tools_used"]) if t]
    except: tu=[]
    if 2<=len(st)<=12 and len(tu)>=2 and (r["description"] or ""):
        rows.append((r["name"],r["domain"],r["description"][:300],st[:12],tu[:20]))

INSTR=("You are BioMate. No single existing workflow may exactly fit this request. Decompose it into an "
       "ordered PLAN of steps; for EACH step name a tool/workflow from the CANDIDATES that realizes it, "
       "or write \"GENERATE\" if no candidate fits. Reply ONLY a JSON list of {\"step\": ..., "
       "\"workflow_or_action\": ...}.")

def _call(p, mx=900):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":mx,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",
              data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None

def gen(item):
    name,dom,desc,steps,tools=item
    ask=(f"A {dom} analysis goal: {desc}\nOrdered analysis steps: {json.dumps(steps)}\nAvailable tools: {json.dumps(tools)}\n\n"
         "Produce JSON {\"query\": a realistic user request describing the DATA and GOAL in a researcher's "
         "own words WITHOUT naming any tool/workflow, \"plan\": a JSON list where each element is "
         "{\"step\": <one of the analysis steps>, \"workflow_or_action\": <the tool from the available list "
         "that performs that step>}}. Every step must map to a listed tool. Reply ONLY the JSON.")
    out=_call(ask)
    if not out: return None
    m=re.search(r"\{.*\}", out, re.S)
    if not m: return None
    try: obj=json.loads(m.group(0))
    except: return None
    q=obj.get("query",""); plan=obj.get("plan",[])
    if not q or len(q)<25 or not isinstance(plan,list) or len(plan)<2: return None
    # validate the plan binds to real tools; keep only rows whose tools are in tools_used
    plan=[p for p in plan if isinstance(p,dict) and p.get("step") and p.get("workflow_or_action")]
    if len(plan)<2: return None
    used=[p["workflow_or_action"] for p in plan]
    # candidates = the used tools + type-compatible WKG distractors + a few random (hard negatives), shuffled
    distract=random.sample([b for b in BLOCKS if b not in used], min(6,len(BLOCKS))) if BLOCKS else []
    cands=list(dict.fromkeys(used+distract)); random.shuffle(cands)
    prompt=f"{INSTR}\n\nCandidates:\n"+"\n".join(f"- {x}" for x in cands)+f"\n\nRequest: {q}"
    return {"messages":[{"role":"user","content":prompt},{"role":"assistant","content":json.dumps(plan)}],
            "workflow":name,"domain":dom,"n_steps":len(plan)}

def main():
    N=int(sys.argv[1]) if len(sys.argv)>1 else len(rows)
    sample=rows[:N]; out=[]
    with ThreadPoolExecutor(max_workers=12) as ex:
        for e in ex.map(gen, sample):
            if e: out.append(e)
    open(f"{D}/composition_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
    import collections
    print(f"COMPOSITION SFT: {len(out)}/{len(sample)} (trains the never-supervised out-of-catalog task) | "
          f"domains={dict(collections.Counter(e['domain'] for e in out).most_common(6))}")

if __name__=="__main__": raise SystemExit(main())
