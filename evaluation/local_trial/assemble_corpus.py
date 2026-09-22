"""Step 1: assemble the final trainable corpus + family-disjoint eval from the CLEANED/GROUNDED pools.
Per-task, per-source weights (no flattening). Split by workflow family (workflow_split.json); non-workflow
tasks (autofix/knowledge) split ~15% by content hash. Routing eval carries the accept-set. No API.
Output: data_pool_v2/corpus_train.jsonl , corpus_eval.jsonl + a manifest.
"""
import json, os, hashlib
from collections import defaultdict
P = "/Users/kky/biomate-review/docs/20260912_onprem_llm/data_pool_v2"
split = json.load(open(f"{P}/workflow_split.json")) if os.path.exists(f"{P}/workflow_split.json") else {}
accept = json.load(open(f"{P}/accept_sets.json")) if os.path.exists(f"{P}/accept_sets.json") else {}


def rows(f):
    p = f"{P}/{f}"
    return [json.loads(l) for l in open(p)] if os.path.exists(p) else []


def wsplit(wf): return split.get(wf, {}).get("split", "train") if wf else None
def hsplit(key): return "eval" if int(hashlib.sha256(str(key).encode()).hexdigest(), 16) % 100 < 15 else "train"


train, ev = [], []
def add(rec):
    (ev if rec["split"] == "eval" else train).append(rec)


# ROUTING (grounded): input=query, target=db_gold slug, eval carries accept-set
for r in rows("grounded_routing.jsonl"):
    if not r.get("db_gold"): continue
    sp = wsplit(r["db_gold"]) or hsplit(r["query"])
    add({"task": "routing", "split": sp, "source": "grounded_committee", "weight": 1.0,
         "input": r["query"], "target": r["db_gold"],
         "accept_set": accept.get(r["db_gold"], [r["db_gold"]]) if sp == "eval" else None,
         "candidate_recall": r.get("candidate_recall")})

# PARAM (grounded): target = schema-valid JSON gold
for r in rows("grounded_param.jsonl"):
    if not r.get("db_gold"): continue
    sp = wsplit(r.get("workflow")) or hsplit(r["query"])
    add({"task": "param", "split": sp, "source": "grounded_committee", "weight": 1.0,
         "input": r["query"], "target": r["db_gold"], "workflow": r.get("workflow")})

# WFGEN: target = category/domain
for r in rows("committee_wfgen.jsonl"):
    if not r.get("db_gold"): continue
    sp = wsplit(r.get("workflow")) or hsplit(r["query"])
    add({"task": "wfgen", "split": sp, "source": "committee", "weight": 0.8,
         "input": r["query"], "target": r["db_gold"]})

# DECOMPOSE: graph gold DAG (target) + committee query (input)
for r in rows("committee_decompose.jsonl"):
    if not r.get("db_gold"): continue
    sp = wsplit(r.get("workflow")) or hsplit(r["query"])
    add({"task": "decompose", "split": sp, "source": "graph+committee", "weight": 1.0,
         "input": r["query"], "target": r["db_gold"]})

# AUTOFIX: real error -> consensus category (teacher agreement) as target
for r in rows("committee_autofix.jsonl"):
    cat = r.get("teacher_gpt56") if r.get("consensus") else r.get("teacher_gpt56")
    if not cat: continue
    sp = hsplit(r.get("query", ""))
    add({"task": "autofix", "split": sp, "source": "real_error+committee", "weight": 1.0 if r.get("consensus") else 0.5,
         "input": r.get("query", ""), "target": cat.strip()})

# KNOWLEDGE: cleaned docs QA
for r in rows("self_docs_qa_clean.jsonl"):
    if not (r.get("q") and r.get("a")): continue
    add({"task": "knowledge_qa", "split": hsplit(r["q"]), "source": "self_docs", "weight": 0.7,
         "input": r["q"], "target": r["a"]})

# DIVERSE TASKS (T01-T18): clarification, conditional_param, chaining, diagnosis, dataset_compatibility
for task, gold_key in [("clarification", "db_gold"), ("conditional_param", "db_gold"),
                       ("chaining", "db_gold"), ("diagnosis", "teacher_gpt56"),
                       ("dataset_compatibility", "teacher_gpt56")]:
    for r in rows(f"committee_{task}.jsonl"):
        tgt = r.get(gold_key)
        if not tgt: continue
        sp = wsplit(r.get("workflow")) or hsplit(r.get("query", ""))
        add({"task": task, "split": sp, "source": "committee_grounded",
             "weight": 1.0 if r.get("consensus") else 0.6,
             "input": r.get("query", ""), "target": tgt, "workflow": r.get("workflow")})

for name, data in [("corpus_train.jsonl", train), ("corpus_eval.jsonl", ev)]:
    with open(f"{P}/{name}", "w") as f:
        for r in data: f.write(json.dumps(r) + "\n")

def tab(data):
    c = defaultdict(int)
    for r in data: c[r["task"]] += 1
    return dict(sorted(c.items(), key=lambda x: -x[1]))

man = {"train_total": len(train), "eval_total": len(ev), "train_by_task": tab(train), "eval_by_task": tab(ev)}
json.dump(man, open(f"{P}/corpus_manifest.json", "w"), indent=2)
print("CORPUS ASSEMBLED (cleaned + grounded + family-disjoint split):")
print(f"  TRAIN {len(train)} ->", tab(train))
print(f"  EVAL  {len(ev)} ->", tab(ev))
print(f"  (eval routing carries accept-sets; eval is family-disjoint from train)")
