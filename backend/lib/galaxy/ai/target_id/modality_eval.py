"""Evaluate the precedent-free modality selector on the ChEMBL approved-drug gold (modality_gold.json).

Run: python -m galaxy.ai.target_id.modality_eval [cache_dir] [out_json]
Scores: selector top-1 vs gold class; baseline A (exposed -> biologic else small molecule); baseline B (majority
class). Reports accuracy (+95% Wilson CI), per-class recall, confusion matrix, on dev / test / all; mixed targets
are reported separately. The selector was tuned on the dev split only; the test split is the headline number.
3.9-safe; stdlib only.
"""
import json
import math
import os
import sys
from collections import Counter, defaultdict
from typing import Any, Dict, List, Optional, Tuple

from . import modality as M

HERE = os.path.dirname(os.path.abspath(__file__))
GOLD = os.path.join(HERE, "modality_gold.json")
OUT = os.path.join(HERE, "modality_eval_results.json")
CLASSES = ["small_molecule", "biologic", "other"]
PRED_CLASSES = list(M.MODALITIES)


def wilson(k: int, n: int) -> Tuple[float, float]:
    if n == 0:
        return (0.0, 0.0)
    z, p = 1.96, k / float(n)
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - h) / d, (c + h) / d)


def metrics(pairs: List[Tuple[str, str]]) -> Dict[str, Any]:
    """pairs = [(gold, predicted)]."""
    n = len(pairs)
    k = sum(1 for g, p in pairs if g == p)
    lo, hi = wilson(k, n)
    conf: Dict[str, Dict[str, int]] = {g: {p: 0 for p in PRED_CLASSES} for g in CLASSES}
    for g, p in pairs:
        conf[g][p] = conf[g].get(p, 0) + 1
    recall = {}
    for g in CLASSES:
        tot = sum(conf[g].values())
        recall[g] = {"n": tot, "recall": (conf[g][g] / float(tot)) if tot else None}
    rec_vals = [v["recall"] for v in recall.values() if v["recall"] is not None]
    return {"n": n, "correct": k, "accuracy": k / float(n) if n else None, "accuracy_ci95": [lo, hi],
            "per_class_recall": recall, "macro_recall": sum(rec_vals) / len(rec_vals) if rec_vals else None,
            "confusion_matrix_rows_gold_cols_pred": conf}


def run(cache_dir: Optional[str] = None, out_path: str = OUT, http_get=None) -> Dict[str, Any]:
    gold = json.load(open(GOLD))
    accs = [t["accession"] for t in gold["targets"] if t["label"] in CLASSES + ["mixed"]]
    feats = M.fetch_uniprot_features(accs, http_get, cache_dir)
    rows, skipped = [], Counter()
    for t in gold["targets"]:
        if t["label"] not in CLASSES + ["mixed"]:
            skipped[t["label"]] += 1
            continue
        p = feats.get(t["accession"])
        if not p:
            skipped["no_uniprot_entry"] += 1
            continue
        if p.get("organism_id") != 9606:
            skipped["non_human"] += 1
            continue
        r = M.select_modality(p)
        rows.append({"symbol": t["symbol"] or p.get("gene"), "accession": t["accession"], "gold": t["label"],
                     "counts": t["counts"], "split": t["split"], "selector_top": r["top"],
                     "ranked": r["ranked_options"], "confidence": r["confidence"], "location_class": r["location_class"],
                     "baseline_membrane": M.baseline_membrane_rule(p), "rationale": r["rationale"],
                     "properties": r["properties"]})
    labelled = [r for r in rows if r["gold"] in CLASSES]
    out: Dict[str, Any] = {
        "gold_sources": gold["sources"], "gold_built": gold["built"], "gold_rules": gold["rules"],
        "n_mechanisms": gold["n_mechanisms"], "n_approved_molecules": gold["n_approved_molecules"],
        "n_targets_with_drugs": gold["n_targets_with_drugs"], "gold_label_counts_all": dict(Counter(t["label"] for t in gold["targets"])),
        "skipped": dict(skipped), "n_scored": len(labelled), "validated_flag_in_module": M.VALIDATED,
        "splits": {},
    }
    for name, sel in (("dev", lambda r: r["split"] == "dev"), ("test", lambda r: r["split"] == "test"), ("all", lambda r: True)):
        sub = [r for r in labelled if sel(r)]
        maj = Counter(r["gold"] for r in sub).most_common(1)[0][0] if sub else None
        out["splits"][name] = {
            "gold_class_counts": dict(Counter(r["gold"] for r in sub)),
            "selector": metrics([(r["gold"], r["selector_top"]) for r in sub]),
            "baseline_membrane_rule": metrics([(r["gold"], r["baseline_membrane"]) for r in sub]),
            "baseline_majority": dict(metrics([(r["gold"], maj) for r in sub]), majority_class=maj),
            "selector_by_confidence": {c: {"n": len([r for r in sub if r["confidence"] == c]),
                                           "accuracy": (lambda xs: (sum(1 for r in xs if r["gold"] == r["selector_top"]) / float(len(xs))) if xs else None)([r for r in sub if r["confidence"] == c])}
                                       for c in ("high", "medium", "low")},
        }
    mixed = [r for r in rows if r["gold"] == "mixed"]
    present = lambda r: {"small_molecule" if k == "small_molecule" else k for k in r["counts"]}  # noqa: E731
    out["mixed_targets"] = {"n": len(mixed), "selector_top_distribution": dict(Counter(r["selector_top"] for r in mixed)),
                            "selector_top_is_one_of_the_approved_classes": sum(1 for r in mixed if r["selector_top"] in present(r)),
                            "note": "Mixed targets (no class >= 75% of approved drugs) are not forced into one class; shown for transparency only."}
    out["per_target"] = rows
    with open(out_path, "w") as f:
        json.dump(out, f, indent=1)
    return out


def format_summary(out: Dict[str, Any]) -> str:
    L = []
    for name in ("dev", "test", "all"):
        s = out["splits"][name]
        L.append("[%s] n=%d classes=%s" % (name, s["selector"]["n"], s["gold_class_counts"]))
        for key in ("selector", "baseline_membrane_rule", "baseline_majority"):
            m = s[key]
            L.append("  %-24s acc=%.3f (95%% CI %.3f-%.3f) macro-recall=%s" % (
                key, m["accuracy"], m["accuracy_ci95"][0], m["accuracy_ci95"][1],
                ("%.3f" % m["macro_recall"]) if m["macro_recall"] is not None else "n/a"))
        L.append("  selector recall: %s" % {k: (None if v["recall"] is None else round(v["recall"], 3), v["n"]) for k, v in s["selector"]["per_class_recall"].items()})
        L.append("  selector confusion (rows gold): %s" % json.dumps(s["selector"]["confusion_matrix_rows_gold_cols_pred"]))
        L.append("  by confidence: %s" % json.dumps(s["selector_by_confidence"]))
    L.append("mixed: %s" % json.dumps({k: v for k, v in out["mixed_targets"].items() if k != "note"}))
    L.append("skipped: %s" % out["skipped"])
    return "\n".join(L)


if __name__ == "__main__":
    o = run(sys.argv[1] if len(sys.argv) > 1 else None, sys.argv[2] if len(sys.argv) > 2 else OUT)
    print(format_summary(o))
