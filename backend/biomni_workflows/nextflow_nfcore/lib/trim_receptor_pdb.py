"""
Trim a receptor PDB to atoms inside a docking/search box (+ padding).

Shared by AutoDock Vina and GROMACS protein-ligand MD workflows so large
deposited assemblies (e.g. viral glycoprotein tetramers) are reduced to a
local binding-site model before solvation.

Literature convention: 8–10 Å padding beyond the search box (OpenMMDL, GROMACS
tutorials, hantavirus Gn MD studies use local receptors, not full assemblies).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def count_pdb_atoms(pdb_path: str | Path) -> int:
    n = 0
    with open(pdb_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith(("ATOM", "HETATM")):
                n += 1
    return n


def trim_pdb_to_search_box(
    pdb_path: str | Path,
    out_path: str | Path,
    cx: float,
    cy: float,
    cz: float,
    sx: float,
    sy: float,
    sz: float,
    pad: float = 10.0,
    min_atoms: int = 50,
) -> int:
    """
    Keep ATOM/HETATM records inside the axis-aligned box centered at (cx,cy,cz)
    with half-extents (sx/2 + pad) per axis — same geometry as Vina trim.

    Returns number of atoms written. Raises RuntimeError if too few atoms kept.
    """
    hx = sx / 2.0 + pad
    hy = sy / 2.0 + pad
    hz = sz / 2.0 + pad
    xmin, xmax = cx - hx, cx + hx
    ymin, ymax = cy - hy, cy + hy
    zmin, zmax = cz - hz, cz + hz
    kept: list[str] = []
    with open(pdb_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.startswith(("ATOM", "HETATM")):
                continue
            try:
                x = float(line[30:38])
                y = float(line[38:46])
                z = float(line[46:54])
            except ValueError:
                continue
            if xmin <= x <= xmax and ymin <= y <= ymax and zmin <= z <= zmax:
                kept.append(line)
    if len(kept) < min_atoms:
        raise RuntimeError(
            f"only {len(kept)} atoms inside padded box — check box_center/box_size/pad"
        )
    pad_s = str(round(float(pad), 1))
    with open(out_path, "w", encoding="utf-8") as out:
        out.write(
            f"REMARK BioMate: receptor trimmed to search box + {pad_s} A pad\n"
        )
        for ln in kept:
            out.write(ln)
        out.write("END\n")
    return len(kept)


def maybe_trim_receptor(
    pdb_path: str | Path,
    out_path: str | Path,
    *,
    auto_trim: bool,
    min_input_atoms: int,
    box_center: tuple[float, float, float] | None,
    box_size: tuple[float, float, float] | None,
    pad: float,
) -> dict:
    """
    Trim when auto_trim is true, box params are set, and input exceeds min_input_atoms.
    Otherwise copy input to output unchanged.
    """
    src = Path(pdb_path)
    dst = Path(out_path)
    n_in = count_pdb_atoms(src)
    if (
        not auto_trim
        or box_center is None
        or box_size is None
        or n_in < min_input_atoms
    ):
        dst.write_text(src.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        return {
            "trimmed": False,
            "input_atoms": n_in,
            "output_atoms": n_in,
            "reason": "skip",
        }
    n_out = trim_pdb_to_search_box(
        src, dst, *box_center, *box_size, pad=pad,
    )
    return {
        "trimmed": True,
        "input_atoms": n_in,
        "output_atoms": n_out,
        "box_center": list(box_center),
        "box_size": list(box_size),
        "trim_pad_A": pad,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input_pdb")
    ap.add_argument("output_pdb")
    ap.add_argument("--box-center", required=True, help='JSON list "[x,y,z]"')
    ap.add_argument("--box-size", required=True, help='JSON list "[sx,sy,sz]"')
    ap.add_argument("--pad", type=float, default=10.0)
    ap.add_argument("--auto-trim", dest="auto_trim", action="store_true", default=True)
    ap.add_argument("--no-auto-trim", dest="auto_trim", action="store_false")
    ap.add_argument("--min-input-atoms", type=int, default=5000)
    args = ap.parse_args(argv)
    center = tuple(json.loads(args.box_center))
    size = tuple(json.loads(args.box_size))
    if len(center) != 3 or len(size) != 3:
        raise SystemExit("box-center and box-size must be length-3 JSON lists")
    result = maybe_trim_receptor(
        args.input_pdb,
        args.output_pdb,
        auto_trim=args.auto_trim,
        min_input_atoms=args.min_input_atoms,
        box_center=center,
        box_size=size,
        pad=args.pad,
    )
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
