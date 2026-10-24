#!/usr/bin/env python3
"""Scale DPO preference pairs across the FULL catalog (all domains/workflows), prioritized.

The exec-grounded pairs (mine_execution_pairs) are high-quality but limited to the ~16 domains that
have BOTH an executed-ok and a failed sibling. For broad, prioritized COVERAGE we also mine
ROUTING preference pairs from the DB-generated routing corpus (query -> gold workflow, already
leak-guarded + domain-prioritized):
  chosen   = the gold workflow for that (grounded) query
  rejected = the most TOOL-CONFUSABLE *different* workflow in the SAME domain (hard negative that
             shares tools/tokens with the gold but is not the answer to this query)
This scales to one pair per routing row (~29k), covers every workflow the routing corpus covers,
and inherits the routing corpus's domain prioritization + leak guard. Lower-grounding than the
execution signal (routing-correctness, not did-it-run), so pairs are tagged source=routing_confusable
and the exec-grounded pairs stay the higher-tier set — both are shipped, labelled.
"""
from __future__ import annotations
import argparse, collections, hashlib, json, random, sqlite3
from pathlib import Path

_HERE = Path(__file__).resolve().parent
DB = _HERE.parents[1] / "backend" / "database" / "galaxy_ai_tools.db"
POOL = _HERE.parent.parent / "docs" / "20260912_onprem_llm" / "data_pool_v2"
INSTR = ("You are BioMate's workflow router. Given a user request, respond with the single nextflow "
         "workflow filename that best fulfills it.")


def _lit(x):
    if isinstance(x, (list, dict)):
        return x
    try:
        return json.loads(x)
    except Exception:
        return []


def _norm(fn):
    return str(fn or "").strip().lower().replace("nf-core", "nfcore")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--routing", default=str(POOL / "db_generated_routing_grpo.jsonl"))
    ap.add_argument("--out", default=str(POOL / "db_generated_routing_dpo_pairs.jsonl"))
    ap.add_argument("--neg-per", type=int, default=1, help="confusable negatives per routing row")
    a = ap.parse_args()

    # catalog: filename -> (domain, tools set) for confusability ranking
    conn = sqlite3.connect(str(DB)); conn.row_factory = sqlite3.Row
    cat = {}
    by_dom = collections.defaultdict(list)
    for r in conn.execute("SELECT filename,domain,tools_used FROM workflows"):
        fn = r["filename"]
        if not fn:
            continue
        tools = set(str(t).split("/")[-1] for t in (_lit(r["tools_used"]) or []))
        cat[_norm(fn)] = {"fn": fn, "domain": r["domain"], "tools": tools}
        if r["domain"]:
            by_dom[r["domain"]].append(_norm(fn))

    rows = [json.loads(l) for l in open(a.routing) if l.strip()]
    pairs = []
    for r in rows:
        q = r["prompt"].split("\n\n", 1)[-1]
        gold = r["gold"]
        gkey = _norm(gold)
        gmeta = cat.get(gkey)
        if not gmeta or not gmeta["domain"]:
            continue
        gtools = gmeta["tools"]
        sibs = [s for s in by_dom[gmeta["domain"]] if s != gkey]
        if not sibs:
            continue
        # rank siblings by tool overlap with the gold (hardest negative first)
        ranked = sorted(sibs, key=lambda s: -len(gtools & cat[s]["tools"]))
        rng = random.Random(int(hashlib.md5(gkey.encode()).hexdigest(), 16))
        picked = ranked[:max(1, a.neg_per)] if any(cat[s]["tools"] & gtools for s in ranked[:3]) \
            else [rng.choice(sibs)]
        for s in picked:
            ov = len(gtools & cat[s]["tools"])
            pairs.append({"prompt": f"{INSTR}\n\n{q}", "chosen": gold, "rejected": cat[s]["fn"],
                          "task": "routing", "source": "routing_confusable",
                          "domain": gmeta["domain"], "confusability": ov})

    # dedup + drop any self-pair
    seen, uniq = set(), []
    for p in pairs:
        k = (p["prompt"], p["chosen"], p["rejected"])
        if k in seen or _norm(p["chosen"]) == _norm(p["rejected"]):
            continue
        seen.add(k); uniq.append(p)
    Path(a.out).write_text("\n".join(json.dumps(p) for p in uniq))
    doms = collections.Counter(p["domain"] for p in uniq)
    print(f"ROUTING-CONFUSABLE DPO PAIRS: {len(uniq)} across {len(doms)} domains -> {a.out}")
    print("top domains:", dict(doms.most_common(8)))
    print("confusability>=1 (shared tool):", sum(1 for p in uniq if p["confusability"] >= 1))


if __name__ == "__main__":
    main()
