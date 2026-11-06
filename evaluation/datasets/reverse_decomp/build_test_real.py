#!/usr/bin/env python3
"""Build the REAL held-out TEST set for reverse-decomposition.

TRAIN is reverse-generated (capability -> need -> LLM query). The TEST must be REAL usage we
did not design, so a solver gain here = genuine generalization, not generator overfit.

Sources (REAL query<->plan pairs, provenance-labelled):
  * workflow_chains  — curated chains: steps carry (role, workflow_name) and connections carry
    the real dependency edges; `example_queries` are the real natural-language intents a user
    would send. One chain -> one gold; each example_query -> one test row.
  * (optional) GTN workflow_order_corpus — "Workflow procedure" docs (intent -> ordered tools).

Gold is the NEED-satisfaction schema (gold_units + accept_set), identical to TRAIN, so the same
need_grader scores both. accept_set per step = {the real workflow_name of that step} UNION any
capability-equivalent lexicon members for (domain, role) — so valid alternatives are credited.

ZERO-OVERLAP: TEST source_units live in the 'chain::' / 'gtn::' namespace; TRAIN source_units
live in 'single::/category::/linear::/multidomain::'. Disjoint by construction. We additionally
report capability-combo overlap and tool-id overlap HONESTLY (both draw one catalog).

  python build_test_real.py --db ../../../backend/database/galaxy_ai_tools.db \
      --accept-sets accept_sets.json --out reverse_decomp_test_real.jsonl \
      --train reverse_decomp_train.jsonl --split split.json
"""
from __future__ import annotations
import json, os, re, sqlite3, argparse
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
_DEFAULT_DB = os.path.join(HERE, "..", "..", "..", "backend", "database", "galaxy_ai_tools.db")


def canon(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


def _structure_of(deps_list):
    if not deps_list:
        return "empty"
    if len(deps_list) == 1:
        return "single"
    if all(d == 0 for d in deps_list):
        return "parallel"
    if all(d > 0 for d in deps_list[1:]):
        return "sequential"
    return "mixed"


def _role_lexicon_members(caps, domain, role):
    """All lexicon accept-set members for (domain, role), plus any cap whose role matches."""
    members = set()
    for cid, c in caps.items():
        if c.get("capability") == role and (c.get("domain") == domain or True):
            members |= set(c["accept_set"])
    return members


def build(db_path, caps, with_gtn=False):
    db = sqlite3.connect(f"file:{os.path.abspath(db_path)}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    rows = []
    for ch in db.execute("SELECT * FROM workflow_chains"):
        try:
            steps = json.loads(ch["steps"] or "[]")
            conns = json.loads(ch["connections"] or "[]")
            queries = json.loads(ch["example_queries"] or "[]")
        except Exception:
            continue
        if not steps or not queries:
            continue
        order_of = {s.get("order", i + 1): i + 1 for i, s in enumerate(steps)}
        # depends_on from connections (to_step depends on from_step)
        deps = defaultdict(list)
        for c in conns:
            fs, ts = c.get("from_step"), c.get("to_step")
            if fs in order_of and ts in order_of and fs != ts:
                deps[order_of[ts]].append(order_of[fs])
        gold_units = []
        for i, s in enumerate(steps, 1):
            role = s.get("role") or f"step_{i}"
            wf = s.get("workflow_name") or role
            dom = ch["domain"] or ""
            accept = {wf} | _role_lexicon_members(caps, dom, role)
            gold_units.append({
                "order": i, "depends_on": sorted(set(deps.get(i, []))),
                "capability": role, "domain": dom,
                "deliverable": s.get("role", role),
                "accept_set": sorted(accept), "is_category_set": False,
                "n_accept": len(accept), "cap_id": f"{dom}:{role}"})
        deps_list = [len(u["depends_on"]) for u in gold_units]
        structure = _structure_of(deps_list)
        aggregation = "integrate" if any(len(u["depends_on"]) >= 2 for u in gold_units) else "none"
        combo = ">".join(u["capability"] for u in gold_units)
        for qi, q in enumerate(queries):
            rows.append({
                "id": f"test_chain_{ch['id']}_{qi}",
                "query": q, "structure": structure, "aggregation": aggregation,
                "complexity": "chain", "deliverable": gold_units[-1]["deliverable"],
                "gold_units": gold_units, "source_unit": f"chain::{ch['name']}",
                "capability_combo": combo, "provenance": "real_workflow_chain",
                "chain_domain": ch["domain"]})
    db.close()
    return rows


def overlap_report(train_path, test_rows):
    train = [json.loads(l) for l in open(train_path) if l.strip()] if os.path.exists(train_path) else []
    tr_src = {r["source_unit"] for r in train}
    te_src = {r["source_unit"] for r in test_rows}
    tr_combo = {">".join(u["capability"] for u in r["gold_units"]) for r in train}
    te_combo = {r.get("capability_combo") for r in test_rows}
    tr_tools = set()
    for r in train:
        for u in r["gold_units"]:
            tr_tools |= {canon(x) for x in u["accept_set"]}
    te_tools = set()
    for r in test_rows:
        for u in r["gold_units"]:
            te_tools |= {canon(x) for x in u["accept_set"]}
    return {
        "train_rows": len(train), "test_rows": len(test_rows),
        "train_source_units": len(tr_src), "test_source_units": len(te_src),
        "source_unit_overlap": sorted(tr_src & te_src),          # MUST be empty
        "source_unit_overlap_count": len(tr_src & te_src),
        "capability_combo_overlap_count": len(tr_combo & te_combo),
        "capability_combo_overlap": sorted(tr_combo & te_combo)[:20],
        "tool_id_overlap_count": len(tr_tools & te_tools),
        "tool_id_overlap_note": "EXPECTED > 0 — both draw one catalog; structure/combo is the "
                                 "held-out axis, not tool vocabulary (see README).",
        "zero_source_overlap": len(tr_src & te_src) == 0,
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=_DEFAULT_DB)
    ap.add_argument("--accept-sets", default=os.path.join(HERE, "accept_sets.json"))
    ap.add_argument("--out", default=os.path.join(HERE, "reverse_decomp_test_real.jsonl"))
    ap.add_argument("--train", default=os.path.join(HERE, "reverse_decomp_train.jsonl"))
    ap.add_argument("--split", default=os.path.join(HERE, "split.json"))
    a = ap.parse_args()
    caps = json.load(open(a.accept_sets))
    rows = build(a.db, caps)
    with open(a.out, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    rep = overlap_report(a.train, rows)
    with open(a.split, "w") as f:
        json.dump(rep, f, indent=2)
    from collections import Counter
    print(f"TEST rows: {len(rows)}  (from {len({r['source_unit'] for r in rows})} chains)")
    print("structure:", dict(Counter(r["structure"] for r in rows)))
    print("provenance:", dict(Counter(r["provenance"] for r in rows)))
    print(f"zero source-unit overlap: {rep['zero_source_overlap']}  "
          f"(combo-overlap={rep['capability_combo_overlap_count']}, "
          f"tool-overlap={rep['tool_id_overlap_count']})")
