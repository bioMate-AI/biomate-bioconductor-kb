#!/usr/bin/env python3
"""FREE deterministic independence test: run BioMate's production rule layer + the semantic scorer on the
held-out param items (never seen during tuning) and report per-probe-class whether the post-hoc fixes
GENERALIZE. No LLM. (Routing held-out needs an LLM bare-vs-harness run — billable, separate.)"""
import ast, json, re, logging, os
from collections import defaultdict
HERE=os.path.dirname(os.path.abspath(__file__)); REPO=os.path.normpath(os.path.join(HERE,"..","..","..",".."))
SRC=os.path.join(REPO,"backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py")
src=open(SRC).read();tree=ast.parse(src)
segs=[ast.get_source_segment(src,n) for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in {"_rule_based_param_inference","_validate_extracted_params"}]
ns={"re":re,"json":json,"log":logging.getLogger("s"),"logging":logging}
exec("from __future__ import annotations\nfrom typing import Dict,List,Any,Optional\n"+"\n\n".join(segs),ns)
rbpi=ns["_rule_based_param_inference"];val=ns["_validate_extracted_params"]
def norm(s): return re.sub(r"\s+"," ",str(s).strip().lower())
GEN={"hg38":"grch38","hg19":"grch37","grch37":"grch37","grch38":"grch38","mm39":"grcm39","grcm39":"grcm39","mm10":"grcm38","grcm38":"grcm38","rnor6.0":"rnor_6.0","rnor_6.0":"rnor_6.0","sscrofa11.1":"sscrofa11.1","grcg7b":"grcg7b"}
BT={"true","yes","on","enabled","1"};BF={"false","no","off","disabled","0"}
def veq(g,p):
    g,p=norm(g),norm(p)
    if g==p or GEN.get(g.replace(" ",""),g)==GEN.get(p.replace(" ",""),p):return True
    if (g in BT and p in BT) or (g in BF and p in BF):return True
    return False
rows=[json.loads(l) for l in open(os.path.join(HERE,"param_heldout.jsonl")) if l.strip()]
by=defaultdict(lambda:[0,0]); viol=0; boundary=[]
for r in rows:
    cls=r["probes"].split(":")[0]
    ap=[{"name":k} for k in (set(r["expected_params"])|set(r["must_not_fill"]))]
    try: got=val(rbpi(r["user_query"],ap),ap) or {}
    except Exception: got={}
    for k,v in (r["expected_params"] or {}).items():
        ok = k in got and veq(v,got[k])
        by[cls][1]+=1; by[cls][0]+=ok
        if cls=="boundary" and not ok: boundary.append((r["id"],v,got.get(k,"(abstained)")))
    for k in r["must_not_fill"]:
        if k in got: viol+=1
print("RULE-LAYER + SCORER on HELD-OUT items (deterministic, no LLM):")
for cls,(h,n) in sorted(by.items()):
    print(f"  {cls:10s}: {h}/{n} expected params filled correctly")
print(f"  must_not_fill violations across all held-out: {viol}")
tot_h=sum(v[0] for k,v in by.items() if k!='boundary'); tot_n=sum(v[1] for k,v in by.items() if k!='boundary')
print(f"\n  GENERALIZATION (covered classes, excl. honest-boundary): {tot_h}/{tot_n} = {tot_h/tot_n:.0%}")
print(f"  honest-boundary (uncovered organisms) outcomes: {boundary}  (abstain = rule correctly did NOT hallucinate)")
