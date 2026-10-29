"""K2 measurement: recall vs K gold, audit-sample drawer (seeded, stratified), cost numbers."""
import argparse, csv, json, random, re
from collections import defaultdict
from merge import toks, jacc
from verify import norm


GOLD_KIND_TOPIC = {"rule": "sar_rule", "fundamental": "structure_property", "card": "prior_work", "caution": "sar_rule"}


def load_gold(path):
    """K's gold: allatom_paper/knowledge/knowledge_kb_v1.json (dict with 'rules') or a jsonl of rules. Entries from non-PMC sources
    (arXiv, internal docs) have no PMCID/DOI in the pilot's Europe PMC corpus and are counted as not-in-corpus."""
    txt = open(path).read().strip()
    d = json.loads(txt) if txt.startswith(("{", "[")) else [json.loads(l) for l in txt.splitlines() if l.strip()]
    return d["rules"] if isinstance(d, dict) and "rules" in d else d


def _gold_fields(g):
    stmt = g.get("statement") or ""
    quotes = [norm(q) for q in ([g.get("quote")] + list(g.get("quotes") or [])) if q]
    src = g.get("source") or {}
    ident = (src.get("doi") or g.get("doi") or "").lower()
    pm = (src.get("pmcid") or g.get("pmcid") or "").upper()
    return stmt, quotes, ident, pm, GOLD_KIND_TOPIC.get(g.get("kind"), "sar_rule")


def recall_vs_gold(gold, rules, corpus_pmcids, corpus_dois):
    by_paper = defaultdict(list)
    for r in rules:
        c = r["citation"]
        by_paper[(c.get("doi") or "").lower()].append(r)
        by_paper[c["pmcid"].upper()].append(r)
    per_topic = defaultdict(lambda: {"gold": 0, "in_corpus": 0, "found": 0})
    rows = []
    for g in gold:
        stmt, quotes, ident, pm, topic = _gold_fields(g)
        per_topic[topic]["gold"] += 1
        if not ((pm and pm in corpus_pmcids) or (ident and ident in corpus_dois)):
            continue
        per_topic[topic]["in_corpus"] += 1
        cand = by_paper.get(ident, []) + by_paper.get(pm, [])
        ok = False
        for r in cand:
            sj = jacc(toks(stmt), toks(r["statement"]))
            qj = max([jacc(set(q.lower().split()), set(r["quote"].lower().split())) for q in quotes] or [0.0])
            if sj >= 0.3 or qj >= 0.5:
                ok = True
                break
        per_topic[topic]["found"] += ok
        rows.append({"gold": g.get("id") or stmt[:60], "topic": topic, "paper": ident or pm, "found": ok, "k2_rules_from_paper": len(cand)})
    tot_in = sum(v["in_corpus"] for v in per_topic.values())
    tot_found = sum(v["found"] for v in per_topic.values())
    return {"gold_total": len(gold), "gold_in_corpus": tot_in, "found": tot_found,
            "recall_of_in_corpus": (tot_found / tot_in if tot_in else None), "per_topic": dict(per_topic), "rows": rows}


def audit_sample(rules, n=100, seed=20261031):
    rng = random.Random(seed)
    strata = defaultdict(list)
    for r in sorted(rules, key=lambda r: r["rule_id"]):
        strata[(r.get("topic", "sar_rule"), r["evidence_tier"])].append(r)
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
        gold = load_gold(a.gold)
        res["recall"] = recall_vs_gold(gold, rules, pm, dois)
    by_topic = defaultdict(lambda: {"rules": 0, "entail_yes": 0, "papers": set()})
    for r in rules:
        t = by_topic[r.get("topic", "sar_rule")]
        t["rules"] += 1
        t["entail_yes"] += r.get("proxy_entailment") == "YES"
        t["papers"].add(r["citation"]["pmcid"])
    res["yield_by_topic"] = {k: {"rules": v["rules"], "papers": len(v["papers"]), "entail_yes_rate": v["entail_yes"] / max(1, v["rules"])}
                             for k, v in by_topic.items()}
    sample = audit_sample(rules)
    with open(a.out + "_audit_sample.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["rule_id", "topic", "tier", "property", "direction", "statement", "quote", "pmcid", "judge_correct_0_1", "note"])
        for r in sample:
            w.writerow([r["rule_id"], r.get("topic", "sar_rule"), r["evidence_tier"], r["property"], r["direction"], r["statement"], r["quote"],
                        r["citation"]["pmcid"], "", ""])
    json.dump(res, open(a.out + "_measure.json", "w"), indent=1)
    print(json.dumps({k: v for k, v in res.items() if k != "recall"}, indent=1))
    if "recall" in res:
        print({k: v for k, v in res["recall"].items() if k != "rows"})


if __name__ == "__main__":
    main()
