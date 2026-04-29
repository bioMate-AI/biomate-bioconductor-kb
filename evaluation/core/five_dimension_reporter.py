"""
five_dimension_reporter.py
--------------------------
Unified 5-dimension evaluation reporter for BioMate benchmarks.

Dimensions (per Evaluation Framework v1):
  D1  Performance   — accuracy score, CI, pass rate
  D2  Stability     — cross-run consistency (flip rate, score std)
  D3  Time          — latency per query (mean, median, p95)
  D4  Cost          — API cost per query and per benchmark
  D5  Hallucination — rate and type breakdown (A/B/C/D)

Usage:
    from evaluation.core.five_dimension_reporter import FiveDimensionReporter
    from evaluation.core.results_store import ResultsStore

    store = ResultsStore()
    reporter = FiveDimensionReporter(store)

    # After a run:
    report = reporter.compute(run_id="routing_20260429_120000")
    print(reporter.render_table([report]))

    # Full 5D run (includes stability + hallucination detection):
    report = reporter.run_full(
        adapter=routing_adapter,
        tasks=tasks,
        client=biomate_client,
        n_stability_repeats=3,
        hallucination_sample_frac=0.3,  # 30% of failed responses
    )
"""
from __future__ import annotations

import math
import statistics
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

from .results_store import ResultsStore
from .base_adapter import BenchmarkResult


# ---------------------------------------------------------------------------
# Hallucination type taxonomy
# ---------------------------------------------------------------------------

HALLUCINATION_TYPES = {
    "A": "Entity fabrication (invented gene/tool/compound/paper)",
    "B": "Numerical error (wrong value, wrong unit, counting error)",
    "C": "False confidence (wrong answer stated without uncertainty)",
    "D": "Format/instruction failure (right answer, wrong format)",
}

# Mapping from detector step_type → primary hallucination type
_STEP_TYPE_TO_HTYPE = {
    "gene_identification":   "A",
    "disease_identification":"A",
    "ensg_lookup":           "A",
    "workflow_selection":    "A",
    "scientific_claim":      "B",
    "findings_report":       "B",
    "mcq_rationale":         "C",
}


@dataclass
class DimensionPerformance:
    n: int
    n_pass: int                    # score >= 0.5
    mean_score: float
    std_score: float
    ci95_low: float
    ci95_high: float
    pass_rate: float               # n_pass / n

    def as_dict(self) -> dict:
        return {
            "n": self.n, "n_pass": self.n_pass,
            "mean_score": round(self.mean_score, 4),
            "std_score": round(self.std_score, 4),
            "ci95": [round(self.ci95_low, 4), round(self.ci95_high, 4)],
            "pass_rate": round(self.pass_rate, 4),
        }


@dataclass
class DimensionStability:
    n_tasks_sampled: int
    n_repeats: int
    consistency_rate: float        # fraction of tasks consistent across all repeats
    flip_rate: float               # fraction that changed correct↔incorrect ≥ once
    mean_score_std: float          # mean per-task std across repeats
    available: bool = True         # False if only 1 run exists

    def as_dict(self) -> dict:
        if not self.available:
            return {"available": False, "note": "Only 1 run — repeat to measure stability"}
        return {
            "n_tasks_sampled": self.n_tasks_sampled,
            "n_repeats": self.n_repeats,
            "consistency_rate": round(self.consistency_rate, 4),
            "flip_rate": round(self.flip_rate, 4),
            "mean_score_std": round(self.mean_score_std, 4),
        }


@dataclass
class DimensionTime:
    n: int
    mean_latency_sec: float
    median_latency_sec: float
    p95_latency_sec: float
    total_time_sec: float

    def as_dict(self) -> dict:
        return {
            "n": self.n,
            "mean_sec": round(self.mean_latency_sec, 2),
            "median_sec": round(self.median_latency_sec, 2),
            "p95_sec": round(self.p95_latency_sec, 2),
            "total_sec": round(self.total_time_sec, 1),
        }


@dataclass
class DimensionCost:
    n: int
    n_with_cost: int                 # how many results had cost_usd != NULL
    total_cost_usd: float            # LLM API cost only (sum of non-NULL cost_usd)
    cost_per_query_usd: float        # LLM API cost per query (0 if none tracked)
    total_input_tokens: int
    total_output_tokens: int
    cost_per_1k_tasks_usd: float
    # Production costs (AWS Batch — populated when workflow actually ran)
    batch_cpu_usd: float = 0.0       # vCPU-hour cost
    batch_gpu_usd: float = 0.0       # GPU-hour cost (g4dn/p3 instances)
    s3_storage_usd: float = 0.0      # S3 storage/transfer cost
    network_usd: float = 0.0         # data egress cost

    @property
    def total_production_usd(self) -> float:
        return self.total_cost_usd + self.batch_cpu_usd + self.batch_gpu_usd + self.s3_storage_usd + self.network_usd

    def as_dict(self) -> dict:
        return {
            "n": self.n,
            "llm_total_usd": round(self.total_cost_usd, 6),
            "llm_per_query_usd": round(self.cost_per_query_usd, 6),
            "llm_per_1k_tasks_usd": round(self.cost_per_1k_tasks_usd, 4),
            "total_input_tokens": self.total_input_tokens,
            "total_output_tokens": self.total_output_tokens,
            "batch_cpu_usd": round(self.batch_cpu_usd, 4),
            "batch_gpu_usd": round(self.batch_gpu_usd, 4),
            "s3_storage_usd": round(self.s3_storage_usd, 6),
            "network_usd": round(self.network_usd, 4),
            "total_production_usd": round(self.total_production_usd, 4),
        }

    def cost_str(self) -> str:
        """Human-readable per-query cost: scientific notation for sub-cent; '?' if not tracked."""
        if self.n_with_cost == 0:
            return "?"           # cost not recorded in DB for this run
        c = self.cost_per_query_usd
        if c == 0:
            return "$0"
        if c < 0.0001:
            return f"${c:.2e}"   # e.g. $3.56e-05
        if c < 0.01:
            return f"${c:.5f}"   # e.g. $0.00355
        return f"${c:.4f}"


@dataclass
class DimensionHallucination:
    n_assessed: int
    n_hallucinated: int
    n_grounded: int
    n_unverifiable: int
    hallucination_rate: float      # n_hallucinated / (n_grounded + n_hallucinated)
    type_counts: Dict[str, int]    # A/B/C/D counts
    type_rates: Dict[str, float]
    available: bool = True

    def as_dict(self) -> dict:
        if not self.available:
            return {"available": False, "note": "Run with --hallucination to classify"}
        return {
            "n_assessed": self.n_assessed,
            "n_hallucinated": self.n_hallucinated,
            "hallucination_rate": round(self.hallucination_rate, 4),
            "type_counts": self.type_counts,
            "type_rates": {k: round(v, 4) for k, v in self.type_rates.items()},
        }


@dataclass
class FiveDimensionReport:
    run_id: str
    benchmark: str
    model: str
    timestamp: str
    performance: DimensionPerformance
    stability: DimensionStability
    time: DimensionTime
    cost: DimensionCost
    hallucination: DimensionHallucination

    def as_dict(self) -> dict:
        return {
            "run_id": self.run_id,
            "benchmark": self.benchmark,
            "model": self.model,
            "timestamp": self.timestamp,
            "D1_performance": self.performance.as_dict(),
            "D2_stability": self.stability.as_dict(),
            "D3_time": self.time.as_dict(),
            "D4_cost": self.cost.as_dict(),
            "D5_hallucination": self.hallucination.as_dict(),
        }

    def one_line(self) -> str:
        p = self.performance
        h = self.hallucination
        s = self.stability
        t = self.time
        c = self.cost
        hrate = f"{h.hallucination_rate*100:.1f}%" if h.available else "?"
        flip  = f"{s.flip_rate*100:.1f}%" if s.available else "?"
        return (
            f"{self.benchmark:35s} | "
            f"score={p.mean_score*100:.1f}% (n={p.n}) | "
            f"stable={flip} flip | "
            f"lat={t.mean_latency_sec:.1f}s | "
            f"cost={c.cost_str()}/q (LLM only) | "
            f"halluc={hrate}"
        )


# ---------------------------------------------------------------------------
# Reporter
# ---------------------------------------------------------------------------

class FiveDimensionReporter:
    """Compute 5-dimension reports from stored benchmark results."""

    def __init__(self, store: ResultsStore):
        self.store = store

    def compute(
        self,
        run_id: str,
        stability_run_ids: Optional[List[str]] = None,
    ) -> FiveDimensionReport:
        """
        Compute all 5 dimensions from the DB for a completed run.

        stability_run_ids: list of additional run_ids for the same benchmark
                           (to compute cross-run stability). If None, D2 = unavailable.
        """
        results = self.store.load(run_id)
        if not results:
            raise ValueError(f"No results found for run_id={run_id!r}")

        benchmark = results[0].benchmark
        model     = results[0].model or "unknown"
        timestamp = results[0].timestamp or ""

        # D1 — Performance
        d1 = _compute_performance(results)

        # D2 — Stability (cross-run)
        if stability_run_ids:
            all_runs = [results] + [self.store.load(rid) for rid in stability_run_ids]
            d2 = _compute_stability_cross_run(all_runs)
        else:
            d2 = DimensionStability(0, 1, 1.0, 0.0, 0.0, available=False)

        # D3 — Time
        d3 = _compute_time(results)

        # D4 — Cost
        d4 = _compute_cost(results)

        # D5 — Hallucination (from DB labels if they exist)
        d5 = _compute_hallucination_from_labels(results)

        return FiveDimensionReport(
            run_id=run_id, benchmark=benchmark, model=model,
            timestamp=timestamp, performance=d1, stability=d2,
            time=d3, cost=d4, hallucination=d5,
        )

    def label_hallucinations(
        self,
        run_id: str,
        step_type: str = "scientific_claim",
        sample_failed_only: bool = True,
        max_n: int = 50,
    ) -> Dict[str, Any]:
        """
        Run HallucinationDetector on stored results and write labels back to DB.
        Returns summary dict.
        """
        try:
            from .hallucination_detector import HallucinationDetector
        except ImportError:
            return {"error": "HallucinationDetector not available"}

        results = self.store.load(run_id)
        if sample_failed_only:
            to_label = [r for r in results if r.score < 0.5]
        else:
            to_label = results
        to_label = to_label[:max_n]

        if not to_label:
            return {"n_labeled": 0, "note": "No responses to label"}

        detector = HallucinationDetector()
        items = [
            {
                "response": r.agent_response,
                "question": r.ground_truth.get("query", "") if isinstance(r.ground_truth, dict) else str(r.ground_truth),
                "step_type": step_type,
                "ground_truth": r.ground_truth.get("expected", "") if isinstance(r.ground_truth, dict) else "",
            }
            for r in to_label
        ]
        report = detector.batch_classify(items)

        # Write labels back
        with self.store._conn() as conn:
            for result, det_result in zip(to_label, report.results):
                conn.execute(
                    "UPDATE results SET hallucination_label=? WHERE run_id=? AND task_id=?",
                    (det_result.label, run_id, result.task_id),
                )

        return report.summary_dict()

    def render_table(self, reports: List[FiveDimensionReport]) -> str:
        """Render a compact ASCII table of all 5 dimensions across multiple reports."""
        lines = [
            "",
            "=" * 120,
            "BioMate Evaluation — 5-Dimension Report",
            "=" * 120,
            f"{'Benchmark':<35} {'D1 Perf':>10} {'D2 Stab':>9} {'D3 Time':>9} {'D4 Cost':>11} {'D5 Halluc':>11}",
            f"{'':35} {'score/CI':>10} {'flip%':>9} {'lat(s)':>9} {'LLM$/q':>11} {'rate%':>11}",
            "-" * 120,
        ]
        for r in reports:
            p  = r.performance
            s  = r.stability
            t  = r.time
            c  = r.cost
            h  = r.hallucination
            score_ci = f"{p.mean_score*100:.1f}±{(p.ci95_high-p.mean_score)*100:.1f}%"
            flip  = f"{s.flip_rate*100:.1f}%" if s.available else "—"
            lat   = f"{t.mean_latency_sec:.1f}" if t.n > 0 else "—"
            cost  = c.cost_str()
            hrate = f"{h.hallucination_rate*100:.1f}%" if h.available else "—"
            lines.append(
                f"{r.benchmark:<35} {score_ci:>10} {flip:>9} {lat:>9} {cost:>11} {hrate:>11}"
            )
        lines += [
            "=" * 120,
            "D1=Performance(mean±95%CI) D2=Stability(flip_rate across runs) "
            "D3=Time(mean latency/query) D4=Cost(LLM API only — add Batch vCPU/GPU/S3/network for production) "
            "D5=Hallucination(rate on failed responses)",
            "",
        ]
        return "\n".join(lines)

    def render_hallucination_breakdown(self, reports: List[FiveDimensionReport]) -> str:
        """Render hallucination type breakdown table."""
        lines = [
            "",
            "Hallucination Type Breakdown",
            "-" * 90,
            f"{'Benchmark':<35} {'TypeA':>7} {'TypeB':>7} {'TypeC':>7} {'TypeD':>7} {'Total':>7} {'Rate':>8}",
            f"{'':35} {'entity':>7} {'number':>7} {'confid':>7} {'format':>7} {'hallucd':>7} {'%':>8}",
            "-" * 90,
        ]
        for r in reports:
            h = r.hallucination
            if not h.available:
                lines.append(f"{r.benchmark:<35} {'—':>7} {'—':>7} {'—':>7} {'—':>7} {'—':>7} {'—':>8}")
                continue
            tc = h.type_counts
            lines.append(
                f"{r.benchmark:<35} "
                f"{tc.get('A',0):>7} "
                f"{tc.get('B',0):>7} "
                f"{tc.get('C',0):>7} "
                f"{tc.get('D',0):>7} "
                f"{h.n_hallucinated:>7} "
                f"{h.hallucination_rate*100:>7.1f}%"
            )
        lines.append("-" * 90)
        return "\n".join(lines)


# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

def _compute_performance(results: List[BenchmarkResult]) -> DimensionPerformance:
    scores = [r.score for r in results if r.score is not None]
    n = len(scores)
    if n == 0:
        return DimensionPerformance(0, 0, 0.0, 0.0, 0.0, 0.0, 0.0)
    mean = statistics.mean(scores)
    std  = statistics.stdev(scores) if n > 1 else 0.0
    # Wilson 95% CI for proportions (use mean as p estimate)
    z = 1.96
    margin = z * math.sqrt(mean * (1 - mean) / n) if n > 0 else 0.0
    n_pass = sum(1 for s in scores if s >= 0.5)
    return DimensionPerformance(
        n=n, n_pass=n_pass, mean_score=mean, std_score=std,
        ci95_low=max(0.0, mean - margin), ci95_high=min(1.0, mean + margin),
        pass_rate=n_pass / n,
    )


def _compute_stability_cross_run(
    all_runs: List[List[BenchmarkResult]],
) -> DimensionStability:
    """Compute stability from multiple runs of the same benchmark.

    Each run may itself contain multiple repeats of the same task (e.g., n_repeats=3).
    We first average scores within each run per task, then compare across runs.
    """
    if len(all_runs) < 2:
        return DimensionStability(0, 1, 1.0, 0.0, 0.0, available=False)

    # Build per-run mean-score maps: {task_id: mean_score_in_this_run}
    run_maps: List[Dict[str, float]] = []
    for run in all_runs:
        task_scores: Dict[str, List[float]] = {}
        for r in run:
            task_scores.setdefault(r.task_id, []).append(r.score)
        run_maps.append({tid: sum(s)/len(s) for tid, s in task_scores.items()})

    # Only consider tasks present in all runs
    all_task_ids = set(run_maps[0].keys())
    for rm in run_maps[1:]:
        all_task_ids &= set(rm.keys())
    complete = {
        tid: [rm[tid] for rm in run_maps]
        for tid in all_task_ids
    }
    n = len(complete)
    if n == 0:
        return DimensionStability(0, len(all_runs), 1.0, 0.0, 0.0, available=False)

    flip_count = 0
    std_sum = 0.0
    consistent_count = 0
    for scores in complete.values():
        buckets = [s >= 0.5 for s in scores]
        if all(b == buckets[0] for b in buckets):
            consistent_count += 1
        else:
            flip_count += 1
        if len(scores) > 1:
            std_sum += statistics.stdev(scores)

    return DimensionStability(
        n_tasks_sampled=n,
        n_repeats=len(all_runs),
        consistency_rate=consistent_count / n,
        flip_rate=flip_count / n,
        mean_score_std=std_sum / n,
        available=True,
    )


def _compute_time(results: List[BenchmarkResult]) -> DimensionTime:
    latencies = [r.latency_sec for r in results
                 if r.latency_sec is not None and r.latency_sec > 0]
    if not latencies:
        return DimensionTime(len(results), 0.0, 0.0, 0.0, 0.0)
    latencies_sorted = sorted(latencies)
    p95_idx = max(0, int(len(latencies_sorted) * 0.95) - 1)
    return DimensionTime(
        n=len(latencies),
        mean_latency_sec=statistics.mean(latencies),
        median_latency_sec=statistics.median(latencies),
        p95_latency_sec=latencies_sorted[p95_idx],
        total_time_sec=sum(latencies),
    )


def _compute_cost(results: List[BenchmarkResult]) -> DimensionCost:
    costs   = [r.cost_usd       for r in results if r.cost_usd       is not None]
    in_tok  = [r.input_tokens   for r in results if r.input_tokens   is not None]
    out_tok = [r.output_tokens  for r in results if r.output_tokens  is not None]
    total   = sum(costs)
    n       = len(results)
    n_with  = len(costs)
    # cost_per_query is only meaningful when we have cost data
    cpq     = total / n_with if n_with > 0 else 0.0
    return DimensionCost(
        n=n,
        n_with_cost=n_with,
        total_cost_usd=total,
        cost_per_query_usd=cpq,
        total_input_tokens=sum(in_tok),
        total_output_tokens=sum(out_tok),
        cost_per_1k_tasks_usd=(cpq * 1000) if n_with > 0 else 0.0,
    )


def _compute_hallucination_from_labels(
    results: List[BenchmarkResult],
) -> DimensionHallucination:
    """Read hallucination_label from DB metadata if stored."""
    # The label is stored per result in the metadata JSON under 'hallucination_label'
    # OR in a separate column that we pass through via a custom load.
    # Check for it in metadata dict.
    labeled = []
    for r in results:
        meta = r.metadata if isinstance(r.metadata, dict) else {}
        lbl = meta.get("hallucination_label")
        if lbl:
            labeled.append(lbl)

    if not labeled:
        return DimensionHallucination(
            n_assessed=0, n_hallucinated=0, n_grounded=0, n_unverifiable=0,
            hallucination_rate=0.0, type_counts={}, type_rates={},
            available=False,
        )

    n_h = sum(1 for l in labeled if l == "hallucinated")
    n_g = sum(1 for l in labeled if l == "grounded")
    n_u = sum(1 for l in labeled if l == "unverifiable")
    assessable = n_h + n_g
    # Type breakdown from metadata
    type_counts: Dict[str, int] = {"A": 0, "B": 0, "C": 0, "D": 0}
    for r in results:
        meta = r.metadata if isinstance(r.metadata, dict) else {}
        htype = meta.get("hallucination_type")
        if htype in type_counts:
            type_counts[htype] += 1

    total_typed = sum(type_counts.values()) or 1
    type_rates = {k: v / total_typed for k, v in type_counts.items()}

    return DimensionHallucination(
        n_assessed=len(labeled),
        n_hallucinated=n_h, n_grounded=n_g, n_unverifiable=n_u,
        hallucination_rate=n_h / assessable if assessable > 0 else 0.0,
        type_counts=type_counts, type_rates=type_rates,
        available=True,
    )


# ---------------------------------------------------------------------------
# Quick standalone report from results DB
# ---------------------------------------------------------------------------

def report_from_db(
    db_path: str = "evaluation/results/eval_results.db",
    benchmarks: Optional[List[str]] = None,
    latest_only: bool = True,
) -> List[FiveDimensionReport]:
    """
    Generate 5D reports for all (or specified) benchmarks from the DB.

    Args:
        db_path: path to eval_results.db
        benchmarks: filter to these benchmarks; None = all
        latest_only: if True, use only the most recent run per benchmark
    """
    import sqlite3
    conn = sqlite3.connect(db_path)
    if benchmarks:
        placeholders = ",".join("?" * len(benchmarks))
        rows = conn.execute(
            f"SELECT run_id, benchmark, started_at FROM runs "
            f"WHERE benchmark IN ({placeholders}) ORDER BY started_at DESC",
            benchmarks,
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT run_id, benchmark, started_at FROM runs ORDER BY started_at DESC"
        ).fetchall()
    conn.close()

    seen: set = set()
    run_ids: List[str] = []
    for run_id, bench, _ in rows:
        if latest_only and bench in seen:
            continue
        seen.add(bench)
        run_ids.append(run_id)

    store = ResultsStore(db_path)
    reports = []
    for rid in run_ids:
        try:
            reporter = FiveDimensionReporter(store)
            reports.append(reporter.compute(rid))
        except Exception:
            pass
    return reports
