#!/usr/bin/env python3
"""
Extract benchmark metrics from a completed BioMate CryoSPARC SPA run directory.

Reads Nextflow output artefacts, QC audit events, FSC curves, particle counts,
and timing information, then writes a structured JSON metrics file and prints a
human-readable comparison table vs expected (manual-expert) processing results.

Usage:
    python extract_benchmark_metrics.py \\
        --run-dir        ./benchmark_results/empiar_10061/pipeline_results \\
        --expected-resolution 2.2 \\
        --output         ./benchmark_results/empiar_10061/metrics.json \\
        [--empiar-id     10061] \\
        [--pixel-size    0.885] \\
        [--baseline-json ./baselines/empiar_10061.json]

Output JSON schema (all values None when data unavailable):
{
    "empiar_id":               "10061",
    "run_dir":                 "/abs/path/to/results",
    "extracted_at":            "2026-04-15T12:34:56Z",
    "wall_time_s":             float | None,
    "gpu_hours":               float | None,
    "n_micrographs_processed": int   | None,
    "n_micrographs_total":     int   | None,
    "acceptance_rate_pct":     float | None,
    "n_particles_picked":      int   | None,
    "n_particles_2d":          int   | None,
    "n_particles_final":       int   | None,
    "fsc_resolution_A":        float | None,
    "expected_resolution_A":   float | None,
    "qc_gate_summary":         {gate: status, ...},
    "regressions":             [str, ...],
    "raw_events":              [...],          // QC audit events
}
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# ===========================================================================
# Helpers
# ===========================================================================

def _utcnow_iso() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _safe_int(val: Any) -> Optional[int]:
    try:
        return int(val)
    except (TypeError, ValueError):
        return None


def _safe_float(val: Any) -> Optional[float]:
    try:
        f = float(val)
        return None if math.isnan(f) or math.isinf(f) else f
    except (TypeError, ValueError):
        return None


def _find_first(directory: Path, *patterns: str) -> Optional[Path]:
    """Return the first existing file matching any of the glob patterns."""
    for pattern in patterns:
        matches = sorted(directory.glob(pattern))
        if matches:
            return matches[0]
    return None


# ===========================================================================
# 1. Wall time
# ===========================================================================

def extract_wall_time(run_dir: Path) -> Optional[float]:
    """
    Parse elapsed wall time in seconds from one of:
      a) Nextflow timeline HTML  (<!-- … Total elapsed: NNN ms … -->)
      b) trace.tsv               (realtime column, sum all tasks)
      c) .nextflow.log           (Duration: HH:mm:ss.sss line near end)
    Returns seconds as float, or None if unparseable.
    """
    # --- (a) timeline HTML ---------------------------------------------------
    timeline = _find_first(run_dir, "timeline.html", "nextflow_report.html")
    if timeline and timeline.exists():
        text = timeline.read_text(errors="replace")
        m = re.search(r"Total elapsed:\s*([\d.,]+)\s*ms", text, re.IGNORECASE)
        if m:
            return float(m.group(1).replace(",", "")) / 1000.0
        # Some Nextflow versions write "duration: Xm Ys" in the report JSON blob
        m = re.search(r'"duration"\s*:\s*"([\dhms. ]+)"', text)
        if m:
            return _parse_nextflow_duration(m.group(1))

    # --- (b) trace.tsv -------------------------------------------------------
    trace = _find_first(run_dir, "trace.tsv", "trace.txt")
    if trace and trace.exists():
        total_ms = 0.0
        found_any = False
        with open(trace) as fh:
            header = None
            for line in fh:
                line = line.rstrip("\n")
                if header is None:
                    header = line.split("\t")
                    continue
                parts = line.split("\t")
                row = dict(zip(header, parts))
                # realtime is stored as milliseconds integer string
                rt = _safe_float(row.get("realtime", ""))
                if rt is not None:
                    total_ms += rt
                    found_any = True
        if found_any:
            return total_ms / 1000.0

    # --- (c) .nextflow.log ---------------------------------------------------
    nf_log = _find_first(run_dir.parent, ".nextflow.log", "nextflow.log")
    if nf_log and nf_log.exists():
        text = nf_log.read_text(errors="replace")
        m = re.search(
            r"Duration\s*:\s*([\d]+h)?\s*([\d]+m)?\s*([\d.]+s)?",
            text,
            re.IGNORECASE,
        )
        if m:
            h = int((m.group(1) or "0h")[:-1])
            mn = int((m.group(2) or "0m")[:-1])
            s = float((m.group(3) or "0s")[:-1])
            return h * 3600 + mn * 60 + s

    return None


def _parse_nextflow_duration(s: str) -> Optional[float]:
    """Parse Nextflow duration string like '2h 13m 4s' or '4m 2.5s' → seconds."""
    total = 0.0
    for m in re.finditer(r"([\d.]+)\s*([hms])", s):
        val = float(m.group(1))
        unit = m.group(2)
        total += val * {"h": 3600, "m": 60, "s": 1}[unit]
    return total if total > 0 else None


# ===========================================================================
# 2. GPU hours
# ===========================================================================

def extract_gpu_hours(run_dir: Path) -> Optional[float]:
    """
    Estimate GPU hours by summing GPU-tagged tasks from trace.tsv.
    Falls back to a simple wall_time × gpu_workers estimate.
    """
    trace = _find_first(run_dir, "trace.tsv", "trace.txt")
    if trace and trace.exists():
        gpu_ms = 0.0
        found_any = False
        with open(trace) as fh:
            header = None
            for line in fh:
                line = line.rstrip("\n")
                if header is None:
                    header = line.split("\t")
                    continue
                parts = line.split("\t")
                row = dict(zip(header, parts))
                # GPU tasks contain 'gpu' in the queue/process name or cpus col
                is_gpu = (
                    "gpu" in (row.get("queue") or "").lower()
                    or "gpu" in (row.get("name") or "").lower()
                )
                if is_gpu:
                    rt = _safe_float(row.get("realtime", ""))
                    if rt is not None:
                        gpu_ms += rt
                        found_any = True
        if found_any:
            return gpu_ms / 3_600_000.0  # ms → GPU hours

    # Fallback: wall_time_s / 3600
    wt = extract_wall_time(run_dir)
    if wt is not None:
        return wt / 3600.0

    return None


# ===========================================================================
# 3. Micrograph counts + acceptance rate
# ===========================================================================

def extract_micrograph_counts(run_dir: Path) -> Tuple[Optional[int], Optional[int]]:
    """
    Returns (n_processed, n_total).
    Looks for:
      - motion_correction_summary.txt / ctf_summary.txt
      - micrographs_ctf.star (RELION-style)
      - trace.tsv IMPORT_MOVIES task count
    """
    # --- STAR file -----------------------------------------------------------
    star = _find_first(run_dir, "**/*ctf*.star", "**/*micrograph*.star")
    if star:
        n = _count_star_particles(star, expect_micrographs=True)
        if n is not None:
            return n, n  # processed = total when CTF star is the final output

    # --- summary text files --------------------------------------------------
    for fname in ("motion_correction_summary.txt", "ctf_summary.txt"):
        summary = _find_first(run_dir, f"**/{fname}", fname)
        if summary and summary.exists():
            text = summary.read_text(errors="replace")
            m = re.search(r"(\d+)\s+(?:of\s+)?(\d+)\s+micrograph", text, re.IGNORECASE)
            if m:
                return int(m.group(1)), int(m.group(2))
            m = re.search(r"total.*?:\s*(\d+)", text, re.IGNORECASE)
            if m:
                n = int(m.group(1))
                return n, n

    # --- trace.tsv import step -----------------------------------------------
    trace = _find_first(run_dir, "trace.tsv", "trace.txt")
    if trace and trace.exists():
        with open(trace) as fh:
            header = None
            import_count = 0
            for line in fh:
                line = line.rstrip("\n")
                if header is None:
                    header = line.split("\t")
                    continue
                parts = line.split("\t")
                row = dict(zip(header, parts))
                if "import" in (row.get("name") or "").lower():
                    import_count += 1
            if import_count > 0:
                return import_count, import_count

    return None, None


def _count_star_particles(path: Path, expect_micrographs: bool = False) -> Optional[int]:
    """Count data rows in a STAR file (skip header blocks)."""
    in_loop = False
    header_lines = 0
    data_lines = 0
    try:
        with open(path, errors="replace") as fh:
            for line in fh:
                stripped = line.strip()
                if stripped.startswith("loop_"):
                    in_loop = True
                    header_lines = 0
                    continue
                if in_loop:
                    if stripped.startswith("_"):
                        header_lines += 1
                    elif stripped and not stripped.startswith("#"):
                        data_lines += 1
        return data_lines if data_lines > 0 else None
    except OSError:
        return None


# ===========================================================================
# 4. Particle counts
# ===========================================================================

def extract_particle_counts(
    run_dir: Path,
) -> Tuple[Optional[int], Optional[int], Optional[int]]:
    """
    Returns (n_picked, n_after_2d, n_final).

    Searches for:
      - particles_picked.star / autopick.star
      - particles_2d.star / class2d.star
      - particles_selected.star / particles_final.star / refine3d.star
    """
    def _count(pattern: str) -> Optional[int]:
        f = _find_first(run_dir, f"**/{pattern}", pattern)
        return _count_star_particles(f) if f else None

    n_picked = _count("particles_picked.star") or _count("autopick.star")
    n_2d = (
        _count("particles_2d.star")
        or _count("class2d.star")
        or _count("particles_class2d.star")
    )
    n_final = (
        _count("particles_selected.star")
        or _count("particles_final.star")
        or _count("refine3d.star")
        or _count("particles_refinement.star")
    )

    # CryoSPARC-style particle counts in JSON job outputs
    for pattern in ("**/J*/job.json", "**/job_stats.json"):
        for jf in sorted(run_dir.glob(pattern)):
            try:
                data = json.loads(jf.read_text())
                if "num_particles_out" in data:
                    n_final = n_final or data["num_particles_out"]
                if "num_particles_picked" in data:
                    n_picked = n_picked or data["num_particles_picked"]
            except (json.JSONDecodeError, OSError):
                continue

    return n_picked, n_2d, n_final


# ===========================================================================
# 5. FSC resolution
# ===========================================================================

def extract_fsc_resolution(run_dir: Path, pixel_size_A: float = 1.0) -> Optional[float]:
    """
    Read FSC curve and interpolate the 0.143 gold-standard crossing.

    Supports:
      - validation_fsc.txt  (two-column: freq_inv_A  fsc)
      - fsc_*.xml           (CryoSPARC XML export)
      - postprocess_fsc.dat (RELION)
    Returns resolution in Å or None.
    """
    # --- Two-column text file ------------------------------------------------
    fsc_txt = _find_first(
        run_dir,
        "**/validation_fsc.txt",
        "**/fsc.txt",
        "**/postprocess_fsc.dat",
        "validation_fsc.txt",
    )
    if fsc_txt and fsc_txt.exists():
        freqs, corrs = [], []
        with open(fsc_txt, errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split()
                if len(parts) >= 2:
                    f = _safe_float(parts[0])
                    c = _safe_float(parts[1])
                    if f is not None and c is not None:
                        freqs.append(f)
                        corrs.append(c)
        if freqs:
            return _interpolate_fsc_crossing(freqs, corrs, threshold=0.143)

    # --- CryoSPARC XML -------------------------------------------------------
    fsc_xml = _find_first(run_dir, "**/fsc_*.xml", "fsc_*.xml")
    if fsc_xml and fsc_xml.exists():
        text = fsc_xml.read_text(errors="replace")
        # <coordinate><x>freq</x><y>corr</y></coordinate>
        xs = re.findall(r"<x>([\d.eE+\-]+)</x>", text)
        ys = re.findall(r"<y>([\d.eE+\-]+)</y>", text)
        if xs and ys and len(xs) == len(ys):
            freqs = [float(x) for x in xs]
            corrs = [float(y) for y in ys]
            return _interpolate_fsc_crossing(freqs, corrs, threshold=0.143)

    # --- CryoSPARC JSON job output -------------------------------------------
    for jf in sorted(run_dir.glob("**/J*/job.json")):
        try:
            data = json.loads(jf.read_text())
            res = data.get("fsc_resolution_A") or data.get("resolution_A")
            if res is not None:
                return float(res)
        except (json.JSONDecodeError, OSError):
            continue

    return None


def _interpolate_fsc_crossing(
    freqs: List[float],
    corrs: List[float],
    threshold: float = 0.143,
) -> Optional[float]:
    """
    Linear interpolation of the spatial frequency at which corr drops to
    *threshold*. Returns resolution in Å (1/frequency) or None.
    """
    import bisect

    if not freqs or not corrs:
        return None

    # Find the first index where corr drops below threshold
    for i in range(1, len(corrs)):
        if corrs[i] <= threshold < corrs[i - 1]:
            # Linear interpolation between (freqs[i-1], corrs[i-1]) and
            # (freqs[i], corrs[i])
            frac = (corrs[i - 1] - threshold) / (corrs[i - 1] - corrs[i])
            freq_at_crossing = freqs[i - 1] + frac * (freqs[i] - freqs[i - 1])
            if freq_at_crossing > 0:
                return 1.0 / freq_at_crossing
            return None

    # Never crossed — no defined resolution
    return None


# ===========================================================================
# 6. QC audit events
# ===========================================================================

def extract_qc_events(run_dir: Path) -> Tuple[Dict[str, str], List[Dict]]:
    """
    Read qc_audit.jsonl and return:
      - gate_summary: {gate_name: worst_status}  ("pass" < "advisory" < "halt")
      - raw_events: list of all audit event dicts
    """
    audit_file = _find_first(run_dir, "**/qc_audit.jsonl", "qc_audit.jsonl")
    if not audit_file or not audit_file.exists():
        return {}, []

    _rank = {"pass": 0, "advisory": 1, "halt": 2}
    gate_summary: Dict[str, str] = {}
    raw_events: List[Dict] = []

    with open(audit_file, errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except json.JSONDecodeError:
                continue
            raw_events.append(evt)
            gate = evt.get("gate", "unknown")
            status = evt.get("status", "pass")
            prev = gate_summary.get(gate, "pass")
            if _rank.get(status, 0) > _rank.get(prev, 0):
                gate_summary[gate] = status

    return gate_summary, raw_events


# ===========================================================================
# 7. Regression detection
# ===========================================================================

def detect_regressions(
    metrics: Dict[str, Any],
    baseline: Optional[Dict[str, Any]],
    expected_resolution_A: Optional[float],
) -> List[str]:
    """
    Compare current metrics against a baseline JSON and the expected resolution.
    Returns a list of human-readable regression descriptions.
    """
    regressions = []

    # Resolution worse than expected (larger Å = lower resolution)
    res = metrics.get("fsc_resolution_A")
    if res is not None and expected_resolution_A is not None:
        tolerance_A = 0.5  # allow 0.5 Å degradation vs expected
        if res > expected_resolution_A + tolerance_A:
            regressions.append(
                f"FSC resolution {res:.2f} Å is worse than expected "
                f"{expected_resolution_A:.2f} Å by "
                f"{res - expected_resolution_A:.2f} Å (tolerance ±{tolerance_A} Å)"
            )

    # Acceptance rate degraded
    acc = metrics.get("acceptance_rate_pct")
    if acc is not None and acc < 50.0:
        regressions.append(
            f"Micrograph acceptance rate {acc:.1f}% is below 50 % threshold"
        )

    # QC halt gates
    qc = metrics.get("qc_gate_summary", {})
    halted = [g for g, s in qc.items() if s == "halt"]
    if halted:
        regressions.append(
            f"QC halt gate(s) triggered: {', '.join(halted)}"
        )

    # Baseline comparison
    if baseline:
        baseline_res = _safe_float(baseline.get("fsc_resolution_A"))
        if baseline_res is not None and res is not None:
            if res > baseline_res + 0.3:
                regressions.append(
                    f"FSC resolution regressed vs baseline: "
                    f"{res:.2f} Å vs baseline {baseline_res:.2f} Å"
                )

        baseline_acc = _safe_float(baseline.get("acceptance_rate_pct"))
        if baseline_acc is not None and acc is not None:
            if acc < baseline_acc - 10.0:
                regressions.append(
                    f"Acceptance rate regressed vs baseline: "
                    f"{acc:.1f}% vs baseline {baseline_acc:.1f}%"
                )

    return regressions


# ===========================================================================
# 8. Comparison table
# ===========================================================================

def print_comparison_table(
    metrics: Dict[str, Any],
    baseline: Optional[Dict[str, Any]],
) -> None:
    """Print a side-by-side comparison of current vs expected/baseline metrics."""
    COL_W = 28

    def _fmt(val: Any, unit: str = "", pct: bool = False) -> str:
        if val is None:
            return "n/a"
        if pct:
            return f"{float(val):.1f}%"
        if isinstance(val, float):
            return f"{val:.2f}{unit}"
        return f"{val}{unit}"

    rows = [
        ("Metric", "Current", "Baseline / Expected"),
        ("-" * COL_W, "-" * 14, "-" * 20),
        (
            "FSC resolution (Å)",
            _fmt(metrics.get("fsc_resolution_A"), " Å"),
            _fmt(
                (baseline or {}).get("fsc_resolution_A")
                or metrics.get("expected_resolution_A"),
                " Å",
            ),
        ),
        (
            "Acceptance rate",
            _fmt(metrics.get("acceptance_rate_pct"), pct=True),
            _fmt((baseline or {}).get("acceptance_rate_pct"), pct=True),
        ),
        (
            "Particles (final)",
            _fmt(metrics.get("n_particles_final")),
            _fmt((baseline or {}).get("n_particles_final")),
        ),
        (
            "Wall time (s)",
            _fmt(metrics.get("wall_time_s"), " s"),
            _fmt((baseline or {}).get("wall_time_s"), " s"),
        ),
        (
            "GPU hours",
            _fmt(metrics.get("gpu_hours"), " GPU·h"),
            _fmt((baseline or {}).get("gpu_hours"), " GPU·h"),
        ),
    ]

    print()
    print("=" * 70)
    print("  Benchmark Comparison Table")
    print("=" * 70)
    for r in rows:
        print(f"  {r[0]:<{COL_W}}  {r[1]:<16}  {r[2]}")
    print("=" * 70)

    regressions = metrics.get("regressions", [])
    if regressions:
        print(f"\n  REGRESSIONS ({len(regressions)}):")
        for reg in regressions:
            print(f"    • {reg}")
    else:
        print("\n  No regressions detected.")
    print()


# ===========================================================================
# Main
# ===========================================================================

def extract_metrics(
    run_dir: Path,
    expected_resolution_A: Optional[float] = None,
    pixel_size_A: float = 1.0,
    empiar_id: str = "",
    baseline: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Read all available artefacts under *run_dir* and return a metrics dict.
    """
    print(f"  Extracting metrics from: {run_dir}", flush=True)

    # -- wall time ------------------------------------------------------------
    wall_time_s = extract_wall_time(run_dir)
    print(f"    wall_time_s          = {wall_time_s}")

    # -- GPU hours ------------------------------------------------------------
    gpu_hours = extract_gpu_hours(run_dir)
    print(f"    gpu_hours            = {gpu_hours}")

    # -- micrograph counts ----------------------------------------------------
    n_proc, n_total = extract_micrograph_counts(run_dir)
    acceptance_pct: Optional[float] = None
    if n_proc is not None and n_total is not None and n_total > 0:
        acceptance_pct = round(100.0 * n_proc / n_total, 2)
    print(f"    micrographs          = {n_proc} / {n_total}  ({acceptance_pct}%)")

    # -- particle counts ------------------------------------------------------
    n_picked, n_2d, n_final = extract_particle_counts(run_dir)
    print(f"    particles            = picked={n_picked}  2D={n_2d}  final={n_final}")

    # -- FSC resolution -------------------------------------------------------
    fsc_res = extract_fsc_resolution(run_dir, pixel_size_A=pixel_size_A)
    print(f"    fsc_resolution_A     = {fsc_res}")

    # -- QC events ------------------------------------------------------------
    qc_summary, raw_events = extract_qc_events(run_dir)
    print(f"    QC gate summary      = {qc_summary}")

    metrics: Dict[str, Any] = {
        "empiar_id":               empiar_id,
        "run_dir":                 str(run_dir),
        "extracted_at":            _utcnow_iso(),
        "wall_time_s":             wall_time_s,
        "gpu_hours":               gpu_hours,
        "n_micrographs_processed": n_proc,
        "n_micrographs_total":     n_total,
        "acceptance_rate_pct":     acceptance_pct,
        "n_particles_picked":      n_picked,
        "n_particles_2d":          n_2d,
        "n_particles_final":       n_final,
        "fsc_resolution_A":        fsc_res,
        "expected_resolution_A":   expected_resolution_A,
        "qc_gate_summary":         qc_summary,
        "regressions":             [],
        "raw_events":              raw_events,
    }

    metrics["regressions"] = detect_regressions(metrics, baseline, expected_resolution_A)

    return metrics


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--run-dir",
        required=True,
        help="Path to the completed pipeline results directory",
    )
    parser.add_argument(
        "--expected-resolution",
        type=float,
        default=None,
        metavar="ANGSTROM",
        help="Expected FSC resolution in Å (from manual expert processing)",
    )
    parser.add_argument(
        "--output",
        default="metrics.json",
        help="Output JSON file path (default: metrics.json)",
    )
    parser.add_argument(
        "--empiar-id",
        default="",
        help="EMPIAR entry identifier (for record-keeping)",
    )
    parser.add_argument(
        "--pixel-size",
        type=float,
        default=1.0,
        metavar="ANGSTROM",
        help="Micrograph pixel size in Å (default: 1.0)",
    )
    parser.add_argument(
        "--baseline-json",
        default=None,
        help="Optional JSON file with baseline metrics for regression detection",
    )
    parser.add_argument(
        "--no-table",
        action="store_true",
        help="Suppress the comparison table printout",
    )

    args = parser.parse_args(argv)

    run_dir = Path(args.run_dir)
    if not run_dir.exists():
        print(f"ERROR: run-dir does not exist: {run_dir}", file=sys.stderr)
        return 1

    # Load optional baseline
    baseline: Optional[Dict[str, Any]] = None
    if args.baseline_json:
        bl_path = Path(args.baseline_json)
        if bl_path.exists():
            try:
                baseline = json.loads(bl_path.read_text())
            except json.JSONDecodeError as exc:
                print(f"WARNING: Could not parse baseline JSON: {exc}", file=sys.stderr)
        else:
            print(f"WARNING: Baseline file not found: {bl_path}", file=sys.stderr)

    # Extract
    metrics = extract_metrics(
        run_dir=run_dir,
        expected_resolution_A=args.expected_resolution,
        pixel_size_A=args.pixel_size,
        empiar_id=args.empiar_id,
        baseline=baseline,
    )

    # Write JSON
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(metrics, indent=2, default=str))
    print(f"\n  Metrics written → {out_path}")

    # Print table
    if not args.no_table:
        print_comparison_table(metrics, baseline)

    # Exit non-zero if regressions detected (useful for CI)
    if metrics["regressions"]:
        print(
            f"  {len(metrics['regressions'])} regression(s) detected.",
            file=sys.stderr,
        )
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
