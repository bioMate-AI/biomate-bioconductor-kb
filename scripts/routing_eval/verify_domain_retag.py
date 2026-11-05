#!/usr/bin/env python3
"""Second-model check of domain_reclassifier proposals; emits the SQL for the agreed changes only.

A change proposed by the first pass (confidence >= --min-conf) is re-asked of an independent model with
the same prompt and closed tag list. It is applied only when that model names the SAME new domain.
Usage: verify_domain_retag.py <proposals.jsonl> <verified.jsonl> <updates.sql> [--model anthropic/claude-sonnet-5.5]
"""
import argparse, json, os, sqlite3, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "backend", "lib"))
from galaxy.ai.chain_composer import domain_reclassifier as D  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("proposals"); ap.add_argument("verified"); ap.add_argument("sql")
ap.add_argument("--model", default="anthropic/claude-sonnet-5.5"); ap.add_argument("--min-conf", type=float, default=0.8)
a = ap.parse_args()
db = sqlite3.connect(str(D._DEFAULT_DB))
from galaxy.ai.domain_registry import CANONICAL_DOMAINS  # noqa: E402
tax = list(CANONICAL_DOMAINS) + ["general"]  # same per-row closed list as reclassify(canonical=True)
props = [json.loads(l) for l in open(a.proposals) if l.strip()]
cand = [p for p in props if p["method"] == "llm" and p["proposed_domain"] != p["current_domain"] and p["confidence"] >= a.min_conf
        # A move INTO 'general' only removes routing signal (the router never prefers it): not applied.
        and p["proposed_domain"] != "general"]
rows_by_id = {r[5]: r for r in db.execute("SELECT name, COALESCE(source,''), COALESCE(description,''), COALESCE(annotation,''), "
                                           "COALESCE(domain,'general'), id FROM workflows WHERE executable=1")}
rows_by_name = {r[0]: r for r in rows_by_id.values()}  # proposals from before ids were recorded
llm = D.openrouter_llm(a.model)

def check(p):
    r = rows_by_id.get(p.get("id")) or rows_by_name.get(p["name"])
    if r is None:  # the row disappeared since the proposal: never edit it
        return {**p, "second_model": a.model, "second_domain": None, "second_reason": "row_missing", "agreed": False}
    v = D._classify_one({"name": r[0], "source": r[1], "description": r[2], "annotation": r[3], "current_domain": r[4]},
                        llm, taxonomy=tax + ([r[4]] if r[4] not in tax else []), keep_on_failure=True)
    return {**p, "id": r[5], "second_model": a.model, "second_domain": v["proposed_domain"], "second_reason": v["reason"],
            "agreed": v["method"] == "llm" and v["proposed_domain"] == p["proposed_domain"]}

out = list(ThreadPoolExecutor(8).map(check, cand))
with open(a.verified, "w") as f:
    for o in out: f.write(json.dumps(o) + "\n")
ok = [o for o in out if o["agreed"]]
with open(a.sql, "w") as f:
    f.write("BEGIN;\n")
    for o in ok:  # guarded by the current tag so a re-run or a diverged DB changes nothing unexpected
        q = lambda x: "'" + str(x).replace("'", "''") + "'"  # noqa: E731
        f.write("UPDATE workflows SET domain = %s WHERE id = %d AND domain = %s;\n"
                % (q(o["proposed_domain"]), int(o["id"]), q(o["current_domain"])))
    f.write("COMMIT;\n")
print(f"proposals {len(props)}; changes >= {a.min_conf}: {len(cand)}; agreed {len(ok)}; disagreed {len(cand) - len(ok)}")
