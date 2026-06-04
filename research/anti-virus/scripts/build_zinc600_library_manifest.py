#!/usr/bin/env python3
"""Attach ZINC substance IDs to the publication zinc600_library (from AAAC tranche)."""
from __future__ import annotations

import argparse
import csv
import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
DEFAULT_TRANCHE_URL = "https://files.docking.org/2D/AA/AAAC.smi"


def fetch_tranche(url: str, cache: Path | None) -> str:
    if cache and cache.is_file():
        return cache.read_text(encoding="utf-8")
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-library-manifest/1.0"})
    with urllib.request.urlopen(req, timeout=600) as resp:
        text = resp.read().decode("utf-8", errors="replace")
    if cache:
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(text, encoding="utf-8")
    return text


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    ap.add_argument("--tranche-url", default=DEFAULT_TRANCHE_URL)
    ap.add_argument("--cache-tranche", type=Path, default=None)
    args = ap.parse_args()

    pub = args.publication_run.resolve()
    assets = pub / "assets"
    smi_path = assets / "zinc600_library.smi"
    if not smi_path.is_file():
        raise SystemExit(f"Missing {smi_path}")

    smiles_order = [l.strip() for l in smi_path.read_text(encoding="utf-8").splitlines() if l.strip()]
    cache = args.cache_tranche or (pub / "zinc600_screen/cache/AAAC_tranche.smi")
    text = fetch_tranche(args.tranche_url, cache)

    tranche_rows: list[tuple[str, str]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("smiles"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        tranche_rows.append((" ".join(parts[:-1]), parts[-1]))

    tranche_by_sm = {sm: zid for sm, zid in tranche_rows}
    tranche_first_n = tranche_rows[: len(smiles_order)]

    if [sm for sm, _ in tranche_first_n] != smiles_order:
        raise SystemExit(
            "zinc600_library.smi does not match first-N order of AAAC tranche — "
            "refuse to write manifest without explicit reconciliation."
        )

    tsv_path = assets / "zinc600_library.tsv"
    with tsv_path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["zinc_substance_id", "smiles"])
        for sm in smiles_order:
            w.writerow([tranche_by_sm[sm], sm])

    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "publication_run": str(pub),
        "compound_count": len(smiles_order),
        "source_tranche_url": args.tranche_url,
        "selection_method": "first_n_in_tranche_file_order",
        "selection_n": len(smiles_order),
        "tranche_total_lines_approx": len(tranche_rows),
        "campaign_gate": "FEEDBACK_CROSSWALK: replace 6-compound demo with >=500 compounds",
        "target_informed": False,
        "pharmacophore_prefilter": False,
        "reference_actives_included": False,
        "files": {
            "smiles_only": str(smi_path.relative_to(ROOT)),
            "id_and_smiles": str(tsv_path.relative_to(ROOT)),
            "provenance_doc": str(
                (pub / "zinc600_screen/ZINC600_LIBRARY_PROVENANCE.md").relative_to(ROOT)
            ),
        },
        "notes": (
            "600 compounds are not ANDV ground truth. They are the first 600 entries of "
            "ZINC20 2D tranche AAAC (polar, small-MW slice). Use zinc600_library.tsv for "
            "purchasability; zinc600_library.smi remains the Vina input deck."
        ),
    }
    manifest_path = assets / "zinc600_library.manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"Wrote {tsv_path} ({len(smiles_order)} rows)")
    print(f"Wrote {manifest_path}")
    print("Order check: PASS (matches AAAC tranche first 600)")


if __name__ == "__main__":
    main()
