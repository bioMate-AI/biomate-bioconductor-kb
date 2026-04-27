#!/usr/bin/env python3
"""
generate_eval_matrix_xlsx.py
----------------------------
Generates a formatted XLSX evaluation matrix from any eval result DB(s).
Used for the main BioMate evaluation report.

Usage:
    python scripts/generate_eval_matrix_xlsx.py --all --output eval_matrix_20260427.xlsx
    python scripts/generate_eval_matrix_xlsx.py --db results/admet_benchmark_v1/eval_results.db
    python scripts/generate_eval_matrix_xlsx.py --all --format summary    # one row per benchmark
    python scripts/generate_eval_matrix_xlsx.py --all --format detailed   # one row per task

Sheet structure for --format summary (default):
  Sheet 1 "Performance"   — n, Mean Score, SE, CI_lo, CI_hi, n_pass, n_fail
  Sheet 2 "Time & Cost"   — Mean/Std/p95 latency, Cost/task, Total Cost
  Sheet 3 "Hallucination" — n_audited, n_grounded, n_hallucinated, Rate with CI
  Sheet 4 "Stability"     — Consistency Rate, Flip Rate, Cohen's κ
  Sheet 5 "All Benchmarks"— combined view: score, latency p95, cost, hallucination, consistency
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any, Optional

import openpyxl
from openpyxl.styles import (
    Alignment, Border, Font, PatternFill, Side
)
from openpyxl.utils import get_column_letter

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

EVAL_DIR = Path(__file__).parent.parent
RESULTS_DIR = EVAL_DIR / "results"
STABILITY_DIR = RESULTS_DIR / "stability"

CANONICAL_DBS = [
    ("BiomniEval1 v20",   "results/biomni_eval1_v20/eval_results.db"),
    ("LABBench",          "results/labbench_v22/eval_results.db"),
    ("Routing",           "results/routing_v11/eval_results.db"),
    ("BixBench",          "results/bixbench_v4/eval_results.db"),
    ("SGI-Bench",         "results/sgi_bench_v1/eval_results.db"),
    ("License Gating",    "results/license_gating_v5/eval_results.db"),
    ("Prereq Recovery",   "results/prereq_recovery_v2/eval_results.db"),
    ("Autofix",           "results/autofix_benchmark_v1/eval_results.db"),
    ("Protocol→Workflow", "results/protocol_to_workflow/eval_results.db"),
    ("Param Prefill",     "results/param_prefill/eval_results.db"),
    # Drug dev benchmarks
    ("ADMET Benchmark",   "results/admet_benchmark_v1/eval_results.db"),
    ("PBPK Benchmark",    "results/pbpk_benchmark_v1/eval_results.db"),
    ("BOIN Benchmark",    "results/boin_benchmark_v1/eval_results.db"),
    ("Docking Benchmark", "results/docking_benchmark_v1/eval_results.db"),
]

# ---------------------------------------------------------------------------
# Colour palette
# ---------------------------------------------------------------------------

_GREEN  = "C6EFCE"  # ≥ 0.90
_YELLOW = "FFEB9C"  # 0.70 – 0.90
_ORANGE = "FFCC99"  # 0.50 – 0.70
_RED    = "FFC7CE"  # < 0.50

_HALL_GREEN  = "C6EFCE"  # < 0.10
_HALL_YELLOW = "FFEB9C"  # 0.10 – 0.20
_HALL_RED    = "FFC7CE"  # > 0.20

_HEADER_FILL = "2F5496"  # dark blue header
_ROW_ALT     = "EEF3FF"  # light-blue alternating row

_THIN_BORDER_SIDE = Side(style="thin", color="AAAAAA")
_THIN_BORDER = Border(
    left=_THIN_BORDER_SIDE,
    right=_THIN_BORDER_SIDE,
    top=_THIN_BORDER_SIDE,
    bottom=_THIN_BORDER_SIDE,
)


def _fill(hex_color: str) -> PatternFill:
    return PatternFill("solid", fgColor=hex_color)


def _score_color(score) -> str:
    """Color for mean score cell; accepts float or string sentinel."""
    if score is None or not isinstance(score, (int, float)):
        return ""
    if score >= 0.90:
        return _GREEN
    if score >= 0.70:
        return _YELLOW
    if score >= 0.50:
        return _ORANGE
    return _RED


def _hall_color(rate) -> str:
    """Color for hallucination rate; accepts float or string sentinel like 'not audited'."""
    if rate is None or not isinstance(rate, (int, float)):
        return ""
    if rate < 0.10:
        return _HALL_GREEN
    if rate <= 0.20:
        return _HALL_YELLOW
    return _HALL_RED


# ---------------------------------------------------------------------------
# Statistics helpers (mirrors generate_eval_report.py)
# ---------------------------------------------------------------------------

def _wilson_ci(p: float, n: int, z: float = 1.96) -> tuple:
    """Wilson score confidence interval for a proportion."""
    if n == 0:
        return 0.0, 1.0
    denom = 1 + z ** 2 / n
    center = (p + z ** 2 / (2 * n)) / denom
    margin = (z * math.sqrt(p * (1 - p) / n + z ** 2 / (4 * n ** 2))) / denom
    return max(0.0, center - margin), min(1.0, center + margin)


def _score_se(p: float, n: int) -> float:
    return math.sqrt(p * (1 - p) / n) if n > 0 else 0.0


def _percentile(vals: list, p: float) -> float:
    if not vals:
        return 0.0
    s = sorted(vals)
    return s[min(int(p * len(s)), len(s) - 1)]


def _std(vals: list) -> float:
    if len(vals) < 2:
        return 0.0
    mean = sum(vals) / len(vals)
    return math.sqrt(sum((v - mean) ** 2 for v in vals) / (len(vals) - 1))


# ---------------------------------------------------------------------------
# DB loading
# ---------------------------------------------------------------------------

def load_db_stats(db_path: str) -> dict[str, Any]:
    """
    Load all four-dimension stats from a single results DB.
    Returns {} if the DB doesn't exist or has no results.
    Handles older DBs that predate hallucination_label and repeat_id columns.
    """
    if not Path(db_path).exists():
        return {}

    try:
        conn = sqlite3.connect(db_path)
    except Exception:
        return {}

    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()}
    if "results" not in tables:
        conn.close()
        return {}

    # Determine which optional columns exist
    existing_cols = {r[1] for r in conn.execute("PRAGMA table_info(results)").fetchall()}
    hall_col   = "hallucination_label" if "hallucination_label" in existing_cols else "NULL"
    repeat_col = "COALESCE(repeat_id, 0)" if "repeat_id" in existing_cols else "0"
    cost_col   = "cost_usd" if "cost_usd" in existing_cols else "NULL"
    intok_col  = "input_tokens" if "input_tokens" in existing_cols else "NULL"
    outtok_col = "output_tokens" if "output_tokens" in existing_cols else "NULL"

    try:
        rows = conn.execute(
            f"SELECT task_id, benchmark, score, latency_sec, {cost_col}, "
            f"{intok_col}, {outtok_col}, {hall_col}, {repeat_col} "
            f"FROM results WHERE (error='' OR error IS NULL)"
        ).fetchall()
    except Exception:
        conn.close()
        return {}

    conn.close()

    if not rows:
        return {}

    # Separate original (repeat_id=0) from stability repeats
    original = [r for r in rows if r[8] == 0]
    repeats  = [r for r in rows if r[8] > 0]

    # Aggregate by benchmark name
    benchmarks: dict[str, dict] = {}
    for task_id, benchmark, score, latency, cost, in_tok, out_tok, hlabel, _ in original:
        b = benchmarks.setdefault(benchmark, {
            "scores": [], "latencies": [], "costs": [],
            "in_tokens": [], "out_tokens": [],
            "hallucination_labels": [],
        })
        b["scores"].append(score or 0.0)
        if latency and latency > 0:
            b["latencies"].append(latency)
        if cost is not None:
            b["costs"].append(cost)
        if in_tok:
            b["in_tokens"].append(in_tok)
        if out_tok:
            b["out_tokens"].append(out_tok)
        if hlabel:
            b["hallucination_labels"].append(hlabel)

    stats: dict[str, Any] = {}
    for bench, d in benchmarks.items():
        scores  = d["scores"]
        lats    = d["latencies"]
        costs   = d["costs"]
        hlabels = d["hallucination_labels"]
        n = len(scores)
        mean_score = sum(scores) / n if n else 0.0
        n_pass = sum(1 for s in scores if s >= 0.5)
        n_fail = n - n_pass

        # Hallucination
        n_grounded     = hlabels.count("grounded")
        n_hallucinated = hlabels.count("hallucinated")
        n_unverifiable = hlabels.count("unverifiable")
        assessable     = n_grounded + n_hallucinated
        hall_rate      = n_hallucinated / assessable if assessable > 0 else None

        ci_lo, ci_hi = _wilson_ci(mean_score, n)
        se = _score_se(mean_score, n)

        stats[bench] = {
            # Performance
            "n":           n,
            "mean_score":  round(mean_score, 4),
            "score_se":    round(se, 4),
            "ci_95_lo":    round(ci_lo, 4),
            "ci_95_hi":    round(ci_hi, 4),
            "n_pass":      n_pass,
            "n_fail":      n_fail,
            # Time
            "mean_latency_sec": round(sum(lats) / len(lats), 2) if lats else None,
            "std_latency_sec":  round(_std(lats), 2) if lats else None,
            "p95_latency_sec":  round(_percentile(lats, 0.95), 2) if lats else None,
            # Cost
            "mean_cost_usd":   round(sum(costs) / len(costs), 6) if costs else None,
            "total_cost_usd":  round(sum(costs), 4) if costs else None,
            # Hallucination
            "n_audited":        len(hlabels),
            "n_grounded":       n_grounded,
            "n_hallucinated":   n_hallucinated,
            "n_unverifiable":   n_unverifiable,
            "hallucination_rate": round(hall_rate, 4) if hall_rate is not None else None,
            # Stability (filled below)
            "consistency_rate": None,
            "flip_rate":        None,
            "kappa":            None,
        }

    # Stability from repeats
    if repeats:
        by_task: dict[str, list[float]] = {}
        for task_id, _, score, *_ in rows:
            by_task.setdefault(task_id, []).append(score or 0.0)
        multi = {tid: sc for tid, sc in by_task.items() if len(sc) > 1}
        if multi:
            n_consistent = sum(
                1 for sc in multi.values()
                if len(set(s >= 0.5 for s in sc)) == 1
            )
            consistency = n_consistent / len(multi)
            for bench in stats:
                stats[bench]["consistency_rate"] = round(consistency, 4)
                stats[bench]["flip_rate"]        = round(1 - consistency, 4)

    # Load stability JSON if available
    bench_name = Path(db_path).parent.name.split("_v")[0].split("_20")[0]
    stability_path = STABILITY_DIR / f"{bench_name}_stability.json"
    if stability_path.exists():
        try:
            with open(stability_path) as f:
                stab = json.load(f)
            for bench in stats:
                stats[bench]["consistency_rate"] = stab.get("consistency_rate")
                stats[bench]["flip_rate"]        = stab.get("flip_rate")
                stats[bench]["kappa"]            = stab.get("kappa")
        except Exception:
            pass

    return stats


def _discover_all_dbs() -> list[tuple[str, str]]:
    """Return all (label, path) pairs: canonical list + auto-discovered extras."""
    canonical_paths = {str(EVAL_DIR / p) for _, p in CANONICAL_DBS}
    result: list[tuple[str, str]] = []

    # Canonical entries first (only if they exist)
    for label, rel_path in CANONICAL_DBS:
        abs_path = str(EVAL_DIR / rel_path)
        if Path(abs_path).exists():
            result.append((label, abs_path))

    # Auto-discover extras not in canonical list
    found = glob.glob(str(RESULTS_DIR / "*/eval_results.db"))
    for db in sorted(found):
        if db in canonical_paths:
            continue
        # Skip noise dirs
        parent = Path(db).parent.name
        if any(skip in parent for skip in ("model_selection", "stability", "smoke")):
            continue
        result.append((parent, db))

    return result


# ---------------------------------------------------------------------------
# Worksheet helpers
# ---------------------------------------------------------------------------

def _write_header_row(ws, headers: list[str], row: int = 1) -> None:
    """Write a styled header row."""
    for col_idx, header in enumerate(headers, start=1):
        cell = ws.cell(row=row, column=col_idx, value=header)
        cell.font = Font(bold=True, color="FFFFFF", size=10)
        cell.fill = _fill(_HEADER_FILL)
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = _THIN_BORDER


def _write_data_row(ws, values: list, row: int, alt: bool = False,
                    color_col: Optional[int] = None,
                    color_fn=None) -> None:
    """Write one data row, optionally colouring one cell."""
    bg = _ROW_ALT if alt else "FFFFFF"
    for col_idx, val in enumerate(values, start=1):
        cell = ws.cell(row=row, column=col_idx, value=val)
        cell.alignment = Alignment(horizontal="center", vertical="center")
        cell.border = _THIN_BORDER
        if color_col and col_idx == color_col and color_fn:
            color = color_fn(val)
            if color:
                cell.fill = _fill(color)
            else:
                cell.fill = _fill(bg)
        else:
            cell.fill = _fill(bg)


def _auto_width(ws, min_width: int = 8, max_width: int = 35) -> None:
    """Set column widths based on content."""
    for col in ws.columns:
        max_len = 0
        col_letter = get_column_letter(col[0].column)
        for cell in col:
            try:
                val = str(cell.value or "")
                max_len = max(max_len, len(val))
            except Exception:
                pass
        ws.column_dimensions[col_letter].width = max(min_width, min(max_len + 2, max_width))


def _freeze_header(ws) -> None:
    ws.freeze_panes = ws["A2"]


# ---------------------------------------------------------------------------
# Sheet builders
# ---------------------------------------------------------------------------

def _build_performance_sheet(wb, all_stats: dict[str, dict[str, Any]]) -> None:
    ws = wb.create_sheet("Performance")
    headers = ["Benchmark", "n", "Mean Score", "SE", "CI_lo (95%)", "CI_hi (95%)", "n_pass", "n_fail"]
    _write_header_row(ws, headers)

    score_col = headers.index("Mean Score") + 1  # 1-based

    for i, (bench_label, stats) in enumerate(all_stats.items()):
        for bench_name, d in stats.items():
            row = i + 2
            label = bench_label if len(stats) == 1 else f"{bench_label} / {bench_name}"
            values = [
                label,
                d["n"],
                round(d["mean_score"], 4) if d["mean_score"] is not None else None,
                round(d["score_se"], 4) if d["score_se"] is not None else None,
                round(d["ci_95_lo"], 4) if d["ci_95_lo"] is not None else None,
                round(d["ci_95_hi"], 4) if d["ci_95_hi"] is not None else None,
                d.get("n_pass"),
                d.get("n_fail"),
            ]
            _write_data_row(ws, values, row, alt=(i % 2 == 0),
                            color_col=score_col, color_fn=_score_color)

    _auto_width(ws)
    _freeze_header(ws)


def _build_time_cost_sheet(wb, all_stats: dict[str, dict[str, Any]]) -> None:
    ws = wb.create_sheet("Time & Cost")
    headers = [
        "Benchmark", "n",
        "Mean Latency (s)", "Std Latency (s)", "p95 Latency (s)",
        "Cost/task ($)", "Total Cost ($)",
    ]
    _write_header_row(ws, headers)

    for i, (bench_label, stats) in enumerate(all_stats.items()):
        for bench_name, d in stats.items():
            row = i + 2
            label = bench_label if len(stats) == 1 else f"{bench_label} / {bench_name}"
            values = [
                label,
                d["n"],
                d.get("mean_latency_sec"),
                d.get("std_latency_sec"),
                d.get("p95_latency_sec"),
                d.get("mean_cost_usd"),
                d.get("total_cost_usd"),
            ]
            _write_data_row(ws, values, row, alt=(i % 2 == 0))

    _auto_width(ws)
    _freeze_header(ws)


def _build_hallucination_sheet(wb, all_stats: dict[str, dict[str, Any]]) -> None:
    ws = wb.create_sheet("Hallucination")
    headers = [
        "Benchmark", "n_audited",
        "n_grounded", "n_hallucinated", "n_unverifiable",
        "Rate", "CI_lo (95%)", "CI_hi (95%)",
    ]
    _write_header_row(ws, headers)

    rate_col = headers.index("Rate") + 1

    for i, (bench_label, stats) in enumerate(all_stats.items()):
        for bench_name, d in stats.items():
            row = i + 2
            label = bench_label if len(stats) == 1 else f"{bench_label} / {bench_name}"
            n_aud = d.get("n_audited", 0)
            rate  = d.get("hallucination_rate")
            ci_lo, ci_hi = (None, None)
            if rate is not None and n_aud > 0:
                ci = _wilson_ci(rate, n_aud)
                ci_lo, ci_hi = round(ci[0], 4), round(ci[1], 4)
            values = [
                label,
                n_aud,
                d.get("n_grounded"),
                d.get("n_hallucinated"),
                d.get("n_unverifiable"),
                round(rate, 4) if rate is not None else "not audited",
                ci_lo,
                ci_hi,
            ]
            _write_data_row(ws, values, row, alt=(i % 2 == 0),
                            color_col=rate_col, color_fn=_hall_color)

    _auto_width(ws)
    _freeze_header(ws)


def _build_stability_sheet(wb, all_stats: dict[str, dict[str, Any]]) -> None:
    ws = wb.create_sheet("Stability")
    headers = ["Benchmark", "n_tasks", "n_repeats", "Consistency Rate", "Flip Rate", "Cohen's κ"]
    _write_header_row(ws, headers)

    for i, (bench_label, stats) in enumerate(all_stats.items()):
        for bench_name, d in stats.items():
            row = i + 2
            label = bench_label if len(stats) == 1 else f"{bench_label} / {bench_name}"
            cons = d.get("consistency_rate")
            flip = d.get("flip_rate")
            kappa = d.get("kappa")
            values = [
                label,
                d["n"],
                None,  # n_repeats not tracked per-row yet
                round(cons, 4) if cons is not None else "not run",
                round(flip, 4) if flip is not None else "not run",
                round(kappa, 4) if kappa is not None else "not run",
            ]
            _write_data_row(ws, values, row, alt=(i % 2 == 0))

    _auto_width(ws)
    _freeze_header(ws)


def _build_combined_sheet(wb, all_stats: dict[str, dict[str, Any]]) -> None:
    """Sheet 5 — all four dimensions side by side, one row per benchmark."""
    ws = wb.create_sheet("All Benchmarks")
    headers = [
        "Benchmark", "n",
        "Score", "SE", "CI [lo, hi]",
        "Time p95 (s)", "Cost/task ($)",
        "Hall. Rate", "Consistency",
    ]
    _write_header_row(ws, headers)

    score_col = headers.index("Score") + 1

    for i, (bench_label, stats) in enumerate(all_stats.items()):
        for bench_name, d in stats.items():
            row = i + 2
            label = bench_label if len(stats) == 1 else f"{bench_label} / {bench_name}"
            score  = d.get("mean_score")
            se     = d.get("score_se")
            ci_lo  = d.get("ci_95_lo")
            ci_hi  = d.get("ci_95_hi")
            ci_str = (f"[{ci_lo:.3f}, {ci_hi:.3f}]"
                      if ci_lo is not None and ci_hi is not None else "")
            hall   = d.get("hallucination_rate")
            cons   = d.get("consistency_rate")

            values = [
                label,
                d["n"],
                round(score, 4) if score is not None else None,
                round(se, 4) if se is not None else None,
                ci_str,
                d.get("p95_latency_sec"),
                d.get("mean_cost_usd"),
                round(hall, 4) if hall is not None else "not audited",
                round(cons, 4) if cons is not None else "not run",
            ]
            _write_data_row(ws, values, row, alt=(i % 2 == 0),
                            color_col=score_col, color_fn=_score_color)

    _auto_width(ws)
    _freeze_header(ws)


def _build_detailed_sheet(wb, all_stats: dict[str, dict[str, Any]],
                           db_paths: dict[str, str]) -> None:
    """Detailed sheet — one row per task (score, latency, error flag)."""
    ws = wb.create_sheet("Task Detail")
    headers = [
        "Benchmark", "task_id", "score", "latency_sec", "has_error",
        "hallucination_label",
    ]
    _write_header_row(ws, headers)

    row = 2
    for bench_label, db_path in db_paths.items():
        if not Path(db_path).exists():
            continue
        try:
            conn = sqlite3.connect(db_path)
            existing = {r[1] for r in conn.execute("PRAGMA table_info(results)").fetchall()}
            hall_col = "hallucination_label" if "hallucination_label" in existing else "NULL"
            rows = conn.execute(
                f"SELECT task_id, benchmark, score, latency_sec, error, {hall_col} "
                f"FROM results ORDER BY task_id"
            ).fetchall()
            conn.close()
        except Exception:
            continue

        for task_id, benchmark, score, latency, error, hlabel in rows:
            label = bench_label
            values = [
                label,
                task_id,
                round(score, 4) if score is not None else 0.0,
                round(latency, 2) if latency else None,
                "YES" if error else "",
                hlabel or "",
            ]
            _write_data_row(ws, values, row,
                            alt=(row % 2 == 0),
                            color_col=3,
                            color_fn=_score_color)
            row += 1

    _auto_width(ws)
    _freeze_header(ws)


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def generate_matrix(
    db_entries: list[tuple[str, str]],
    output_path: str,
    fmt: str = "summary",
) -> None:
    """
    Build the evaluation matrix workbook and write to output_path.

    db_entries: list of (benchmark_label, absolute_db_path)
    fmt:        "summary" (default) or "detailed"
    """
    # Load stats for each DB
    all_stats: dict[str, dict[str, Any]] = {}
    db_paths_map: dict[str, str] = {}
    for label, db_path in db_entries:
        stats = load_db_stats(db_path)
        if stats:
            all_stats[label] = stats
            db_paths_map[label] = db_path

    wb = openpyxl.Workbook()
    # Remove the default empty sheet
    if "Sheet" in wb.sheetnames:
        del wb["Sheet"]

    # ── Build sheets ─────────────────────────────────────────────────────
    _build_performance_sheet(wb, all_stats)
    _build_time_cost_sheet(wb, all_stats)
    _build_hallucination_sheet(wb, all_stats)
    _build_stability_sheet(wb, all_stats)
    _build_combined_sheet(wb, all_stats)

    if fmt == "detailed":
        _build_detailed_sheet(wb, all_stats, db_paths_map)

    wb.save(output_path)
    n_benchmarks = len(all_stats)
    n_rows = sum(len(s) for s in all_stats.values())
    print(f"Matrix written to: {output_path}")
    print(f"  Benchmarks: {n_benchmarks}  |  Benchmark×sub-bench rows: {n_rows}")
    print(f"  Sheets: {', '.join(wb.sheetnames)}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate formatted XLSX evaluation matrix from benchmark DBs",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Include all canonical benchmarks + auto-discovered extras",
    )
    parser.add_argument(
        "--db",
        default=None,
        help="Path to a single eval_results.db",
    )
    parser.add_argument(
        "--output",
        default="results/eval_matrix.xlsx",
        help="Output .xlsx file path (default: results/eval_matrix.xlsx)",
    )
    parser.add_argument(
        "--format",
        choices=["summary", "detailed"],
        default="summary",
        help="summary = one row per benchmark; detailed = one row per task",
    )
    args = parser.parse_args()

    # Resolve working directory to evaluation/
    os.chdir(EVAL_DIR)

    if args.db:
        db_path = Path(args.db)
        if not db_path.is_absolute():
            db_path = EVAL_DIR / db_path
        label = db_path.parent.name
        db_entries = [(label, str(db_path))]
    elif args.all:
        db_entries = _discover_all_dbs()
    else:
        # Default: canonical list
        db_entries = [
            (label, str(EVAL_DIR / rel))
            for label, rel in CANONICAL_DBS
            if (EVAL_DIR / rel).exists()
        ]

    if not db_entries:
        print("No databases found. Use --db <path> or --all.", file=sys.stderr)
        sys.exit(1)

    output_path = args.output
    if not Path(output_path).is_absolute():
        output_path = str(EVAL_DIR / output_path)
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    generate_matrix(db_entries, output_path, fmt=args.format)


if __name__ == "__main__":
    main()
