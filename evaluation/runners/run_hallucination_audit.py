#!/usr/bin/env python3
"""
run_hallucination_audit.py
--------------------------
Post-hoc hallucination audit: loads stored responses from an eval DB,
runs HallucinationDetector on each, writes labels back to the DB.

Usage:
    cd /home/yzhang/biomate/evaluation
    python runners/run_hallucination_audit.py --db results/biomni_eval1_v20/eval_results.db
    python runners/run_hallucination_audit.py --all            # all results/ DBs
    python runners/run_hallucination_audit.py --dry-run --db results/biomni_eval1_v20/eval_results.db
    python runners/run_hallucination_audit.py --db results/labbench_v22/eval_results.db --run-id labbench_20260415_...

Output:
    Writes hallucination_label back to each result row.
    Prints summary: n_grounded, n_hallucinated, n_unverifiable, hallucination_rate.
"""
from __future__ import annotations

import argparse
import glob
import json
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent))

from core.hallucination_detector import HallucinationDetector

# Map benchmark/task_id prefix → step_type for the judge prompt
_STEP_TYPE_MAP = {
    "gwas_causal":       "gene_identification",
    "gwas_variant":      "gene_identification",
    "rare_disease":      "disease_identification",
    "patient_gene":      "ensg_lookup",
    "screen_gene":       "gene_identification",
    "CloningScenarios":  "mcq_rationale",
    "ProtocolQA":        "mcq_rationale",
    "LitQA2":            "mcq_rationale",
    "labbench":          "mcq_rationale",
    "sgi_bench":         "scientific_claim",
    "bixbench":          "scientific_claim",
    "routing":           "workflow_selection",
    "cross_domain":      "workflow_selection",
}


def _infer_step_type(task_id: str, benchmark: str) -> str:
    tid_lower = task_id.lower()
    for key, stype in _STEP_TYPE_MAP.items():
        if key.lower() in tid_lower or key.lower() in benchmark.lower():
            return stype
    return "scientific_claim"


# Cache of task_id → question loaded from adapters
_QUESTION_CACHE: dict = {}


def _load_question_cache() -> None:
    """Pre-load actual questions from benchmark adapters for accurate hallucination judging."""
    try:
        import yaml
        eval_dir = Path(__file__).parent.parent
        with open(eval_dir / "config.yaml") as f:
            config = yaml.safe_load(f)
        from evaluation.adapters.biomni_eval1_adapter import BiomniEval1Adapter
        for t in BiomniEval1Adapter(config).load_tasks():
            _QUESTION_CACHE[t.task_id] = t.question
        print(f"  [cache] Loaded {len(_QUESTION_CACHE)} BiomniEval1 questions")
    except Exception as e:
        print(f"  [cache warn] {e}")


def _get_question(task_id: str, agent_response: str, ground_truth: str) -> str:
    """Return actual question text from cache, or informative stub if unavailable."""
    if task_id in _QUESTION_CACHE:
        return _QUESTION_CACHE[task_id]
    # For routing tasks: construct from task_id structure
    if "routing" in task_id.lower() or "cross_domain" in task_id.lower():
        return f"User asked about a bioinformatics workflow. Task: {task_id}"
    return f"[Task: {task_id}] Ground truth: {str(ground_truth)[:100]}"


def audit_db(db_path: str, run_id: str | None, dry_run: bool, verbose: bool) -> dict:
    detector = HallucinationDetector()
    conn = sqlite3.connect(db_path)

    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
    if "results" not in tables:
        conn.close()
        return {"db": db_path, "skipped": True, "reason": "no results table"}

    # Ensure column exists
    existing = {r[1] for r in conn.execute("PRAGMA table_info(results)").fetchall()}
    if "hallucination_label" not in existing:
        conn.execute("ALTER TABLE results ADD COLUMN hallucination_label TEXT")
        conn.commit()

    # Fetch rows that need auditing
    query = (
        "SELECT id, task_id, benchmark, agent_response, ground_truth, score "
        "FROM results WHERE hallucination_label IS NULL AND agent_response IS NOT NULL "
        "AND LENGTH(agent_response) > 5"
    )
    if run_id:
        query += f" AND run_id='{run_id}'"

    rows = conn.execute(query).fetchall()
    conn.close()

    if not rows:
        return {"db": db_path, "rows_audited": 0, "reason": "all already labeled"}

    print(f"\n  Auditing {len(rows)} rows in {Path(db_path).parent.name}...")

    counts = {"grounded": 0, "hallucinated": 0, "unverifiable": 0}
    total_cost = 0.0

    for i, (row_id, task_id, benchmark, response, gt_json, score) in enumerate(rows):
        step_type = _infer_step_type(task_id, benchmark)
        try:
            gt = json.loads(gt_json) if gt_json else ""
            if isinstance(gt, str):
                try:
                    gt = json.loads(gt)
                except Exception:
                    pass
        except Exception:
            gt = gt_json or ""

        if verbose:
            print(f"  [{i+1:4d}/{len(rows)}] {step_type:25s} score={score:.2f}", end="", flush=True)

        question = _get_question(task_id, response, str(gt))
        result = detector.classify(
            response=response[:1500],
            question=question[:800],
            step_type=step_type,
            ground_truth=str(gt)[:300],
        )
        counts[result.label] = counts.get(result.label, 0) + 1
        total_cost += result.cost_usd

        if verbose:
            print(f" → {result.label} ({result.confidence:.2f})  {result.reason[:60]}")

        if not dry_run:
            conn2 = sqlite3.connect(db_path)
            conn2.execute("UPDATE results SET hallucination_label=? WHERE id=?",
                         (result.label, row_id))
            conn2.commit()
            conn2.close()

        time.sleep(0.05)

    assessable = counts["grounded"] + counts["hallucinated"]
    rate = counts["hallucinated"] / assessable if assessable > 0 else None

    summary = {
        "db": db_path,
        "rows_audited": len(rows),
        "n_grounded": counts["grounded"],
        "n_hallucinated": counts["hallucinated"],
        "n_unverifiable": counts["unverifiable"],
        "hallucination_rate": round(rate, 4) if rate is not None else None,
        "total_cost_usd": round(total_cost, 5),
        "dry_run": dry_run,
    }
    return summary


def main():
    # Pre-load actual question text so judge has real context (not stubs)
    print("Loading question cache from adapters...")
    _load_question_cache()
    parser = argparse.ArgumentParser(description="Post-hoc hallucination audit on eval result DBs")
    parser.add_argument("--db", default=None, help="Single DB path")
    parser.add_argument("--all", action="store_true", help="Audit all results/ DBs")
    parser.add_argument("--run-id", default=None, help="Limit to specific run_id")
    parser.add_argument("--dry-run", action="store_true", help="Classify but don't write to DB")
    parser.add_argument("--verbose", action="store_true", default=True)
    args = parser.parse_args()

    if args.all:
        base = Path(__file__).parent.parent / "results"
        dbs = sorted(glob.glob(str(base / "**/eval_results.db"), recursive=True))
        dbs = [d for d in dbs if "model_selection" not in d]
    elif args.db:
        dbs = [args.db]
    else:
        parser.error("Specify --db <path> or --all")

    print(f"{'[DRY RUN] ' if args.dry_run else ''}Auditing {len(dbs)} DB(s)\n")

    totals = {"rows": 0, "hallucinated": 0, "grounded": 0, "unverifiable": 0, "cost": 0.0}
    for db in dbs:
        result = audit_db(db, args.run_id, args.dry_run, args.verbose)
        if result.get("skipped"):
            print(f"  SKIP {db}: {result.get('reason')}")
            continue
        print(f"  {Path(db).parent.name:35s}  "
              f"n={result['rows_audited']:4d}  "
              f"hallucinated={result.get('n_hallucinated',0):4d}  "
              f"rate={result.get('hallucination_rate') or 'N/A'!s:6s}  "
              f"cost=${result.get('total_cost_usd',0):.4f}")
        totals["rows"]        += result.get("rows_audited", 0)
        totals["hallucinated"] += result.get("n_hallucinated", 0)
        totals["grounded"]     += result.get("n_grounded", 0)
        totals["unverifiable"] += result.get("n_unverifiable", 0)
        totals["cost"]         += result.get("total_cost_usd", 0)

    assessable = totals["grounded"] + totals["hallucinated"]
    overall_rate = totals["hallucinated"] / assessable if assessable > 0 else None
    print(f"\nTotal rows audited: {totals['rows']}")
    print(f"Overall hallucination rate: {overall_rate:.1%}" if overall_rate is not None else "Overall: no assessable rows")
    print(f"Total judge cost: ${totals['cost']:.4f}")
    if args.dry_run:
        print("(DRY RUN — no labels written)")


if __name__ == "__main__":
    main()
