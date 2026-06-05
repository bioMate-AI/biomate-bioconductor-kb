#!/usr/bin/env python3
"""Pharmacophore-filter the publication ZINC600 AAAC library (local RDKit).

Mirrors BioMate `pharmacophore_filtering` SMARTS matching (min_features default 3)
using ANDV antiviral reference actives from the publication run.

Outputs under `<publication-run>/zinc600_pharmacophore/`:
  - pharmacophore_model.json
  - match_report.tsv
  - screened_scores.json
  - zinc600_pharmacophore_filtered.tsv  (zinc_substance_id, smiles, features_matched)
  - zinc600_pharmacophore_filtered.smi
  - ZINC600_PHARMACOPHORE_LIBRARY.md
  - zinc600_pharmacophore_filtered.manifest.json

Usage:
  python3 research/anti-virus/scripts/filter_zinc_library_pharmacophore.py \\
    --publication-run research/anti-virus/runs/publication_20260528T223525Z
"""
from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from rdkit import Chem
from rdkit.Chem import ChemicalFeatures, MolFromSmiles, MolFromSmarts, RDConfig

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"

SMARTS_MAP = {
    "Donor": "[OX2H,NX3H2,NX3H1]",
    "Acceptor": "[OX1,NX3;!$(NC=O)]",
    "Aromatic": "c1ccccc1",
    "Hydrophobe": "[c,s,S&H0&v2,Br,I,$(C(F)(F)F),$(CC(F)(F)F)]",
    "PosIonizable": "[+!H0,$(N-[CX3]=[NH]),$(NC(=N)N),$(n1ccnc1)]",
    "NegIonizable": "[$([CX3](=O)[OX1H0-,OX2H1]),$([SX4](=[OX1])(=[OX1])([OX2H,OX1H0-])[OX2H,OX1H0-])]",
}


def build_feature_factory():
    for fdef in (
        RDConfig.RDDataDir + "/BaseFeatures.fdef",
        "/usr/share/rdkit/Data/BaseFeatures.fdef",
        "/usr/local/share/rdkit/Data/BaseFeatures.fdef",
    ):
        if Path(fdef).is_file():
            return ChemicalFeatures.BuildFeatureFactory(fdef)
    raise SystemExit("Could not locate RDKit BaseFeatures.fdef")


def load_reference_smiles(path: Path) -> list[str]:
    smiles: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "\t" in line:
            smiles.append(line.split("\t", 1)[1].strip())
        else:
            smiles.append(line.split()[0])
    return smiles


def build_model(reference_smiles: list[str], factory) -> dict[str, Any]:
    feature_counts: dict[str, int] = defaultdict(int)
    n_valid = 0
    for smi in reference_smiles:
        mol = MolFromSmiles(smi)
        if mol is None:
            continue
        n_valid += 1
        seen: set[str] = set()
        for feat in factory.GetFeaturesForMol(mol):
            ft = feat.GetFamily()
            if ft not in seen:
                feature_counts[ft] += 1
                seen.add(ft)
    if n_valid == 0:
        raise SystemExit("No valid reference SMILES")

    features = []
    for idx, (ftype, count) in enumerate(sorted(feature_counts.items(), key=lambda x: -x[1])):
        features.append(
            {
                "type": ftype,
                "label": f"{ftype[0]}{idx}",
                "description": ftype,
                "count_in_references": count,
                "fraction": round(count / n_valid, 3),
                "smarts": SMARTS_MAP.get(ftype, ""),
            }
        )
    return {
        "source": "rdkit",
        "n_references": n_valid,
        "reference_smiles": reference_smiles,
        "n_features": len(features),
        "features": features,
        "generate_3d": False,
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }


def compile_patterns(model: dict[str, Any]) -> list[tuple[str, str, Any]]:
    compiled = []
    for ft in model["features"]:
        smarts = ft.get("smarts") or ""
        if not smarts:
            continue
        pat = MolFromSmarts(smarts)
        if pat is not None:
            compiled.append((ft["type"], ft["label"], pat))
    return compiled


def load_library_tsv(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    with path.open(newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            zid = (row.get("zinc_substance_id") or "").strip()
            sm = (row.get("smiles") or "").strip()
            if zid and sm:
                rows.append((zid, sm))
    return rows


def screen_library(
    library: list[tuple[str, str]],
    compiled: list[tuple[str, str, Any]],
    *,
    min_features: int,
) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for zid, smi in library:
        mol = MolFromSmiles(smi)
        if mol is None:
            results.append(
                {
                    "compound_id": zid,
                    "smiles": smi,
                    "features_matched": 0,
                    "feature_types": [],
                    "pass": False,
                    "parse_error": True,
                }
            )
            continue
        matched: list[str] = []
        seen: set[str] = set()
        for ftype, _label, pat in compiled:
            if ftype not in seen and mol.HasSubstructMatch(pat):
                matched.append(ftype)
                seen.add(ftype)
        n_matched = len(matched)
        results.append(
            {
                "compound_id": zid,
                "smiles": smi,
                "features_matched": n_matched,
                "feature_types": matched,
                "pass": n_matched >= min_features,
            }
        )
    return results


def write_match_report(path: Path, results: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["compound_id", "smiles", "features_matched", "feature_types_matched", "pass"])
        for r in results:
            w.writerow(
                [
                    r["compound_id"],
                    r["smiles"],
                    r["features_matched"],
                    ",".join(r["feature_types"]),
                    "PASS" if r["pass"] else "FAIL",
                ]
            )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    ap.add_argument(
        "--reference-actives",
        type=Path,
        default=None,
        help="SMILES or named TSV (default: assets/reference_actives_antiviral.smi)",
    )
    ap.add_argument("--library-tsv", type=Path, default=None, help="Default: assets/zinc600_library.tsv")
    ap.add_argument("--min-features", type=int, default=3)
    ap.add_argument("--max-output", type=int, default=None, help="Cap filtered library size (default: all passed)")
    args = ap.parse_args()

    pub = args.publication_run.resolve()
    assets = pub / "assets"
    ref_path = args.reference_actives or (assets / "reference_actives_antiviral.smi")
    lib_path = args.library_tsv or (assets / "zinc600_library.tsv")
    if not ref_path.is_file():
        raise SystemExit(f"Reference actives not found: {ref_path}")
    if not lib_path.is_file():
        raise SystemExit(f"Library TSV not found: {lib_path}")

    out_dir = pub / "zinc600_pharmacophore"
    out_dir.mkdir(parents=True, exist_ok=True)

    factory = build_feature_factory()
    ref_smiles = load_reference_smiles(ref_path)
    model = build_model(ref_smiles, factory)
    compiled = compile_patterns(model)
    library = load_library_tsv(lib_path)
    results = screen_library(library, compiled, min_features=args.min_features)
    passed = [r for r in results if r["pass"]]
    if args.max_output:
        passed = passed[: args.max_output]

    (out_dir / "pharmacophore_model.json").write_text(json.dumps(model, indent=2), encoding="utf-8")
    write_match_report(out_dir / "match_report.tsv", results)
    scores = {
        "pharmacophore_model": "pharmacophore_model.json",
        "library": str(lib_path),
        "reference_actives": str(ref_path),
        "n_screened": len(results),
        "n_passed": len(passed),
        "min_features": args.min_features,
        "pass_rate_pct": round(100.0 * len(passed) / max(len(results), 1), 2),
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    (out_dir / "screened_scores.json").write_text(json.dumps(scores, indent=2), encoding="utf-8")

    filtered_tsv = out_dir / "zinc600_pharmacophore_filtered.tsv"
    with filtered_tsv.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["zinc_substance_id", "smiles", "features_matched", "feature_types_matched"])
        for r in passed:
            w.writerow([r["compound_id"], r["smiles"], r["features_matched"], ",".join(r["feature_types"])])

    filtered_smi = out_dir / "zinc600_pharmacophore_filtered.smi"
    filtered_smi.write_text("\n".join(r["smiles"] for r in passed) + ("\n" if passed else ""), encoding="utf-8")

    manifest = {
        "created_at": scores["timestamp"],
        "publication_run": str(pub),
        "parent_library": str(lib_path),
        "parent_provenance": str(pub / "assets/zinc600_library.manifest.json"),
        "reference_actives": str(ref_path),
        "min_features": args.min_features,
        "n_screened": len(results),
        "n_passed": len(passed),
        "pass_rate_pct": scores["pass_rate_pct"],
        "target_informed": True,
        "pharmacophore_prefilter": True,
        "selection_method": "rdkit_smarts_min_features_from_antiviral_references",
        "files": {
            "filtered_tsv": str(filtered_tsv.relative_to(ROOT)),
            "filtered_smi": str(filtered_smi.relative_to(ROOT)),
            "match_report": str((out_dir / "match_report.tsv").relative_to(ROOT)),
            "model": str((out_dir / "pharmacophore_model.json").relative_to(ROOT)),
        },
    }
    (out_dir / "zinc600_pharmacophore_filtered.manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )

    md = [
        "# ZINC600 pharmacophore-filtered library",
        "",
        f"_Generated: {scores['timestamp']}_",
        "",
        "## Design",
        "",
        f"- **Parent deck:** AAAC tranche first 600 (`assets/zinc600_library.tsv`)",
        f"- **Reference actives:** `{ref_path.name}` (ribavirin, favipiravir, umifenovir, oseltamivir)",
        f"- **Filter:** RDKit SMARTS consensus model, **min_features = {args.min_features}**",
        f"- **Pass rate:** **{len(passed)} / {len(results)}** ({scores['pass_rate_pct']}%)",
        "",
        "## vs raw AAAC slice",
        "",
        "| | Raw ZINC600 | Pharmacophore-filtered |",
        "|---|---:|---:|",
        f"| Target-informed pre-filter | No | **Yes** |",
        f"| Compounds | 600 | {len(passed)} |",
        f"| Reference actives in deck | 0/4 | screened separately |",
        "",
        "## Outputs",
        "",
        f"- `{filtered_tsv.name}` — substance ID + SMILES + match stats",
        f"- `{filtered_smi.name}` — Vina input deck",
        f"- `match_report.tsv` — full 600-row screen",
        f"- `pharmacophore_model.json` — feature model from references",
        "",
        "## Next step",
        "",
        "Dock `zinc600_pharmacophore_filtered.smi` with the same 9P3I box as ZINC600 "
        "(compare hit rates and chemotype overlap vs unfiltered AAAC).",
    ]
    (out_dir / "ZINC600_PHARMACOPHORE_LIBRARY.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    print(f"Screened {len(results)} → {len(passed)} passed (min_features={args.min_features})")
    print(f"Wrote {out_dir}")


if __name__ == "__main__":
    main()
