#!/usr/bin/env python3
"""
Merge Plan A epitopeprediction TSVs from multiple predictors (MHCnuggets + MHCflurry).

Downloads tool-specific TSVs from S3 when needed, concatenates rows (same schema),
and writes a merged table plus a short summary JSON.

Usage:
  python3 research/anti-virus/scripts/merge_plan_a_epitope_multitool.py \\
    --publication-run research/anti-virus/runs/publication_20260528T223525Z \\
    --mhcflurry-s3 s3://biomate-nextflow-work/.../mhcflurry/predictions/PLAN_A_FULL_GP.tsv
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]


def s3_cp(uri: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(["aws", "s3", "cp", uri, str(dest)], capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise SystemExit(f"aws s3 cp failed: {uri}\n{r.stderr}")


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        if not reader.fieldnames:
            raise SystemExit(f"Empty TSV header: {path}")
        rows = list(reader)
    return list(reader.fieldnames), rows


def write_tsv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t", extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def summarize_rows(rows: list[dict[str, str]]) -> dict[str, Any]:
    by_predictor = Counter(r.get("predictor", "unknown") for r in rows)
    binders = [r for r in rows if str(r.get("binder", "")).lower() == "true"]
    binder_peptides = {r.get("sequence", "").upper() for r in binders if r.get("sequence")}
    return {
        "total_rows": len(rows),
        "rows_by_predictor": dict(by_predictor),
        "binder_rows": len(binders),
        "binder_unique_peptides": len(binder_peptides),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--publication-run", type=Path, required=True)
    ap.add_argument(
        "--mhcnuggets-tsv",
        type=Path,
        default=None,
        help="Local MHCnuggets TSV (default: plan_a_epitope/PLAN_A_FULL_GP_mhcnuggets.tsv or PLAN_A_FULL_GP.tsv)",
    )
    ap.add_argument(
        "--mhcflurry-tsv",
        type=Path,
        default=None,
        help="Local MHCflurry TSV (default: plan_a_epitope/PLAN_A_FULL_GP_mhcflurry.tsv)",
    )
    ap.add_argument(
        "--mhcflurry-s3",
        default=(
            "s3://biomate-nextflow-work/nextflow/outputs/plan_a_full_gp/"
            "20260528T223525Z_commercial_multitool/mhcflurry/predictions/PLAN_A_FULL_GP.tsv"
        ),
        help="S3 URI for MHCflurry predictions (downloaded if local file missing)",
    )
    args = ap.parse_args()

    pub = args.publication_run.resolve()
    epitope_dir = pub / "plan_a_epitope"
    epitope_dir.mkdir(parents=True, exist_ok=True)

    mhcn_path = args.mhcnuggets_tsv
    if mhcn_path is None:
        for candidate in (
            epitope_dir / "PLAN_A_FULL_GP_mhcnuggets.tsv",
            epitope_dir / "PLAN_A_FULL_GP.tsv",
        ):
            if candidate.is_file():
                mhcn_path = candidate
                break
    if mhcn_path is None or not mhcn_path.is_file():
        raise SystemExit("MHCnuggets TSV not found; pass --mhcnuggets-tsv")

    mhcfl_path = args.mhcflurry_tsv or epitope_dir / "PLAN_A_FULL_GP_mhcflurry.tsv"
    if not mhcfl_path.is_file():
        print(f"Downloading MHCflurry TSV from {args.mhcflurry_s3}")
        s3_cp(args.mhcflurry_s3, mhcfl_path)

    # Preserve mhcnuggets-only copy if we started from the legacy combined filename.
    legacy = epitope_dir / "PLAN_A_FULL_GP.tsv"
    mhcn_archive = epitope_dir / "PLAN_A_FULL_GP_mhcnuggets.tsv"
    if mhcn_path == legacy and not mhcn_archive.is_file():
        mhcn_archive.write_bytes(legacy.read_bytes())
        mhcn_path = mhcn_archive

    header_m, rows_m = read_tsv(mhcn_path)
    header_f, rows_f = read_tsv(mhcfl_path)
    if header_m != header_f:
        raise SystemExit(f"TSV header mismatch:\n  mhcnuggets: {header_m}\n  mhcflurry: {header_f}")

    merged_rows = rows_m + rows_f
    merged_path = epitope_dir / "PLAN_A_FULL_GP_MULTITOOL.tsv"
    write_tsv(merged_path, header_m, merged_rows)

    summary = {
        "merged_at": datetime.now(timezone.utc).isoformat(),
        "sources": {
            "mhcnuggets": str(mhcn_path),
            "mhcflurry": str(mhcfl_path),
            "mhcflurry_s3": args.mhcflurry_s3,
        },
        "output": str(merged_path),
        "mhcnuggets": summarize_rows(rows_m),
        "mhcflurry": summarize_rows(rows_f),
        "merged": summarize_rows(merged_rows),
    }
    summary_path = epitope_dir / "PLAN_A_MULTITOOL_SUMMARY.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(f"Wrote {merged_path} ({len(merged_rows)} rows)")
    print(f"Wrote {summary_path}")
    print(
        f"MHCnuggets binders: {summary['mhcnuggets']['binder_rows']} | "
        f"MHCflurry binders: {summary['mhcflurry']['binder_rows']} | "
        f"merged unique binder peptides: {summary['merged']['binder_unique_peptides']}"
    )


if __name__ == "__main__":
    main()
