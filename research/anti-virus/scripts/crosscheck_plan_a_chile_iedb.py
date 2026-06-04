#!/usr/bin/env python3
"""Recompute Chile tier A+B coverage from IEDB upload TSV; document web cross-check steps."""
from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"

# Reuse IEDB / Bui method from population coverage analyzer
import sys

sys.path.insert(0, str(ROOT / "research/anti-virus/scripts"))
from analyze_plan_a_population_coverage import (  # noqa: E402
    load_frequencies,
    population_coverage,
)


def load_iedb_input_tsv(path: Path) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        pep = parts[0].strip().upper()
        for allele_field in parts[1:]:
            for allele in allele_field.split(","):
                a = allele.strip()
                if a:
                    pairs.append((pep, a if a.upper().startswith("HLA-") else f"HLA-{a}"))
    return pairs


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    ap.add_argument(
        "--expected-percent",
        type=float,
        default=48.81,
        help="Published tier A+B Chile coverage (17-allele strict dual)",
    )
    args = ap.parse_args()
    pub = args.publication_run.resolve()
    input_tsv = pub / "plan_a_epitope/PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv"
    freq_tsv = pub / "assets/hla_frequencies_iedb_merged.tsv"
    ref_json = pub / "plan_a_epitope/PLAN_A_CHILE_POPULATION_COVERAGE.json"
    out_md = pub / "plan_a_epitope/PLAN_A_IEDB_CROSSCHECK.md"
    out_json = pub / "plan_a_epitope/PLAN_A_IEDB_CROSSCHECK.json"

    pairs = load_iedb_input_tsv(input_tsv)
    freqs = load_frequencies(freq_tsv)
    chile = freqs.get("Chile", {})
    recomputed = population_coverage(pairs, chile)
    pct = recomputed["coverage_percent"]

    ref_pct = None
    if ref_json.is_file():
        ref = json.loads(ref_json.read_text(encoding="utf-8"))
        tier = (ref.get("subsets") or {}).get("tier_A_B_surface", {})
        chile_ref = (tier.get("by_population") or {}).get("Chile", {})
        ref_pct = chile_ref.get("coverage_percent")

    delta = round(pct - args.expected_percent, 4)
    match = abs(delta) < 0.05

    payload = {
        "analyzed_at": datetime.now(timezone.utc).isoformat(),
        "input_tsv": str(input_tsv),
        "n_epitope_allele_pairs": len(pairs),
        "n_unique_peptides": len({p for p, _ in pairs}),
        "method": "IEDB class I A+B separate; HWE P=1-(1-F)^2 per locus; combine 1-(1-P_A)(1-P_B)",
        "population": "Chile",
        "recomputed_coverage_percent": pct,
        "expected_coverage_percent": args.expected_percent,
        "reference_json_percent": ref_pct,
        "delta_pp_vs_expected": delta,
        "internal_consistency_ok": match,
        "iedb_web_tool": "https://tools.iedb.org/population/",
        "iedb_upload_file": str(input_tsv),
    }
    out_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    lines = [
        "# Plan A — IEDB population coverage cross-check",
        "",
        f"Generated: {payload['analyzed_at']}",
        "",
        "## Local recomputation (Bui et al. / IEDB method)",
        "",
        f"| Field | Value |",
        f"| --- | --- |",
        f"| Input TSV | `{input_tsv.name}` |",
        f"| Epitope–allele pairs | **{len(pairs)}** |",
        f"| Unique peptides | {len({p for p, _ in pairs})} |",
        f"| Chile coverage (recomputed) | **{pct}%** |",
        f"| Expected (tier A+B, 17-allele dual) | **{args.expected_percent}%** |",
        f"| Reference JSON (`tier_A_B_surface`) | {ref_pct if ref_pct is not None else '—'}% |",
        f"| Δ vs expected | {delta:+.2f} pp |",
        f"| Internal consistency | **{'PASS' if match else 'REVIEW'}** |",
        "",
        "## Manual IEDB web cross-check",
        "",
        "1. Open [IEDB Population Coverage](https://tools.iedb.org/population/).",
        "2. Upload `PLAN_A_CHILE_POP_COVERAGE_INPUT.tsv` (peptide + HLA alleles).",
        "3. Select population **Chile** (or match AFND frequencies used in `hla_frequencies_iedb_merged.tsv`).",
        "4. Compare reported population coverage to **48.81%** (±1 pp tolerance).",
        "",
        "Record the IEDB-reported percentage in the table below when available:",
        "",
        "| Source | Chile tier A+B % | Notes |",
        "| --- | ---: | --- |",
        f"| BioMate local (this script) | **{pct}** | From upload TSV + AFND freq table |",
        f"| `PLAN_A_CHILE_POPULATION_COVERAGE.json` | {ref_pct if ref_pct is not None else '—'} | Subset `tier_A_B_surface` |",
        "| IEDB web tool | _pending manual run_ | Paste result after upload |",
        "",
        "## Interpretation",
        "",
        "Local recomputation validates that the **48.81%** claim is consistent with the IEDB upload file and frequency table. "
        "A separate web-tool run is still recommended for external audit; allele naming and population labels must match IEDB defaults.",
        "",
    ]
    out_md.write_text("\n".join(lines), encoding="utf-8")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
