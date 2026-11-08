"""Verbalize workflow BIOLOGICAL ORDER + steps into natural-language procedures for mid-training.
Source: workflows.step_metadata (ordered [{step,phase,outputs,params,qc,visualizations}]) +
tools_used + input/output types. Captures: step order, phases, per-step outputs & params, tool set,
data types. Emits {text,source,id}. (tool_compatibility is degenerate -> not used.)"""
import sqlite3, json, os, hashlib
REPO="/Users/kky/biomate-review"; OUT=f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus"
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
seen=set(); n=0
def clip(x,nn): return (str(x)[:nn] if x else "")
with open(f"{OUT}/workflow_order_corpus.jsonl","w") as f:
    for r in c.execute("select name,domain,step_metadata,tools_used,input_types,output_types from workflows where step_metadata is not null and length(step_metadata)>40"):
        d=dict(r)
        try: steps=json.loads(d["step_metadata"])
        except Exception: continue
        if not isinstance(steps,list) or not steps: continue
        lines=[f"# Workflow procedure: {d['name']} (domain: {d.get('domain')})",
               f"This workflow runs {len(steps)} steps in the following biological order:"]
        for i,s in enumerate(steps,1):
            if not isinstance(s,dict): continue
            seg=f"{i}. "
            if s.get("phase"): seg+=f"[{s['phase']}] "
            seg+=str(s.get("step",""))[:120]
            outs=s.get("outputs") or []
            if outs: seg+=" — produces "+", ".join(str(o.get('file',o) if isinstance(o,dict) else o) for o in outs[:4])[:150]
            prm=s.get("params") or []
            if prm: seg+=" — key params: "+", ".join(p.get("name","") for p in prm[:6] if isinstance(p,dict))[:120]
            lines.append(seg)
        if d.get("tools_used"): lines.append("Tools used: "+clip(d["tools_used"],400))
        io=[]
        if d.get("input_types"): io.append("Inputs: "+clip(d["input_types"],200))
        if d.get("output_types"): io.append("Outputs: "+clip(d["output_types"],200))
        if io: lines.append(" | ".join(io))
        text="\n".join(lines)
        if len(text)<120: continue
        h=hashlib.sha256(text.encode()).hexdigest()[:16]
        if h in seen: continue
        seen.add(h); f.write(json.dumps({"text":text[:6000],"source":"workflow_order","id":d["name"]})+"\n"); n+=1
chars=sum(len(json.loads(l)['text']) for l in open(f"{OUT}/workflow_order_corpus.jsonl"))
print(f"workflow_order corpus: {n} ordered procedures, ~{chars//4/1e6:.1f}M tokens")
