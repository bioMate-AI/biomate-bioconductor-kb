"""Turn real GEO study->pipeline labels into routing episodes.
Corrected design: workflow LABELS may overlap the RealBio test (that's correct for
routing); we split by QUERY and drop any train query near-duplicate to a test query.
Candidates = correct + distractors from the full workflow-name pool (correct always in)."""
import json, re, sqlite3, random
random.seed(23)
REPO="/Users/kky/biomate-review"
D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
def toks(s): return set(re.sub(r"[^a-z0-9 ]"," ",str(s).lower()).split())
# test queries (to dedup against) + candidate pool
test=[json.loads(l) for l in open(f"{REPO}/evaluation/datasets/public_export/cross_domain_routing/data.jsonl")]
test_tok=[toks(t["query"]) for t in test]
def near_dup(q):
    qt=toks(q)
    for tt in test_tok:
        if not qt or not tt: continue
        j=len(qt&tt)/len(qt|tt)
        if j>0.6: return True
    return False
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True)
pool=[r[0] for r in c.execute("select name from workflows where name is not null")]
real=[json.loads(l) for l in open(f"{D}/real_studies_labeled.jsonl") if l.strip()]
random.shuffle(real)
labels=sorted(set(e["correct_workflow"] for e in real))
def cands(correct):
    distract=random.sample([n for n in pool if n!=correct], 6)+random.sample([l for l in labels if l!=correct], min(3,len(labels)-1))
    cs=list(dict.fromkeys([correct]+distract))[:9]; random.shuffle(cs)
    if correct not in cs: cs[0]=correct
    return cs
eps=[]; dropped=0
for e in real:
    if near_dup(e["query"]): dropped+=1; continue
    eps.append({"query":e["query"],"correct_workflow":e["correct_workflow"],"candidates":cands(e["correct_workflow"]),"source":"geo:"+e.get("geo_uid","")})
random.shuffle(eps)
n=len(eps); dv=int(n*0.15)
for i,e in enumerate(eps): e["split"]="dev" if i<dv else "train"
from collections import Counter
open(f"{D}/routing_episodes.jsonl","w").write("\n".join(json.dumps(e) for e in eps))
print("real routing episodes:",len(eps),"| dropped near-dup-to-test:",dropped)
print("splits:",dict(Counter(e["split"] for e in eps)))
print("label coverage:",dict(Counter(e["correct_workflow"] for e in eps)))
