import json, re, glob
REPO="/Users/kky/biomate-review"
def norm(s): return re.sub(r"[^a-z0-9 ]"," ",str(s).lower()).strip()
def toks(s): return set(norm(s).split())
def ch3(s): 
    z=norm(s).replace(" ",""); return set(z[i:i+3] for i in range(len(z)-2))
test=[json.loads(l) for l in open(f"{REPO}/evaluation/datasets/public_export/cross_domain_routing/data.jsonl")]
T=[(t["query"], toks(t["query"]), ch3(t["query"]), norm(t["query"])) for t in test]
def max_sim(q):
    qt,qc,qn=toks(q),ch3(q),norm(q); best=0.0; how=""
    for (_,tt,tc,tn) in T:
        if qn and (qn in tn or tn in qn): return 1.0,"substring"
        jt=len(qt&tt)/len(qt|tt) if qt|tt else 0
        jc=len(qc&tc)/len(qc|tc) if qc|tc else 0
        s=max(jt,jc)
        if s>best: best=s; how=f"tokJ={jt:.2f},chrJ={jc:.2f}"
    return best,how
# sources to audit
srcs={
 "gen_merged_pass": f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/audited_pass_merged.jsonl",
 "geo_train": f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/real_studies_labeled.jsonl",
 "protocol_to_workflow": f"{REPO}/evaluation/datasets/protocol_to_workflow",
 "lane_arbitration": f"{REPO}/evaluation/datasets/lane_arbitration",
 "prereq_recovery": f"{REPO}/evaluation/datasets/prereq_recovery",
 "workflow_generation": f"{REPO}/evaluation/datasets/workflow_generation",
}
def load_queries(path):
    qs=[]
    files=[path] if path.endswith(".jsonl") else glob.glob(path+"/*.jsonl")+glob.glob(path+"/*.json")
    for f in files:
        try:
            if f.endswith(".jsonl"): rows=[json.loads(l) for l in open(f) if l.strip()]
            else:
                import json as J; d=J.load(open(f)); rows=d if isinstance(d,list) else (d.get("cases") or d.get("items") or d.get("tasks") or [])
        except Exception: rows=[]
        for r in rows:
            if isinstance(r,dict):
                q=r.get("query") or r.get("user_query") or r.get("intent") or r.get("protocol_text") or r.get("question") or ""
                if q: qs.append(q)
    return qs
print("=== overlap vs RealBio (max query similarity distribution) ===")
for name,path in srcs.items():
    qs=load_queries(path)
    if not qs: print(f"{name}: no queries loaded"); continue
    sims=[max_sim(q)[0] for q in qs]
    hi=sum(1 for s in sims if s>=0.5); vhi=sum(1 for s in sims if s>=0.7); dup=sum(1 for s in sims if s>=0.95)
    print(f"{name}: n={len(qs)} | max-sim>=0.95(dup)={dup} >=0.7={vhi} >=0.5={hi} | median={sorted(sims)[len(sims)//2]:.2f} max={max(sims):.2f}")
