"""
qsar_scorer.py — N2 qsar_benchmark (S3 lead optimization).
----------------------------------------------------------
Scores QSAR potency regression with explicit ACTIVITY-CLIFF stratification (the MoleculeACE
lesson: aggregate RMSE hides the only hard part — pairs of near-identical structures with large
activity differences). Predicted/reference are pIC50 (or pKi) keyed by molecule id.

Metrics:
  rmse        — RMSE over all scored molecules (kcal-free, log-potency units)
  rmse_cliff  — RMSE restricted to molecules that participate in an activity-cliff pair
                (the headline MoleculeACE metric; a model that only interpolates fails here)
  score       — composite in [0,1]: 0.4*f(rmse) + 0.6*f(rmse_cliff), f(x)=max(0,1-x/2.0)
                (cliff-weighted, so smoothing-only models cannot win)

Pure/stdlib. CPU self-test:  python3 evaluation/scorers/qsar_scorer.py --selftest
"""
from __future__ import annotations
import argparse
import math
from typing import Any, Dict, List, Optional


def _safe(v: Any) -> Optional[float]:
    try:
        f = float(v)
        return f if math.isfinite(f) else None
    except (TypeError, ValueError):
        return None


def _rmse(pred: Dict[str, Any], ref: Dict[str, Any], keys) -> Optional[float]:
    d = [(_safe(pred.get(k)), _safe(ref.get(k))) for k in keys]
    d = [(p, r) for p, r in d if p is not None and r is not None]
    if not d:
        return None
    return math.sqrt(sum((p - r) ** 2 for p, r in d) / len(d))


def score_qsar(predicted: Dict[str, Any], reference: Dict[str, Any],
               cliff_ids: Optional[List[str]] = None) -> Dict[str, Any]:
    """`cliff_ids` = molecule ids that participate in an activity-cliff pair (from the gold)."""
    keys = [k for k in reference if _safe(reference[k]) is not None and _safe(predicted.get(k)) is not None]
    n = len(keys)
    rmse = _rmse(predicted, reference, keys)
    cliff = [k for k in keys if cliff_ids and k in set(cliff_ids)]
    rmse_cliff = _rmse(predicted, reference, cliff) if cliff else None

    def f(x):
        return None if x is None else max(0.0, 1.0 - x / 2.0)

    fr, fc = f(rmse), f(rmse_cliff)
    if fc is None:                       # no cliff pairs scored → fall back to plain rmse
        score = fr if fr is not None else 0.0
    else:
        score = 0.4 * (fr or 0.0) + 0.6 * fc
    return {"n": n, "n_cliff": len(cliff), "rmse": rmse, "rmse_cliff": rmse_cliff,
            "score": round(max(0.0, min(1.0, score)), 4)}


def _selftest() -> int:
    R = []

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name); R.append(bool(cond))

    ref = {"M1": 5.0, "M2": 7.5, "M3": 6.0, "M4": 8.0}   # pIC50
    cliffs = ["M2", "M4"]                                 # the activity-cliff molecules
    o = score_qsar(dict(ref), ref, cliffs)
    ck("oracle: rmse 0, rmse_cliff 0, score 1", o["rmse"] == 0 and o["rmse_cliff"] == 0 and o["score"] == 1.0)

    # a model that nails the easy ones but misses the cliffs → rmse_cliff high → low score
    smooth = {"M1": 5.0, "M2": 6.0, "M3": 6.0, "M4": 6.5}
    s = score_qsar(smooth, ref, cliffs)
    ck("cliff-blind model: rmse_cliff > rmse, score penalised",
       s["rmse_cliff"] > s["rmse"] and s["score"] < o["score"])

    noisy = {k: v + 0.3 for k, v in ref.items()}
    ns = score_qsar(noisy, ref, cliffs)
    ck("small noise: high-but-not-perfect score", 0.7 < ns["score"] < 1.0)

    ck("no overlap → n 0", score_qsar({"X": 1}, ref, cliffs)["n"] == 0)
    p = sum(R); print(f"\n{p}/{len(R)} passed"); return 0 if p == len(R) else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return _selftest()
    ap.error("nothing to do; use --selftest (scoring is a library call)")


if __name__ == "__main__":
    import sys
    sys.exit(main())
