#!/usr/bin/env python3
"""
training_data_extractor.py — BioMate LLM Fine-Tuning Data Pipeline

Joins project_episodes + execution_runs + ux_feedback tables to produce
JSONL training examples for:
  1. Full dialogue fine-tuning  → evaluation/outputs/training_data_YYYYMMDD.jsonl
  2. Routing-only pair fine-tuning → evaluation/outputs/routing_pairs_YYYYMMDD.jsonl

DB connection: reads DATABASE_URL env var (PostgreSQL). Falls back to reading
from the Galaxy SQLite DB when DATABASE_URL is not set (limited data).

Usage:
    python evaluation/training_data_extractor.py --dry-run
    python evaluation/training_data_extractor.py --output path.jsonl --min-quality 0.7
    python evaluation/training_data_extractor.py --outcome completed --limit 500
"""

import os
import sys
import json
import argparse
import datetime
from pathlib import Path
from collections import defaultdict
from typing import Optional

OUTPUT_DIR = Path(__file__).parent / "outputs"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
TODAY = datetime.date.today().strftime("%Y%m%d")


def _connect_postgres(database_url: str):
    try:
        import psycopg2
        import psycopg2.extras
        conn = psycopg2.connect(database_url)
        conn.cursor_factory = psycopg2.extras.RealDictCursor
        return conn, "postgres"
    except ImportError:
        print("psycopg2 not installed — pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)


def _connect_sqlite(sqlite_path: str):
    import sqlite3
    conn = sqlite3.connect(sqlite_path)
    conn.row_factory = sqlite3.Row
    return conn, "sqlite"


def get_db_connection():
    database_url = os.environ.get("DATABASE_URL", "")
    if database_url:
        print(f"Connecting to PostgreSQL ({database_url[:40]}...)")
        return _connect_postgres(database_url)
    candidate_paths = [
        os.path.expanduser("~/biomate/backend/universe.sqlite"),
        os.path.expanduser("~/biomate/backend/database/universe.sqlite"),
        "/home/yzhang/biomate/backend/universe.sqlite",
        "/home/yzhang/biomate/backend/database/universe.sqlite",
    ]
    for p in candidate_paths:
        if os.path.exists(p):
            print(f"Connecting to SQLite fallback: {p}")
            return _connect_sqlite(p)
    print("ERROR: No database found. Set DATABASE_URL or ensure Galaxy SQLite DB exists.", file=sys.stderr)
    sys.exit(1)


def fetch_episodes(conn, dialect: str, outcome: str, limit: Optional[int]) -> list:
    if dialect == "postgres":
        sql = """
            SELECT pe.id, pe.user_query, pe.assistant_response, pe.user_intent,
                   pe.workflow_generated, pe.parameters_set, pe.outcome_success,
                   pe.what_worked, pe.what_failed, pe.lessons_learned,
                   pe.created_at, pe.session_id, pe.project_id,
                   w.name AS workflow_name, w.domain AS domain
            FROM project_episodes pe
            LEFT JOIN workflows w ON w.id = pe.workflow_id
            WHERE pe.user_query IS NOT NULL
              AND pe.assistant_response IS NOT NULL
              AND pe.workflow_generated = TRUE
        """
        if outcome == "completed":
            sql += " AND pe.outcome_success = TRUE"
        sql += " ORDER BY pe.created_at DESC"
        if limit:
            sql += f" LIMIT {int(limit)}"
    else:
        sql = """
            SELECT pe.id, pe.user_query, pe.assistant_response, pe.outcome_success,
                   pe.created_at, pe.session_id, pe.workflow_generated,
                   NULL AS workflow_name, NULL AS domain, NULL AS parameters_set,
                   NULL AS what_worked, NULL AS what_failed, NULL AS lessons_learned
            FROM project_episodes pe
            WHERE pe.user_query IS NOT NULL AND pe.workflow_generated = 1
        """
        if outcome == "completed":
            sql += " AND pe.outcome_success = 1"
        sql += " ORDER BY pe.created_at DESC"
        if limit:
            sql += f" LIMIT {int(limit)}"
    cur = conn.cursor()
    try:
        cur.execute(sql)
        return [dict(r) for r in cur.fetchall()]
    except Exception as e:
        print(f"WARNING: Could not fetch episodes: {e}", file=sys.stderr)
        return []


def fetch_execution_runs_by_sessions(conn, dialect: str, session_ids: list) -> dict:
    if not session_ids:
        return {}
    placeholders = ",".join(["%s"] * len(session_ids)) if dialect == "postgres" else ",".join(["?"] * len(session_ids))
    sql = f"""
        SELECT chat_session_id, workflow_name, status, parameters, metrics, created_at
        FROM execution_runs
        WHERE chat_session_id IN ({placeholders})
        ORDER BY created_at DESC
    """
    cur = conn.cursor()
    try:
        cur.execute(sql, session_ids)
        runs = {}
        for row in [dict(r) for r in cur.fetchall()]:
            sid = str(row.get("chat_session_id", ""))
            if sid not in runs:
                runs[sid] = row
        return runs
    except Exception as e:
        print(f"WARNING: Could not fetch execution_runs: {e}", file=sys.stderr)
        return {}


def fetch_ux_feedback_by_sessions(conn, dialect: str, session_ids: list) -> dict:
    if not session_ids:
        return {}
    placeholders = ",".join(["%s"] * len(session_ids)) if dialect == "postgres" else ",".join(["?"] * len(session_ids))
    sql = f"""
        SELECT session_id, status_clarity_score, output_usefulness_score, output_actionability_score
        FROM ux_feedback WHERE session_id IN ({placeholders})
    """
    cur = conn.cursor()
    try:
        cur.execute(sql, session_ids)
        feedback = {}
        for row in [dict(r) for r in cur.fetchall()]:
            sid = str(row.get("session_id", ""))
            scores = [row.get("status_clarity_score"), row.get("output_usefulness_score"), row.get("output_actionability_score")]
            valid = [s for s in scores if s is not None]
            feedback[sid] = sum(valid) / len(valid) if valid else None
        return feedback
    except Exception as e:
        print(f"WARNING: Could not fetch ux_feedback: {e}", file=sys.stderr)
        return {}


def _extract_quality_score(metrics_str) -> Optional[float]:
    if not metrics_str:
        return None
    try:
        m = json.loads(metrics_str) if isinstance(metrics_str, str) else metrics_str
        for path in [["quality", "overall"], ["quality", "score"], ["qc", "score"], ["quality"]]:
            val = m
            for key in path:
                val = val.get(key) if isinstance(val, dict) else None
            if isinstance(val, (int, float)):
                return float(val)
        return None
    except Exception:
        return None


def build_full_example(episode: dict, run: Optional[dict], ux_score: Optional[float], min_quality: float) -> Optional[dict]:
    quality = _extract_quality_score(run.get("metrics") if run else None)
    if quality is not None and quality < min_quality:
        return None
    user_content = (episode.get("user_query") or "").strip()
    if not user_content:
        return None
    assistant_content = (episode.get("assistant_response") or "").strip()
    if not assistant_content and run:
        assistant_content = f"Running {run.get('workflow_name', 'workflow')} with the specified parameters."
    params_summary = None
    if run and run.get("parameters"):
        try:
            p = json.loads(run["parameters"]) if isinstance(run["parameters"], str) else run["parameters"]
            params_summary = {k: v for k, v in (p.get("current", p) or {}).items() if not k.startswith("_")}
        except Exception:
            pass
    return {
        "messages": [
            {"role": "user", "content": user_content},
            {"role": "assistant", "content": assistant_content},
        ],
        "metadata": {
            "workflow": episode.get("workflow_name") or (run.get("workflow_name") if run else None),
            "domain": episode.get("domain"),
            "outcome": run.get("status") if run else ("completed" if episode.get("outcome_success") else "failed"),
            "outcome_success": bool(episode.get("outcome_success")),
            "quality_score": quality,
            "what_worked": episode.get("what_worked"),
            "what_failed": episode.get("what_failed"),
            "lessons_learned": episode.get("lessons_learned"),
            "ux_feedback_score": ux_score,
            "parameters": params_summary,
            "session_id": str(episode.get("session_id", "")),
            "created_at": str(episode.get("created_at", ""))[:10],
        },
    }


def build_routing_pair(episode: dict) -> Optional[dict]:
    query = (episode.get("user_query") or "").strip()
    workflow = episode.get("workflow_name")
    if not query or not workflow:
        return None
    return {"query": query, "workflow": workflow, "domain": episode.get("domain")}


def extract(dry_run: bool, output_path: Optional[str], min_quality: float, outcome: str, limit: Optional[int]):
    conn, dialect = get_db_connection()
    print(f"\n{'='*60}")
    print(f"BioMate Training Data Extractor — {TODAY}")
    print(f"{'='*60}")
    print(f"  Mode:        {'DRY RUN (no files written)' if dry_run else 'WRITING'}")
    print(f"  Outcome:     {outcome}  |  Min quality: {min_quality}  |  Limit: {limit or 'all'}\n")

    episodes = fetch_episodes(conn, dialect, outcome, limit)
    print(f"Episodes found:                  {len(episodes)}")
    if not episodes:
        print("No episodes found. Check DB connection and data.")
        return

    session_ids = [str(e["session_id"]) for e in episodes if e.get("session_id")]
    runs_by_session = fetch_execution_runs_by_sessions(conn, dialect, session_ids)
    ux_by_session = fetch_ux_feedback_by_sessions(conn, dialect, session_ids)
    print(f"Episodes with linked exec run:   {sum(1 for e in episodes if str(e.get('session_id','')) in runs_by_session)}")
    print(f"Episodes with UX feedback:       {sum(1 for e in episodes if str(e.get('session_id','')) in ux_by_session)}")

    full_examples, routing_pairs = [], []
    skipped_quality = 0
    domain_counts: dict = defaultdict(int)
    quality_scores = []

    for ep in episodes:
        sid = str(ep.get("session_id", ""))
        run = runs_by_session.get(sid)
        ux = ux_by_session.get(sid)
        pair = build_routing_pair(ep)
        if pair:
            routing_pairs.append(pair)
        ex = build_full_example(ep, run, ux, min_quality)
        if ex is None:
            skipped_quality += 1
            continue
        full_examples.append(ex)
        domain_counts[ex["metadata"].get("domain") or "unknown"] += 1
        if ex["metadata"]["quality_score"] is not None:
            quality_scores.append(ex["metadata"]["quality_score"])

    print(f"\nFull training examples:          {len(full_examples)}")
    print(f"Routing pairs:                   {len(routing_pairs)}")
    print(f"Skipped (quality < {min_quality}): {skipped_quality}")
    if quality_scores:
        print(f"Quality:  min={min(quality_scores):.3f}  avg={sum(quality_scores)/len(quality_scores):.3f}  max={max(quality_scores):.3f}")
    if domain_counts:
        print("\nExamples by domain:")
        for d, n in sorted(domain_counts.items(), key=lambda x: -x[1]):
            print(f"  {d:<30} {n}")

    if dry_run:
        print(f"\n[DRY RUN] Would write {len(full_examples)} full examples and {len(routing_pairs)} routing pairs.")
        return

    full_path = Path(output_path) if output_path else OUTPUT_DIR / f"training_data_{TODAY}.jsonl"
    routing_path = OUTPUT_DIR / f"routing_pairs_{TODAY}.jsonl"
    with open(full_path, "w", encoding="utf-8") as f:
        for ex in full_examples:
            f.write(json.dumps(ex, ensure_ascii=False, default=str) + "\n")
    with open(routing_path, "w", encoding="utf-8") as f:
        for pair in routing_pairs:
            f.write(json.dumps(pair, ensure_ascii=False, default=str) + "\n")
    print(f"\nWrote {len(full_examples)} full examples → {full_path}")
    print(f"Wrote {len(routing_pairs)} routing pairs  → {routing_path}")


def main():
    parser = argparse.ArgumentParser(description="BioMate training data extractor")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--output", type=str, default=None)
    parser.add_argument("--min-quality", type=float, default=0.0)
    parser.add_argument("--outcome", type=str, default="all", choices=["all", "completed"])
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()
    extract(dry_run=args.dry_run, output_path=args.output, min_quality=args.min_quality, outcome=args.outcome, limit=args.limit)


if __name__ == "__main__":
    main()
