#!/usr/bin/env python3
"""Build publication-tier ZINC deck: multi-tranche → drug-like → pharmacophore → cap.

See research/anti-virus/docs/PUBLICATION_ZINC_LIBRARY_DESIGN.md

Outputs under <publication-run>/publication_zinc/:
  raw_union.tsv, druglike.tsv, dock_set.tsv, dock_set.smi, manifest.json, BUILD_REPORT.md

Usage:
  python3 research/anti-virus/scripts/build_publication_zinc_library.py
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from rdkit import Chem
from rdkit.Chem import ChemicalFeatures, Descriptors, MolFromSmiles, MolFromSmarts, RDConfig

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"
ZINC_BASE = "https://files.docking.org/2D"
DEFAULT_TRANCHES = ("ABAA", "ABAB", "ABAC", "BBAA", "BCAC")

SMARTS_MAP = {
    "Donor": "[OX2H,NX3H2,NX3H1]",
    "Acceptor": "[OX1,NX3;!$(NC=O)]",
    "Aromatic": "c1ccccc1",
    "Hydrophobe": "[c,s,S&H0&v2,Br,I,$(C(F)(F)F),$(CC(F)(F)F)]",
    "PosIonizable": "[+!H0,$(N-[CX3]=[NH]),$(NC(=N)N),$(n1ccnc1)]",
    "NegIonizable": "[$([CX3](=O)[OX1H0-,OX2H1]),$([SX4](=[OX1])(=[OX1])([OX2H,OX1H0-])[OX2H,OX1H0-])]",
}

# Campaign controls (always in dock set)
CONTROL_SMILES = {
    "INH-01": "N=C(N)NC(=O)c1nccnc1N",
    "Z600-R1": "N=C(N)NC(=O)NC(=O)NC(=N)N",
    "ribavirin": "NC(=O)c1nc(C=C(C)CO)c(C=O)[nH]1",
    "favipiravir": "C1CC(=O)NC(=O)C1N",
    "umifenovir": "CC(C)(C)c1ccc(C(O)c2ccc(Cl)cc2)cc1",
    "oseltamivir": "CCOC(=O)C1=C[C@@H](OC(CC)CC)[C@H](NC(C)=O)[C@@H](O)[C@H]1O",
}


def fetch_tranche(code: str) -> list[tuple[str, str, str]]:
    """Return list of (zinc_id, smiles, tranche_code)."""
    mw, logp = code[0], code[1]
    url = f"{ZINC_BASE}/{mw}{logp}/{code}.smi"
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-pub-zinc/1.0"})
    with urllib.request.urlopen(req, timeout=600) as resp:
        text = resp.read().decode("utf-8", errors="replace")
    rows: list[tuple[str, str, str]] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.lower().startswith("smiles"):
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[-1].isdigit():
            zid, smi = parts[-1], " ".join(parts[:-1])
        else:
            zid, smi = "", parts[0]
        if smi:
            rows.append((zid, smi, code))
    return rows


def build_feature_factory():
    for fdef in (
        RDConfig.RDDataDir + "/BaseFeatures.fdef",
        "/usr/share/rdkit/Data/BaseFeatures.fdef",
        "/usr/local/share/rdkit/Data/BaseFeatures.fdef",
    ):
        if Path(fdef).is_file():
            return ChemicalFeatures.BuildFeatureFactory(fdef)
    raise SystemExit("RDKit BaseFeatures.fdef not found")


def pharmacophore_model(factory, ref_smiles: list[str]) -> list[tuple[str, str, Any]]:
    feature_counts: dict[str, int] = defaultdict(int)
    n_valid = 0
    for smi in ref_smiles:
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
    compiled = []
    for ft in sorted(feature_counts, key=lambda k: -feature_counts[k]):
        smarts = SMARTS_MAP.get(ft, "")
        if smarts:
            pat = MolFromSmarts(smarts)
            if pat is not None:
                compiled.append((ft, ft[0], pat))
    return compiled


def druglike_ok(mol) -> bool:
    mw = Descriptors.MolWt(mol)
    logp = Descriptors.MolLogP(mol)
    tpsa = Descriptors.TPSA(mol)
    hbd = Descriptors.NumHDonors(mol)
    hba = Descriptors.NumHAcceptors(mol)
    return 150 <= mw <= 500 and -2 <= logp <= 5 and tpsa <= 140 and hbd <= 5 and hba <= 10


def match_features(mol, compiled) -> tuple[int, list[str]]:
    matched: list[str] = []
    seen: set[str] = set()
    for ftype, _label, pat in compiled:
        if ftype not in seen and mol.HasSubstructMatch(pat):
            matched.append(ftype)
            seen.add(ftype)
    return len(matched), matched


def stratified_cap(rows: list[dict[str, Any]], cap: int, seed: int = 42) -> list[dict[str, Any]]:
    if len(rows) <= cap:
        return rows
    rng = random.Random(seed)
    by_feat: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for r in rows:
        by_feat[r["features_matched"]].append(r)
    keys = sorted(by_feat.keys(), reverse=True)
    total = len(rows)
    picked: list[dict[str, Any]] = []
    for k in keys:
        bucket = by_feat[k]
        n_take = max(1, round(cap * len(bucket) / total))
        rng.shuffle(bucket)
        picked.extend(bucket[:n_take])
    if len(picked) > cap:
        rng.shuffle(picked)
        picked = picked[:cap]
    elif len(picked) < cap:
        rest = [r for r in rows if r not in picked]
        rng.shuffle(rest)
        picked.extend(rest[: cap - len(picked)])
    return picked


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    ap.add_argument("--tranches", nargs="+", default=list(DEFAULT_TRANCHES))
    ap.add_argument("--min-features", type=int, default=3)
    ap.add_argument("--max-dock", type=int, default=5000)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    pub = args.publication_run.resolve()
    out = pub / "publication_zinc"
    out.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    # Step 1: union
    by_smiles: dict[str, dict[str, str]] = {}
    tranche_counts: dict[str, int] = {}
    for code in args.tranches:
        rows = fetch_tranche(code)
        tranche_counts[code] = len(rows)
        for zid, smi, tc in rows:
            if smi not in by_smiles:
                by_smiles[smi] = {"zinc_substance_id": zid, "smiles": smi, "source_tranche": tc}

    raw_path = out / "raw_union.tsv"
    with raw_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["zinc_substance_id", "smiles", "source_tranche"], delimiter="\t")
        w.writeheader()
        for smi, rec in sorted(by_smiles.items(), key=lambda x: x[1]["source_tranche"]):
            w.writerow(rec)

    # Step 2: drug-like
    druglike_rows: list[dict[str, str]] = []
    for smi, rec in by_smiles.items():
        mol = MolFromSmiles(smi)
        if mol is None:
            continue
        if druglike_ok(mol):
            druglike_rows.append(dict(rec))

    drug_path = out / "druglike.tsv"
    with drug_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["zinc_substance_id", "smiles", "source_tranche"], delimiter="\t")
        w.writeheader()
        w.writerows(druglike_rows)

    # Step 3: pharmacophore
    factory = build_feature_factory()
    compiled = pharmacophore_model(factory, list(CONTROL_SMILES.values()))
    pharm_pass: list[dict[str, Any]] = []
    for rec in druglike_rows:
        mol = MolFromSmiles(rec["smiles"])
        if mol is None:
            continue
        n, types = match_features(mol, compiled)
        if n >= args.min_features:
            pharm_pass.append({**rec, "features_matched": n, "feature_types": ",".join(types)})

    pharm_path = out / "pharmacophore_pass.tsv"
    with pharm_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(
            fh,
            fieldnames=["zinc_substance_id", "smiles", "source_tranche", "features_matched", "feature_types"],
            delimiter="\t",
        )
        w.writeheader()
        w.writerows(pharm_pass)

    # Step 4: cap + controls
    dock_rows = stratified_cap(pharm_pass, args.max_dock, seed=args.seed)
    dock_smiles = {r["smiles"] for r in dock_rows}
    for label, smi in CONTROL_SMILES.items():
        if smi not in dock_smiles:
            dock_rows.insert(0, {
                "zinc_substance_id": f"CONTROL_{label}",
                "smiles": smi,
                "source_tranche": "control",
                "features_matched": 0,
                "feature_types": "control",
            })
            dock_smiles.add(smi)

    dock_tsv = out / "dock_set.tsv"
    with dock_tsv.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(
            fh,
            fieldnames=["zinc_substance_id", "smiles", "source_tranche", "features_matched", "feature_types"],
            delimiter="\t",
        )
        w.writeheader()
        w.writerows(dock_rows)

    dock_smi = out / "dock_set.smi"
    dock_smi.write_text("\n".join(r["smiles"] for r in dock_rows) + "\n", encoding="utf-8")

    manifest = {
        "created_at": ts,
        "tier": "publication_hts",
        "tranche_urls": [f"{ZINC_BASE}/{c[0]}{c[1]}/{c}.smi" for c in args.tranches],
        "tranche_line_counts": tranche_counts,
        "raw_union_unique": len(by_smiles),
        "druglike_count": len(druglike_rows),
        "pharmacophore_pass_count": len(pharm_pass),
        "dock_set_count": len(dock_rows),
        "min_features": args.min_features,
        "max_dock_cap": args.max_dock,
        "controls_injected": list(CONTROL_SMILES.keys()),
        "selection_method": "multi_tranche_union_druglike_pharmacophore_stratified_cap",
        "target_informed": True,
        "blog_tier_comparison": "zinc600_screen/ (600 AAAC — not this deck)",
        "files": {
            "raw_union": str(raw_path.relative_to(ROOT)),
            "druglike": str(drug_path.relative_to(ROOT)),
            "pharmacophore_pass": str(pharm_path.relative_to(ROOT)),
            "dock_set_tsv": str(dock_tsv.relative_to(ROOT)),
            "dock_set_smi": str(dock_smi.relative_to(ROOT)),
        },
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    report = [
        "# Publication ZINC library build",
        "",
        f"_Generated: {ts}_",
        "",
        "## Funnel",
        "",
        f"| Stage | Count |",
        f"|-------|------:|",
        f"| Tranche union (dedup) | {len(by_smiles)} |",
        f"| Drug-like gate | {len(druglike_rows)} |",
        f"| Pharmacophore pass (≥{args.min_features}) | {len(pharm_pass)} |",
        f"| Dock set (cap {args.max_dock} + controls) | **{len(dock_rows)}** |",
        "",
        "## Tranches",
        "",
    ]
    for code, n in sorted(tranche_counts.items()):
        report.append(f"- `{code}`: {n} lines")
    report.extend(["", "## Next", "", f"Dock: `run_publication_zinc_docking.py`", ""])
    (out / "BUILD_REPORT.md").write_text("\n".join(report) + "\n", encoding="utf-8")

    print(f"Raw union: {len(by_smiles)}")
    print(f"Drug-like: {len(druglike_rows)}")
    print(f"Pharmacophore pass: {len(pharm_pass)}")
    print(f"Dock set: {len(dock_rows)} → {dock_smi}")


if __name__ == "__main__":
    main()
