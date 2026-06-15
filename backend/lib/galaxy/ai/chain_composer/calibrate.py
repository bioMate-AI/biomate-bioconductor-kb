"""Offline calibration driver for the chain composer.

Reads a JSONL of representative queries and runs the composer on each
(stub path by default so it's free; opt into LLM via `--use-llm`).
Aggregates:

- per-query: actual mode vs expected, top pattern hit vs expected,
  per-signal contribution.
- aggregate: mode distribution, per-pattern hit-rate, confidence
  histogram, signal medians.

Output: JSON report on stdout (or `--output` path) + a short summary
table on stderr. Used to tune the surfacing-mode thresholds without
LLM cost.

Usage:
    python -m galaxy.ai.chain_composer.calibrate eval_queries.jsonl
    python -m galaxy.ai.chain_composer.calibrate eval_queries.jsonl --output report.json
    python -m galaxy.ai.chain_composer.calibrate eval_queries.jsonl --use-llm
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path
from typing import Any, Dict, List

from .composer import compose_chain
from .llm_adapter import default_llm


def _load_jsonl(path: Path) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError as exc:
            sys.stderr.write(f"skip line {i}: {exc}\n")
    return out


def _histogram(values: List[float], bins: List[float]) -> List[int]:
    """Return counts of `values` falling in each `[bins[i], bins[i+1])` interval."""
    counts = [0] * (len(bins) - 1)
    for v in values:
        for i in range(len(bins) - 1):
            lo, hi = bins[i], bins[i + 1]
            if lo <= v < hi or (i == len(bins) - 2 and v <= hi):
                counts[i] += 1
                break
    return counts


def run(
    queries: List[Dict[str, Any]],
    *,
    use_llm: bool = False,
) -> Dict[str, Any]:
    llm = default_llm() if use_llm else None
    per_query: List[Dict[str, Any]] = []
    for q in queries:
        result = compose_chain(q["query"], llm=llm)
        signals = result.signals
        per_query.append({
            "query": q["query"],
            "expected_pattern": q.get("expect_pattern"),
            "expected_mode": q.get("expect_mode"),
            "actual_mode": result.surfacing_mode,
            "confidence": round(result.confidence, 3),
            "source": result.source,
            "top_pattern": result.patterns_used[0] if result.patterns_used else None,
            "top_pattern_in_top_k": (
                q.get("expect_pattern") in result.patterns_used
                if q.get("expect_pattern") else None
            ),
            "step_count": len(result.steps),
            "signals": {
                k: signals.get(k)
                for k in (
                    "normalized_chain_score",
                    "normalized_pattern_score",
                    "query_specificity",
                    "downstream_determinism",
                    "pattern_chain_agreement",
                    "user_signal",
                )
            },
            "note": q.get("note"),
        })

    confs = [r["confidence"] for r in per_query]
    modes = [r["actual_mode"] for r in per_query]
    mode_match = [
        r for r in per_query
        if r["expected_mode"] is None or r["actual_mode"] == r["expected_mode"]
    ]
    pattern_match = [
        r for r in per_query
        if r["expected_pattern"] is None or r["top_pattern_in_top_k"]
    ]

    aggregate = {
        "n_queries": len(per_query),
        "n_with_llm": sum(1 for r in per_query if r["source"] in {"llm", "llm_revised"}),
        "n_curated_passthrough": sum(1 for r in per_query if r["source"] == "curated_passthrough"),
        "n_stub": sum(1 for r in per_query if r["source"] == "stub"),
        "mode_distribution": {m: modes.count(m) for m in ("upfront", "stepwise", "reactive")},
        "mode_match_rate": round(len(mode_match) / max(1, len(per_query)), 3),
        "pattern_top_k_hit_rate": round(len(pattern_match) / max(1, len(per_query)), 3),
        "confidence": {
            "min": round(min(confs), 3) if confs else None,
            "median": round(statistics.median(confs), 3) if confs else None,
            "max": round(max(confs), 3) if confs else None,
            "histogram_bins": [0.0, 0.2, 0.45, 0.6, 0.75, 0.9, 1.001],
            "histogram_counts": _histogram(confs, [0.0, 0.2, 0.45, 0.6, 0.75, 0.9, 1.001]),
        },
        "signal_medians": _signal_medians(per_query),
    }

    return {"aggregate": aggregate, "per_query": per_query}


def _signal_medians(per_query: List[Dict[str, Any]]) -> Dict[str, float]:
    out: Dict[str, float] = {}
    keys = (
        "normalized_chain_score",
        "normalized_pattern_score",
        "query_specificity",
        "downstream_determinism",
        "pattern_chain_agreement",
    )
    for k in keys:
        vals = [r["signals"].get(k) for r in per_query if r["signals"].get(k) is not None]
        if vals:
            out[k] = round(statistics.median(vals), 3)
    return out


def _summary_table(report: Dict[str, Any]) -> str:
    agg = report["aggregate"]
    lines = [
        f"queries={agg['n_queries']}  llm={agg['n_with_llm']}  curated={agg['n_curated_passthrough']}  stub={agg['n_stub']}",
        f"mode_distribution: {agg['mode_distribution']}",
        f"mode_match_rate:   {agg['mode_match_rate']:.2%}",
        f"pattern_top_k_hit: {agg['pattern_top_k_hit_rate']:.2%}",
        f"confidence: min={agg['confidence']['min']} median={agg['confidence']['median']} max={agg['confidence']['max']}",
        f"histogram (bins {agg['confidence']['histogram_bins']}): {agg['confidence']['histogram_counts']}",
        f"signal medians: {agg['signal_medians']}",
        "",
        "per-query mismatches (mode or pattern):",
    ]
    for r in report["per_query"]:
        mode_ok = r["expected_mode"] is None or r["actual_mode"] == r["expected_mode"]
        pat_ok = r["expected_pattern"] is None or r["top_pattern_in_top_k"]
        if not (mode_ok and pat_ok):
            lines.append(
                f"  - mode: {r['expected_mode']!r}→{r['actual_mode']!r}  "
                f"pattern: expected={r['expected_pattern']!r} got_top={r['top_pattern']!r}  "
                f"conf={r['confidence']}  q={r['query'][:60]!r}"
            )
    return "\n".join(lines)


def _cli(argv=None) -> int:
    p = argparse.ArgumentParser(prog="chain_composer.calibrate", description=__doc__)
    p.add_argument("jsonl", help="path to eval queries JSONL")
    p.add_argument("--output", default=None, help="write report JSON here (default: stdout)")
    p.add_argument("--use-llm", action="store_true", help="use real LLM (default: stub-only, no API cost)")
    args = p.parse_args(argv)

    queries = _load_jsonl(Path(args.jsonl))
    report = run(queries, use_llm=args.use_llm)

    sys.stderr.write(_summary_table(report) + "\n")
    out = json.dumps(report, indent=2)
    if args.output:
        Path(args.output).write_text(out, encoding="utf-8")
    else:
        sys.stdout.write(out + "\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli(sys.argv[1:]))
