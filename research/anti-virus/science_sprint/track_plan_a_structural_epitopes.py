#!/usr/bin/env python3
"""
Science sprint — crude solvent-exposure patches on ANDV GPC structure (stdlib only).

Primary structure: research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb
Fallback (when the pocket marker PDB lacks protein ATOM records): structures/9P3I.cif via cif_to_pdb.

Algorithm:
  - Parse ATOM records; collect C-alpha coordinates per residue.
  - Residue is "exposed" when it has <= neighbor_threshold other CA atoms within 10 Å.
  - Cluster consecutive exposed residues into patches using a sliding window (default 9 residues).

Outputs under research/anti-virus/science_sprint/runs/<timestamp>/track_plan_a_structural_epitopes/:
  - structural_epitope_patches.json
  - structural_epitope_summary.md

Usage:
  python3 research/anti-virus/science_sprint/track_plan_a_structural_epitopes.py
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_POCKET_PDB = (
    ROOT
    / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/01_pocket/structure_top_pocket.pdb"
)
DEFAULT_CIF = ROOT / "research/anti-virus/structures/9P3I.cif"
CIF_TO_PDB = ROOT / "research/anti-virus/scripts/cif_to_pdb.py"
MIN_CA_ATOMS = 20
DISTANCE_A = 10.0
DEFAULT_NEIGHBOR_THRESHOLD = 8
DEFAULT_WINDOW = 9
DEFAULT_MIN_EXPOSED_IN_WINDOW = 5


def log(msg: str) -> None:
    print(msg, flush=True)


def parse_pdb_ca_atoms(pdb_path: Path) -> list[dict[str, Any]]:
    """Return ordered CA atoms from ATOM records."""
    atoms: list[dict[str, Any]] = []
    for line in pdb_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.startswith("ATOM"):
            continue
        if line[12:16].strip() != "CA":
            continue
        chain = line[21].strip() or "_"
        try:
            resseq = int(line[22:26])
        except ValueError:
            continue
        resname = line[17:20].strip()
        x = float(line[30:38])
        y = float(line[38:46])
        z = float(line[46:54])
        atoms.append(
            {
                "chain": chain,
                "resseq": resseq,
                "resname": resname,
                "x": x,
                "y": y,
                "z": z,
                "key": (chain, resseq),
            }
        )
    return atoms


def convert_cif_to_pdb(cif_path: Path, pdb_path: Path) -> None:
    if not CIF_TO_PDB.is_file():
        raise SystemExit(f"Missing converter script: {CIF_TO_PDB}")
    subprocess.run(
        [sys.executable, str(CIF_TO_PDB), str(cif_path), "-o", str(pdb_path)],
        check=True,
    )


def resolve_structure_pdb(pocket_pdb: Path, cif_path: Path) -> tuple[Path, str]:
    if pocket_pdb.is_file():
        ca_count = len(parse_pdb_ca_atoms(pocket_pdb))
        if ca_count >= MIN_CA_ATOMS:
            return pocket_pdb, "pocket_pdb"
        log(f"Pocket PDB has only {ca_count} CA atoms; falling back to {cif_path.name}")

    if not cif_path.is_file():
        raise SystemExit(f"No usable structure: {pocket_pdb} lacks ATOM records and {cif_path} missing.")

    tmp = tempfile.NamedTemporaryFile(suffix=".pdb", delete=False)
    tmp_path = Path(tmp.name)
    tmp.close()
    convert_cif_to_pdb(cif_path, tmp_path)
    return tmp_path, "9P3I_cif"


def distance(a: dict[str, Any], b: dict[str, Any]) -> float:
    return math.sqrt((a["x"] - b["x"]) ** 2 + (a["y"] - b["y"]) ** 2 + (a["z"] - b["z"]) ** 2)


def compute_exposure(atoms: list[dict[str, Any]], neighbor_threshold: int, cutoff_a: float) -> list[dict[str, Any]]:
    enriched: list[dict[str, Any]] = []
    for i, atom in enumerate(atoms):
        neighbors = 0
        for j, other in enumerate(atoms):
            if i == j:
                continue
            if distance(atom, other) <= cutoff_a:
                neighbors += 1
        exposed = neighbors <= neighbor_threshold
        enriched.append({**atom, "ca_neighbors_within_10A": neighbors, "exposed": exposed})
    return enriched


def cluster_patches(
    residues: list[dict[str, Any]],
    *,
    window: int,
    min_exposed_in_window: int,
) -> list[dict[str, Any]]:
    if not residues:
        return []

    patches: list[dict[str, Any]] = []
    patch_id = 0
    n = len(residues)
    covered: set[tuple[str, int]] = set()

    for start in range(0, n - window + 1):
        window_slice = residues[start : start + window]
        exposed_count = sum(1 for r in window_slice if r["exposed"])
        if exposed_count < min_exposed_in_window:
            continue
        keys = [r["key"] for r in window_slice if r["exposed"]]
        if not keys:
            continue
        if any(k in covered for k in keys):
            continue
        for k in keys:
            covered.add(k)
        patch_id += 1
        exposed_residues = [r for r in window_slice if r["exposed"]]
        patches.append(
            {
                "patch_id": patch_id,
                "window_start_index": start,
                "window_size": window,
                "exposed_in_window": exposed_count,
                "chain": window_slice[0]["chain"],
                "residue_range": {
                    "start": window_slice[0]["resseq"],
                    "end": window_slice[-1]["resseq"],
                },
                "residues": [
                    {
                        "chain": r["chain"],
                        "resseq": r["resseq"],
                        "resname": r["resname"],
                        "ca_neighbors_within_10A": r["ca_neighbors_within_10A"],
                    }
                    for r in exposed_residues
                ],
            }
        )
    return patches


def summarize_by_chain(residues: list[dict[str, Any]]) -> dict[str, Any]:
    by_chain: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in residues:
        by_chain[r["chain"]].append(r)
    summary: dict[str, Any] = {}
    for chain, chain_res in sorted(by_chain.items()):
        exposed = [r for r in chain_res if r["exposed"]]
        summary[chain] = {
            "total_ca_residues": len(chain_res),
            "exposed_ca_residues": len(exposed),
            "fraction_exposed": round(len(exposed) / len(chain_res), 4) if chain_res else 0.0,
        }
    return summary


def write_summary_md(path: Path, payload: dict[str, Any]) -> None:
    lines = [
        "# Plan A structural epitope patches (crude solvent exposure)",
        "",
        f"- **Created:** {payload['created_at']}",
        f"- **Structure source:** {payload['structure_source']} (`{payload['structure_path']}`)",
        f"- **CA atoms parsed:** {payload['n_ca_atoms']}",
        f"- **Exposure rule:** CA with ≤ {payload['neighbor_threshold']} neighbors within {payload['distance_cutoff_A']} Å",
        f"- **Patch rule:** sliding window {payload['window']} residues, ≥ {payload['min_exposed_in_window']} exposed",
        "",
        "## Chain summary",
        "",
    ]
    for chain, stats in sorted(payload["chain_summary"].items()):
        lines.append(
            f"- **Chain {chain}:** {stats['exposed_ca_residues']}/{stats['total_ca_residues']} "
            f"CA exposed ({stats['fraction_exposed']:.1%})"
        )
    lines.extend(["", "## Patches", ""])
    if not payload["patches"]:
        lines.append("_No patches passed the window filter._")
    else:
        for patch in payload["patches"]:
            rr = patch["residue_range"]
            lines.append(
                f"- **Patch {patch['patch_id']}** (chain {patch['chain']}, "
                f"residues {rr['start']}–{rr['end']}, {patch['exposed_in_window']} exposed in window): "
                + ", ".join(f"{r['resname']}{r['resseq']}" for r in patch["residues"][:12])
                + (" …" if len(patch["residues"]) > 12 else "")
            )
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pocket-pdb", type=Path, default=DEFAULT_POCKET_PDB)
    ap.add_argument("--cif-fallback", type=Path, default=DEFAULT_CIF)
    ap.add_argument("--neighbor-threshold", type=int, default=DEFAULT_NEIGHBOR_THRESHOLD)
    ap.add_argument("--distance-cutoff", type=float, default=DISTANCE_A)
    ap.add_argument("--window", type=int, default=DEFAULT_WINDOW)
    ap.add_argument("--min-exposed-in-window", type=int, default=DEFAULT_MIN_EXPOSED_IN_WINDOW)
    ap.add_argument("--out-dir", type=Path, default=None, help="Override output directory")
    args = ap.parse_args()

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = args.out_dir or (
        ROOT / "research/anti-virus/science_sprint/runs" / stamp / "track_plan_a_structural_epitopes"
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    pdb_path, source = resolve_structure_pdb(args.pocket_pdb.resolve(), args.cif_fallback.resolve())
    log(f"Using structure: {pdb_path} (source={source})")

    ca_atoms = parse_pdb_ca_atoms(pdb_path)
    if len(ca_atoms) < MIN_CA_ATOMS:
        raise SystemExit(f"Insufficient CA atoms ({len(ca_atoms)}) in {pdb_path}")

    residues = compute_exposure(ca_atoms, args.neighbor_threshold, args.distance_cutoff)
    patches = cluster_patches(
        residues,
        window=args.window,
        min_exposed_in_window=args.min_exposed_in_window,
    )

    payload = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "stamp": stamp,
        "structure_source": source,
        "structure_path": str(pdb_path),
        "pocket_pdb": str(args.pocket_pdb.resolve()),
        "cif_fallback": str(args.cif_fallback.resolve()),
        "n_ca_atoms": len(ca_atoms),
        "neighbor_threshold": args.neighbor_threshold,
        "distance_cutoff_A": args.distance_cutoff,
        "window": args.window,
        "min_exposed_in_window": args.min_exposed_in_window,
        "chain_summary": summarize_by_chain(residues),
        "n_exposed_residues": sum(1 for r in residues if r["exposed"]),
        "patches": patches,
    }

    json_path = out_dir / "structural_epitope_patches.json"
    md_path = out_dir / "structural_epitope_summary.md"
    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    write_summary_md(md_path, payload)
    log(f"Wrote {json_path}")
    log(f"Wrote {md_path}")
    log(f"Patches: {len(patches)} | exposed CA: {payload['n_exposed_residues']}/{len(ca_atoms)}")


if __name__ == "__main__":
    main()
