"""
results_store.py
----------------
SQLite-backed persistence for benchmark results.

Schema:
  runs(run_id, benchmark, suite, git_commit, started_at, finished_at, config_hash)
  results(id, run_id, task_id, benchmark, score, latency_sec, error, agent_response,
          ground_truth, metadata_json, timestamp)

Provides:
  - save(run_id, results)
  - load(run_id) -> List[BenchmarkResult]
  - summary(run_id) -> dict with mean/std/n per benchmark
  - competitive_table() -> DataFrame comparing all runs
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
import statistics
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base_adapter import BenchmarkResult


def _safe_json_truncate(obj: Any, max_len: int) -> str:
    """Serialize obj to JSON string, truncating at a clean JSON boundary if too long."""
    s = json.dumps(obj)
    if len(s) <= max_len:
        return s
    # Truncate to a string that is still valid JSON — store as a short string sentinel
    return json.dumps(str(obj)[:max_len])


class ResultsStore:
    """SQLite-backed store for benchmark results."""

    def __init__(self, db_path: str = "results/eval_results.db"):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    # ------------------------------------------------------------------
    # Write
    # ------------------------------------------------------------------

    def start_run(self, benchmark: str, suite: str,
                  config: Dict[str, Any], git_commit: str = "") -> str:
        """Register a new evaluation run; return run_id."""
        run_id = f"{benchmark}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        config_hash = hashlib.md5(json.dumps(config, sort_keys=True).encode()).hexdigest()[:8]
        with self._conn() as conn:
            conn.execute(
                "INSERT OR IGNORE INTO runs VALUES (?,?,?,?,?,?,?)",
                (run_id, benchmark, suite, git_commit,
                 datetime.now().isoformat(), None, config_hash),
            )
        return run_id

    def finish_run(self, run_id: str) -> None:
        with self._conn() as conn:
            conn.execute(
                "UPDATE runs SET finished_at=? WHERE run_id=?",
                (datetime.now().isoformat(), run_id),
            )

    def save_one(self, run_id: str, result: BenchmarkResult,
                 hallucination_label: Optional[str] = None,
                 repeat_id: int = 0) -> None:
        """Persist a single result immediately — use this for incremental saves."""
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO results (run_id, task_id, benchmark, score, latency_sec, "
                "error, agent_response, ground_truth, metadata_json, timestamp, "
                "input_tokens, output_tokens, cost_usd, model, hallucination_label, repeat_id) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (
                    run_id, result.task_id, result.benchmark, result.score,
                    result.latency_sec, result.error or "",
                    result.agent_response[:4000],
                    json.dumps(result.ground_truth)[:1000],
                    json.dumps(result.metadata),
                    result.timestamp,
                    result.input_tokens,
                    result.output_tokens,
                    result.cost_usd,
                    result.model,
                    hallucination_label,
                    repeat_id,
                ),
            )

    def update_hallucination_label(self, row_id: int, label: str) -> None:
        """Write hallucination label back to an existing result row."""
        with self._conn() as conn:
            conn.execute(
                "UPDATE results SET hallucination_label=? WHERE id=?",
                (label, row_id),
            )

    def save(self, run_id: str, results: List[BenchmarkResult]) -> None:
        rows = [
            (
                run_id,
                r.task_id,
                r.benchmark,
                r.score,
                r.latency_sec,
                r.error or "",
                r.agent_response[:4000],
                _safe_json_truncate(r.ground_truth, 1000),
                json.dumps(r.metadata),
                r.timestamp,
                r.input_tokens,
                r.output_tokens,
                r.cost_usd,
                r.model,
                None,  # hallucination_label
                0,     # repeat_id
            )
            for r in results
        ]
        with self._conn() as conn:
            conn.executemany(
                "INSERT INTO results (run_id, task_id, benchmark, score, latency_sec, "
                "error, agent_response, ground_truth, metadata_json, timestamp, "
                "input_tokens, output_tokens, cost_usd, model, hallucination_label, repeat_id) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                rows,
            )

    # ------------------------------------------------------------------
    # Read
    # ------------------------------------------------------------------

    def load(self, run_id: str) -> List[BenchmarkResult]:
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT task_id, benchmark, score, agent_response, ground_truth, "
                "latency_sec, metadata_json, error, timestamp, "
                "input_tokens, output_tokens, cost_usd, model FROM results WHERE run_id=?",
                (run_id,),
            ).fetchall()
        return [
            BenchmarkResult(
                task_id=r[0], benchmark=r[1], score=r[2],
                agent_response=r[3], ground_truth=json.loads(r[4]),
                latency_sec=r[5], metadata=json.loads(r[6]),
                error=r[7] or None, timestamp=r[8],
                input_tokens=r[9], output_tokens=r[10],
                cost_usd=r[11], model=r[12],
            )
            for r in rows
        ]

    def summary(self, run_id: str) -> Dict[str, Any]:
        """Return per-benchmark mean score, std, n, error_rate."""
        results = self.load(run_id)
        by_bench: Dict[str, List[float]] = {}
        errors: Dict[str, int] = {}
        for r in results:
            by_bench.setdefault(r.benchmark, []).append(r.score)
            if r.error:
                errors[r.benchmark] = errors.get(r.benchmark, 0) + 1

        summary = {}
        for bench, scores in by_bench.items():
            summary[bench] = {
                "n": len(scores),
                "mean": statistics.mean(scores),
                "std": statistics.stdev(scores) if len(scores) > 1 else 0.0,
                "error_count": errors.get(bench, 0),
            }
        return summary

    def all_run_summaries(self) -> List[Dict[str, Any]]:
        """Return a list of {run_id, benchmark, suite, mean_score, n, finished_at}."""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT r.run_id, r.benchmark, r.suite, r.finished_at, "
                "AVG(res.score) as mean_score, COUNT(res.id) as n "
                "FROM runs r JOIN results res ON r.run_id = res.run_id "
                "GROUP BY r.run_id",
            ).fetchall()
        return [
            {"run_id": r[0], "benchmark": r[1], "suite": r[2],
             "finished_at": r[3], "mean_score": round(r[4], 4), "n": r[5]}
            for r in rows
        ]

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def cost_summary(self, run_id: str) -> Dict[str, Any]:
        """Return cost/token/latency aggregates for a run, grouped by benchmark.

        Returns dict keyed by benchmark name with keys:
            n, total_cost_usd, mean_cost_usd, total_input_tokens, total_output_tokens,
            mean_latency_sec, tasks_with_cost (how many had token data recorded)
        """
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT benchmark, COUNT(*) as n, "
                "SUM(COALESCE(cost_usd, 0)) as total_cost, "
                "AVG(CASE WHEN cost_usd IS NOT NULL THEN cost_usd END) as mean_cost, "
                "SUM(COALESCE(input_tokens, 0)) as total_in, "
                "SUM(COALESCE(output_tokens, 0)) as total_out, "
                "AVG(latency_sec) as mean_lat, "
                "COUNT(cost_usd) as n_with_cost "
                "FROM results WHERE run_id=? GROUP BY benchmark",
                (run_id,),
            ).fetchall()
        result = {}
        for r in rows:
            bench, n, total_cost, mean_cost, total_in, total_out, mean_lat, n_with_cost = r
            result[bench] = {
                "n": n,
                "total_cost_usd": round(total_cost or 0.0, 6),
                "mean_cost_usd":  round(mean_cost or 0.0, 6) if mean_cost else None,
                "total_input_tokens":  int(total_in or 0),
                "total_output_tokens": int(total_out or 0),
                "mean_latency_sec":    round(mean_lat or 0.0, 2),
                "tasks_with_cost": int(n_with_cost),
            }
        return result

    def time_summary(self, run_id: str) -> Dict[str, Any]:
        """Return latency stats (mean, std, p50, p95) per benchmark for a run."""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT benchmark, latency_sec FROM results "
                "WHERE run_id=? AND latency_sec IS NOT NULL AND latency_sec > 0",
                (run_id,),
            ).fetchall()
        by_bench: Dict[str, List[float]] = {}
        for bench, lat in rows:
            by_bench.setdefault(bench, []).append(lat)
        result = {}
        for bench, lats in by_bench.items():
            lats_sorted = sorted(lats)
            n = len(lats)
            mean = sum(lats) / n
            std  = (sum((l - mean) ** 2 for l in lats) / max(n - 1, 1)) ** 0.5
            p50  = lats_sorted[n // 2]
            p95  = lats_sorted[int(0.95 * n)]
            result[bench] = {
                "n": n,
                "mean_latency_sec": round(mean, 2),
                "std_latency_sec":  round(std, 2),
                "p50_latency_sec":  round(p50, 2),
                "p95_latency_sec":  round(p95, 2),
                "min_latency_sec":  round(lats_sorted[0], 2),
                "max_latency_sec":  round(lats_sorted[-1], 2),
            }
        return result

    def hallucination_summary(self, run_id: str) -> Dict[str, Any]:
        """Return hallucination label counts and rate per benchmark for a run."""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT benchmark, hallucination_label, COUNT(*) "
                "FROM results WHERE run_id=? AND hallucination_label IS NOT NULL "
                "GROUP BY benchmark, hallucination_label",
                (run_id,),
            ).fetchall()
        by_bench: Dict[str, Dict[str, int]] = {}
        for bench, label, cnt in rows:
            by_bench.setdefault(bench, {})[label or "null"] = cnt
        result = {}
        for bench, counts in by_bench.items():
            grounded     = counts.get("grounded", 0)
            hallucinated = counts.get("hallucinated", 0)
            unverifiable = counts.get("unverifiable", 0)
            assessable   = grounded + hallucinated
            rate         = hallucinated / assessable if assessable > 0 else None
            result[bench] = {
                "n_grounded":     grounded,
                "n_hallucinated": hallucinated,
                "n_unverifiable": unverifiable,
                "n_assessable":   assessable,
                "hallucination_rate": round(rate, 4) if rate is not None else None,
            }
        return result

    def stability_summary(self, run_id: str) -> Dict[str, Any]:
        """Return consistency stats for stability runs (repeat_id > 0) in this DB."""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT task_id, repeat_id, score FROM results "
                "WHERE run_id LIKE ? ORDER BY task_id, repeat_id",
                (f"{run_id}%",),
            ).fetchall()
        by_task: Dict[str, List[float]] = {}
        for task_id, repeat_id, score in rows:
            by_task.setdefault(task_id, []).append(score or 0.0)
        if not by_task:
            return {}
        n_consistent = sum(
            1 for scores in by_task.values()
            if len(set(s >= 0.5 for s in scores)) == 1
        )
        n_tasks = len(by_task)
        all_stds = []
        for scores in by_task.values():
            if len(scores) > 1:
                mean = sum(scores) / len(scores)
                std  = (sum((s - mean) ** 2 for s in scores) / (len(scores) - 1)) ** 0.5
                all_stds.append(std)
        return {
            "n_tasks":          n_tasks,
            "consistency_rate": round(n_consistent / n_tasks, 4) if n_tasks else None,
            "flip_rate":        round(1 - n_consistent / n_tasks, 4) if n_tasks else None,
            "mean_score_std":   round(sum(all_stds) / len(all_stds), 4) if all_stds else None,
        }

    def _conn(self) -> sqlite3.Connection:
        return sqlite3.connect(self.db_path)

    def _init_db(self) -> None:
        with self._conn() as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS runs (
                    run_id TEXT PRIMARY KEY,
                    benchmark TEXT,
                    suite TEXT,
                    git_commit TEXT,
                    started_at TEXT,
                    finished_at TEXT,
                    config_hash TEXT
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS results (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_id TEXT,
                    task_id TEXT,
                    benchmark TEXT,
                    score REAL,
                    latency_sec REAL,
                    error TEXT,
                    agent_response TEXT,
                    ground_truth TEXT,
                    metadata_json TEXT,
                    timestamp REAL,
                    input_tokens INTEGER,
                    output_tokens INTEGER,
                    cost_usd REAL,
                    model TEXT
                )
            """)
            # Migrate existing DBs incrementally
            existing = {r[1] for r in conn.execute("PRAGMA table_info(results)").fetchall()}
            for col, typedef in [
                ("input_tokens",       "INTEGER"),
                ("output_tokens",      "INTEGER"),
                ("cost_usd",           "REAL"),
                ("model",              "TEXT"),
                ("hallucination_label","TEXT"),    # grounded|hallucinated|unverifiable|null
                ("repeat_id",          "INTEGER"), # 0=original, 1,2,...=stability repeats
            ]:
                if col not in existing:
                    conn.execute(f"ALTER TABLE results ADD COLUMN {col} {typedef}")
