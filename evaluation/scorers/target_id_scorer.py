"""
target_id_scorer.py — T2a target_id_benchmark (S0 target discovery).
--------------------------------------------------------------------
Scores a predicted TARGET PRIORITIZATION for a disease/indication against a gene-disease
association ground truth (Open Targets-style). The agent returns a ranked list of gene targets;
the gold is the set of validated associated targets (optionally with an association score).

Grounds in the existing backend `target_id` system (channels → OT harmonic-sum arbiter →
TargetScore.rank); this scorer evaluates that ranking's quality.

Metrics (ranking, leakage note: use a TEMPORAL split on the evidence to avoid training-on-future):
  hit@k      — fraction of the gold targets recovered in the top-k predictions
  mrr        — mean reciprocal rank of the gold targets in the prediction
  score      — composite in [0,1]: 0.6*hit@k + 0.4*mrr

Pure/stdlib. CPU self-test:  python3 evaluation/scorers/target_id_scorer.py --selftest
"""
from __future__ import annotations
import argparse
from typing import Any, Dict, List


def _norm(x) -> str:
    return str(x or "").strip().upper()


def score_target_id(predicted_ranking: List[Any], reference: Dict[str, Any],
                    k: int = 10) -> Dict[str, Any]:
    """`predicted_ranking` = [gene_symbol, ...] best-first. `reference` = {"gold_targets": [...]}
    (the validated associated genes; a `min_assoc` field may pre-filter OT by score upstream)."""
    pred = [_norm(t) for t in (predicted_ranking or [])]
    gold = {_norm(t) for t in (reference.get("gold_targets") or []) if _norm(t)}
    if not gold:
        return {"n_gold": 0, "hit_at_k": None, "mrr": 0.0, "score": 0.0}
    topk = set(pred[:k])
    hit_at_k = len(topk & gold) / len(gold)
    rr = 0.0
    for g in gold:
        if g in pred:
            rr += 1.0 / (pred.index(g) + 1)
    mrr = rr / len(gold)
    score = 0.6 * hit_at_k + 0.4 * mrr
    return {"n_gold": len(gold), "k": k, "hit_at_k": round(hit_at_k, 4),
            "mrr": round(mrr, 4), "score": round(max(0.0, min(1.0, score)), 4)}


def _selftest() -> int:
    R = []

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name); R.append(bool(cond))

    ref = {"gold_targets": ["PCSK9", "HMGCR"]}
    perfect = ["PCSK9", "HMGCR", "APOB", "LDLR"]
    o = score_target_id(perfect, ref, k=10)
    ck("gold ranked 1,2 → hit@k 1, mrr 0.75, high score",
       o["hit_at_k"] == 1.0 and abs(o["mrr"] - 0.75) < 1e-9 and o["score"] > 0.85)

    buried = ["A", "B", "C", "D", "E", "F", "G", "H", "PCSK9", "HMGCR"]
    b = score_target_id(buried, ref, k=10)
    ck("gold recovered but deep: hit@10 1 yet low mrr → lower score", b["hit_at_k"] == 1.0 and b["score"] < o["score"])

    miss = ["A", "B", "C"]
    m = score_target_id(miss, ref, k=10)
    ck("no gold found → hit 0, score 0", m["hit_at_k"] == 0.0 and m["score"] == 0.0)

    ck("out-of-top-k not credited", score_target_id(buried, ref, k=5)["hit_at_k"] == 0.0)
    ck("no gold → score 0", score_target_id(perfect, {"gold_targets": []})["score"] == 0.0)

    p = sum(R); print(f"\n{p}/{len(R)} passed"); return 0 if p == len(R) else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return _selftest()
    ap.error("nothing to do; use --selftest")


if __name__ == "__main__":
    import sys
    sys.exit(main())
