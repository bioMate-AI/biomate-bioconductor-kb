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

    def save_one(self, run_id: str, result: BenchmarkResult) -> None:
        """Persist a single result immediately — use this for incremental saves."""
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO results (run_id, task_id, benchmark, score, latency_sec, "
                "error, agent_response, ground_truth, metadata_json, timestamp) "
                "VALUES (?,?,?,?,?,?,?,?,?,?)",
                (
                    run_id, result.task_id, result.benchmark, result.score,
                    result.latency_sec, result.error or "",
                    result.agent_response[:4000],
                    json.dumps(result.ground_truth)[:1000],
                    json.dumps(result.metadata),
                    result.timestamp,
                ),
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
                r.agent_response[:4000],   # cap storage
                _safe_json_truncate(r.ground_truth, 1000),
                json.dumps(r.metadata),
                r.timestamp,
            )
            for r in results
        ]
        with self._conn() as conn:
            conn.executemany(
                "INSERT INTO results (run_id, task_id, benchmark, score, latency_sec, "
                "error, agent_response, ground_truth, metadata_json, timestamp) "
                "VALUES (?,?,?,?,?,?,?,?,?,?)",
                rows,
            )

    # ------------------------------------------------------------------
    # Read
    # ------------------------------------------------------------------

    def load(self, run_id: str) -> List[BenchmarkResult]:
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT task_id, benchmark, score, agent_response, ground_truth, "
                "latency_sec, metadata_json, error, timestamp FROM results WHERE run_id=?",
                (run_id,),
            ).fetchall()
        return [
            BenchmarkResult(
                task_id=r[0], benchmark=r[1], score=r[2],
                agent_response=r[3], ground_truth=json.loads(r[4]),
                latency_sec=r[5], metadata=json.loads(r[6]),
                error=r[7] or None, timestamp=r[8],
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
                    timestamp REAL
                )
            """)
