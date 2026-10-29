"""K2 measurement: recall vs K gold, audit-sample drawer (seeded, stratified), cost numbers."""
import argparse, csv, json, random, re
from collections import defaultdict
from merge import toks, jacc
from verify import norm


def _gold_fields(g):
    stmt = g.get("statement") or g.get("rule") or ""
    c = g.get("citation") or {}
    ident = (g.get("doi") or c.get("doi") or g.get("pmcid") or c.get("pmcid") or "").lower()
    pm = (g.get("pmcid") or c.get("pmcid") or "").upper()
    return stmt, norm(g.get("quote") or ""), ident, pm


def recall_vs_gold(gold, rules, corpus_pmcids, corpus_dois):
    by_paper = defaultdict(list)
    for r in rules:
        c = r["citation"]
        by_paper[(c.get("doi") or "").lower()].append(r)
        by_paper[c["pmcid"].upper()].append(r)
    in_corpus, found, rows = 0, 0, []
    for g in gold:
        stmt, quote, ident, pm = _gold_fields(g)
        if not ((pm and pm in corpus_pmcids) or (ident and ident in corpus_dois)):
            continue
        in_corpus += 1
        cand = by_paper.get(ident, []) + by_paper.get(pm, [])
        ok = False
        for r in cand:
            sj = jacc(toks(stmt), toks(r["statement"]))
            qj = jacc(set(quote.lower().split()), set(r["quote"].lower().split())) if quote else 0.0
            if sj >= 0.3 or qj >= 0.5:
                ok = True
                break
        found += ok
        rows.append({"gold": g.get("rule_id") or stmt[:60], "paper": ident or pm, "found": ok})
    return {"gold_total": len(gold), "gold_in_corpus": in_corpus, "found": found,
            "recall_of_in_corpus": (found / in_corpus if in_corpus else None), "rows": rows}


def audit_sample(rules, n=100, seed=20261031):
    rng = random.Random(seed)
    strata = defaultdict(list)
    for r in sorted(rules, key=lambda r: r["rule_id"]):
        strata[(r["evidence_tier"], r["property"])].append(r)
    keys = sorted(strata)
    picks, i = [], 0
    for k in keys:
        rng.shuffle(strata[k])
    while len(picks) < min(n, len(rules)) and any(strata[k] for k in keys):
        k = keys[i % len(keys)]
        i += 1
        if strata[k]:
            picks.append(strata[k].pop())
    return picks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rules", required=True)
    ap.add_argument("--corpus-index", required=True, help="JSON list of {pmcid, doi}")
    ap.add_argument("--gold", help="K gold rules jsonl or json")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rules = [json.loads(l) for l in open(a.rules)]
    idx = json.load(open(a.corpus_index))
    pm = {x["pmcid"].upper() for x in idx}
    dois = {(x.get("doi") or "").lower() for x in idx if x.get("doi")}
    res = {"n_rules": len(rules)}
    if a.gold:
        txt = open(a.gold).read().strip()
        gold = json.loads(txt) if txt.startswith("[") else [json.loads(l) for l in txt.splitlines() if l.strip()]
        res["recall"] = recall_vs_gold(gold, rules, pm, dois)
    sample = audit_sample(rules)
    with open(a.out + "_audit_sample.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["rule_id", "tier", "property", "direction", "statement", "quote", "pmcid", "judge_correct_0_1", "note"])
        for r in sample:
            w.writerow([r["rule_id"], r["evidence_tier"], r["property"], r["direction"], r["statement"], r["quote"],
                        r["citation"]["pmcid"], "", ""])
    json.dump(res, open(a.out + "_measure.json", "w"), indent=1)
    print(json.dumps({k: v for k, v in res.items() if k != "recall"}, indent=1))
    if "recall" in res:
        print({k: v for k, v in res["recall"].items() if k != "rows"})


if __name__ == "__main__":
    main()
