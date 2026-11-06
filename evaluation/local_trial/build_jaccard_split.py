"""Fix 3 (committee data audit): defensible train/eval split. Cluster the 4,200 workflows by tool-set
Jaccard (union-find over candidate pairs sharing >=1 tool, merge if Jaccard>=0.5), then assign WHOLE
clusters to train/eval (~15% eval). Prevents prefix-hash leakage (modular pipelines sharing 80% DAG
across different prefixes). Emits workflow->{cluster,split}. Deterministic, no API.
"""
import json, os, sqlite3, re
from collections import defaultdict
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
OUT = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def toolset(s):
    if not s: return set()
    try:
        v = json.loads(s)
        if isinstance(v, list): return set(str(x).lower().strip() for x in v if x)
    except Exception: pass
    return set(t.lower().strip() for t in re.split(r"[,;|\s]+", str(s)) if len(t) > 1)


wf = {}
for r in c.execute("select name,domain,tools_used from workflows where name is not null"):
    wf[r["name"]] = {"tools": toolset(r["tools_used"]), "domain": r["domain"]}

# union-find
parent = {n: n for n in wf}
def find(x):
    while parent[x] != x: parent[x] = parent[parent[x]]; x = parent[x]
    return x
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb: parent[ra] = rb

# candidate pairs: workflows sharing >=1 tool
tool_idx = defaultdict(list)
for n, d in wf.items():
    for t in d["tools"]: tool_idx[t].append(n)
seen_pairs = set()
for t, members in tool_idx.items():
    if len(members) > 400: continue  # skip ubiquitous utility tools (would collapse catalog)
    for i in range(len(members)):
        for j in range(i + 1, len(members)):
            a, b = members[i], members[j]
            key = (a, b) if a < b else (b, a)
            if key in seen_pairs: continue
            seen_pairs.add(key)
            ta, tb = wf[a]["tools"], wf[b]["tools"]
            if not ta or not tb: continue
            jac = len(ta & tb) / len(ta | tb)
            if jac >= 0.5: union(a, b)

clusters = defaultdict(list)
for n in wf: clusters[find(n)].append(n)
cl = sorted(clusters.values(), key=len, reverse=True)

# assign whole clusters to eval until ~15%
total = len(wf); target_eval = int(total * 0.15); ev = 0; split = {}
for members in cl:  # largest first go to train; take smaller clusters for eval to hit 15%
    pass
# assign eval from a mix: iterate clusters, put into eval if under target (skip the few giant clusters)
for members in sorted(cl, key=len):
    s = "eval" if (ev + len(members) <= target_eval and len(members) <= 40) else "train"
    if s == "eval": ev += len(members)
    for m in members: split[m] = {"cluster": find(m), "split": s}

with open(f"{OUT}/workflow_split.json", "w") as f:
    json.dump(split, f)
singletons = sum(1 for m in cl if len(m) == 1)
print(f"workflows: {total} | clusters: {len(cl)} (singletons {singletons}, largest {len(cl[0])})")
print(f"split: train {sum(1 for v in split.values() if v['split']=='train')} | eval {ev} (~{ev/total:.0%}, whole-cluster, family-disjoint)")
print(f"-> {OUT}/workflow_split.json")
