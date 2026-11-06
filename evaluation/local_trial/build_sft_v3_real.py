#!/usr/bin/env python3
"""Fold the REAL (non-synthetic) decomposition rows + the param must_not_fill negative anchors
into the frozen v2 SFT mix (2026-10-07, v3).

Why (docs/20260912_onprem_llm/20261007_REAL_DECOMP_DATA.md + 20261006_SFT_V2_DECOMP_RETRAIN.md):
  * The v2 decomposition win (node-F1 0.36->0.73) was IN-DISTRIBUTION to the one synthetic
    constructor that emitted both the SFT rows AND the decomposition_v2 benchmark. v3 folds in
    219 REAL dependency graphs (nf-core channel graphs / workflow_chains / GTN tutorials) whose
    topology we did NOT design, to add out-of-generator training signal.
  * The v2 fold also regressed param must_not_fill (34 -> 61 violations). v3 folds in 854 real
    negative anchors (gold_params={} or minimal, must_not_fill populated) to teach restraint.

Faithful fold (identical method to build_sft_v2_decomp.py): the v2 mix is kept BYTE-FROZEN and the
new rows are APPENDED (stripped to the uniform {messages, task, source} schema), then de-duplicated
with the same user+assistant hash key the prior builders used, then shuffled with the same seed.
No v2 row is dropped except an exact duplicate.

Usage:
  python3 build_sft_v3_real.py --prior v2mix.jsonl \
      --decomp-real ../../docs/20260912_onprem_llm/data_pool_v2/decomp_real.jsonl \
      --mustnotfill ../../docs/20260912_onprem_llm/data_pool_v2/param_mustnotfill_neg.jsonl \
      --out sft_from_gold_v3_real_20261007.jsonl
"""
from __future__ import annotations
import argparse, json, random, hashlib, collections, re

random.seed(20261006)  # same seed as build_sft_from_gold.py / build_sft_v2_decomp.py


def ukey(ex):
    m = {x["role"]: str(x.get("content", "")) for x in ex["messages"]}
    return hashlib.md5((m.get("user", "")[:400] + "||" + m.get("assistant", "")[:300]).encode()).hexdigest()


def load(path):
    return [json.loads(l) for l in open(path) if l.strip()]


def strip(r, default_task, default_source):
    return {"messages": r["messages"],
            "task": r.get("task", default_task),
            "source": r.get("source", default_source)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prior", required=True, help="frozen v2 mix sft_from_gold_v2_decomp_20261006.jsonl")
    ap.add_argument("--decomp-real", required=True, help="decomp_real.jsonl (219 real depends_on rows)")
    ap.add_argument("--mustnotfill", required=True, help="param_mustnotfill_neg.jsonl (854 anchors)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    prior = load(a.prior)
    real = [strip(r, "task_decomposition", "real_decomp") for r in load(a.decomp_real)]
    mnf = [strip(r, "param_extraction", "real_params_schema_restraint") for r in load(a.mustnotfill)]

    out = list(prior) + real + mnf
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
    bysource = collections.Counter(ex["source"] for ex in dedup
                                   if str(ex["source"]).startswith("real_"))

    def struct(plan):
        deps = [len(s.get("depends_on", []) or []) for s in plan if isinstance(s, dict)]
        if not deps:
            return "empty"
        if all(d == 0 for d in deps):
            return "parallel"
        if all(d > 0 for d in deps[1:]):
            return "sequential"
        return "mixed"

    sc = collections.Counter()
    for ex in dedup:
        if ex["task"] not in ("decomposition", "task_decomposition"):
            continue
        aa = next((m["content"] for m in ex["messages"] if m["role"] == "assistant"), "")
        try:
            m = re.search(r"\[.*\]", aa, re.S)
            plan = json.loads(m.group()) if m else []
        except Exception:
            plan = []
        sc[struct(plan)] += 1

    print(f"=== SFT v3 (real decomp + mustnotfill folded): prior {len(prior)} + decomp_real {len(real)} "
          f"+ mustnotfill {len(mnf)} - {dropped} dup = {len(dedup)} rows -> {a.out}")
    print("by task:", bytask.most_common())
    print("real_* source rows:", bysource.most_common())
    print("decomposition structure distribution:", sc.most_common())


if __name__ == "__main__":
    main()
