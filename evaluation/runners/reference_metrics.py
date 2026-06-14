"""Reference-based metrics — zero-cost eval lane.

Scores candidate regulatory prose against the gold target already present
in sample_pool.jsonl. Pure-Python, no API calls, no model downloads:

  - chrF      character-n-gram F-score (sacrebleu-style, n=6, β=2)
  - ROUGE-L   longest-common-subsequence F-score
  - num_match Jaccard on (value, unit) numeric tuples
  - cit_overlap Jaccard on ICH/EMA/FDA citation tokens

Aggregates into evaluation/results/multitask_crossjudge_v1/summary_reference_based.csv
so the reference-based scoreboard sits beside the existing cross-judge one.
Two-metric divergence (e.g. Haiku last on cross-judge, first on reference-
based) is the signal CLAUDE.md §'Model-flip discipline' demands before
flipping a production default.
"""
from __future__ import annotations
import json, re, statistics
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT_DIR = REPO / "evaluation" / "results" / "multitask_crossjudge_v1"
POOL = OUT_DIR / "sample_pool.jsonl"


# ─── chrF ──────────────────────────────────────────────────────────────────
def _char_ngrams(s: str, n: int) -> Counter:
    s = re.sub(r"\s+", " ", s.lower()).strip()
    return Counter(s[i : i + n] for i in range(max(0, len(s) - n + 1)))


def chrf(candidate: str, reference: str, n: int = 6, beta: float = 2.0) -> float:
    if not candidate.strip() or not reference.strip():
        return 0.0
    f_scores = []
    for k in range(1, n + 1):
        c, r = _char_ngrams(candidate, k), _char_ngrams(reference, k)
        if not c or not r:
            continue
        overlap = sum((c & r).values())
        p = overlap / max(sum(c.values()), 1)
        rc = overlap / max(sum(r.values()), 1)
        if p + rc == 0:
            f_scores.append(0.0)
        else:
            f_scores.append((1 + beta ** 2) * p * rc / (beta ** 2 * p + rc))
    return statistics.mean(f_scores) if f_scores else 0.0


# ─── ROUGE-L ───────────────────────────────────────────────────────────────
def _tokens(s: str) -> list[str]:
    return re.findall(r"\w+", s.lower())


def _lcs_len(a: list[str], b: list[str]) -> int:
    if not a or not b:
        return 0
    m, n = len(a), len(b)
    dp = [0] * (n + 1)
    for i in range(1, m + 1):
        prev = 0
        for j in range(1, n + 1):
            tmp = dp[j]
            if a[i - 1] == b[j - 1]:
                dp[j] = prev + 1
            else:
                dp[j] = max(dp[j], dp[j - 1])
            prev = tmp
    return dp[n]


def rouge_l(candidate: str, reference: str, beta: float = 1.2) -> float:
    a, b = _tokens(candidate), _tokens(reference)
    if not a or not b:
        return 0.0
    lcs = _lcs_len(a, b)
    if lcs == 0:
        return 0.0
    p = lcs / len(a)
    r = lcs / len(b)
    return (1 + beta ** 2) * p * r / (r + beta ** 2 * p)


# ─── Numeric-tuple Jaccard ─────────────────────────────────────────────────
_NUM_RE = re.compile(
    r"\b(\d+(?:\.\d+)?)\s*"
    r"(mg/kg(?:/day)?|µg/kg|ug/kg|ng/kg|mg|µg|ug|ng|kg|%|fold|×|x|"
    r"hours?|days?|weeks?|months?|years?|hr|h)\b",
    re.IGNORECASE,
)


def _num_tuples(s: str) -> set:
    out = set()
    for m in _NUM_RE.finditer(s):
        val = float(m.group(1))
        unit = m.group(2).lower().replace("µ", "u").rstrip("s")
        out.add((round(val, 1), unit))
    return out


def num_match(candidate: str, reference: str) -> float:
    c, r = _num_tuples(candidate), _num_tuples(reference)
    if not c and not r:
        return 1.0
    if not c or not r:
        return 0.0
    return len(c & r) / len(c | r)


# ─── Citation overlap ──────────────────────────────────────────────────────
_CIT_RE = re.compile(
    r"\b("
    r"ICH\s*[MQSE]\d+[A-Z]?(?:\([RS]?\d+\))?"
    r"|EMA/CHMP/[A-Z0-9/]+"
    r"|FDA\s+\d{4}"
    r"|21\s*CFR\s*\d+(?:\.\d+)*"
    r"|CDER|CBER|CDISC|GLP|GCP|GMP|NMPA|PMDA|MHRA|TGA"
    r")\b",
    re.IGNORECASE,
)


def _cits(s: str) -> set:
    return {re.sub(r"\s+", "", m.group(0).upper()) for m in _CIT_RE.finditer(s)}


def cit_overlap(candidate: str, reference: str) -> float:
    c, r = _cits(candidate), _cits(reference)
    if not c and not r:
        return 1.0
    if not c or not r:
        return 0.0
    return len(c & r) / len(c | r)


# ─── Driver ────────────────────────────────────────────────────────────────
def score_model_file(jsonl_path: Path, targets_by_id: dict[str, str]) -> list[dict]:
    rows = [json.loads(l) for l in jsonl_path.read_text().splitlines() if l.strip()]
    out = []
    for r in rows:
        ex_id = r["example_id"]
        tgt = targets_by_id.get(ex_id, "")
        if not tgt:
            continue
        cand = r.get("output", "") or ""
        scores = {
            "chrf": round(chrf(cand, tgt), 4),
            "rouge_l": round(rouge_l(cand, tgt), 4),
            "num_match": round(num_match(cand, tgt), 4),
            "cit_overlap": round(cit_overlap(cand, tgt), 4),
        }
        scores["ref_macro"] = round(statistics.mean(scores.values()), 4)
        out.append({"example_id": ex_id, "task": r.get("task"), **scores})
    return out


def bootstrap_ci(vals: list[float], n_boot: int = 1000, ci: float = 0.95) -> tuple[float, float]:
    import random
    if not vals:
        return 0.0, 0.0
    rng = random.Random(42)
    means = sorted(
        statistics.mean(rng.choices(vals, k=len(vals))) for _ in range(n_boot)
    )
    lo = means[int(((1 - ci) / 2) * n_boot)]
    hi = means[int((1 - (1 - ci) / 2) * n_boot)]
    return round(lo, 4), round(hi, 4)


def main() -> None:
    pool = [json.loads(l) for l in POOL.read_text().splitlines() if l.strip()]
    targets = {r["example_id"]: r.get("target", "") for r in pool}

    print(f"{'model':30s}  n  chrf   rouge_l  num    cit    macro      CI")
    print("-" * 90)
    summary = []
    for jsonl in sorted(OUT_DIR.glob("*.jsonl")):
        if jsonl.name == "sample_pool.jsonl":
            continue
        rows = score_model_file(jsonl, targets)
        if not rows:
            continue
        model = jsonl.stem
        agg = {k: statistics.mean(r[k] for r in rows)
               for k in ("chrf", "rouge_l", "num_match", "cit_overlap", "ref_macro")}
        lo, hi = bootstrap_ci([r["ref_macro"] for r in rows])
        summary.append({"model": model, "n": len(rows), **agg, "ci_lo": lo, "ci_hi": hi})
        print(f"{model:30s}  {len(rows):2d}  {agg['chrf']:.3f}  {agg['rouge_l']:.3f}    "
              f"{agg['num_match']:.3f}  {agg['cit_overlap']:.3f}  {agg['ref_macro']:.3f}  "
              f"[{lo:.3f},{hi:.3f}]")

    out_csv = OUT_DIR / "summary_reference_based.csv"
    with out_csv.open("w") as f:
        f.write("model,n,chrf,rouge_l,num_match,cit_overlap,ref_macro,ci_lo,ci_hi\n")
        for s in summary:
            f.write(f"{s['model']},{s['n']},{s['chrf']:.4f},{s['rouge_l']:.4f},"
                    f"{s['num_match']:.4f},{s['cit_overlap']:.4f},"
                    f"{s['ref_macro']:.4f},{s['ci_lo']:.4f},{s['ci_hi']:.4f}\n")
    print(f"\nwrote {out_csv}")


if __name__ == "__main__":
    main()
