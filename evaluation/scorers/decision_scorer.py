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


# ── categorical-verdict decision scorer ──────────────────────────────────────
# Serves archetypes whose decision is a single categorical call from a controlled
# vocabulary (plus an optional numeric estimate): F2 tissue/organ exposure
# (reaches_target | excluded) and F4 special-population dose adjustment
# (no_change | reduce_dose | avoid_or_contraindicated).

def _assert_verdicts(response: str, vocab: Dict[str, Sequence[str]]) -> Set[str]:
    """Which canonical verdicts the response asserts. Prefers a `verdict:`/`action:`
    line; else scans the text for an alias not immediately negated ('not reduce')."""
    text = response or ""
    # 1) structured verdict/action line
    asserted: Set[str] = set()
    for key in ("verdict", "action", "decision"):
        m = re.search(rf"(?im)^\s*{key}\s*[:=]\s*(.+)$", text)
        if m:
            val = m.group(1).lower()
            for canon, aliases in vocab.items():
                if any(a in val for a in aliases) or canon.lower() in val:
                    asserted.add(canon)
            if asserted:
                return asserted
    # 2) free-text: alias present and not immediately preceded by a negator
    low = text.lower()
    for canon, aliases in vocab.items():
        for a in list(aliases) + [canon.lower()]:
            for m in re.finditer(re.escape(a), low):
                pre = low[max(0, m.start() - 6):m.start()]
                if pre.rstrip().endswith(("not", "n't", "no")):
                    continue
                asserted.add(canon)
                break
    return asserted


def score_numeric_decision(response: str, ground_truth: Dict[str, Any]) -> Dict[str, Any]:
    """Grade a numeric dose/PK projection (e.g. FIH MRSD, allometric human clearance)
    against a deterministic ground-truth value.

    ground_truth:
      true_value     : the correct number
      tolerance_fold : within-fold credit band (default 1.5) — full credit if the
                       prediction is within this fold, half credit within fold^2
      cue            : optional substring to anchor the number (else prefer an
                       'answer:' line, then the last number in the text)
      rationale_must_mention : optional [terms]
    Composite: 0.85 numeric + 0.15 rationale.
    """
    import math
    text = response or ""
    true_val = float(ground_truth["true_value"])
    tol = float(ground_truth.get("tolerance_fold", 1.5))
    cue = ground_truth.get("cue")

    def _nums_near(scope: str) -> List[float]:
        return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", scope.replace(",", ""))]

    parsed: Optional[float] = None
    m = re.search(r"(?im)^\s*answer\s*[:=]\s*(.+)$", text)
    if m:
        nums = _nums_near(m.group(1))
        parsed = nums[0] if nums else None
    if parsed is None and cue:
        cm = re.search(re.escape(cue.lower()) + r"[^0-9\-]{0,25}(-?\d+(?:\.\d+)?)",
                       text.lower().replace(",", ""))
        if cm:
            parsed = float(cm.group(1))
    if parsed is None:
        nums = _nums_near(text)
        parsed = nums[-1] if nums else None

    if parsed is None or parsed == 0 or true_val == 0:
        numeric_score = 0.0
        fold = None
    else:
        fold = max(parsed / true_val, true_val / parsed)
        numeric_score = 1.0 if fold <= tol else (0.5 if fold <= tol * tol else 0.0)

    rationale = _rationale_coverage(response, ground_truth.get("rationale_must_mention", []))
    score = 0.85 * numeric_score + 0.15 * rationale
    return {
        "score": round(score, 4),
        "numeric_score": numeric_score,
        "parsed_value": parsed,
        "true_value": true_val,
        "fold_error": None if fold is None else round(fold, 3),
        "rationale_coverage": round(rationale, 4),
    }


def _assert_members(response: str, vocab: Dict[str, Sequence[str]]) -> Set[str]:
    """All canonical items the response asserts (multi-select), negation-guarded. Unlike
    _assert_verdicts this never early-returns — used for 'which of these apply' tasks."""
    low = (response or "").lower()
    got: Set[str] = set()
    for canon, aliases in vocab.items():
        for a in list(aliases) + [canon.lower()]:
            matched = False
            for m in re.finditer(re.escape(a), low):
                pre = low[max(0, m.start() - 6):m.start()]
                if pre.rstrip().endswith(("not", "n't", "no", "without", "exclud")):
                    continue
                matched = True
                break
            if matched:
                got.add(canon)
                break
    return got


def score_set_decision(response: str, ground_truth: Dict[str, Any]) -> Dict[str, Any]:
    """Grade a multi-select decision — which items from a controlled vocabulary apply
    (e.g. which deliverables are prerequisite before advancing a stage gate).

    ground_truth:
      required     : list of canonical items that MUST be named
      item_vocab   : {canonical: [aliases]} covering required items AND distractors
      rationale_must_mention : optional [terms]
    Composite: 0.85 set-F1 (penalises naming a distractor and missing a required item)
               + 0.15 rationale.
    """
    vocab = {k: [a.lower() for a in v] for k, v in ground_truth.get("item_vocab", {}).items()}
    required = {str(x) for x in ground_truth.get("required", [])}
    # Prefer a structured answer line ('required:' / 'prerequisites:' / 'answer:'); only
    # items named ON that line count, so distractors the prose dismisses ("the NDA comes
    # later") are not miscounted. Fall back to a whole-text scan.
    structured = None
    for key in ("required", "prerequisites", "prerequisite", "answer", "items"):
        m = re.search(rf"(?im)^\s*{key}\s*[:=]\s*(.+)$", response or "")
        if m:
            structured = m.group(1)
            break
    got = _assert_members(structured if structured is not None else (response or ""), vocab)
    set_f1 = _set_f1(got, required)
    rationale = _rationale_coverage(response, ground_truth.get("rationale_must_mention", []))
    score = 0.85 * set_f1 + 0.15 * rationale
    return {
        "score": round(score, 4),
        "set_f1": round(set_f1, 4),
        "parsed_items": sorted(got),
        "required": sorted(required),
        "missing": sorted(required - got),
        "extra": sorted(got - required),
        "rationale_coverage": round(rationale, 4),
    }


def score_categorical_decision(response: str, ground_truth: Dict[str, Any]) -> Dict[str, Any]:
    """Grade a single categorical decision + optional numeric estimate.

    ground_truth:
      verdict        : the correct canonical verdict (str)
      verdict_vocab  : {canonical: [lowercased alias substrings]}
      numeric        : optional {cue, true_value, tolerance_fold} — parse a number near
                       `cue` (regex-escaped substring) and credit if within fold
      rationale_must_mention : optional [lowercased terms]
    Composite: with numeric → 0.60 verdict + 0.25 numeric + 0.15 rationale;
               without      → 0.80 verdict + 0.20 rationale.
    """
    vocab = {k: [a.lower() for a in v] for k, v in ground_truth.get("verdict_vocab", {}).items()}
    true_v = ground_truth["verdict"]
    asserted = _assert_verdicts(response, vocab)
    if true_v in asserted and len(asserted) == 1:
        verdict_score = 1.0
    elif true_v in asserted:
        verdict_score = 0.5          # hedged — asserted the right one but also others
    else:
        verdict_score = 0.0

    num = ground_truth.get("numeric")
    numeric_score: Optional[float] = None
    parsed_num: Optional[float] = None
    if num:
        import math
        cue = num.get("cue", "")
        tol = float(num.get("tolerance_fold", 2.0))
        true_val = float(num["true_value"])
        low = (response or "").lower()
        best = None
        for m in re.finditer(re.escape(cue.lower()) + r"[^0-9\-]{0,25}(-?[0-9]+(?:\.[0-9]+)?)", low):
            best = float(m.group(1))
        parsed_num = best
        if best is None:
            numeric_score = 0.0
        else:
            fold = max(best / true_val, true_val / best) if (best and true_val) else math.inf
            numeric_score = 1.0 if fold <= tol else 0.0

    rationale = _rationale_coverage(response, ground_truth.get("rationale_must_mention", []))

    if numeric_score is not None:
        score = 0.60 * verdict_score + 0.25 * numeric_score + 0.15 * rationale
    else:
        score = 0.80 * verdict_score + 0.20 * rationale
    return {
        "score": round(score, 4),
        "verdict_score": verdict_score,
        "parsed_verdicts": sorted(asserted),
        "numeric_score": numeric_score,
        "parsed_numeric": parsed_num,
        "rationale_coverage": round(rationale, 4),
    }


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

    # ---- categorical verdict scorer (F2 / F4) ----
    gt_f2 = {
        "verdict": "excluded",
        "verdict_vocab": {
            "reaches": ["reaches", "engages", "penetrat", "sufficient exposure"],
            "excluded": ["excluded", "does not reach", "will not engage", "efflux", "restricted"],
        },
        "rationale_must_mention": ["p-gp"],
    }
    cg = score_categorical_decision(
        "P-gp efflux keeps brain exposure low.\nverdict: excluded", gt_f2)
    ck("F2 structured verdict correct → 1.0 verdict, high score",
       cg["verdict_score"] == 1.0 and cg["score"] > 0.9)
    cw = score_categorical_decision("verdict: reaches", gt_f2)
    ck("F2 wrong verdict → 0", cw["verdict_score"] == 0.0 and cw["score"] < 0.2)

    gt_f4 = {
        "verdict": "avoid_or_contraindicated",
        "verdict_vocab": {
            "no_change": ["no adjustment", "no change", "standard dose", "unchanged"],
            "reduce_dose": ["reduce", "lower the dose", "dose reduction", "decrease the dose"],
            "avoid_or_contraindicated": ["contraindicated", "avoid", "do not use", "not recommended"],
        },
        "numeric": {"cue": "egfr", "true_value": 30, "tolerance_fold": 1.4},
        "rationale_must_mention": ["renal"],
    }
    cf = score_categorical_decision(
        "With renal impairment below eGFR 30 this is contraindicated.\n"
        "action: avoid_or_contraindicated", gt_f4)
    ck("F4 verdict+numeric+rationale correct → score ~1.0", cf["score"] > 0.95)
    cfn = score_categorical_decision("action: reduce_dose", gt_f4)
    ck("F4 wrong action (reduce vs contraindicated) → low", cfn["verdict_score"] == 0.0)
    cneg = score_categorical_decision(
        "The drug is not contraindicated; use standard dose.\nverdict: no_change",
        {**gt_f4, "verdict": "no_change"})
    ck("F4 negation guard: 'not contraindicated' not counted as contraindicated",
       "avoid_or_contraindicated" not in cneg["parsed_verdicts"] and cneg["verdict_score"] == 1.0)

    # ---- set-membership scorer (process-knowledge prerequisites) ----
    gt_set = {
        "required": ["glp_tox", "cmc", "nonclinical_package", "clinical_protocol"],
        "item_vocab": {
            "glp_tox": ["glp tox", "glp toxicolog", "ind-enabling tox", "preclinical safety"],
            "cmc": ["cmc", "manufacturing", "drug substance", "formulation and manufacturing"],
            "nonclinical_package": ["nonclinical package", "2.6", "pharmacology/pk package",
                                    "nonclinical pharmacology"],
            "clinical_protocol": ["clinical protocol", "phase 1 protocol", "study protocol"],
            "phase2_efficacy": ["phase 2 efficacy", "proof of concept efficacy", "phase ii data"],
            "nda": ["nda", "new drug application", "marketing application"],
        },
        "rationale_must_mention": ["ind"],
    }
    good_set = ("Phase 2 efficacy and the NDA come much later, not before the IND.\n"
                "required: GLP toxicology, CMC/manufacturing, the nonclinical "
                "pharmacology/PK package (2.6), clinical protocol")
    ss = score_set_decision(good_set, gt_set)
    ck("set: structured answer, 4 IND prerequisites, no distractors → high score",
       ss["set_f1"] == 1.0 and ss["extra"] == [] and ss["score"] > 0.95)
    bad_set = score_set_decision(
        "You need GLP tox and also Phase 2 efficacy data and an NDA.", gt_set)
    ck("set: missing prereqs + names distractors → low score",
       bad_set["set_f1"] < 0.5 and "nda" in bad_set["extra"])

    # ---- numeric scorer (dose projection) ----
    gt_num = {"true_value": 0.811, "tolerance_fold": 1.4, "cue": "mrsd",
              "rationale_must_mention": ["noael"]}
    sn_ok = score_numeric_decision(
        "From the NOAEL and km factors, HED is 8.1 mg/kg.\nanswer: MRSD = 0.81 mg/kg", gt_num)
    ck("numeric: correct MRSD within fold → high score",
       sn_ok["numeric_score"] == 1.0 and sn_ok["score"] > 0.95)
    sn_bad = score_numeric_decision("answer: 50 mg/kg", gt_num)
    ck("numeric: off by >fold^2 → 0", sn_bad["numeric_score"] == 0.0)
    sn_half = score_numeric_decision("answer: MRSD 1.5 mg/kg", gt_num)
    ck("numeric: within fold^2 but not fold → half credit",
       sn_half["numeric_score"] == 0.5)

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
