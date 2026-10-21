"""
decision_scorer.py
------------------
Scores a drug-development *decision* task — the practical, context-rich shape of the
DrugDev benchmark. Unlike the routing scorers (which grade "did the agent pick the
right tool"), this grades the DECISION the agent reached: which compound/target to
advance, which to deprioritize, what the dominant liability is, and whether the
rationale cites the right mechanism. Tool execution is the means; this scores the
judgement.

Ground truth per task (`ground_truth` dict):
  advance_best        : list of acceptable "advance / top pick" labels (>=1 correct)
  deprioritize        : list of labels that MUST be dropped (the real liability)
  primary_liability   : canonical liability name (e.g. "hERG")
  liability_aliases   : surface strings that count as naming it (lowercased)
  rationale_must_mention : lowercased terms the rationale should reference

Agent response: free text. If it ends with a structured block it is parsed exactly;
otherwise a tolerant free-text parse maps advance/deprioritize verbs onto the compound
labels. The structured convention (robust, format-light):

    DECISION:
      advance: A, C
      deprioritize: B
      primary_liability: hERG

Composite score in [0,1]:
    0.60 decision   = 0.40 deprioritize-set match + 0.20 best-pick acceptable
    0.25 liability  = named the correct dominant liability (alias hit)
    0.15 rationale  = coverage of rationale_must_mention terms

All functions pure, stdlib only. CPU self-test:
    python3 evaluation/scorers/decision_scorer.py --selftest
"""
from __future__ import annotations

import argparse
import re
from typing import Any, Dict, List, Optional, Sequence, Set

_ADVANCE_VERBS = ["advance", "progress", "prioriti", "take forward", "move forward",
                  "carry forward", "select", "top pick", "best", "recommend"]
_DROP_VERBS = ["deprioriti", "drop", "discard", "reject", "eliminate", "avoid",
               "kill", "exclude", "remove", "flag", "liability", "concern", "worst"]


# ── parsing ──────────────────────────────────────────────────────────────────

def _norm(s: str) -> str:
    return str(s).strip().lower()


def _labels_in(fragment: str, labels: Sequence[str]) -> Set[str]:
    """Return which compound labels appear in a text fragment, delimited so a label
    does not match inside a larger token: 'C3' does not match inside 'C30', and an
    apostrophe counts as a boundary char so label 'D' never matches the 'd' in "I'd".

    Labels should be non-colliding tokens (e.g. 'C1', 'Cpd-7', or a compound name) —
    bare single letters like 'A' collide with the English article and must be avoided
    in task gold."""
    out: Set[str] = set()
    frag = fragment.lower()
    for lab in labels:
        l = lab.lower()
        if re.search(rf"(?<![a-z0-9']){re.escape(l)}(?![a-z0-9'])", frag):
            out.add(lab)
    return out


def parse_decision(response: str, labels: Sequence[str]) -> Dict[str, Set[str]]:
    """Extract {'advance': set, 'deprioritize': set} from the agent response.

    Prefers a trailing `DECISION:` block (advance:/deprioritize: lines); falls back
    to a tolerant per-line verb scan over the whole response."""
    text = response or ""

    # 1) structured block
    adv = _kv_line(text, "advance", labels) | _kv_line(text, "progress", labels)
    dep = (_kv_line(text, "deprioritize", labels) | _kv_line(text, "drop", labels)
           | _kv_line(text, "deprioritise", labels))
    if adv or dep:
        return {"advance": adv, "deprioritize": dep}

    # 2) tolerant free-text: split into clauses (sentence / semicolon / newline), so a
    #    single line carrying both an advance and a drop clause is still separated.
    adv, dep = set(), set()
    # split on ';', newline, or a sentence-final period (one at end/before whitespace)
    # — NOT a decimal point like "0.2", which must stay intact.
    for clause in re.split(r"[;\n]+|\.(?=\s|$)", text):
        ll = clause.lower()
        labs = _labels_in(clause, labels)
        if not labs:
            continue
        drop = any(v in ll for v in _DROP_VERBS)
        up = any(v in ll for v in _ADVANCE_VERBS)
        if drop and not up:
            dep |= labs
        elif up and not drop:
            adv |= labs
    return {"advance": adv, "deprioritize": dep}


def _kv_line(text: str, key: str, labels: Sequence[str]) -> Set[str]:
    """Find a 'key: A, B' line and return the labels named on its value side."""
    out: Set[str] = set()
    for m in re.finditer(rf"(?im)^\s*{re.escape(key)}\s*[:=]\s*(.+)$", text):
        out |= _labels_in(m.group(1), labels)
    return out


def _liability_named(response: str, aliases: Sequence[str]) -> bool:
    t = (response or "").lower()
    return any(a in t for a in aliases)


def _rationale_coverage(response: str, terms: Sequence[str]) -> float:
    if not terms:
        return 1.0
    t = (response or "").lower()
    hit = sum(1 for term in terms if term in t)
    return hit / len(terms)


# ── scoring ──────────────────────────────────────────────────────────────────

def score_decision(response: str, ground_truth: Dict[str, Any],
                   labels: Optional[Sequence[str]] = None) -> Dict[str, Any]:
    gt_drop = {str(x) for x in ground_truth.get("deprioritize", [])}
    gt_best = {str(x) for x in ground_truth.get("advance_best", [])}
    if labels is None:
        labels = sorted(gt_drop | gt_best)
    parsed = parse_decision(response, labels)
    got_drop, got_adv = parsed["deprioritize"], parsed["advance"]

    # deprioritize-set match: Jaccard-style F1 over the must-drop set, penalising
    # dropping a compound that should have advanced.
    drop_score = _set_f1(got_drop, gt_drop)

    # best-pick: did at least one named advance fall in the acceptable set AND the
    # agent did NOT advance a must-drop compound?
    advanced_a_drop = bool(got_adv & gt_drop)
    best_ok = bool(got_adv & gt_best) and not advanced_a_drop
    best_score = 1.0 if best_ok else (0.5 if (got_adv and not advanced_a_drop) else 0.0)

    decision = 0.40 * drop_score + 0.20 * best_score  # of the 0.60 decision weight → scaled below
    decision_norm = decision / 0.60  # 0..1 within the decision component

    liability = 1.0 if _liability_named(response, ground_truth.get("liability_aliases", [])) else 0.0
    rationale = _rationale_coverage(response, ground_truth.get("rationale_must_mention", []))

    score = 0.60 * decision_norm + 0.25 * liability + 0.15 * rationale
    return {
        "score": round(score, 4),
        "decision": round(decision_norm, 4),
        "drop_match": round(drop_score, 4),
        "best_pick": best_score,
        "liability_named": liability == 1.0,
        "rationale_coverage": round(rationale, 4),
        "advanced_a_must_drop": advanced_a_drop,
        "parsed_advance": sorted(got_adv),
        "parsed_deprioritize": sorted(got_drop),
    }


def _set_f1(got: Set[str], gold: Set[str]) -> float:
    if not gold and not got:
        return 1.0
    if not gold:
        return 0.0 if got else 1.0
    tp = len(got & gold)
    prec = tp / len(got) if got else 0.0
    rec = tp / len(gold)
    return 0.0 if (prec + rec) == 0 else 2 * prec * rec / (prec + rec)


# ── CPU self-test ──────────────────────────────────────────────────────────

def _selftest() -> int:
    R: List[bool] = []

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name)
        R.append(bool(cond))

    labels = ["C1", "C2", "C3", "C4"]
    gt = {
        "advance_best": ["C1", "C4"],
        "deprioritize": ["C3"],
        "primary_liability": "hERG",
        "liability_aliases": ["herg", "cardiotox", "qt prolong"],
        "rationale_must_mention": ["herg", "ic50"],
    }

    perfect = ("Compounds C1 and C4 have clean profiles and should advance.\n"
               "DECISION:\n  advance: C1, C4\n  deprioritize: C3\n  primary_liability: hERG\n"
               "C3 shows a hERG IC50 of 0.2 µM — clear cardiotox risk.")
    sp = score_decision(perfect, gt, labels)
    ck("perfect structured answer → score ~1.0", sp["score"] > 0.97 and sp["drop_match"] == 1.0)

    free = ("I would progress compound C1 as the top pick; C4 is also fine to advance. "
            "I'd drop C3 because its hERG IC50 (0.2 µM) flags cardiotox liability.")
    sf = score_decision(free, gt, labels)
    ck("free-text answer parsed → high score",
       sf["score"] > 0.9 and sf["parsed_deprioritize"] == ["C3"])

    wrong = ("DECISION:\n  advance: C3\n  deprioritize: C1\n  primary_liability: solubility\n"
             "C1 looks too polar.")
    sw = score_decision(wrong, gt, labels)
    ck("advancing the must-drop compound → low score + flag",
       sw["advanced_a_must_drop"] and sw["score"] < 0.3)

    no_liab = ("DECISION:\n  advance: C1, C4\n  deprioritize: C3\nC3 is the weakest.")
    sn = score_decision(no_liab, gt, labels)
    ck("right decision but no liability named → partial (decision credit, no liability)",
       sn["drop_match"] == 1.0 and not sn["liability_named"] and 0.5 < sn["score"] < 0.9)

    ck("word-boundary: 'C3' does not match inside 'C30'",
       _labels_in("potency is 30 nM for C30", ["C3"]) == set())

    passed = sum(R)
    print(f"\n{passed}/{len(R)} passed")
    return 0 if passed == len(R) else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true", help="CPU self-test; no external data")
    args = ap.parse_args()
    if args.selftest:
        return _selftest()
    ap.error("nothing to do; use --selftest (scoring is called as a library)")


if __name__ == "__main__":
    import sys
    sys.exit(main())
