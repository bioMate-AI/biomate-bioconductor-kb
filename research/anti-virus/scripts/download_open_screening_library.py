#!/usr/bin/env python3
"""
Download an openly usable compound set for virtual screening benchmarks.

Sources:

  **delaney** (default) — DeepChem Delaney (ESOL) CSV (~1.1k compounds).
  Stable single URL; good for ML-style smoke tests.

  **zinc** — A **ZINC20 2D tranche** `.smi` file from `files.docking.org` (DISI).
  ZINC is not one monolithic file: chemistry is split into **tranches** (MW / logP /
  reactivity / purchasability code). You choose e.g. `2D/AA/AAAC.smi` via `--zinc-url`.
  See <https://files.docking.org/2D/> and the ZINC tranche browser.

Outputs (zinc source):
  - `<dataset>_<stamp>.tsv` — zinc_substance_id, smiles (recommended; preserves IDs)
  - `<dataset>_<stamp>.smi` — SMILES only (legacy / Vina input)
  - `<dataset>_<stamp>.manifest.json` — provenance and selection metadata

Usage:
  python3 research/anti-virus/scripts/download_open_screening_library.py
  python3 research/anti-virus/scripts/download_open_screening_library.py --max-compounds 500
  python3 research/anti-virus/scripts/download_open_screening_library.py --source zinc --max-compounds 600
  python3 research/anti-virus/scripts/download_open_screening_library.py --source zinc \\
    --zinc-url https://files.docking.org/2D/AA/AABA.smi --max-compounds 200
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
LIBS = ROOT / "research/anti-virus/libraries"
DELANEY_URL = "https://deepchemdata.s3-us-west-1.amazonaws.com/datasets/delaney-processed.csv"
DEFAULT_ZINC_TRANCHE_URL = "https://files.docking.org/2D/AA/AAAC.smi"


def fetch_text(url: str, timeout: int = 300) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-library-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def parse_zinc_smi_line(line: str) -> tuple[str, str] | None:
    """Parse ZINC tranche line → (smiles, zinc_substance_id)."""
    line = line.strip()
    if not line:
        return None
    parts = line.split()
    if not parts or parts[0].lower() == "smiles":
        return None
    if len(parts) >= 2 and parts[-1].isdigit():
        smi = " ".join(parts[:-1]).strip()
        zid = parts[-1]
        return smi, zid
    return parts[0], ""


def write_delaney(url: str, out_smi: Path, max_compounds: int) -> int:
    text = fetch_text(url, timeout=120)
    reader = csv.DictReader(text.splitlines())
    if not reader.fieldnames or "smiles" not in reader.fieldnames:
        raise SystemExit(f"Expected CSV with 'smiles' column; got {reader.fieldnames}")
    n = 0
    with out_smi.open("w", encoding="utf-8") as smi_out:
        for row in reader:
            smi = (row.get("smiles") or "").strip()
            if not smi:
                continue
            smi_out.write(smi + "\n")
            n += 1
            if max_compounds and n >= max_compounds:
                break
    return n


def write_zinc_tranche(
    url: str,
    out_tsv: Path,
    out_smi: Path,
    max_compounds: int,
) -> tuple[int, dict[str, Any]]:
    text = fetch_text(url, timeout=600)
    n = 0
    stats: dict[str, Any] = {"with_zinc_id": 0, "without_zinc_id": 0}
    with out_tsv.open("w", encoding="utf-8", newline="") as tsv_out, out_smi.open(
        "w", encoding="utf-8"
    ) as smi_out:
        w = csv.writer(tsv_out, delimiter="\t")
        w.writerow(["zinc_substance_id", "smiles"])
        for line in text.splitlines():
            parsed = parse_zinc_smi_line(line)
            if not parsed:
                continue
            smi, zid = parsed
            w.writerow([zid, smi])
            smi_out.write(smi + "\n")
            if zid:
                stats["with_zinc_id"] += 1
            else:
                stats["without_zinc_id"] += 1
            n += 1
            if max_compounds and n >= max_compounds:
                break
    return n, stats


def slug_from_zinc_url(url: str) -> str:
    m = re.search(r"/([^/]+)\.smi/?$", url.rstrip("/"))
    return (m.group(1) if m else "zinc_tranche").lower()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument(
        "--source",
        choices=("delaney", "zinc"),
        default="delaney",
        help="delaney=DeepChem CSV; zinc=ZINC20 2D tranche .smi",
    )
    ap.add_argument("--url", default="", help="Override URL for delaney (CSV with 'smiles' column)")
    ap.add_argument(
        "--zinc-url",
        default=DEFAULT_ZINC_TRANCHE_URL,
        help="ZINC20 2D tranche .smi URL (default: AA/AAAC)",
    )
    ap.add_argument(
        "--max-compounds",
        type=int,
        default=0,
        help="Cap compounds written (0 = parse until stream ends)",
    )
    ap.add_argument(
        "--selection",
        default="first_n_in_tranche_order",
        help="Document how compounds were chosen (manifest field)",
    )
    ap.add_argument("--out-dir", type=Path, default=LIBS)
    args = ap.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    if args.source == "delaney":
        url = args.url or DELANEY_URL
        out_smi = args.out_dir / f"delaney_esol_{stamp}.smi"
        manifest_path = args.out_dir / f"delaney_esol_{stamp}.manifest.json"
        n = write_delaney(url, out_smi, args.max_compounds)
        manifest = {
            "source_url": url,
            "dataset_name": "delaney_esol",
            "selection_method": args.selection,
            "notes": (
                "DeepChem Delaney solubility benchmark; convenient single CSV. "
                "For vendor-like decks use ZINC tranches or internal libraries."
            ),
            "compound_count": n,
            "output_smi": str(out_smi.relative_to(ROOT)),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
    else:
        url = args.zinc_url
        slug = slug_from_zinc_url(url)
        base = f"zinc20_2d_{slug}_{stamp}"
        out_tsv = args.out_dir / f"{base}.tsv"
        out_smi = args.out_dir / f"{base}.smi"
        manifest_path = args.out_dir / f"{base}.manifest.json"
        n, stats = write_zinc_tranche(url, out_tsv, out_smi, args.max_compounds)
        manifest = {
            "source_url": url,
            "dataset_name": f"zinc20_2d_{slug}",
            "zinc_tranche_slug": slug,
            "selection_method": args.selection,
            "max_compounds_requested": args.max_compounds or None,
            "notes": (
                "Subset of one ZINC20 2D tranche from DISI files.docking.org — not the full ZINC database. "
                "zinc_substance_id is the numeric ID from the tranche file (map to ZINC000… via CartBlanche). "
                "Not ANDV-target-informed unless a separate pharmacophore filter is applied."
            ),
            "compound_count": n,
            "zinc_id_stats": stats,
            "output_tsv": str(out_tsv.relative_to(ROOT)),
            "output_smi": str(out_smi.relative_to(ROOT)),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Wrote {n} compounds")
    if args.source == "zinc":
        print(f"  TSV (id+SMILES) -> {out_tsv}")
        print(f"  SMI (Vina)     -> {out_smi}")
    else:
        print(f"  SMI -> {out_smi}")
    print(f"  Manifest -> {manifest_path}")


if __name__ == "__main__":
    main()
