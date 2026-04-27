#!/usr/bin/env python3
"""
run_admet_benchmark.py — B1 ADMET Screening Benchmark runner.

Tests the full chain: NL intent → workflow routing → parameter extraction
→ prerequisite detection (L1–L4) and optionally output validity (L5–L6).

Usage:
    # Dry-run: list tasks without running
    python runners/run_admet_benchmark.py --dry-run

    # L1–L4 evaluation (routing + params + prereq), up to 20 tasks
    python runners/run_admet_benchmark.py --layers L1L4 --max-tasks 20

    # Full 60-task L1–L4 run
    python runners/run_admet_benchmark.py --layers L1L4

    # L5–L6 output validity from a completed Nextflow run directory
    python runners/run_admet_benchmark.py --layers L5L6 \\
        --run-output-dir /path/to/nextflow/outputs/

Per-task display format:
    [ADMET-001 / complete_single] ROUTED=✓ PARAMS=✓ score=1.00 (15s)
    [ADMET-003 / incomplete    ] PREREQ=✓ score=1.00 (22s)
    [ADMET-004 / negative_ctrl ] ROUTING=✓ (correctly NOT admet) score=1.00 (8s)
"""

from __future__ import annotations

import argparse
import math
import statistics
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

# Ensure project root is on sys.path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from evaluation.core import BioMateEvalClient, ResultsStore
from evaluation.adapters import AdmetBenchmarkAdapter

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
    case_id   = result.metadata.get("case_id", result.task_id)
    qtype     = result.metadata.get("query_type", "?")
    score     = result.score
    elapsed   = result.latency_sec
    err       = f" [ERR: {result.error[:50]}]" if result.error else ""

    qtype_display = {
        "complete_single": "complete_single",
        "incomplete":      "incomplete     ",
        "negative_control": "negative_ctrl  ",
    }.get(qtype, qtype.ljust(15))

    prefix = f"  [{idx:>3}/{total}] [{case_id} / {qtype_display}]"

    if qtype == "complete_single":
        routed = "✓" if details.get("routed_ok") else "✗"
        params = "✓" if details.get("params_ok") else "✗"
        body = f"ROUTED={routed} PARAMS={params} score={score:.2f} ({elapsed:.0f}s)"
    elif qtype == "incomplete":
        prereq = "✓" if details.get("prereq_asked") else "✗"
        body = f"PREREQ={prereq} score={score:.2f} ({elapsed:.0f}s)"
    elif qtype == "negative_control":
        ok = "✓" if not details.get("routed_to_admet") else "✗"
        body = f"ROUTING={ok} (correctly NOT admet) score={score:.2f} ({elapsed:.0f}s)"
    else:
        body = f"score={score:.2f} ({elapsed:.0f}s)"

    return f"{prefix} {body}{err}"


def _compute_summary(results: List, adapter: AdmetBenchmarkAdapter) -> Dict[str, Any]:
    """Compute per-metric aggregates over all results."""
    by_qtype: Dict[str, List] = {
        "complete_single":  [],
        "incomplete":       [],
        "negative_control": [],
    }
    for r in results:
        qt = r.metadata.get("query_type", "")
        if qt in by_qtype:
            by_qtype[qt].append(r)

    # Routing accuracy (complete_single)
    routing_correct = sum(
        1 for r in by_qtype["complete_single"]
        if adapter.score_routing(r.agent_response, _mock_task(r)) >= 1.0
    )
    routing_total = max(1, len(by_qtype["complete_single"]))

    # Param extraction F1 proxy (complete_single)
    param_scores = [
        adapter.score_param_extraction(r.agent_response, _mock_task(r))
        for r in by_qtype["complete_single"]
    ]
    param_f1 = statistics.mean(param_scores) if param_scores else 0.0

    # Prereq detection (incomplete)
    prereq_correct = sum(
        1 for r in by_qtype["incomplete"]
        if adapter._response_asks_for_smiles(r.agent_response)
    )
    prereq_total = max(1, len(by_qtype["incomplete"]))

    # Negative control (correct non-routing)
    negctrl_correct = sum(
        1 for r in by_qtype["negative_control"]
        if not adapter._response_routed_to_admet(r.agent_response)
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
        "routing_accuracy":   routing_correct / routing_total,
        "routing_correct":    routing_correct,
        "routing_total":      routing_total,
        "param_f1":           param_f1,
        "param_scores":       param_scores,
        "prereq_rate":        prereq_correct / prereq_total,
        "prereq_correct":     prereq_correct,
        "prereq_total":       prereq_total,
        "negctrl_rate":       negctrl_correct / negctrl_total,
        "negctrl_correct":    negctrl_correct,
        "negctrl_total":      negctrl_total,
        "mean_latency":       mean_latency,
        "p95_latency":        p95_latency,
        "total_cost":         total_cost,
        "n_total":            len(results),
        "n_errors":           sum(1 for r in results if r.error),
    }


def _mock_task(result):
    """
    Reconstruct a minimal BenchmarkTask-like object from a result's metadata.
    Used for re-scoring in summary computation.
    """
    from evaluation.core.base_adapter import BenchmarkTask
    return BenchmarkTask(
        task_id=result.task_id,
        question="",
        ground_truth={},
        metadata=result.metadata,
    )


# ---------------------------------------------------------------------------
# L5–L6 output validity scoring
# ---------------------------------------------------------------------------

def run_l5l6(output_dir: str, cases_yaml: Path) -> Dict[str, Any]:
    """
    Parse Nextflow ADMET output files and compute L6 output validity metrics.

    Parameters
    ----------
    output_dir : str
        Path to the Nextflow run output directory (containing results.csv etc.)
    cases_yaml : Path
        Path to the cases YAML file (for reference values).

    Returns
    -------
    dict
        Aggregate + per-compound scores from admet_scorer.
    """
    from evaluation.scorers.admet_scorer import parse_admet_output, score_admet_batch

    with open(cases_yaml) as f:
        data = yaml.safe_load(f)
    cases = data["cases"]

    print(f"\nL5-L6: parsing ADMET output from: {output_dir}")
    try:
        predictions = parse_admet_output(output_dir)
        print(f"  Found predictions for {len(predictions)} compounds")
    except FileNotFoundError as e:
        print(f"  ERROR: {e}")
        return {"error": str(e)}

    metrics = score_admet_batch(predictions, cases)
    return metrics


def _print_l5l6_summary(metrics: Dict[str, Any]) -> None:
    """Print a formatted L5–L6 output validity summary."""
    if "error" in metrics:
        print(f"\nL5-L6 scoring failed: {metrics['error']}")
        return

    n = metrics.get("n_total", 0)
    matched = metrics.get("n_matched", 0)
    print(f"\n{'='*60}")
    print(f"ADMET Benchmark — L5-L6 Output Validity")
    print(f"{'='*60}")
    print(f"  Compounds:         {matched}/{n} matched")
    print(f"  hERG accuracy:     {metrics.get('herg_accuracy', 0):.3f}")
    print(f"  DILI accuracy:     {metrics.get('dili_accuracy', 0):.3f}")
    print(f"  Ames accuracy:     {metrics.get('ames_accuracy', 0):.3f}")
    print(f"  Ro5 accuracy:      {metrics.get('ro5_accuracy', 0):.3f}")
    print(f"  Overall accuracy:  {metrics.get('overall_accuracy', 0):.3f}  "
          f"(target ≥ 0.80)")
    rho = metrics.get("spearman_rho")
    rho_str = f"{rho:.3f}" if rho is not None else "N/A"
    print(f"  Spearman rho:      {rho_str}  (target ≥ 0.65)")
    print(f"  Completeness:      {metrics.get('mean_completeness', 0):.3f}")


# ---------------------------------------------------------------------------
# Excel export
# ---------------------------------------------------------------------------

def _export_xlsx(
    results: List,
    summary: Dict[str, Any],
    output_dir: Path,
    l5l6_metrics: Optional[Dict[str, Any]] = None,
) -> Optional[Path]:
    """
    Generate eval_matrix.xlsx with Summary and Per-Task sheets.

    Uses openpyxl with conditional colour coding:
      green  = score ≥ 0.9
      yellow = score 0.7–0.9
      red    = score < 0.7
    """
    try:
        import openpyxl
        from openpyxl.styles import PatternFill, Font, Alignment
        from openpyxl.utils import get_column_letter
    except ImportError:
        print("  (openpyxl not available — skipping XLSX export)")
        return None

    GREEN  = PatternFill("solid", fgColor="C6EFCE")
    YELLOW = PatternFill("solid", fgColor="FFEB9C")
    RED    = PatternFill("solid", fgColor="FFC7CE")
    HEADER = PatternFill("solid", fgColor="4472C4")
    HEADER_FONT = Font(color="FFFFFF", bold=True)

    wb = openpyxl.Workbook()

    # ---- Sheet 1: Summary -----------------------------------------------
    ws1 = wb.active
    ws1.title = "Summary"

    def _hdr(ws, row, col, val):
        cell = ws.cell(row=row, column=col, value=val)
        cell.fill = HEADER
        cell.font = HEADER_FONT
        cell.alignment = Alignment(horizontal="center")

    def _color_score(ws, row, col, val):
        cell = ws.cell(row=row, column=col, value=val)
        if isinstance(val, (int, float)):
            if val >= 0.9:
                cell.fill = GREEN
            elif val >= 0.7:
                cell.fill = YELLOW
            else:
                cell.fill = RED
        return cell

    summary_headers = [
        "Metric", "Value", "Target", "Status"
    ]
    for ci, h in enumerate(summary_headers, 1):
        _hdr(ws1, 1, ci, h)

    summary_rows = [
        ("Benchmark",            "B1 ADMET Screening", "",       ""),
        ("Dataset",              "20 compounds (ChEMBL + PharmaBench)", "", ""),
        ("Tasks (L1–L4)",        summary.get("n_total", 0),       "", ""),
        ("Errors",               summary.get("n_errors", 0),      "", ""),
        ("",                     "",                              "",  ""),
        ("Routing accuracy",     round(summary.get("routing_accuracy", 0), 3), "≥ 0.90",
         "✓" if summary.get("routing_accuracy", 0) >= 0.90 else "✗"),
        ("Param F1",             round(summary.get("param_f1", 0), 3),        "≥ 0.80",
         "✓" if summary.get("param_f1", 0) >= 0.80 else "✗"),
        ("Prereq detection",     round(summary.get("prereq_rate", 0), 3),     "≥ 0.95",
         "✓" if summary.get("prereq_rate", 0) >= 0.95 else "✗"),
        ("Neg-ctrl routing",     round(summary.get("negctrl_rate", 0), 3),    "≥ 0.95",
         "✓" if summary.get("negctrl_rate", 0) >= 0.95 else "✗"),
        ("",                     "",                              "",  ""),
        ("Mean latency (s)",     round(summary.get("mean_latency", 0), 1),    "", ""),
        ("p95 latency (s)",      round(summary.get("p95_latency", 0), 1),     "", ""),
        ("Total cost ($)",       round(summary.get("total_cost", 0), 4),      "", ""),
        ("Cost/task ($)",
         round(summary.get("total_cost", 0) / max(1, summary.get("n_total", 1)), 5),
         "", ""),
    ]

    if l5l6_metrics and "error" not in l5l6_metrics:
        summary_rows += [
            ("",                 "",                              "",  ""),
            ("L6 hERG accuracy", round(l5l6_metrics.get("herg_accuracy", 0), 3), "≥ 0.80", ""),
            ("L6 DILI accuracy", round(l5l6_metrics.get("dili_accuracy", 0), 3), "≥ 0.80", ""),
            ("L6 Ames accuracy", round(l5l6_metrics.get("ames_accuracy", 0), 3), "≥ 0.80", ""),
            ("L6 Ro5 accuracy",  round(l5l6_metrics.get("ro5_accuracy", 0), 3),  "≥ 0.80", ""),
            ("L6 Overall acc.",  round(l5l6_metrics.get("overall_accuracy", 0), 3), "≥ 0.80",
             "✓" if l5l6_metrics.get("overall_accuracy", 0) >= 0.80 else "✗"),
            ("L6 Spearman rho",
             round(l5l6_metrics.get("spearman_rho") or 0, 3), "≥ 0.65", ""),
        ]

    for ri, (metric, val, target, status) in enumerate(summary_rows, 2):
        ws1.cell(row=ri, column=1, value=metric)
        if isinstance(val, float) and 0.0 <= val <= 1.0 and metric != "":
            _color_score(ws1, ri, 2, val)
        else:
            ws1.cell(row=ri, column=2, value=val)
        ws1.cell(row=ri, column=3, value=target)
        ws1.cell(row=ri, column=4, value=status)

    ws1.column_dimensions["A"].width = 26
    ws1.column_dimensions["B"].width = 40
    ws1.column_dimensions["C"].width = 12
    ws1.column_dimensions["D"].width = 8

    # ---- Sheet 2: Per-Task ----------------------------------------------
    ws2 = wb.create_sheet("Per-Task")
    task_headers = [
        "Task ID", "Case ID", "Compound", "Query Type",
        "Score", "Latency (s)", "Error", "Response Preview",
    ]
    for ci, h in enumerate(task_headers, 1):
        _hdr(ws2, 1, ci, h)

    for ri, r in enumerate(sorted(results, key=lambda x: x.task_id), 2):
        case_id    = r.metadata.get("case_id", "")
        compound   = r.metadata.get("compound_name", "")
        qtype      = r.metadata.get("query_type", "")
        preview    = r.agent_response[:120].replace("\n", " ") if r.agent_response else ""

        ws2.cell(row=ri, column=1, value=r.task_id)
        ws2.cell(row=ri, column=2, value=case_id)
        ws2.cell(row=ri, column=3, value=compound)
        ws2.cell(row=ri, column=4, value=qtype)
        _color_score(ws2, ri, 5, round(r.score, 3))
        ws2.cell(row=ri, column=6, value=round(r.latency_sec, 1))
        ws2.cell(row=ri, column=7, value=r.error or "")
        ws2.cell(row=ri, column=8, value=preview)

    ws2.column_dimensions["A"].width = 26
    ws2.column_dimensions["B"].width = 14
    ws2.column_dimensions["C"].width = 18
    ws2.column_dimensions["D"].width = 18
    ws2.column_dimensions["E"].width = 8
    ws2.column_dimensions["F"].width = 12
    ws2.column_dimensions["G"].width = 20
    ws2.column_dimensions["H"].width = 60

    xlsx_path = output_dir / "eval_matrix.xlsx"
    wb.save(xlsx_path)
    return xlsx_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="B1 ADMET Screening Benchmark runner (L1–L4 and optional L5–L6)"
    )
    parser.add_argument(
        "--output", default="results/admet_benchmark_v1/",
        help="Output directory for results DB and Excel export (default: results/admet_benchmark_v1/)"
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
        help="L1L4 = routing/params/prereq eval via chat API; "
             "L5L6 = output validity from existing Nextflow run directory "
             "(requires --run-output-dir)"
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

    # ---- Load config ------------------------------------------------------
    config_path = Path(__file__).parent.parent / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    config["paths"]["results_db"] = str(output_dir / "eval_results.db")

    if args.workers:
        config.setdefault("concurrency", {})["max_parallel_tasks"] = args.workers

    # ---- L5–L6 mode -------------------------------------------------------
    if args.layers == "L5L6":
        if not args.run_output_dir:
            print("ERROR: --run-output-dir is required for --layers L5L6")
            sys.exit(1)
        cases_yaml = Path(__file__).parent.parent / "datasets" / "admet_benchmark" / "cases.yaml"
        metrics = run_l5l6(args.run_output_dir, cases_yaml)
        _print_l5l6_summary(metrics)
        # Save JSON metrics
        import json
        out_json = output_dir / "l5l6_metrics.json"
        with open(out_json, "w") as f:
            json.dump(metrics, f, indent=2, default=str)
        print(f"\n  L5-L6 metrics saved to: {out_json}")
        return

    # ---- L1–L4 mode -------------------------------------------------------
    adapter = AdmetBenchmarkAdapter(config)
    tasks = adapter.load_tasks()

    if args.max_tasks:
        tasks = tasks[:args.max_tasks]

    if args.dry_run:
        print(f"ADMET Benchmark — {len(tasks)} tasks would run:\n")
        by_type: Dict[str, int] = {}
        for t in tasks:
            qt = t.metadata.get("query_type", "?")
            by_type[qt] = by_type.get(qt, 0) + 1
            compound = t.metadata.get("compound_name", "?")
            print(f"  [{t.task_id}] {qt:<18} compound={compound}")
        print(f"\n  By query type: {by_type}")
        return

    # ---- Server health check ----------------------------------------------
    base_url = config["biomate"]["base_url"]
    print(f"Checking BioMate server at {base_url}...", end=" ", flush=True)
    server_up = _check_server(base_url)
    if not server_up:
        print("DOWN")
        print(f"\nWARNING: BioMate server is not reachable at {base_url}.")
        print("Code build complete. Skipping execution — start server and re-run.")
        return
    print("UP")

    print(f"\nADMET Benchmark — L1-L4")
    print(f"  Tasks:       {len(tasks)} ({len(tasks)//3} compounds × 3 query types)")
    print(f"  Output:      {args.output}")
    print(f"  Concurrency: {config.get('concurrency', {}).get('max_parallel_tasks', 16)}")
    print()

    client = BioMateEvalClient.from_config(config)
    store  = ResultsStore(config["paths"]["results_db"])
    run_id = store.start_run("admet_benchmark", suite="L1L4", config=config)

    completed = [0]
    all_results: List = []

    def _on_result(r) -> None:
        store.save_one(run_id, r)
        completed[0] += 1
        details = adapter.score_detailed(
            _mock_task(r), r.agent_response
        )
        line = _format_task_line(completed[0], len(tasks), r, details)
        print(line, flush=True)
        all_results.append(r)

    t0 = time.time()
    results = adapter.run_tasks(client, tasks, on_result=_on_result)
    store.finish_run(run_id)
    elapsed = time.time() - t0

    # ---- Summary ----------------------------------------------------------
    summary = _compute_summary(results, adapter)

    print(f"\n{'='*60}")
    print(f"ADMET Benchmark — L1-L4 Results")
    print(f"{'='*60}")
    print(f"  Tasks:                {summary['n_total']}  ({summary['n_errors']} errors)")
    print(f"  Routing accuracy:     "
          f"{summary['routing_correct']}/{summary['routing_total']} "
          f"({summary['routing_accuracy']:.1%})")
    print(f"  Param F1:             {summary['param_f1']:.2f}  (target ≥ 0.80)")
    print(f"  Prereq detection:     "
          f"{summary['prereq_correct']}/{summary['prereq_total']} "
          f"({summary['prereq_rate']:.1%})  (target ≥ 0.95)")
    print(f"  Neg-ctrl accuracy:    "
          f"{summary['negctrl_correct']}/{summary['negctrl_total']} "
          f"({summary['negctrl_rate']:.1%})")
    print(f"  Mean latency:         {summary['mean_latency']:.0f}s  "
          f"(p95={summary['p95_latency']:.0f}s)")
    print(f"  Total cost:           ${summary['total_cost']:.4f}")
    if summary['n_total'] > 0:
        print(f"  Cost/task:            ${summary['total_cost'] / summary['n_total']:.5f}")
    print(f"  Elapsed:              {elapsed:.0f}s")
    print(f"\n  Results DB:           {config['paths']['results_db']}")

    # ---- Excel export -----------------------------------------------------
    if not args.no_xlsx:
        xlsx_path = _export_xlsx(results, summary, output_dir)
        if xlsx_path:
            print(f"  Excel export:         {xlsx_path}")

    print()


if __name__ == "__main__":
    main()
