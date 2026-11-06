"""
retrosynthesis_scorer.py — N4 retrosynthesis_benchmark (synthesis stage).
-------------------------------------------------------------------------
Scores single/multi-step retrosynthetic route proposals against a reference route, mirroring
the USPTO-50k / PaRoutes conventions (top-k set match + route validity). The agent returns a
ranked list of proposed routes; each route is an ordered list of steps, each step = the set of
precursor molecule ids (canonical SMILES/ids) that make the step's product.

Metrics:
  top_k_match   — is the REFERENCE route's precursor set recovered within the top-k proposed
                  routes? (set-equality on the first disconnection, the standard single-step
                  top-k accuracy; k from the proposal order)
  validity      — fraction of proposed steps that are well-formed (non-empty precursor set,
                  product != precursor) — a structural gate, NOT a chemistry oracle
  score         — composite in [0,1]: 0.7*top_k_hit + 0.3*validity

Pure/stdlib (NO RDKit — validity is structural only; a chemistry-aware check is the to-source
upgrade). CPU self-test:  python3 evaluation/scorers/retrosynthesis_scorer.py --selftest
"""
from __future__ import annotations
import argparse
from typing import Any, Dict, List


def _norm_set(precursors) -> frozenset:
    return frozenset(str(p).strip().lower() for p in (precursors or []) if str(p).strip())


def _step_valid(step: Dict[str, Any]) -> bool:
    prec = _norm_set(step.get("precursors"))
    prod = str(step.get("product", "")).strip().lower()
    return bool(prec) and prod not in prec


def score_retrosynthesis(predicted_routes: List[Dict[str, Any]], reference: Dict[str, Any],
                         k: int = 3) -> Dict[str, Any]:
    """`predicted_routes` = ranked list [{steps:[{product, precursors:[...]}, ...]}, ...].
    `reference` = {"target": id, "precursors": [...]} — the gold first-disconnection set
    (extend to full-route match when the gold carries multi-step routes)."""
    gold = _norm_set(reference.get("precursors"))
    topk = predicted_routes[:k] if k else predicted_routes
    hit = False
    for route in topk:
        steps = route.get("steps") or []
        if steps and _norm_set(steps[0].get("precursors")) == gold and gold:
            hit = True
            break
    all_steps = [s for route in predicted_routes for s in (route.get("steps") or [])]
    validity = (sum(1 for s in all_steps if _step_valid(s)) / len(all_steps)) if all_steps else 0.0
    score = 0.7 * (1.0 if hit else 0.0) + 0.3 * validity
    return {"n_routes": len(predicted_routes), "k": k, "top_k_match": hit,
            "validity": round(validity, 4), "score": round(score, 4)}


def _selftest() -> int:
    R = []

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name); R.append(bool(cond))

    ref = {"target": "T", "precursors": ["A", "B"]}
    good = [{"steps": [{"product": "T", "precursors": ["A", "B"]}]}]
    o = score_retrosynthesis(good, ref)
    ck("oracle route in top-k, valid → score ~1", o["top_k_match"] and o["validity"] == 1.0 and o["score"] > 0.97)

    # correct route at rank 3 (within k=3), with some junk ahead
    ranked = [{"steps": [{"product": "T", "precursors": ["X"]}]},
              {"steps": [{"product": "T", "precursors": ["Y", "Z"]}]},
              {"steps": [{"product": "T", "precursors": ["A", "B"]}]}]
    ck("match within top-3", score_retrosynthesis(ranked, ref, k=3)["top_k_match"])
    ck("miss outside top-1", not score_retrosynthesis(ranked, ref, k=1)["top_k_match"])

    invalid = [{"steps": [{"product": "T", "precursors": []}]}]       # empty precursors → invalid
    s = score_retrosynthesis(invalid, ref)
    ck("invalid step: validity 0, no match, low score", s["validity"] == 0.0 and s["score"] == 0.0)

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
