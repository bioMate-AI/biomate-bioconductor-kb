"""Phase 1 of the data rebuild: extract REAL gold anchors per task from the full graph (DB), at scale.
Deterministic (no LLM) — these are the ground-truth anchors. Committee distillation (Phase 2) then
synthesizes realistic queries for each and collects teacher responses; docs/commits mining is Phase 3.
Leakage split: a frozen family-disjoint eval slice is marked per record (split=eval by domain hash).
"""
import json, os, re, sqlite3, hashlib
REPO = "/Users/kky/biomate-review"
DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
OUT = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
os.makedirs(OUT, exist_ok=True)
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def split_of(family):
    # frozen leakage split: ~15% of families -> eval, by stable hash (family-disjoint from train)
    return "eval" if int(hashlib.sha256(str(family).encode()).hexdigest(), 16) % 100 < 15 else "train"


def w(path, recs):
    with open(f"{OUT}/{path}", "w") as f:
        for r in recs:
            f.write(json.dumps(r) + "\n")
    return len(recs)


counts = {}

# ROUTING + WFGEN: every workflow is a gold anchor (query synthesized in Phase 2)
routing, wfgen = [], []
for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows where description is not null and length(description)>20"):
    fam = (r["name"] or "").split("_")[0]
    base = {"workflow": r["name"], "domain": r["domain"], "split": split_of(fam),
            "anchor": {"input_types": r["input_types"], "output_types": r["output_types"], "tools_used": r["tools_used"], "description": (r["description"] or "")[:600]}}
    routing.append({"task": "routing", "gold_workflow": r["name"], **base})
    wfgen.append({"task": "wfgen", "gold_category": r["domain"], **base})
counts["routing"] = w("anchor_routing.jsonl", routing)
counts["wfgen"] = w("anchor_wfgen.jsonl", wfgen)

# PARAM: sample a real gold subset from params_schema (required/enum params)
param = []
for r in c.execute("select name,domain,params_schema from workflows where params_schema is not null and length(params_schema)>20"):
    try: sch = json.loads(r["params_schema"])
    except: continue
    plist = sch.get("parameters") or sch.get("params") or sch.get("properties") or [] if isinstance(sch, dict) else sch
    if isinstance(plist, dict):
        plist = [{"name": k, **(v if isinstance(v, dict) else {})} for k, v in plist.items()]
    gold = {}
    for p in plist:
        if not isinstance(p, dict): continue
        nm = p.get("name") or p.get("id")
        av = p.get("allowed_values") or p.get("enum") or []
        val = p.get("default")
        if val in (None, "") and av: val = av[0]
        # deterministic gold only where a concrete value exists (enum/non-null default); free-text -> committee
        if nm and val not in (None, ""):
            gold[nm] = val
        if len(gold) >= 3: break
    if gold:
        fam = (r["name"] or "").split("_")[0]
        param.append({"task": "param", "workflow": r["name"], "domain": r["domain"], "split": split_of(fam),
                      "gold_params": gold, "schema_params": [p.get("name") for p in plist if isinstance(p, dict)][:30]})
counts["param"] = w("anchor_param.jsonl", param)

# AUTOFIX/DIAGNOSIS: real execution errors are the gold anchor (category classified in Phase 2)
autofix = []
for r in c.execute("select name,domain,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>20"):
    fam = (r["name"] or "").split("_")[0]
    autofix.append({"task": "autofix", "workflow": r["name"], "domain": r["domain"], "split": split_of(fam),
                    "error_log": (r["real_exec_err"] or "")[:1500]})
counts["autofix"] = w("anchor_autofix.jsonl", autofix)

print("GRAPH POOL (real gold anchors, deduped by DB row):")
for k, v in counts.items():
    ev = sum(1 for _ in open(f"{OUT}/anchor_{k}.jsonl") if json.loads(_)["split"] == "eval")
    print(f"  {k:10s} {v:>6d}  (frozen eval slice: {ev})")
print("  decompose  3396  (from build_decomp_pool.py)")
print(f"  -> total anchors: {sum(counts.values())+3396}  (vs templated ~18.6k across ALL tasks)")
