"""K2 merge: dedupe equivalent rules, evidence counts, contradiction flags, benchmark-overlap flag, coverage matrix before/after."""
import argparse, csv, gzip, hashlib, json, os, re
from collections import defaultdict
from config import PROPERTIES, SUBSTRUCTURES
from verify import benchmark_overlap

STOP = set("the a an of in on to for and or with by is are was were be been that this these those as at from it its their than "
           "increase increased increases decrease decreased decreases improve improved improves higher lower more less when which".split())
TIER_RANK = {"T1": 0, "T2": 1, "T3": 2}


def toks(s):
    out = set()
    for w in re.findall(r"[a-z0-9\-]+", (s or "").lower()):
        if w in STOP or len(w) < 3:
            continue
        out.add(w[:-1] if w.endswith("s") and len(w) > 4 else w)
    return out


def jacc(a, b):
    return len(a & b) / len(a | b) if a and b else 0.0


class UF:
    def __init__(self, n):
        self.p = list(range(n))

    def f(self, x):
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def u(self, a, b):
        self.p[self.f(a)] = self.f(b)


def merge(rules, source_names):
    groups = defaultdict(list)
    for i, r in enumerate(rules):
        groups[(r["property"], r["substructure_class"], r["direction"])].append(i)
    uf = UF(len(rules))
    tk = [toks(r["statement"]) for r in rules]
    for idx in groups.values():
        for a in range(len(idx)):
            for b in range(a + 1, len(idx)):
                if jacc(tk[idx[a]], tk[idx[b]]) >= 0.5:
                    uf.u(idx[a], idx[b])
    clusters = defaultdict(list)
    for i in range(len(rules)):
        clusters[uf.f(i)].append(i)
    merged = []
    for members in clusters.values():
        ms = sorted(members, key=lambda i: (TIER_RANK[rules[i]["evidence_tier"]],
                                            0 if rules[i].get("proxy_entailment") == "YES" else 1, -rules[i]["confidence"]))
        rep = dict(rules[ms[0]])
        dois = sorted({rules[i]["citation"].get("doi") or rules[i]["citation"]["pmcid"] for i in members})
        rep["support"] = {"n_rules": len(members), "n_papers": len(dois), "papers": dois,
                          "tiers": sorted({rules[i]["evidence_tier"] for i in members}),
                          "entail_yes": sum(1 for i in members if rules[i].get("proxy_entailment") == "YES")}
        ov = set()
        for i in members:
            c = rules[i]["citation"]
            ov.update(benchmark_overlap(c.get("authors"), c.get("year"), source_names))
        rep["possible_benchmark_source"] = sorted(ov)
        merged.append(rep)
    cell = defaultdict(lambda: defaultdict(set))
    for m in merged:
        cell[(m["property"], m["substructure_class"])][m["direction"]].update(m["support"]["papers"])
    conflicts = {k: {d: sorted(v) for d, v in dd.items()} for k, dd in cell.items()
                 if dd.get("increases") and dd.get("decreases") and (dd["increases"] != dd["decreases"])}
    for m in merged:
        k = (m["property"], m["substructure_class"])
        m["direction_conflict_in_cell"] = k in conflicts and m["direction"] in ("increases", "decreases")
    return merged, {"|".join(k): v for k, v in conflicts.items()}


def coverage(rules_for_cells):
    """cell FILLED = >= 3 verified rules from >= 3 distinct papers, at least one at T1/T2."""
    cells = defaultdict(lambda: {"rules": 0, "papers": set(), "t12": 0})
    for r in rules_for_cells:
        c = cells[(r["property"], r["substructure_class"])]
        c["rules"] += 1
        c["papers"].add(r["citation"].get("doi") or r["citation"]["pmcid"])
        c["t12"] += r["evidence_tier"] in ("T1", "T2")
    out = {}
    for p in PROPERTIES:
        for s in SUBSTRUCTURES:
            c = cells.get((p, s), {"rules": 0, "papers": set(), "t12": 0})
            out[f"{p}|{s}"] = {"rules": c["rules"], "papers": len(c["papers"]),
                               "filled": c["rules"] >= 3 and len(c["papers"]) >= 3 and c["t12"] >= 1}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rules", required=True)
    ap.add_argument("--annotations", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--before", help="JSON list of {property, substructure_class, doi/pmcid, tier} for existing KBs")
    a = ap.parse_args()
    rules = [json.loads(l) for l in open(a.rules)]
    uniq = {}
    for r in rules:
        uniq[r["rule_id"]] = r
    rules = list(uniq.values())
    rd = csv.reader(gzip.open(a.annotations, "rt"))
    h = next(rd)
    si = h.index("Source")
    sources = sorted({row[si] for row in rd})
    merged, conflicts = merge(rules, sources)
    os.makedirs(a.outdir, exist_ok=True)
    kb_path = os.path.join(a.outdir, "knowledge_kb_scaled_v1.jsonl")
    with open(kb_path, "w") as fh:
        for m in sorted(merged, key=lambda m: m["rule_id"]):
            fh.write(json.dumps(m, sort_keys=True) + "\n")
    after_rules = rules
    cov_after = coverage(after_rules)
    before = json.load(open(a.before)) if a.before else []
    cov_before = coverage([{"property": b["property"], "substructure_class": b["substructure_class"],
                            "citation": {"doi": b.get("doi"), "pmcid": b.get("pmcid", b.get("doi"))},
                            "evidence_tier": b.get("tier", "T2")} for b in before])
    comb = coverage([{"property": b["property"], "substructure_class": b["substructure_class"],
                      "citation": {"doi": b.get("doi"), "pmcid": b.get("pmcid", b.get("doi"))},
                      "evidence_tier": b.get("tier", "T2")} for b in before] + after_rules)
    n = len(cov_after)
    summ = {"n_verified_rules": len(rules), "n_merged": len(merged),
            "n_papers": len({r["citation"]["pmcid"] for r in rules}),
            "tier_counts": {t: sum(1 for r in rules if r["evidence_tier"] == t) for t in ("T1", "T2", "T3")},
            "entail_yes_rate": (sum(1 for r in rules if r.get("proxy_entailment") == "YES") / max(1, len(rules))),
            "cells_total": n, "cells_filled_before": sum(v["filled"] for v in cov_before.values()),
            "cells_filled_scaled_only": sum(v["filled"] for v in cov_after.values()),
            "cells_filled_combined": sum(v["filled"] for v in comb.values()),
            "n_possible_benchmark_source_rules": sum(1 for m in merged if m["possible_benchmark_source"]),
            "n_direction_conflict_cells": len(conflicts)}
    gap = [k for k, v in comb.items() if not v["filled"]]
    json.dump({"summary": summ, "coverage_before": cov_before, "coverage_scaled": cov_after, "coverage_combined": comb,
               "conflicts": conflicts, "gap_cells": gap}, open(os.path.join(a.outdir, "coverage_and_merge.json"), "w"), indent=1)
    h256 = hashlib.sha256(open(kb_path, "rb").read()).hexdigest()
    json.dump({"file": "knowledge_kb_scaled_v1.jsonl", "sha256": h256, **summ}, open(os.path.join(a.outdir, "manifest.json"), "w"), indent=1)
    print(json.dumps(summ, indent=1))


if __name__ == "__main__":
    main()
