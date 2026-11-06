"""Merge audited generated routing episodes into the GEO SFT set (shared build_messages
format). Split by query hash; keeps GEO train/dev intact and appends generated ones."""
import json, hashlib, sys
sys.path.insert(0, "evaluation/local_trial")
from routing_prompt import build_messages
D = "docs/20260912_onprem_llm/routing_data_v1"
def h(s): return int(hashlib.sha256(s.encode()).hexdigest()[:8], 16)
gen = [json.loads(l) for l in open(f"{D}/audited_pass_merged.jsonl") if l.strip()]
gtr, gdv = [], []
for e in gen:
    q, c, w = e["query"], e.get("candidates") or [], e["correct_workflow"]
    if w not in c: c = [w] + c
    msgs = build_messages(q, c, in_format=True, few_shot=True) + [{"role": "assistant", "content": w}]
    (gdv if h(q) % 100 < 15 else gtr).append({"messages": msgs})
def load(f): return [json.loads(l) for l in open(f) if l.strip()]
tr = load(f"{D}/routing_sft_train.jsonl") + gtr
dv = load(f"{D}/routing_sft_dev.jsonl") + gdv
open(f"{D}/routing_sft_train_v2.jsonl","w").write("\n".join(json.dumps(r) for r in tr))
open(f"{D}/routing_sft_dev_v2.jsonl","w").write("\n".join(json.dumps(r) for r in dv))
print(f"generated: {len(gtr)} train + {len(gdv)} dev | COMBINED train={len(tr)} dev={len(dv)}")
