#!/usr/bin/env python3
"""
run_boin_benchmark.py — B4 BOIN Clinical Trial Design Benchmark runner.

Tests the full chain: NL intent → workflow routing → parameter extraction
→ prerequisite detection (L1–L4) and optionally output validity (L5–L6).

Usage:
    # Dry-run: list tasks without running
    python runners/run_boin_benchmark.py --dry-run

    # L1–L4 evaluation, limited to 20 tasks
    python runners/run_boin_benchmark.py --layers L1L4 --max-tasks 20

    # Full 60-task L1–L4 run
    python runners/run_boin_benchmark.py --layers L1L4

    # L5–L6 output validity from a completed Nextflow run directory
    python runners/run_boin_benchmark.py --layers L5L6 \\
        --run-output-dir /path/to/nextflow/outputs/

Per-task display format:
    [CT-001 / complete         ] ROUTED=✓ PARAMS=✓ score=1.00 (16s)
    [CT-005 / incomplete       ] PREREQ=✓ score=1.00 (11s)
    [CT-007 / negative_control ] ROUTING=✓ (correctly NOT boin) score=1.00 (9s)
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
from evaluation.adapters import BOINClinicalBenchmarkAdapter


# ---------------------------------------------------------------------------
# Runner helpers
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
    qtype    = result.metadata.get("query_type", "?")
    score    = result.score
    elapsed  = result.latency_sec
    err      = f" [ERR: {result.error[:50]}]" if result.error else ""

    qtype_display = {
        "complete":          "complete        ",
        "incomplete":        "incomplete      ",
        "negative_control":  "negative_control",
    }.get(qtype, qtype.ljust(16))

    prefix = f"  [{idx:>3}/{total}] [{case_id} / {qtype_display}]"

    if qtype == "complete":
        routed = "✓" if details.get("routed_ok") else "✗"
        params = "✓" if details.get("params_ok") else "✗"
        body = f"ROUTED={routed} PARAMS={params} score={score:.2f} ({elapsed:.0f}s)"
    elif qtype == "incomplete":
        prereq = "✓" if details.get("prereq_asked") else "✗"
        body = f"PREREQ={prereq} score={score:.2f} ({elapsed:.0f}s)"
    elif qtype == "negative_control":
        ok = "✓" if not details.get("routed_to_boin") else "✗"
        body = f"ROUTING={ok} (correctly NOT boin) score={score:.2f} ({elapsed:.0f}s)"
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
    adapter: BOINClinicalBenchmarkAdapter,
) -> Dict[str, Any]:
    """Compute per-metric aggregates over all results."""
    by_qtype: Dict[str, List] = {
        "complete":          [],
        "incomplete":        [],
        "negative_control":  [],
    }
    for r in results:
        qt = r.metadata.get("query_type", "")
        if qt in by_qtype:
            by_qtype[qt].append(r)

    # Routing accuracy (complete)
    routing_correct = sum(
        1 for r in by_qtype["complete"]
        if adapter.score_routing(r.agent_response, _mock_task(r)) >= 1.0
    )
    routing_total = max(1, len(by_qtype["complete"]))

    # Param extraction F1 proxy (complete)
    param_scores = [
        adapter.score_param_extraction(r.agent_response, _mock_task(r))
        for r in by_qtype["complete"]
    ]
    param_f1 = statistics.mean(param_scores) if param_scores else 0.0

    # Prereq detection (incomplete)
    prereq_correct = sum(
        1 for r in by_qtype["incomplete"]
        if adapter._response_asks_for_trial_params(r.agent_response)
    )
    prereq_total = max(1, len(by_qtype["incomplete"]))

    # Negative control (correct non-routing to BOIN)
    negctrl_correct = sum(
        1 for r in by_qtype["negative_control"]
        if not adapter._response_routed_to_boin(r.agent_response)
    )
    negctrl_total = max(1, len(by_qtype["negative_control"]))

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

    return {
        "routing_accuracy":  routing_correct / routing_total,
        "routing_correct":   routing_correct,
        "routing_total":     routing_total,
        "param_f1":          param_f1,
        "param_scores":      param_scores,
        "prereq_rate":       prereq_correct / prereq_total,
        "prereq_correct":    prereq_correct,
        "prereq_total":      prereq_total,
        "negctrl_rate":      negctrl_correct / negctrl_total,
        "negctrl_correct":   negctrl_correct,
        "negctrl_total":     negctrl_total,
        "mean_latency":      mean_latency,
        "p95_latency":       p95_latency,
        "total_cost":        total_cost,
        "n_total":           len(results),
        "n_errors":          sum(1 for r in results if r.error),
    }


# ---------------------------------------------------------------------------
# L5–L6 output validity scoring
# ---------------------------------------------------------------------------

def run_l5l6(output_dir: str, cases_yaml: Path) -> Dict[str, Any]:
    """
    Parse Nextflow clinical_trial_simulation output files and compute
    L6 MTD accuracy metrics.

    Parameters
    ----------
    output_dir : str
        Path to the Nextflow run output directory (one subdirectory per scenario).
    cases_yaml : Path
        Path to cases.yaml (for reference MTD values).

    Returns
    -------
    dict
        Aggregate + per-scenario scores from boin_scorer.
    """
    from evaluation.scorers.boin_scorer import (
        parse_boin_output, score_boin_case, score_boin_batch
    )
    import json

    with open(cases_yaml) as f:
        data = yaml.safe_load(f)
    cases = data["cases"]

    print(f"\nL5-L6: parsing BOIN output from: {output_dir}")
    all_scores = []
    for case in cases:
        case_id    = case["id"]
        inputs     = case["inputs"]
        dlt_target = float(inputs.get("DLT_rate_target", 0.25))

        # Check for per-scenario subdirectory, fall back to flat
        scenario_dir = Path(output_dir) / case_id
        if not scenario_dir.exists():
            scenario_dir = Path(output_dir)

        predicted  = parse_boin_output(scenario_dir)
        case_score = score_boin_case(predicted, case["reference"], dlt_target)
        all_scores.append(case_score)

        true_level = case["reference"].get("true_MTD_level")
        pred_level = predicted.get("recommended_MTD_level")
        exact_sym  = "✓" if case_score["mtd_exact"] else "✗"
        adj_sym    = "✓" if case_score["mtd_adjacent"] else "✗"
        print(f"  {case_id:8} level: true={true_level} pred={pred_level} "
              f"exact={exact_sym} adj={adj_sym}")

    metrics = score_boin_batch(all_scores, cases)
    return metrics


def _print_l5l6_summary(metrics: Dict[str, Any]) -> None:
    """Print a formatted L5–L6 output validity summary."""
    if "error" in metrics:
        print(f"\nL5-L6 scoring failed: {metrics['error']}")
        return

    n = metrics.get("n_cases", 0)
    print(f"\n{'='*60}")
    print(f"BOIN Benchmark — L5-L6 Output Validity")
    print(f"{'='*60}")
    print(f"  Scenarios scored:    {n}")
    print(f"  MTD exact rate:      {metrics.get('mtd_exact_rate', 0):.3f}  "
          f"(target ≥ 0.70)")
    print(f"  MTD adjacent rate:   {metrics.get('mtd_adjacent_rate', 0):.3f}  "
          f"(target ≥ 0.90)")
    print(f"  Safety flag rate:    {metrics.get('safety_flag_rate', 0):.3f}")
    print(f"  DLT in-band rate:    {metrics.get('dlt_band_rate', 0):.3f}")
    print(f"  Mean overall score:  {metrics.get('mean_overall_score', 0):.3f}")
    print(f"  Passes exact target: {'YES' if metrics.get('passes_exact_target') else 'NO'}")
    print(f"  Passes adj. target:  {'YES' if metrics.get('passes_adjacent_target') else 'NO'}")
    print()
    print(f"  By difficulty:")
    for diff, stats in metrics.get("by_difficulty", {}).items():
        print(f"    {diff:<8}  n={stats['n']:2}  "
              f"exact={stats.get('mtd_exact_rate', 0):.3f}  "
              f"adj={stats.get('mtd_adjacent_rate', 0):.3f}")


# ---------------------------------------------------------------------------
# Excel export
# ---------------------------------------------------------------------------

def _export_xlsx(
    results: List,
    summary: Dict[str, Any],
    output_dir: Path,
    l5l6_metrics: Optional[Dict[str, Any]] = None,
) -> Optional[Path]:
    """Generate eval_matrix.xlsx with Summary and Per-Task sheets."""
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
            cell.fill = GREEN if val >= 0.9 else (YELLOW if val >= 0.7 else RED)
        return cell

    for ci, h in enumerate(["Metric", "Value", "Target", "Status"], 1):
        _hdr(ws1, 1, ci, h)

    summary_rows = [
        ("Benchmark",           "B4 BOIN Clinical Trial Design", "", ""),
        ("Dataset",             "20 Phase I scenarios (BOIN + 3+3)", "", ""),
        ("Tasks (L1–L4)",       summary.get("n_total", 0), "", ""),
        ("Errors",              summary.get("n_errors", 0), "", ""),
        ("",                    "", "", ""),
        ("Routing accuracy",    round(summary.get("routing_accuracy", 0), 3), "≥ 0.90",
         "✓" if summary.get("routing_accuracy", 0) >= 0.90 else "✗"),
        ("Param F1",            round(summary.get("param_f1", 0), 3),         "≥ 0.80",
         "✓" if summary.get("param_f1", 0) >= 0.80 else "✗"),
        ("Prereq detection",    round(summary.get("prereq_rate", 0), 3),      "≥ 0.90",
         "✓" if summary.get("prereq_rate", 0) >= 0.90 else "✗"),
        ("Neg-ctrl routing",    round(summary.get("negctrl_rate", 0), 3),     "≥ 0.95",
         "✓" if summary.get("negctrl_rate", 0) >= 0.95 else "✗"),
        ("",                    "", "", ""),
        ("Mean latency (s)",    round(summary.get("mean_latency", 0), 1),     "", ""),
        ("p95 latency (s)",     round(summary.get("p95_latency", 0), 1),      "", ""),
        ("Total cost ($)",      round(summary.get("total_cost", 0), 4),       "", ""),
    ]

    if l5l6_metrics and "error" not in l5l6_metrics:
        summary_rows += [
            ("", "", "", ""),
            ("L6 MTD exact rate",  round(l5l6_metrics.get("mtd_exact_rate", 0), 3), "≥ 0.70",
             "✓" if l5l6_metrics.get("passes_exact_target") else "✗"),
            ("L6 MTD adj. rate",   round(l5l6_metrics.get("mtd_adjacent_rate", 0), 3), "≥ 0.90",
             "✓" if l5l6_metrics.get("passes_adjacent_target") else "✗"),
            ("L6 Safety flag rate", round(l5l6_metrics.get("safety_flag_rate", 0), 3), "1.0", ""),
            ("L6 DLT in-band rate", round(l5l6_metrics.get("dlt_band_rate", 0), 3), "≥ 0.90", ""),
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
    ws1.column_dimensions["B"].width = 38
    ws1.column_dimensions["C"].width = 12
    ws1.column_dimensions["D"].width = 8

    # Per-Task sheet
    ws2 = wb.create_sheet("Per-Task")
    task_headers = [
        "Task ID", "Case ID", "Scenario", "Query Type",
        "Score", "Latency (s)", "Error", "Response Preview",
    ]
    for ci, h in enumerate(task_headers, 1):
        _hdr(ws2, 1, ci, h)

    for ri, r in enumerate(sorted(results, key=lambda x: x.task_id), 2):
        case_id  = r.metadata.get("case_id", "")
        scenario = r.metadata.get("scenario", "")[:40]
        qtype    = r.metadata.get("query_type", "")
        preview  = r.agent_response[:120].replace("\n", " ") if r.agent_response else ""

        ws2.cell(row=ri, column=1, value=r.task_id)
        ws2.cell(row=ri, column=2, value=case_id)
        ws2.cell(row=ri, column=3, value=scenario)
        ws2.cell(row=ri, column=4, value=qtype)
        _color_score(ws2, ri, 5, round(r.score, 3))
        ws2.cell(row=ri, column=6, value=round(r.latency_sec, 1))
        ws2.cell(row=ri, column=7, value=r.error or "")
        ws2.cell(row=ri, column=8, value=preview)

    for col, width in zip("ABCDEFGH", [28, 12, 44, 18, 8, 12, 20, 60]):
        ws2.column_dimensions[col].width = width

    xlsx_path = output_dir / "eval_matrix.xlsx"
    wb.save(xlsx_path)
    return xlsx_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="B4 BOIN Clinical Trial Design Benchmark runner (L1–L4 and L5–L6)"
    )
    parser.add_argument(
        "--output", default="results/boin_benchmark_v1/",
        help="Output directory (default: results/boin_benchmark_v1/)"
    )
    parser.add_argument(
        "--config", default="config.yaml",
        help="Path to evaluation config YAML (default: config.yaml)"
    )
    parser.add_argument(
        "--max-tasks", type=int, default=None,
        help="Limit number of tasks to run (default: all 60)"
    )
    parser.add_argument(
        "--layers", choices=["L1L4", "L5L6"], default="L1L4",
        help="L1L4 = routing/params/prereq eval; "
             "L5L6 = output validity from Nextflow run dir"
    )
    parser.add_argument(
        "--run-output-dir", default=None,
        help="Path to Nextflow output directory for L5–L6 scoring"
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

    # ---- L5–L6 mode ---------------------------------------------------------
    if args.layers == "L5L6":
        if not args.run_output_dir:
            print("ERROR: --run-output-dir is required for --layers L5L6")
            sys.exit(1)
        cases_yaml = (
            Path(__file__).parent.parent / "datasets" / "boin_benchmark" / "cases.yaml"
        )
        metrics = run_l5l6(args.run_output_dir, cases_yaml)
        _print_l5l6_summary(metrics)
        import json
        out_json = output_dir / "l5l6_metrics.json"
        with open(out_json, "w") as f:
            json.dump(metrics, f, indent=2, default=str)
        print(f"\n  L5-L6 metrics saved to: {out_json}")
        return

    # ---- L1–L4 mode ---------------------------------------------------------
    adapter = BOINClinicalBenchmarkAdapter(config)
    tasks = adapter.load_tasks()

    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"BOIN Benchmark — {len(tasks)} tasks would run:\n")
        by_type: Dict[str, int] = {}
        for t in tasks:
            qt = t.metadata.get("query_type", "?")
            by_type[qt] = by_type.get(qt, 0) + 1
            scenario = t.metadata.get("scenario", "?")[:40]
            print(f"  [{t.task_id}] {qt:<18} scenario={scenario}")
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

    print(f"\nBOIN Clinical Trial Benchmark — L1-L4")
    print(f"  Tasks:       {len(tasks)} ({len(tasks)//3} scenarios × 3 query types)")
    print(f"  Output:      {args.output}")
    print(f"  Concurrency: {config.get('concurrency', {}).get('max_parallel_tasks', 16)}")
    print()

    client = BioMateEvalClient.from_config(config)
    store  = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("boin_benchmark", suite="L1L4", config=config)

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

    print(f"\n{'='*60}")
    print(f"BOIN Benchmark — L1-L4 Results")
    print(f"{'='*60}")
    print(f"  Tasks:                {summary['n_total']}  ({summary['n_errors']} errors)")
    print(f"  Routing accuracy:     "
          f"{summary['routing_correct']}/{summary['routing_total']} "
          f"({summary['routing_accuracy']:.1%})")
    print(f"  Param F1:             {summary['param_f1']:.2f}  (target ≥ 0.80)")
    print(f"  Prereq detection:     "
          f"{summary['prereq_correct']}/{summary['prereq_total']} "
          f"({summary['prereq_rate']:.1%})  (target ≥ 0.90)")
    print(f"  Neg-ctrl accuracy:    "
          f"{summary['negctrl_correct']}/{summary['negctrl_total']} "
          f"({summary['negctrl_rate']:.1%})")
    print(f"  Mean latency:         {summary['mean_latency']:.0f}s  "
          f"(p95={summary['p95_latency']:.0f}s)")
    print(f"  Total cost:           ${summary['total_cost']:.4f}")
    if summary['n_total'] > 0:
        print(f"  Cost/task:            "
              f"${summary['total_cost'] / summary['n_total']:.5f}")
    print(f"  Elapsed:              {elapsed:.0f}s")
    print(f"\n  Results DB:           {config['paths']['results_db']}")

    # ---- Excel export -------------------------------------------------------
    if not args.no_xlsx:
        xlsx_path = _export_xlsx(results, summary, output_dir)
        if xlsx_path:
            print(f"  Excel export:         {xlsx_path}")

    print()


if __name__ == "__main__":
    main()
