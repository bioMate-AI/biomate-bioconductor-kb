"""Drop empty/uninformative error logs from autofix_harness_raw -> autofix_harness_clean."""
import json,re,collections
D="/Users/kky/biomate-review/docs/20260912_onprem_llm/routing_data_v1"
raw=[json.loads(l) for l in open(f"{D}/autofix_harness_raw.jsonl")]
def informative(e):
    log=(e.get("error_log") or "").strip(); low=log.lower()
    if len(log)<40: return False
    if low.startswith("command error:") and len(log)<80: return False
    return any(k in low for k in ["error","not found","failed","no such","missing","cannot","exception","fatal","traceback","undefined","unable","invalid","denied","exceeded"])
clean=[e for e in raw if informative(e)]
open(f"{D}/autofix_harness_clean.jsonl","w").write("\n".join(json.dumps(e) for e in clean))
print(f"autofix: {len(raw)} -> {len(clean)} | {dict(collections.Counter(e['category'] for e in clean))}")
