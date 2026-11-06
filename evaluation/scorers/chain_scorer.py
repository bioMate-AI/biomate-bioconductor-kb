"""
chain_scorer.py
---------------
Scores a LONG WORKFLOW CHAIN — a multi-stage pipeline the agent must sequence to reach
an outcome (RNA-seq QC→align→quant→DE→enrichment→report; a cross-stage drug-dev
remediation loop ADMET→redesign→re-screen→PK→decision). This grades the agent's
**plan**: did it name the right stages, in the right order, respecting the gates
(e.g. QC before alignment, find-the-liability before redesign).

This is the OFFLINE (plan) layer of the N8/N9 flagship. The EXECUTION layer — actually
running the chain on Batch and grading each stage's real artifact — is graded by
`execution_grader.py` on the live stack and is NOT part of this scorer.

ground_truth:
  reference_chain : ordered list of canonical stage ids (the correct pipeline)
  step_vocab      : {canonical: [lowercased alias substrings]}
  gates           : optional [[before, after], ...] ordering constraints that MUST hold
  rationale_must_mention : optional [terms]

Scoring (composite in [0,1]):
  coverage (set-F1 of named stages vs reference)        weight 0.40
  order    (LCS of named stages vs reference order)     weight 0.40  (0.50/0.50 if no gates)
  gates    (fraction of before→after constraints held)  weight 0.20  (only if gates given)

Agent plan is parsed from a structured `chain:`/`plan:` line or a numbered/arrow list;
stage order = order of first appearance. Pure/stdlib. CPU self-test:
    python3 evaluation/scorers/chain_scorer.py --selftest
"""
from __future__ import annotations

import argparse
import re
from typing import Any, Dict, List, Optional, Sequence, Tuple


def _rationale_coverage(response: str, terms: Sequence[str]) -> float:
    if not terms:
        return 1.0
    t = (response or "").lower()
    return sum(1 for term in terms if term.lower() in t) / len(terms)


def parse_chain(response: str, step_vocab: Dict[str, Sequence[str]]) -> List[str]:
    """Ordered list of canonical stages by first appearance (deduped). Prefers a
    structured `chain:`/`plan:`/`pipeline:` line, else scans the whole response."""
    text = response or ""
    scope = text
    for key in ("chain", "plan", "pipeline", "sequence", "workflow"):
        m = re.search(rf"(?im)^\s*{key}\s*[:=]\s*(.+)$", text)
        if m:
            scope = m.group(1)
            break
    low = scope.lower()
    first_pos: Dict[str, int] = {}
    for canon, aliases in step_vocab.items():
        pos = None
        for a in list(aliases) + [canon.lower()]:
            i = low.find(a.lower())
            if i != -1 and (pos is None or i < pos):
                pos = i
        if pos is not None:
            first_pos[canon] = pos
    return [c for c, _ in sorted(first_pos.items(), key=lambda kv: kv[1])]


def _lcs_len(a: Sequence[str], b: Sequence[str]) -> int:
    """Length of the longest common subsequence of a and b."""
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        return 0
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            dp[i][j] = dp[i - 1][j - 1] + 1 if a[i - 1] == b[j - 1] \
                else max(dp[i - 1][j], dp[i][j - 1])
    return dp[n][m]


def _set_f1(got: set, gold: set) -> float:
    if not gold and not got:
        return 1.0
    if not gold:
        return 0.0 if got else 1.0
    tp = len(got & gold)
    prec = tp / len(got) if got else 0.0
    rec = tp / len(gold)
    return 0.0 if (prec + rec) == 0 else 2 * prec * rec / (prec + rec)


def score_chain(response: str, ground_truth: Dict[str, Any]) -> Dict[str, Any]:
    ref: List[str] = list(ground_truth.get("reference_chain", []))
    vocab = ground_truth.get("step_vocab", {})
    gates: List[Tuple[str, str]] = [tuple(g) for g in ground_truth.get("gates", [])]

    got = parse_chain(response, vocab)
    got_set, ref_set = set(got), set(ref)

    coverage = _set_f1(got_set, ref_set)

    # order fidelity: LCS of the agent's sequence (restricted to reference stages) vs the
    # reference order, normalised by the reference length.
    got_in_ref = [s for s in got if s in ref_set]
    order = _lcs_len(got_in_ref, ref) / len(ref) if ref else 0.0

    # gate adherence: each before→after must appear and be correctly ordered
    gate_score: Optional[float] = None
    gate_violations: List[str] = []
    if gates:
        pos = {s: i for i, s in enumerate(got)}
        held = 0
        for before, after in gates:
            if before in pos and after in pos and pos[before] < pos[after]:
                held += 1
            else:
                gate_violations.append(f"{before}->{after}")
        gate_score = held / len(gates)

    rationale = _rationale_coverage(response, ground_truth.get("rationale_must_mention", []))

    if gate_score is not None:
        core = 0.40 * coverage + 0.40 * order + 0.20 * gate_score
    else:
        core = 0.50 * coverage + 0.50 * order
    score = 0.85 * core + 0.15 * rationale
    return {
        "score": round(score, 4),
        "coverage": round(coverage, 4),
        "order": round(order, 4),
        "gate_score": None if gate_score is None else round(gate_score, 4),
        "gate_violations": gate_violations,
        "parsed_chain": got,
        "missing": sorted(ref_set - got_set),
        "extra": sorted(got_set - ref_set),
        "rationale_coverage": round(rationale, 4),
    }


# ── CPU self-test ────────────────────────────────────────────────────────────

def _selftest() -> int:
    R: List[bool] = []

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name)
        R.append(bool(cond))

    gt = {
        "reference_chain": ["qc", "align", "quant", "de", "enrich", "report"],
        "step_vocab": {
            "qc": ["qc", "quality control", "fastqc", "trim"],
            "align": ["align", "mapping", "star", "bwa"],
            "quant": ["quantif", "counts", "featurecounts", "salmon"],
            "de": ["differential expression", "deseq", "edger"],
            "enrich": ["enrichment", "pathway", "enrichgo", "gsea"],
            "report": ["report", "summary", "interpretation"],
        },
        "gates": [["qc", "align"], ["de", "enrich"]],
        "rationale_must_mention": ["fastq"],
    }

    perfect = ("From FASTQ: \nchain: QC (FastQC/trim) -> alignment (STAR) -> quantification "
               "(featureCounts) -> differential expression (DESeq2) -> pathway enrichment "
               "(enrichGO) -> report")
    sp = score_chain(perfect, gt)
    ck("perfect ordered chain → score ~1.0, no gate violations",
       sp["coverage"] == 1.0 and sp["order"] == 1.0 and sp["gate_score"] == 1.0 and sp["score"] > 0.97)

    scrambled = ("plan: enrichment first, then differential expression, alignment, QC, "
                 "quantification, report")
    ss = score_chain(scrambled, gt)
    ck("scrambled order → full coverage but low order + gate violations",
       ss["coverage"] == 1.0 and ss["order"] < 0.7 and ss["gate_score"] < 1.0)

    missing = ("chain: alignment -> quantification -> differential expression -> report")
    sm = score_chain(missing, gt)
    ck("missing QC+enrichment → coverage < 1, missing listed",
       sm["coverage"] < 1.0 and set(sm["missing"]) == {"qc", "enrich"})

    wrong = score_chain("I'd just run a BLAST search and call it done.", gt)
    ck("off-task answer → near-zero", wrong["score"] < 0.2)

    ck("LCS basic", _lcs_len(["a", "b", "c"], ["a", "c"]) == 2)

    passed = sum(R)
    print(f"\n{passed}/{len(R)} passed")
    return 0 if passed == len(R) else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return _selftest()
    ap.error("nothing to do; use --selftest (scoring is called as a library)")


if __name__ == "__main__":
    import sys
    sys.exit(main())
