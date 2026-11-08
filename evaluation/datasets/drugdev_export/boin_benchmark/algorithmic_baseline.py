#!/usr/bin/env python3
"""BOIN algorithmic baseline — the established MTD-selection rule, as a non-LLM reference.

Committee (2026-10-27, gpt-6.1-sol-pro): "the [BOIN] comparison needs the established algorithmic
rule as a baseline, not only other LLMs." This implements it.

The task (../../public_export/boin_benchmark/data.jsonl): each item gives PK + exposure-response
(Emax) model inputs and a dose grid; the system must pick the MTD. The GRADER holds the true
per-level DLT curve (reference.true_dlt_rate_per_level) — NOT shown to the solver.

This baseline is an ORACLE/UPPER BOUND: it applies the standard MTD-selection rule to the TRUE DLT
curve (so it answers "given the real exposure-response, what MTD does the rule pick?"). It bounds
how well any curve-predicting system could do under this exact selection rule and surfaces the
selection-rule edge cases where "the MTD" is itself a judgment call.

Rule (Liu & Yuan, JRSS-C 2015, selection step): eliminate dose levels whose true DLT rate exceeds
the target by more than the elimination band (0.10); if the lowest level is eliminated, declare NO
MTD; otherwise select the admissible level whose DLT rate is closest to the target (ties -> higher
dose), reported in mg.

Run:  python3 algorithmic_baseline.py          # prints per-item + summary, writes _algo_baseline.json
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "..", "public_export", "boin_benchmark", "data.jsonl")
ELIM_BAND = 0.10  # standard BOIN elimination band above target


def algo_mtd(rates, target, doses):
    if rates[0] > target + ELIM_BAND + 1e-9:
        return None  # lowest dose already overly toxic -> no MTD
    adm = [i for i, r in enumerate(rates) if r <= target + ELIM_BAND + 1e-9]
    best = min(adm, key=lambda i: (abs(rates[i] - target), -i))
    return doses[best]


def main():
    rows = [json.loads(l) for l in open(DATA)]
    hit = 0
    out = []
    for r in rows:
        inp, ref = r["inputs"], r["reference"]
        rates = ref["true_dlt_rate_per_level"]
        target = inp["DLT_rate_target"]
        doses = json.loads(inp["dose_levels_json"])
        gold = ref.get("true_MTD_mg")  # None == no MTD
        pred = algo_mtd(rates, target, doses)
        ok = pred == gold
        hit += ok
        out.append({"id": r["id"], "gold_mtd_mg": gold, "algo_mtd_mg": pred, "correct": ok})
    acc = hit / len(rows)
    summary = {
        "baseline": "BOIN MTD-selection rule on the TRUE exposure-response DLT curve (oracle upper bound)",
        "n": len(rows), "correct": hit, "accuracy": round(acc, 4),
        "misses": [o["id"] for o in out if not o["correct"]],
        "note": ("misses are selection-rule edge cases, not curve errors: CT-005/CT-017 are no-MTD "
                 "safety declarations the fixed 0.10 band does not trigger; CT-009 is a closest-vs-"
                 "higher-dose tie. These mark items where 'the MTD' is itself a judgment call."),
        "per_item": out,
    }
    json.dump(summary, open(os.path.join(HERE, "_algo_baseline.json"), "w"), indent=2)
    print(f"BOIN algorithmic baseline (rule on true DLT curve): {hit}/{len(rows)} = {acc:.3f}")
    for o in out:
        print(f"  {o['id']}: gold={o['gold_mtd_mg']} algo={o['algo_mtd_mg']} {'OK' if o['correct'] else 'MISS'}")
    print("Compare: LLMs 0.11-0.50 (frontier), 0.778 (on-prem 9B base) — see leaderboard.csv")


if __name__ == "__main__":
    main()
