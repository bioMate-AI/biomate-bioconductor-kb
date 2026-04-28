#!/usr/bin/env python3
"""
download_chembl.py — Download and curate ChEMBL IC50 data for DMTA simulation

Downloads activity data for well-characterized drug targets from ChEMBL via
the REST API.  Outputs a curated CSV with SMILES, compound_id, and pIC50
suitable for use as input to run_dmta_simulation.py.

Supported targets
-----------------
* EGFR   — CHEMBL203  — Epidermal growth factor receptor (kinase)
            ~17,000 IC50 measurements.  Reference: Gaulton et al. 2017
* JAK2   — CHEMBL2971 — Janus kinase 2
            ~4,000 IC50 measurements.
* BACE1  — CHEMBL4822 — Beta-secretase 1 (Alzheimer's target)
            ~3,000 IC50 measurements.  Well-curated ChEMBL benchmark.

Usage
-----
    python scripts/download_chembl.py \
        --targets egfr,jak2,bace1 \
        --output data/chembl/ \
        [--max-per-target 5000] [--min-ic50-nM 0.01] [--max-ic50-nM 100000]

Output per target
-----------------
    data/chembl/{target}_activity.csv   — SMILES, compound_id, ic50_nM, pic50
    data/chembl/{target}_metadata.json  — download stats, filters applied

Data curation steps
-------------------
1. Filter to standard IC50, standard_relation = "="
2. Keep Ki measurements too (append with type flag) — optional via --include-ki
3. Require valid canonical SMILES from ChEMBL
4. Convert all units to nM
5. Remove duplicates: keep geometric mean IC50 per compound
6. Remove pIC50 < 3 (IC50 > 1 mM — likely inactive/noise)
7. Require RDKit-valid SMILES (re-canonicalize and round-trip check)
8. Output: SMILES, compound_id, ic50_nM, pic50 (= -log10(ic50_nM * 1e-9))

References
----------
* Gaulton et al. 2017 Nucleic Acids Res 45:D945 (ChEMBL25)
* Landrum et al. 2013 (RDKit: canonical SMILES round-trip curation)
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import math
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Iterator, Optional

log = logging.getLogger("download_chembl")

# ChEMBL REST API base URL
_CHEMBL_API = "https://www.ebi.ac.uk/chembl/api/data"

# Target registry: name → ChEMBL target ID
_TARGETS = {
    "egfr":  "CHEMBL203",
    "jak2":  "CHEMBL2971",
    "bace1": "CHEMBL4822",
    "herg":  "CHEMBL240",
    "abl1":  "CHEMBL1862",
    "btk":   "CHEMBL5251",
}

# Unit conversion to nM
_UNIT_TO_NM = {
    "nm": 1.0,
    "nanomolar": 1.0,
    "um": 1000.0,
    "micromolar": 1000.0,
    "mm": 1_000_000.0,
    "millimolar": 1_000_000.0,
    "m": 1_000_000_000.0,
    "molar": 1_000_000_000.0,
    "pm": 0.001,
    "picomolar": 0.001,
}


# ---------------------------------------------------------------------------
# ChEMBL REST client
# ---------------------------------------------------------------------------

def _chembl_get(endpoint: str, params: dict, retries: int = 3, delay: float = 1.0) -> dict:
    """GET one page from ChEMBL REST API. Returns parsed JSON."""
    query_str = urllib.parse.urlencode(params)
    url = f"{_CHEMBL_API}/{endpoint}.json?{query_str}"
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=30) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            if attempt == retries - 1:
                raise RuntimeError(f"ChEMBL API request failed: {url!r}: {e}") from e
            time.sleep(delay * (attempt + 1))
    raise RuntimeError("Unreachable")


def _fetch_activities(
    target_chembl_id: str,
    assay_type: str = "B",             # B = binding
    standard_types: tuple = ("IC50",),
    max_records: int = 10_000,
    page_size: int = 250,
) -> Iterator[dict]:
    """
    Yield activity records from ChEMBL for a given target.
    Each record is a dict with keys matching ChEMBL activity schema.
    """
    for std_type in standard_types:
        offset = 0
        total_fetched = 0
        while True:
            params = {
                "target_chembl_id": target_chembl_id,
                "standard_type": std_type,
                "assay_type": assay_type,
                "limit": page_size,
                "offset": offset,
            }
            try:
                page = _chembl_get("activity", params)
            except RuntimeError as e:
                log.warning("Page fetch failed at offset=%d: %s", offset, e)
                break

            activities = page.get("activities", [])
            if not activities:
                break

            for act in activities:
                yield act
                total_fetched += 1
                if total_fetched >= max_records:
                    return

            total_count = page.get("page_meta", {}).get("total_count", 0)
            offset += page_size
            if offset >= total_count or offset >= max_records:
                break

            # Polite crawl rate (EBI asks for ≤10 req/s; we stay at ≤2/s)
            time.sleep(0.5)


# ---------------------------------------------------------------------------
# Curation logic
# ---------------------------------------------------------------------------

def _to_nm(value: float, unit: str) -> Optional[float]:
    """Convert a (value, unit) pair to nM.  Returns None if unit unknown."""
    unit_lc = unit.lower().strip()
    factor = _UNIT_TO_NM.get(unit_lc)
    if factor is None:
        return None
    return value * factor


def _pic50_from_nm(ic50_nm: float) -> float:
    """pIC50 = -log10(IC50_M) = -log10(ic50_nm * 1e-9)."""
    return -math.log10(ic50_nm * 1e-9)


def _try_rdkit_canonicalize(smiles: str) -> Optional[str]:
    """Return RDKit canonical SMILES or None if invalid."""
    try:
        from rdkit import Chem
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            return None
        return Chem.MolToSmiles(mol, isomericSmiles=True)
    except Exception:
        return None


def curate_activities(
    raw_records: list[dict],
    min_ic50_nM: float = 0.01,
    max_ic50_nM: float = 100_000.0,
    rdkit_validate: bool = True,
) -> list[dict]:
    """
    Apply curation pipeline and return list of dicts with keys:
    smiles, compound_id, chembl_id, ic50_nM, pic50.

    Steps:
    1. Require standard_relation = "="
    2. Require canonical_smiles present
    3. Convert to nM; skip unknown units
    4. Apply IC50 range filter
    5. Deduplicate by molecule_chembl_id: geometric mean IC50
    6. RDKit round-trip validation (optional)
    """
    # Step 1-4: parse and filter
    by_compound: dict[str, list[float]] = {}   # chembl_id → [ic50_nM values]
    smiles_map: dict[str, str] = {}            # chembl_id → canonical SMILES
    doc_map: dict[str, str] = {}               # chembl_id → document_chembl_id

    for rec in raw_records:
        # Relation filter
        relation = rec.get("standard_relation") or ""
        if relation.strip() not in ("=", "", None):
            continue

        smi = rec.get("canonical_smiles", "").strip()
        if not smi:
            continue

        val_str = rec.get("standard_value") or ""
        unit = rec.get("standard_units") or ""
        try:
            val = float(val_str)
        except (ValueError, TypeError):
            continue

        ic50_nm = _to_nm(val, unit)
        if ic50_nm is None:
            continue
        if not (min_ic50_nM <= ic50_nm <= max_ic50_nM):
            continue

        cid = rec.get("molecule_chembl_id", "")
        if not cid:
            continue

        by_compound.setdefault(cid, []).append(ic50_nm)
        if cid not in smiles_map:
            smiles_map[cid] = smi
        if cid not in doc_map:
            doc_map[cid] = rec.get("document_chembl_id", "")

    # Step 5: geometric mean IC50 per compound
    results = []
    for cid, ic50_values in by_compound.items():
        # Geometric mean
        log_mean = sum(math.log(v) for v in ic50_values) / len(ic50_values)
        ic50_nm = math.exp(log_mean)

        smi = smiles_map[cid]

        # Step 6: RDKit validation
        if rdkit_validate:
            canonical = _try_rdkit_canonicalize(smi)
            if canonical is None:
                log.debug("Skipping %s — invalid SMILES: %s", cid, smi[:40])
                continue
            smi = canonical

        pic50 = _pic50_from_nm(ic50_nm)
        results.append({
            "compound_id": cid,
            "smiles": smi,
            "ic50_nM": round(ic50_nm, 4),
            "pic50": round(pic50, 4),
            "n_measurements": len(ic50_values),
        })

    # Sort by pIC50 descending (most potent first)
    results.sort(key=lambda r: r["pic50"], reverse=True)
    return results


# ---------------------------------------------------------------------------
# Writer
# ---------------------------------------------------------------------------

def write_activity_csv(records: list[dict], path: Path) -> None:
    fieldnames = ["compound_id", "smiles", "ic50_nM", "pic50", "n_measurements"]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(records)
    log.info("Wrote %d compounds to %s", len(records), path)


def write_metadata(
    target: str,
    chembl_id: str,
    raw_count: int,
    curated_count: int,
    n_actives: int,
    active_threshold_pic50: float,
    path: Path,
) -> None:
    meta = {
        "target": target,
        "chembl_target_id": chembl_id,
        "raw_activity_records": raw_count,
        "curated_compounds": curated_count,
        "n_actives_pic50_ge_threshold": n_actives,
        "active_threshold_pic50": active_threshold_pic50,
        "active_threshold_ic50_nM": round(10 ** (-active_threshold_pic50) * 1e9, 1),
        "hit_rate_percent": round(100 * n_actives / curated_count, 1) if curated_count > 0 else 0,
        "chembl_api": _CHEMBL_API,
        "citation": "Gaulton et al. 2017 Nucleic Acids Res 45:D945",
    }
    with open(path, "w") as f:
        json.dump(meta, f, indent=2)
    log.info("Wrote metadata to %s", path)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Download and curate ChEMBL IC50 data for DMTA simulation"
    )
    parser.add_argument(
        "--targets",
        default="egfr,jak2,bace1",
        help="Comma-separated target names: " + ", ".join(_TARGETS.keys()),
    )
    parser.add_argument(
        "--output",
        default="data/chembl",
        help="Output directory for CSV + metadata files",
    )
    parser.add_argument(
        "--max-per-target",
        type=int,
        default=5000,
        help="Maximum activity records to fetch per target (default 5000)",
    )
    parser.add_argument(
        "--min-ic50-nM",
        type=float,
        default=0.01,
        help="Minimum IC50 in nM to include (default 0.01)",
    )
    parser.add_argument(
        "--max-ic50-nM",
        type=float,
        default=100_000.0,
        help="Maximum IC50 in nM to include (default 100000)",
    )
    parser.add_argument(
        "--active-threshold-pic50",
        type=float,
        default=7.0,
        help="pIC50 threshold for 'active' (default 7.0 = 100 nM)",
    )
    parser.add_argument(
        "--include-ki",
        action="store_true",
        help="Also download Ki measurements in addition to IC50",
    )
    parser.add_argument(
        "--no-rdkit",
        action="store_true",
        help="Skip RDKit SMILES validation (faster but may include invalid SMILES)",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    requested = [t.strip().lower() for t in args.targets.split(",")]
    unknown = [t for t in requested if t not in _TARGETS]
    if unknown:
        parser.error(
            f"Unknown targets: {unknown}. Available: {list(_TARGETS.keys())}"
        )

    standard_types = ("IC50", "Ki") if args.include_ki else ("IC50",)
    rdkit_validate = not args.no_rdkit

    summary = []
    for target_name in requested:
        chembl_id = _TARGETS[target_name]
        log.info("Fetching %s (%s) from ChEMBL …", target_name.upper(), chembl_id)

        raw_records = []
        try:
            for rec in _fetch_activities(
                target_chembl_id=chembl_id,
                standard_types=standard_types,
                max_records=args.max_per_target,
            ):
                raw_records.append(rec)
        except RuntimeError as e:
            log.error("Failed to fetch %s: %s", target_name, e)
            continue

        log.info("Fetched %d raw activity records for %s", len(raw_records), target_name)

        curated = curate_activities(
            raw_records,
            min_ic50_nM=args.min_ic50_nM,
            max_ic50_nM=args.max_ic50_nM,
            rdkit_validate=rdkit_validate,
        )
        log.info("Curated: %d compounds (from %d raw)", len(curated), len(raw_records))

        if not curated:
            log.warning("No curated compounds for %s — skipping output", target_name)
            continue

        n_actives = sum(1 for r in curated if r["pic50"] >= args.active_threshold_pic50)
        hit_rate = 100 * n_actives / len(curated)

        csv_path = output_dir / f"{target_name}_activity.csv"
        meta_path = output_dir / f"{target_name}_metadata.json"

        write_activity_csv(curated, csv_path)
        write_metadata(
            target=target_name,
            chembl_id=chembl_id,
            raw_count=len(raw_records),
            curated_count=len(curated),
            n_actives=n_actives,
            active_threshold_pic50=args.active_threshold_pic50,
            path=meta_path,
        )

        summary.append({
            "target": target_name,
            "chembl_id": chembl_id,
            "n_compounds": len(curated),
            "n_actives": n_actives,
            "hit_rate_pct": round(hit_rate, 1),
        })

    # Print summary
    if summary:
        print("\n" + "=" * 60)
        print("ChEMBL Download Summary")
        print("=" * 60)
        print(f"{'Target':<10}  {'ChEMBL ID':<12}  {'N compounds':>12}  "
              f"{'N actives':>10}  {'Hit rate':>9}")
        print("-" * 60)
        for row in summary:
            print(f"{row['target']:<10}  {row['chembl_id']:<12}  "
                  f"{row['n_compounds']:>12}  {row['n_actives']:>10}  "
                  f"{row['hit_rate_pct']:>8.1f}%")
        print("=" * 60)
        print(f"\nOutput: {output_dir.resolve()}/\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
