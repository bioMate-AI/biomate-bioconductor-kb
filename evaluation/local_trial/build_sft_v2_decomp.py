#!/usr/bin/env python3
"""Fold the dependency-graph decomposition rows into the prior SFT-from-gold mix (2026-10-06, v2).

Root cause the fold fixes (docs/20260912_onprem_llm/20261006_DECOMPOSITION_ERROR_ANALYSIS.md):
the prior gold mix's 3,395 `decomposition` rows are 100% SEQUENTIAL — 0 parallel, 0 mixed, i.e.
the `depends_on` topology the eval asks for has ~0% density. This appends the 4,300
dependency-graph rows (1,700 parallel / 1,700 mixed / 900 sequential, every row in the exact eval
output schema {sub_task, order, depends_on}) built in
docs/20260912_onprem_llm/20261006_DECOMP_DATA_AND_BENCHMARK.md.

Faithful fold: the PRIOR mix is kept BYTE-FROZEN (it is the trained artifact) and the new rows are
APPENDED, then de-duplicated with the same user+assistant hash key the prior builder used
(build_sft_from_gold.py), then shuffled with the same seed. No prior row is dropped except an exact
duplicate; no eval leakage is introduced (decomposition_v2 benchmark workflows are hash-disjoint
from these training rows — proven in decomp_depgraph.split.json, overlap=0).

Usage:
  python3 build_sft_v2_decomp.py \
      --prior prior_mix.jsonl \
      --decomp ../../docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl \
      --out sft_from_gold_v2_decomp_20261006.jsonl
"""
from __future__ import annotations
import argparse, json, random, hashlib, collections

random.seed(20261006)  # same seed as build_sft_from_gold.py


def ukey(ex):
    m = {x["role"]: str(x.get("content", "")) for x in ex["messages"]}
    return hashlib.md5((m.get("user", "")[:400] + "||" + m.get("assistant", "")[:300]).encode()).hexdigest()


def load(path):
    return [json.loads(l) for l in open(path) if l.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prior", required=True, help="prior frozen mix sft_from_gold_20261006.jsonl")
    ap.add_argument("--decomp", required=True, help="decomp_depgraph.jsonl (4,300 depends_on rows)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    prior = load(a.prior)
    decomp = load(a.decomp)
    # keep only the training schema fields the prior mix uses ({messages, task, source});
    # drop the extra "structure" provenance key so the dataset schema stays uniform.
    decomp_clean = [{"messages": r["messages"], "task": r.get("task", "task_decomposition"),
                     "source": r.get("source", "catalog_depgraph_synth")} for r in decomp]

    out = list(prior) + decomp_clean
    seen, dedup, dropped = set(), [], 0
    for ex in out:
        k = ukey(ex)
        if k in seen:
            dropped += 1
            continue
        seen.add(k)
        dedup.append(ex)
    random.shuffle(dedup)

    with open(a.out, "w") as f:
        for ex in dedup:
            f.write(json.dumps(ex) + "\n")

    bytask = collections.Counter(ex["task"] for ex in dedup)
    # structure distribution of the folded task_decomposition rows (sanity: parallel/mixed now present)
    import re
    def struct(plan):
        deps = [len(s.get("depends_on", []) or []) for s in plan if isinstance(s, dict)]
        if not deps: return "empty"
        if all(d == 0 for d in deps): return "parallel"
        if all(d > 0 for d in deps[1:]): return "sequential"
        return "mixed"
    sc = collections.Counter()
    for ex in dedup:
        if ex["task"] not in ("decomposition", "task_decomposition"): continue
        aa = next((m["content"] for m in ex["messages"] if m["role"] == "assistant"), "")
        try:
            m = re.search(r"\[.*\]", aa, re.S); plan = json.loads(m.group()) if m else []
        except Exception:
            plan = []
        sc[struct(plan)] += 1
    print(f"=== SFT v2 (decomp folded): prior {len(prior)} + decomp {len(decomp_clean)} "
          f"- {dropped} dup = {len(dedup)} rows -> {a.out}")
    print("by task:", bytask.most_common())
    print("decomposition+task_decomposition structure distribution:", sc.most_common())


if __name__ == "__main__":
    main()
