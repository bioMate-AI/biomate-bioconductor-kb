#!/usr/bin/env python3
"""
backfill_costs.py
-----------------
Estimates LLM cost for historical eval runs that predate token-count tracking.

Method:
  - input_tokens  ≈ len(agent_response) / 4  (chars → tokens proxy, rough)
  - output_tokens ≈ len(agent_response) / 4
  - model         = 'claude-sonnet-4-6' (assumed for all historical runs)
  - cost_usd      = computed from pricing table

All backfilled values are ESTIMATES. They are tagged with model='claude-sonnet-4-6 (backfill)'
so they can be distinguished from real measurements.

Usage:
    python evaluation/scripts/backfill_costs.py
    python evaluation/scripts/backfill_costs.py --dry-run
    python evaluation/scripts/backfill_costs.py --db evaluation/results/labbench_v22/eval_results.db
"""
from __future__ import annotations
import argparse
import glob
import sqlite3
from pathlib import Path

PRICING = {
    "claude-sonnet-4-6": {"input_per_1m": 3.00, "output_per_1m": 15.00},
}
DEFAULT_MODEL = "claude-sonnet-4-6"
BACKFILL_TAG = f"{DEFAULT_MODEL} (backfill)"


def estimate_tokens(text: str) -> int:
    """Rough chars/4 heuristic — acceptable for order-of-magnitude cost estimates."""
    return max(1, len(text) // 4)


def backfill_db(db_path: str, dry_run: bool) -> dict:
    conn = sqlite3.connect(db_path)
    # Ensure columns exist (migration)
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
    if "results" not in tables:
        conn.close()
        return {"db": db_path, "rows_updated": 0, "est_total_cost_usd": 0.0}
    existing = {r[1] for r in conn.execute("PRAGMA table_info(results)").fetchall()}
    for col, typedef in [("input_tokens","INTEGER"), ("output_tokens","INTEGER"),
                         ("cost_usd","REAL"), ("model","TEXT")]:
        if col not in existing:
            conn.execute(f"ALTER TABLE results ADD COLUMN {col} {typedef}")
    conn.commit()

    rows = conn.execute(
        "SELECT id, agent_response FROM results WHERE cost_usd IS NULL AND agent_response IS NOT NULL"
    ).fetchall()

    updated = 0
    total_cost = 0.0
    p = PRICING[DEFAULT_MODEL]
    for row_id, response in rows:
        out_tok = estimate_tokens(response or "")
        in_tok  = out_tok // 2  # conservative: input ≈ half output length
        cost    = (in_tok * p["input_per_1m"] + out_tok * p["output_per_1m"]) / 1_000_000
        if not dry_run:
            conn.execute(
                "UPDATE results SET input_tokens=?, output_tokens=?, cost_usd=?, model=? WHERE id=?",
                (in_tok, out_tok, round(cost, 8), BACKFILL_TAG, row_id),
            )
        updated += 1
        total_cost += cost

    if not dry_run:
        conn.commit()
    conn.close()
    return {"db": db_path, "rows_updated": updated, "est_total_cost_usd": round(total_cost, 4)}


def main():
    parser = argparse.ArgumentParser(description="Backfill cost estimates for historical eval DBs")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be updated, don't write")
    parser.add_argument("--db", default=None, help="Single DB path (default: all results/**/eval_results.db)")
    args = parser.parse_args()

    if args.db:
        dbs = [args.db]
    else:
        base = Path(__file__).parent.parent / "results"
        dbs = sorted(glob.glob(str(base / "**/eval_results.db"), recursive=True))

    print(f"{'DRY RUN — ' if args.dry_run else ''}Backfilling {len(dbs)} eval DB(s)\n")
    grand_total = 0.0
    for db in dbs:
        result = backfill_db(db, args.dry_run)
        print(f"  {result['db']}")
        print(f"    rows: {result['rows_updated']}  est_cost: ${result['est_total_cost_usd']:.4f}")
        grand_total += result['est_total_cost_usd']
    print(f"\nEstimated total historical eval cost: ${grand_total:.4f}")
    if args.dry_run:
        print("(DRY RUN — no changes written)")


if __name__ == "__main__":
    main()
