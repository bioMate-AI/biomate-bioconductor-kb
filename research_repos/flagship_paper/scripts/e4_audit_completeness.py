"""E4 auditor: score every threshold decision in a run log for provenance completeness.

Operational definition:
  audit_completeness = (# threshold decisions with paper_ref + DOI + provenance)
                       / (# total threshold decisions)
Per-decision score:
   0    = none of {paper_ref, paper_doi, provenance grade} present
   1/3  = exactly one
   2/3  = exactly two
   1    = all three

Then per-run = mean over its decisions; per-tool = mean across runs.

Usage:
  python e4_audit_completeness.py
Reads from data/e4_logs/{biomate,baseline}/*.json (produced by e4_generate_logs.py).
Writes per-run CSV and summary CSV under results/.
"""
from __future__ import annotations
import csv
import json
import math
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOGDIR = ROOT / "data" / "e4_logs"
RESULTS = ROOT / "results"
RESULTS.mkdir(exist_ok=True)

FIELDS = ("paper_ref", "paper_doi", "provenance")


def _score_evidence_entry(ev: dict) -> float:
    """Score one evidence dict on 0/1-3/2-3/1 scale."""
    if not isinstance(ev, dict):
        return 0.0
    present = 0
    for f in FIELDS:
        v = ev.get(f)
        if v not in (None, "", []):
            present += 1
    return present / 3.0


def _score_decision_biomate(gate: dict) -> float:
    """Take best evidence entry for that gate."""
    evlist = gate.get("evidence") or []
    if not evlist:
        return 0.0
    return max(_score_evidence_entry(e) for e in evlist)


def _score_decision_baseline(row: dict) -> float:
    """Baselines: paper_ref / paper_doi / provenance live at top level if anywhere.
    Vendor doc URLs do NOT count as paper_ref or DOI."""
    present = 0
    for f in FIELDS:
        v = row.get(f)
        if v not in (None, "", []):
            present += 1
    return present / 3.0


def score_biomate_log(log: dict) -> tuple[float, int]:
    gates = log.get("gates", [])
    if not gates:
        return 0.0, 0
    scores = [_score_decision_biomate(g) for g in gates]
    return sum(scores) / len(scores), len(scores)


def score_baseline_log(log: dict) -> tuple[float, int]:
    decisions = log.get("decisions", [])
    if not decisions:
        return 0.0, 0
    scores = [_score_decision_baseline(d) for d in decisions]
    return sum(scores) / len(scores), len(scores)


def _mannwhitneyu(x, y):
    """Tiny Mann-Whitney U implementation (two-sided, no ties correction).
    Returns (U, approx_p). For n=10/10 the normal approximation is adequate."""
    n1, n2 = len(x), len(y)
    ranks = {}
    combined = sorted([(v, "x") for v in x] + [(v, "y") for v in y], key=lambda t: t[0])
    # average-rank ties handling
    i = 0
    cur_rank = 1
    while i < len(combined):
        j = i
        while j + 1 < len(combined) and combined[j + 1][0] == combined[i][0]:
            j += 1
        avg = (cur_rank + cur_rank + (j - i)) / 2.0
        for k in range(i, j + 1):
            ranks.setdefault(id(combined[k]), avg)
            combined[k] = (combined[k][0], combined[k][1], avg)
        cur_rank += (j - i + 1)
        i = j + 1
    r1 = sum(r for v, g, r in combined if g == "x")
    u1 = r1 - n1 * (n1 + 1) / 2.0
    u2 = n1 * n2 - u1
    u = min(u1, u2)
    mu = n1 * n2 / 2.0
    sigma = math.sqrt(n1 * n2 * (n1 + n2 + 1) / 12.0)
    if sigma == 0:
        return u, 1.0
    z = (u - mu) / sigma
    # two-sided p from standard normal
    p = math.erfc(abs(z) / math.sqrt(2))
    return u, p


def main():
    rows = []
    biomate_scores: list[float] = []
    baseline_scores: list[float] = []

    for fp in sorted((LOGDIR / "biomate").glob("*.json")):
        with open(fp) as f:
            log = json.load(f)
        sc, n = score_biomate_log(log)
        biomate_scores.append(sc)
        rows.append({
            "tool": "biomate",
            "run_id": log["run_id"],
            "domain": log.get("domain", ""),
            "n_decisions": n,
            "completeness": round(sc, 4),
        })

    for fp in sorted((LOGDIR / "baseline").glob("*.json")):
        with open(fp) as f:
            log = json.load(f)
        sc, n = score_baseline_log(log)
        baseline_scores.append(sc)
        rows.append({
            "tool": log.get("tool", "baseline"),
            "run_id": log["run_id"],
            "domain": log.get("domain", ""),
            "n_decisions": n,
            "completeness": round(sc, 4),
        })

    out_perrun = RESULTS / "e4_audit_completeness_per_run.csv"
    with open(out_perrun, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["tool", "run_id", "domain", "n_decisions", "completeness"])
        w.writeheader()
        w.writerows(rows)

    def _summ(scores):
        if not scores:
            return (0, 0, 0, 0, 0)
        mn = min(scores); mx = max(scores)
        med = statistics.median(scores)
        # quartiles via statistics.quantiles n=4 exclusive
        q = statistics.quantiles(scores, n=4) if len(scores) > 1 else [med, med, med]
        return (mn, q[0], med, q[2], mx)

    bm = _summ(biomate_scores)
    bl = _summ(baseline_scores)
    u, p = _mannwhitneyu(biomate_scores, baseline_scores)

    summary = [
        {"group": "biomate", "n": len(biomate_scores), "min": bm[0], "q1": bm[1],
         "median": bm[2], "q3": bm[3], "max": bm[4],
         "mean": round(sum(biomate_scores) / len(biomate_scores), 4)},
        {"group": "baseline_grouped", "n": len(baseline_scores), "min": bl[0], "q1": bl[1],
         "median": bl[2], "q3": bl[3], "max": bl[4],
         "mean": round(sum(baseline_scores) / len(baseline_scores), 4)},
    ]
    out_summary = RESULTS / "e4_completeness_summary.csv"
    with open(out_summary, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["group", "n", "min", "q1", "median", "q3", "max", "mean"])
        w.writeheader()
        w.writerows(summary)
        # statistical test stored as a trailing row
        f.write(f"# Mann-Whitney U two-sided: U={u:.2f}, p={p:.3e}\n")

    print(f"BioMate  n={len(biomate_scores)}  median={bm[2]:.3f}  IQR=[{bm[1]:.3f}, {bm[3]:.3f}]")
    print(f"Baseline n={len(baseline_scores)} median={bl[2]:.3f}  IQR=[{bl[1]:.3f}, {bl[3]:.3f}]")
    print(f"Mann-Whitney U={u:.2f}, p={p:.3e}")
    print(f"Wrote {out_perrun}")
    print(f"Wrote {out_summary}")


if __name__ == "__main__":
    main()
