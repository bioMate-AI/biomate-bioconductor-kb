"""Workflow chaining / I-O compatibility task (committee gap #4), grounded in the WKG. Teaches the
model which workflow can validly FOLLOW another based on real data-type flow: positive = a true precede
successor (A.output feeds B.input via a specific type); hard negatives = TYPE-INCOMPATIBLE workflows
(don't consume any of A's outputs). Discriminative/contrastive, fully grounded (no API)."""
import json, os, sys, random, collections
random.seed(84); REPO="/Users/kky/biomate-review"; D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
KG=json.load(open(f"{D}/wkg.json")); WF=KG["workflows"]; PRE=KG["precede"]; ET=KG["edge_types"]
names=list(WF)

INSTR=("You have run workflow '{A}', which produces: {outs}. From the candidates below, choose the "
       "workflow(s) that can CONSUME its output to continue the analysis (input-compatible). Reply with "
       "ONLY the exact compatible name(s), comma-separated.")

def outputs(n): return [t for t in WF[n].get("out",[]) if t]

def gen_one(a):
    succ=PRE.get(a,[])
    if not succ or not outputs(a): return None
    pos=random.choice(succ)
    # hard negatives: workflows that do NOT consume any of A's outputs (type-incompatible)
    a_out=set(WF[a].get("out",[]))
    incompatible=[b for b in random.sample(names, min(60,len(names)))
                  if b!=a and b not in succ and not (a_out & set(WF[b].get("in",[])))]
    if len(incompatible)<3: return None
    negs=random.sample(incompatible,3)
    cands=[pos]+negs; random.shuffle(cands)
    conn=ET.get(f"{a}|{pos}",[])
    prompt=(INSTR.format(A=a, outs=", ".join(outputs(a))) +
            "\n\nCandidates:\n"+"\n".join(f"- {c}" for c in cands))
    return {"messages":[{"role":"user","content":prompt},{"role":"assistant","content":pos}],
            "connecting_type":conn,"hard_negatives":negs,"task":"chaining"}

def main():
    N=int(sys.argv[1]) if len(sys.argv)>1 else 800
    cand_wf=[a for a in PRE if PRE[a] and outputs(a)]
    random.shuffle(cand_wf); out=[]
    for a in cand_wf:
        e=gen_one(a)
        if e: out.append(e)
        if len(out)>=N: break
    open(f"{D}/chaining_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
    print(f"CHAINING/IO-COMPAT: {len(out)} ex (positive=type-compatible successor, 3 type-incompatible negs)")

if __name__=="__main__": raise SystemExit(main())
