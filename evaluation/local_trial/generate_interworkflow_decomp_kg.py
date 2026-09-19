"""KG-grounded inter-workflow decomposition — replaces random-domain synthesis (which caused the
phenomis/scRNA-seq mislabel). Chains are grounded in the Workflow Knowledge Graph:
  (A) the 70 CURATED chains (real steps + data-flow connections + real example_queries) -> gold DAG
      whose deps come from the actual connections; highest precision.
  (B) TYPE-COMPATIBLE synthetic chains walked over the precede graph (A->B iff A.output feeds B.input
      via a specific type) -> valid-by-construction; per-workflow aligned sub-requests for the query.
Both give correct data-flow dependencies, unlike random domain sampling."""
import json, os, sys, re, random, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(83); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"; KG=json.load(open(f"{D}/wkg.json"))
WF=KG["workflows"]; PRE=KG["precede"]; CHAINS=KG["curated_chains"]
INSTR=("Decompose this multi-part request into an ordered plan of WORKFLOWS. Reply ONLY a JSON list of "
       "{sub_task, workflow, order, depends_on} (depends_on lists prerequisite orders; independent parts "
       "may run in parallel with empty depends_on).")

def _call(p, mx=700):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":mx,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",
              data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None
def purpose(n):
    d=(WF.get(n,{}).get("desc") or "").strip()
    c=re.split(r"[.;\n]", d)[0].strip() if d else ""
    return c[:80] or f"{WF.get(n,{}).get('domain','')} analysis"

def from_curated(ch):
    steps=sorted(ch["steps"], key=lambda s:s.get("order",0))
    order_of={s.get("order"):i+1 for i,s in enumerate(steps)}
    deps={}
    for cn in ch.get("connections",[]):
        fr,to=cn.get("from_step"),cn.get("to_step")
        if fr in order_of and to in order_of: deps.setdefault(order_of[to],set()).add(order_of[fr])
    gold=[]
    for i,s in enumerate(steps):
        o=i+1; wn=s.get("workflow_name","?")
        gold.append({"sub_task":s.get("role") or purpose(wn),"workflow":wn,"order":o,
                     "depends_on":sorted(deps.get(o,[]))})
    out=[]
    for q in (ch.get("example_queries") or [])[:3]:
        if q and len(q)>15:
            out.append({"messages":[{"role":"user","content":f"{INSTR}\n\nINPUT:\n{q}"},
                        {"role":"assistant","content":json.dumps(gold)}],"n_wf":len(steps),"source":"curated_chain"})
    return out

def walk_chain(k):
    starts=[a for a in PRE if PRE[a]]
    if not starts: return None
    a=random.choice(starts); chain=[a]
    for _ in range(k-1):
        nxts=[b for b in PRE.get(chain[-1],[]) if b not in chain]
        if not nxts: break
        chain.append(random.choice(nxts))
    return chain if len(chain)>=2 else None

def from_synthetic(_):
    k=random.randint(2,3); chain=walk_chain(k)
    if not chain: return None
    goals="\n".join(f"{i+1}. {(WF[n].get('desc') or n)[:120]}" for i,n in enumerate(chain))
    raw=_call(f"For EACH of these {len(chain)} sequential analysis steps, write a short natural sub-request "
              f"in a researcher's own words (data + goal), WITHOUT naming any tool, faithful to its step:\n"
              f"{goals}\n\nReply ONLY a JSON list of {len(chain)} strings, SAME order.")
    if not raw: return None
    m=re.search(r"\[.*\]", raw, re.S)
    if not m: return None
    try: subs=json.loads(m.group(0))
    except: return None
    if not isinstance(subs,list) or len(subs)!=len(chain) or any(not isinstance(s,str) or len(s.strip())<15 for s in subs):
        return None
    conns=["First, ","Then, ","Finally, "]
    q=" ".join((conns[i] if i<len(conns) else "")+s.strip() for i,s in enumerate(subs))
    gold=[{"sub_task":purpose(n),"workflow":n,"order":i+1,"depends_on":([i] if i>0 else [])}
          for i,n in enumerate(chain)]   # sequential type-flow chain
    return {"messages":[{"role":"user","content":f"{INSTR}\n\nINPUT:\n{q}"},
            {"role":"assistant","content":json.dumps(gold)}],"n_wf":len(chain),"source":"type_compatible"}

def main():
    N=int(sys.argv[1]) if len(sys.argv)>1 else 300
    out=[]
    for ch in CHAINS: out.extend(from_curated(ch))    # high-precision curated (no API)
    with ThreadPoolExecutor(max_workers=10) as ex:    # type-compatible synthetic (API)
        for e in ex.map(from_synthetic, range(N)):
            if e: out.append(e)
    open(f"{D}/interworkflow_decomp_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
    import collections
    print(f"INTER-WF DECOMP (KG-grounded): {len(out)} | sources={dict(collections.Counter(e['source'] for e in out))}")

if __name__=="__main__": raise SystemExit(main())
