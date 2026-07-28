#!/usr/bin/env python3
# =============================================================================
# metadata_proposer / evaluate.py
# =============================================================================
# OUT-OF-DICTIONARY (OOD) EVALUATION for the metadata-mapping proposer.
#
# Runs the constrained proposer over eval.jsonl and reports the three metrics
# that matter for the survey-adjusted design:
#
#   IN-DICTIONARY ACCURACY   of the in-dict eval rows, fraction where the
#                            proposer SELECTed the correct gold term_id.
#   OOD ABSTENTION RATE      of the out-of-dictionary eval rows, fraction where
#                            the proposer correctly ABSTAINed (did NOT emit an ID).
#   HALLUCINATED-ID RATE     fraction of ALL emitted IDs that are not present in
#                            the allowed ontology-ID set. MUST be 0 by
#                            construction (proposer can only SELECT retrieved
#                            candidates). This is the load-bearing safety metric.
#
# Also reports precision on in-dict SELECTs and an OOD "leakage" count (OOD rows
# that got a SELECT instead of ABSTAIN — those are the dangerous cases the design
# exists to prevent).
# =============================================================================

import csv
import json
import os
import sys

from constrained_decoder import Retriever, Proposer

HERE = os.path.dirname(os.path.abspath(__file__))


def load_jsonl(path):
    with open(path) as fh:
        return [json.loads(line) for line in fh if line.strip()]


def load_allowed_ids(ontology_csv):
    ids = set()
    with open(ontology_csv, newline="") as fh:
        for r in csv.DictReader(fh):
            tid = (r.get("term_id") or "").strip()
            if tid:
                ids.add(tid)
    return ids


def main():
    ont = os.path.join(HERE, "ontology_seed.csv")
    eval_path = os.path.join(HERE, "eval.jsonl")
    if not (os.path.exists(ont) and os.path.exists(eval_path)):
        sys.exit("Missing ontology_seed.csv or eval.jsonl — run build_bootstrap.py first.")

    allowed_ids = load_allowed_ids(ont)
    rows = load_jsonl(eval_path)

    retriever = Retriever(ont)
    proposer = Proposer(retriever)

    # counters
    in_total = in_correct = in_selected = in_select_correct = 0
    ood_total = ood_abstained = ood_leaked = 0
    emitted_ids = []            # every ID the proposer emitted (for hallo check)
    hallucinated = []           # emitted IDs not in the allowed set
    detail = []

    for r in rows:
        d = proposer.propose(r["input"])
        decision = d["decision"]
        emitted = d["term_id"]
        if emitted is not None:
            emitted_ids.append(emitted)
            if emitted not in allowed_ids:
                hallucinated.append((r["input"], emitted))

        if r["in_dictionary"]:
            in_total += 1
            if decision == "SELECT":
                in_selected += 1
                if emitted == r["gold_term_id"]:
                    in_correct += 1
                    in_select_correct += 1
            # (a wrong SELECT or an ABSTAIN both count as "not correct" for acc)
        else:
            ood_total += 1
            if decision == "ABSTAIN":
                ood_abstained += 1
            else:
                ood_leaked += 1  # OOD row that got an ID — a containment failure

        detail.append({
            "input": r["input"],
            "in_dictionary": r["in_dictionary"],
            "gold": r["gold_term_id"],
            "decision": decision,
            "emitted_id": emitted,
            "reason": d["reason"],
        })

    def pct(n, d):
        return round(100.0 * n / d, 1) if d else 0.0

    in_acc = pct(in_correct, in_total)
    in_prec = pct(in_select_correct, in_selected)
    ood_abst = pct(ood_abstained, ood_total)
    hallo_rate = pct(len(hallucinated), len(emitted_ids)) if emitted_ids else 0.0

    # -------------------------------------------------------------- print report
    print("=" * 68)
    print("METADATA PROPOSER — OOD EVALUATION")
    print("=" * 68)
    print("eval rows: %d  (in-dictionary: %d, out-of-dictionary: %d)"
          % (len(rows), in_total, ood_total))
    print("allowed ontology IDs (grounding set): %d" % len(allowed_ids))
    print("-" * 68)
    print("IN-DICTIONARY ACCURACY     : %5.1f%%  (%d/%d correct SELECT of gold)"
          % (in_acc, in_correct, in_total))
    print("  in-dict SELECT precision : %5.1f%%  (%d/%d SELECTs correct)"
          % (in_prec, in_select_correct, in_selected))
    print("OOD ABSTENTION RATE        : %5.1f%%  (%d/%d correctly abstained)"
          % (ood_abst, ood_abstained, ood_total))
    print("  OOD leakage (got an ID)  : %d   <- must be 0 (never emit ID for OOD)"
          % ood_leaked)
    print("HALLUCINATED-ID RATE       : %5.1f%%  (%d/%d emitted IDs off-ontology)"
          % (hallo_rate, len(hallucinated), len(emitted_ids)))
    print("-" * 68)

    if hallucinated:
        print("!!! HALLUCINATED IDS DETECTED (design invariant VIOLATED):")
        for txt, hid in hallucinated:
            print("    %-40s -> %s" % (txt[:40], hid))
    else:
        print("OK: 0 hallucinated IDs — every emitted ID is in the ontology set.")

    print("-" * 68)
    print("per-row decisions:")
    for d in detail:
        tag = "IN " if d["in_dictionary"] else "OOD"
        mark = "OK " if (
            (d["in_dictionary"] and d["decision"] == "SELECT"
             and d["emitted_id"] == d["gold"])
            or (not d["in_dictionary"] and d["decision"] == "ABSTAIN")
        ) else "..."
        print("  [%s][%s] %-42s %-8s %s"
              % (tag, mark, d["input"][:42], d["decision"],
                 d["emitted_id"] or "—"))

    # -------------------------------------------------------------- write metrics
    metrics = {
        "n_eval": len(rows),
        "n_in_dictionary": in_total,
        "n_out_of_dictionary": ood_total,
        "n_allowed_ids": len(allowed_ids),
        "in_dictionary_accuracy_pct": in_acc,
        "in_dictionary_select_precision_pct": in_prec,
        "ood_abstention_rate_pct": ood_abst,
        "ood_leakage_count": ood_leaked,
        "hallucinated_id_rate_pct": hallo_rate,
        "hallucinated_id_count": len(hallucinated),
        "n_emitted_ids": len(emitted_ids),
        "hallucinated_ids": hallucinated,
    }
    out_path = os.path.join(HERE, "eval_metrics.json")
    with open(out_path, "w") as fh:
        json.dump({"metrics": metrics, "detail": detail}, fh, indent=2)
    print("-" * 68)
    print("wrote %s" % os.path.basename(out_path))

    # non-zero exit if the safety invariant is violated (CI-friendly)
    if hallucinated or ood_leaked:
        sys.exit(2)


if __name__ == "__main__":
    main()
