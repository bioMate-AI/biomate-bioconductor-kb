#!/usr/bin/env python3
"""
run_target_structure_benchmark.py — B5 Target Structure Benchmark runner.

Evaluates BioMate's ability to route protein structure prediction queries,
identify druggable binding pockets, and detect missing-sequence prerequisites.

10 protein targets × 2 query types = 20 tasks.

Usage:
    # Dry-run: list tasks without running
    python runners/run_target_structure_benchmark.py --dry-run

    # Full 20-task run
    python runners/run_target_structure_benchmark.py --output results/target_structure_benchmark_v1/

    # Limit tasks
    python runners/run_target_structure_benchmark.py --max-tasks 10

Per-task display format:
    [TS-001 / complete   ] STRUCT=✓ POCKET=✓ score=1.00 (14s)
    [TS-001 / incomplete ] PREREQ=✓ score=1.00 (11s)
"""

from __future__ import annotations

import argparse
import statistics
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

# Ensure project root is on sys.path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import TargetStructureAdapter


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _check_server(base_url: str) -> bool:
    """Return True if the BioMate server responds at /health or /."""
    import requests
    for endpoint in ("/health", "/api/health", "/"):
        try:
            resp = requests.get(f"{base_url}{endpoint}", timeout=10)
            if resp.status_code < 500:
                return True
        except Exception:
            continue
    return False


def _format_task_line(
    idx: int,
    total: int,
    result,
    details: Dict[str, Any],
) -> str:
    """Format a single completed task result for stdout."""
    case_id  = result.metadata.get("case_id", result.task_id)
    name     = result.metadata.get("target_name", "")
    qtype    = result.metadata.get("query_type", "?")
    score    = result.score
    elapsed  = result.latency_sec
    err      = f" [ERR: {result.error[:50]}]" if result.error else ""

    qtype_display = qtype.ljust(10)
    prefix = f"  [{idx:>3}/{total}] [{case_id} {name:<16} / {qtype_display}]"

    if qtype == "complete":
        struct = "✓" if details.get("structure_routing") else "✗"
        pocket = "✓" if details.get("pocket_detected") else "✗"
        body = f"STRUCT={struct} POCKET={pocket} score={score:.2f} ({elapsed:.0f}s)"
    elif qtype == "incomplete":
        prereq = "✓" if details.get("prereq_asked") else "✗"
        body = f"PREREQ={prereq} score={score:.2f} ({elapsed:.0f}s)"
    else:
        body = f"score={score:.2f} ({elapsed:.0f}s)"

    return f"{prefix} {body}{err}"


def _mock_task(result):
    """Reconstruct a minimal BenchmarkTask-like object from a result's metadata."""
    from evaluation.core.base_adapter import BenchmarkTask
    return BenchmarkTask(
        task_id=result.task_id,
        question="",
        ground_truth={},
        metadata=result.metadata,
    )


def _compute_summary(
    results: List,
    adapter: TargetStructureAdapter,
) -> Dict[str, Any]:
    """Compute per-metric aggregates over all results."""
    complete_results   = [r for r in results if r.metadata.get("query_type") == "complete"]
    incomplete_results = [r for r in results if r.metadata.get("query_type") == "incomplete"]

    # Structure routing accuracy (complete queries)
    struct_correct = sum(
        1 for r in complete_results
        if adapter._has_structure_keyword(r.agent_response)
    )
    struct_total = max(1, len(complete_results))

    # Pocket detection accuracy (complete queries)
    pocket_correct = sum(
        1 for r in complete_results
        if adapter._has_pocket_keyword(r.agent_response)
    )
    pocket_total = max(1, len(complete_results))

    # Prereq detection (incomplete queries)
    prereq_correct = sum(
        1 for r in incomplete_results
        if adapter._asks_for_sequence(r.agent_response)
    )
    prereq_total = max(1, len(incomplete_results))

    # Latency
    latencies = [r.latency_sec for r in results if r.latency_sec > 0]
    mean_latency = statistics.mean(latencies) if latencies else 0.0
    latencies_sorted = sorted(latencies)
    p95_latency = (
        latencies_sorted[int(0.95 * len(latencies_sorted))]
        if latencies_sorted else 0.0
    )

    # Cost
    costs = [r.cost_usd for r in results if r.cost_usd is not None]
    total_cost = sum(costs)

    # Overall score
    all_scores = [r.score for r in results]
    mean_score = statistics.mean(all_scores) if all_scores else 0.0

    return {
        "mean_score":         mean_score,
        "struct_accuracy":    struct_correct / struct_total,
        "struct_correct":     struct_correct,
        "struct_total":       struct_total,
        "pocket_accuracy":    pocket_correct / pocket_total,
        "pocket_correct":     pocket_correct,
        "pocket_total":       pocket_total,
        "prereq_rate":        prereq_correct / prereq_total,
        "prereq_correct":     prereq_correct,
        "prereq_total":       prereq_total,
        "mean_latency":       mean_latency,
        "p95_latency":        p95_latency,
        "total_cost":         total_cost,
        "n_total":            len(results),
        "n_errors":           sum(1 for r in results if r.error),
        "n_complete":         len(complete_results),
        "n_incomplete":       len(incomplete_results),
    }


# ---------------------------------------------------------------------------
# Excel export
# ---------------------------------------------------------------------------

def _export_xlsx(
    results: List,
    summary: Dict[str, Any],
    output_dir: Path,
) -> Optional[Path]:
    """Generate eval_summary.xlsx with Summary and Per-Task sheets."""
    try:
        import openpyxl
        from openpyxl.styles import PatternFill, Font, Alignment
    except ImportError:
        print("  (openpyxl not available — skipping XLSX export)")
        return None

    GREEN  = PatternFill("solid", fgColor="C6EFCE")
    YELLOW = PatternFill("solid", fgColor="FFEB9C")
    RED    = PatternFill("solid", fgColor="FFC7CE")
    HEADER = PatternFill("solid", fgColor="4472C4")
    HEADER_FONT = Font(color="FFFFFF", bold=True)

    wb = openpyxl.Workbook()
    ws1 = wb.active
    ws1.title = "Summary"

    def _hdr(ws, row, col, val):
        cell = ws.cell(row=row, column=col, value=val)
        cell.fill = HEADER
        cell.font = HEADER_FONT
        cell.alignment = Alignment(horizontal="center")

    def _color_score(ws, row, col, val):
        cell = ws.cell(row=row, column=col, value=val)
        if isinstance(val, (int, float)) and 0.0 <= val <= 1.0:
            cell.fill = GREEN if val >= 0.9 else (YELLOW if val >= 0.6 else RED)
        return cell

    for ci, h in enumerate(["Metric", "Value", "Target", "Status"], 1):
        _hdr(ws1, 1, ci, h)

    summary_rows = [
        ("Benchmark",            "B5 Target Structure", "", ""),
        ("Dataset",              "10 protein targets × 2 query types", "", ""),
        ("Tasks (L1–L4)",        summary.get("n_total", 0), "", ""),
        ("  Complete queries",   summary.get("n_complete", 0), "", ""),
        ("  Incomplete queries", summary.get("n_incomplete", 0), "", ""),
        ("Errors",               summary.get("n_errors", 0), "", ""),
        ("",                     "", "", ""),
        ("Overall mean score",   round(summary.get("mean_score", 0), 3), "≥ 0.80",
         "✓" if summary.get("mean_score", 0) >= 0.80 else "✗"),
        ("Structure routing",    round(summary.get("struct_accuracy", 0), 3), "≥ 0.90",
         "✓" if summary.get("struct_accuracy", 0) >= 0.90 else "✗"),
        ("Pocket detection",     round(summary.get("pocket_accuracy", 0), 3), "≥ 0.80",
         "✓" if summary.get("pocket_accuracy", 0) >= 0.80 else "✗"),
        ("Prereq detection",     round(summary.get("prereq_rate", 0), 3), "≥ 0.90",
         "✓" if summary.get("prereq_rate", 0) >= 0.90 else "✗"),
        ("",                     "", "", ""),
        ("Mean latency (s)",     round(summary.get("mean_latency", 0), 1), "", ""),
        ("p95 latency (s)",      round(summary.get("p95_latency", 0), 1), "", ""),
        ("Total cost ($)",       round(summary.get("total_cost", 0), 4), "", ""),
    ]

    for ri, (metric, val, target, status) in enumerate(summary_rows, 2):
        ws1.cell(row=ri, column=1, value=metric)
        if isinstance(val, float) and 0.0 <= val <= 1.0 and metric:
            _color_score(ws1, ri, 2, val)
        else:
            ws1.cell(row=ri, column=2, value=val)
        ws1.cell(row=ri, column=3, value=target)
        ws1.cell(row=ri, column=4, value=status)

    ws1.column_dimensions["A"].width = 28
    ws1.column_dimensions["B"].width = 40
    ws1.column_dimensions["C"].width = 12
    ws1.column_dimensions["D"].width = 8

    # Per-Task sheet
    ws2 = wb.create_sheet("Per-Task")
    task_headers = [
        "Task ID", "Case ID", "Target", "Query Type",
        "Score", "Struct Routing", "Pocket Hit", "Prereq Asked",
        "Latency (s)", "Error", "Response Preview",
    ]
    for ci, h in enumerate(task_headers, 1):
        _hdr(ws2, 1, ci, h)

    adapter = TargetStructureAdapter({})
    for ri, r in enumerate(sorted(results, key=lambda x: x.task_id), 2):
        case_id  = r.metadata.get("case_id", "")
        target   = r.metadata.get("target_name", "")
        qtype    = r.metadata.get("query_type", "")
        preview  = r.agent_response[:120].replace("\n", " ") if r.agent_response else ""
        task     = _mock_task(r)
        details  = adapter.score_detailed(task, r.agent_response)

        ws2.cell(row=ri, column=1, value=r.task_id)
        ws2.cell(row=ri, column=2, value=case_id)
        ws2.cell(row=ri, column=3, value=target)
        ws2.cell(row=ri, column=4, value=qtype)
        _color_score(ws2, ri, 5, round(r.score, 3))
        ws2.cell(row=ri, column=6, value=str(details.get("structure_routing", "")))
        ws2.cell(row=ri, column=7, value=str(details.get("pocket_detected", "")))
        ws2.cell(row=ri, column=8, value=str(details.get("prereq_asked", "")))
        ws2.cell(row=ri, column=9, value=round(r.latency_sec, 1))
        ws2.cell(row=ri, column=10, value=r.error or "")
        ws2.cell(row=ri, column=11, value=preview)

    for col, width in zip("ABCDEFGHIJK", [28, 10, 16, 12, 8, 14, 12, 14, 12, 20, 60]):
        ws2.column_dimensions[col].width = width

    xlsx_path = output_dir / "eval_summary.xlsx"
    wb.save(xlsx_path)
    return xlsx_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="B5 Target Structure Benchmark runner"
    )
    parser.add_argument(
        "--output", default="results/target_structure_benchmark_v1/",
        help="Output directory (default: results/target_structure_benchmark_v1/)"
    )
    parser.add_argument(
        "--config", default="config.yaml",
        help="Path to evaluation config YAML (default: config.yaml)"
    )
    parser.add_argument(
        "--max-tasks", type=int, default=None,
        help="Limit number of tasks to run (default: all 20)"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="List tasks without running them"
    )
    parser.add_argument(
        "--workers", type=int, default=None,
        help="Override max_parallel_tasks from config"
    )
    parser.add_argument(
        "--no-xlsx", action="store_true",
        help="Skip Excel export"
    )
    args = parser.parse_args()

    # ---- Load config --------------------------------------------------------
    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    if args.workers:
        config.setdefault("concurrency", {})["max_parallel_tasks"] = args.workers

    # ---- Build adapter + tasks ----------------------------------------------
    adapter = TargetStructureAdapter(config)
    tasks = adapter.load_tasks()

    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"Target Structure Benchmark — {len(tasks)} tasks would run:\n")
        by_type: Dict[str, int] = {}
        for t in tasks:
            qt = t.metadata.get("query_type", "?")
            by_type[qt] = by_type.get(qt, 0) + 1
            name = t.metadata.get("target_name", "?")
            print(f"  [{t.task_id}] {qt:<12} target={name}")
        print(f"\n  By query type: {by_type}")
        return

    # ---- Server health check ------------------------------------------------
    base_url = config["biomate"]["base_url"]
    print(f"Checking BioMate server at {base_url}...", end=" ", flush=True)
    server_up = _check_server(base_url)
    if not server_up:
        print("DOWN")
        print(f"\nWARNING: BioMate server is not reachable at {base_url}.")
        print("Code build complete. Skipping execution — start server and re-run.")
        return
    print("UP")

    print(f"\nTarget Structure Benchmark — L1-L4")
    print(f"  Tasks:       {len(tasks)} ({len(tasks) // 2} targets × 2 query types)")
    print(f"  Output:      {args.output}")
    print(f"  Concurrency: {config.get('concurrency', {}).get('max_parallel_tasks', 16)}")
    print()

    client = BioMateEvalClient.from_config(config)
    store  = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run(
        "target_structure_benchmark", suite="L1L4", config=config
    )

    completed = [0]
    all_results: List = []

    def _on_result(r) -> None:
        store.save_one(run_id, r)
        completed[0] += 1
        details = adapter.score_detailed(_mock_task(r), r.agent_response)
        line = _format_task_line(completed[0], len(tasks), r, details)
        print(line, flush=True)
        all_results.append(r)

    t0 = time.time()
    results = adapter.run_tasks(client, tasks, on_result=_on_result)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    # ---- Summary ------------------------------------------------------------
    summary = _compute_summary(results, adapter)

    print(f"\n{'='*65}")
    print(f"Target Structure Benchmark — L1-L4 Results")
    print(f"{'='*65}")
    print(f"  Tasks:                  {summary['n_total']}  ({summary['n_errors']} errors)")
    print(f"  Overall mean score:     {summary['mean_score']:.3f}  (target ≥ 0.80)")
    print(f"  Structure routing:      "
          f"{summary['struct_correct']}/{summary['struct_total']} "
          f"({summary['struct_accuracy']:.1%})  (target ≥ 0.90)")
    print(f"  Pocket detection:       "
          f"{summary['pocket_correct']}/{summary['pocket_total']} "
          f"({summary['pocket_accuracy']:.1%})  (target ≥ 0.80)")
    print(f"  Prereq detection:       "
          f"{summary['prereq_correct']}/{summary['prereq_total']} "
          f"({summary['prereq_rate']:.1%})  (target ≥ 0.90)")
    print(f"  Mean latency:           {summary['mean_latency']:.0f}s  "
          f"(p95={summary['p95_latency']:.0f}s)")
    print(f"  Total cost:             ${summary['total_cost']:.4f}")
    if summary['n_total'] > 0:
        print(f"  Cost/task:              "
              f"${summary['total_cost'] / summary['n_total']:.5f}")
    print(f"  Elapsed:                {elapsed:.0f}s")
    print(f"\n  Results DB:             {config['paths']['results_db']}")

    # ---- Excel export -------------------------------------------------------
    if not args.no_xlsx:
        xlsx_path = _export_xlsx(results, summary, output_dir)
        if xlsx_path:
            print(f"  Excel export:           {xlsx_path}")

    print()


if __name__ == "__main__":
    main()
