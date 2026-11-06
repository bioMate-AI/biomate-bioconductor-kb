"""Corrected routing gold contract (committee data audit): a query's correct answer is an ACCEPT-SET of
functionally-equivalent workflows, not a single slug. Equivalence = same functional signature
(sorted input_types, sorted output_types, domain) UNION the tool-Jaccard cluster. Emits accept_sets.json
{workflow -> [equivalent workflow slugs]}. Deterministic, no API.
"""
import json, os, sqlite3, re
from collections import defaultdict
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
OUT = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def toks(s):
    if not s: return frozenset()
    try:
        v = json.loads(s)
        if isinstance(v, list): return frozenset(str(x).lower().strip() for x in v if x)
    except Exception: pass
    return frozenset(t.lower().strip() for t in re.split(r"[,;|]+", str(s)) if t.strip())


wf = {}
for r in c.execute("select name,domain,input_types,output_types from workflows where name is not null"):
    wf[r["name"]] = (toks(r["input_types"]), toks(r["output_types"]), (r["domain"] or "").lower())

# group by functional signature
sig = defaultdict(list)
for n, (i, o, d) in wf.items():
    sig[(i, o, d)].append(n)

# cluster membership from Fix-3 split
split = {}
sp = f"{OUT}/workflow_split.json"
if os.path.exists(sp):
    split = json.load(open(sp))
cluster = defaultdict(list)
for n, v in split.items():
    cluster[v["cluster"]].append(n)

accept = {}
for n, (i, o, d) in wf.items():
    s = set(sig[(i, o, d)])                 # same I/O + domain
    cid = split.get(n, {}).get("cluster")
    if cid: s |= set(cluster.get(cid, []))  # + tool-Jaccard cluster
    accept[n] = sorted(s)

json.dump(accept, open(f"{OUT}/accept_sets.json", "w"))
sizes = [len(v) for v in accept.values()]
import statistics as st
print(f"accept-sets for {len(accept)} workflows | mean size {st.mean(sizes):.1f} | median {st.median(sizes)} | "
      f"singletons {sum(1 for s in sizes if s==1)} | max {max(sizes)}")
print(f"-> {OUT}/accept_sets.json")
