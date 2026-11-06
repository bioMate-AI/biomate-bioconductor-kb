#!/usr/bin/env python3
"""Shared target-prep pocket-extraction primitives (gap G9).

Three target-prep paths each re-implemented the SAME all-atom pocket core inline:
  * avb6_pocket_truncate.py    — keep receptor residues whose heavy atoms are within CUT of
                                 any PEPTIDE heavy atom, then write a truncated complex.
  * boltzgen_ourtarget.sh      — (python heredoc) per-receptor-chain 1-based indices of residues
                                 whose heavy atoms are within 5 A of any peptide heavy atom.
  * pdl1_m2c_stage_target.py   — PepGLAD's OWN **CB-CB** interface rule (blocks_cb_interface,
                                 stock process.py). This is a DIFFERENT geometric definition and is
                                 intentionally NOT unified here (see HONESTY note below).

This module unifies the all-atom heavy-atom core shared by the first two. gemmi is imported
lazily so the module imports (and py_compiles / unit-tests the pure helpers) on machines without
gemmi; the gemmi-backed functions raise a clear error only when actually called.

HONESTY: pdl1_m2c_stage_target.py uses CB-CB within pocket_th (PepGLAD stock), NOT the all-atom
rule here. Its pocket is defined inside the stock PepGLAD `process.py`, not inline, and the two
definitions are not identical. We do NOT force it onto this helper and we do NOT claim the pockets
are the same — exactly the caveat documented in that script's header.
"""
from __future__ import annotations

from typing import List, Sequence, Tuple

import numpy as np

# Residue names treated as solvent / not part of a peptide ligand.
WATERS = ("HOH", "WAT", "H2O", "DOD")


def _gemmi():
    """Lazy gemmi import — the all-atom primitives need it; the pure ones (below) do not."""
    try:
        import gemmi  # type: ignore
    except Exception as exc:  # noqa: BLE001
        raise ImportError(
            "pocket_extract: gemmi is required for structure parsing (pip install gemmi). "
            f"Underlying error: {exc}"
        ) from exc
    return gemmi


# --------------------------------------------------------------------------------------------
# residue / atom primitives (the duplicated core)
# --------------------------------------------------------------------------------------------
def is_amino_acid(res) -> bool:
    """True if the residue is a tabulated amino acid (gemmi). Mirrors the inline `is_aa` that
    both avb6_pocket_truncate.py and boltzgen_ourtarget.sh defined independently."""
    gemmi = _gemmi()
    info = gemmi.find_tabulated_residue(res.name)
    return bool(info) and info.is_amino_acid()


def heavy_atoms(res) -> list:
    """Non-hydrogen atoms of a residue."""
    return [a for a in res if a.element.name != "H"]


def heavy_coords(res) -> np.ndarray:
    """(M,3) float array of this residue's heavy-atom coordinates (empty (0,3) if none)."""
    c = [[a.pos.x, a.pos.y, a.pos.z] for a in res if a.element.name != "H"]
    return np.array(c, dtype=float) if c else np.zeros((0, 3), dtype=float)


def min_heavy_distance(res_coords: np.ndarray, pep_coords: np.ndarray) -> float:
    """Minimum heavy-atom-to-heavy-atom distance between a residue and the peptide.

    Pure numpy — unit-testable with no gemmi. Returns +inf if either side is empty.
    """
    res_coords = np.asarray(res_coords, dtype=float)
    pep_coords = np.asarray(pep_coords, dtype=float)
    if res_coords.size == 0 or pep_coords.size == 0:
        return float("inf")
    d2 = ((res_coords[:, None, :] - pep_coords[None, :, :]) ** 2).sum(-1)
    return float(np.sqrt(d2.min()))


# --------------------------------------------------------------------------------------------
# chain selection + peptide coordinates
# --------------------------------------------------------------------------------------------
def amino_acid_chains(model) -> List[Tuple[str, int]]:
    """[(chain_name, n_amino_acid_residues), ...] for chains that have >=1 amino acid,
    sorted ascending by count (so the first is the shortest = peptide candidate)."""
    out = [(c.name, sum(1 for r in c if is_amino_acid(r))) for c in model]
    out = [t for t in out if t[1] > 0]
    out.sort(key=lambda x: x[1])
    return out


def split_peptide_receptor(model) -> Tuple[str, List[str]]:
    """Peptide = the fewest-amino-acid chain; receptor = every other aa-bearing chain.
    Returns (peptide_chain_name, [receptor_chain_names]). Matches avb6_pocket_truncate.py."""
    aa = amino_acid_chains(model)
    if not aa:
        raise ValueError("pocket_extract: no amino-acid chains in model")
    return aa[0][0], [c for c, _ in aa[1:]]


def get_chain(model, name):
    for ch in model:
        if ch.name == name:
            return ch
    return None


def peptide_heavy_coords(chain, mode: str = "aa_only") -> np.ndarray:
    """Stacked (N,3) heavy coords of the peptide chain.

    mode="aa_only"   : only tabulated amino-acid residues  (avb6_pocket_truncate.py semantics)
    mode="non_water" : all residues except water           (boltzgen_ourtarget.sh semantics —
                       includes non-canonical macrocycle residues like MEA/SAR/9KK/CCS)
    """
    if mode == "aa_only":
        residues = [r for r in chain if is_amino_acid(r)]
    elif mode == "non_water":
        residues = [r for r in chain if r.name not in WATERS]
    else:
        raise ValueError(f"peptide_heavy_coords: unknown mode {mode!r}")
    blocks = [heavy_coords(r) for r in residues]
    blocks = [b for b in blocks if b.size]
    return np.vstack(blocks) if blocks else np.zeros((0, 3), dtype=float)


# --------------------------------------------------------------------------------------------
# the two pocket flavours the callers need
# --------------------------------------------------------------------------------------------
def select_pocket_residues(rec_chain, pep_coords: np.ndarray, cut: float) -> list:
    """Return the amino-acid residues of a receptor chain whose heavy atoms come within `cut`
    of any peptide heavy atom (avb6_pocket_truncate.py: build a truncated complex from these)."""
    keep = []
    for r in rec_chain:
        if not is_amino_acid(r):
            continue
        if min_heavy_distance(heavy_coords(r), pep_coords) < cut:
            keep.append(r)
    return keep


def pocket_indices_1based(rec_chain, pep_coords: np.ndarray, cut: float) -> List[int]:
    """1-based indices (within the chain's resolved amino-acid residues, in file order) of residues
    within `cut` of the peptide. This matches BoltzGen's per-chain binding-residue enumeration in
    boltzgen_ourtarget.sh (which indexes by position among the residues it builds per chain)."""
    rres = [r for r in rec_chain if is_amino_acid(r)]
    pocket = []
    for i, res in enumerate(rres):
        if min_heavy_distance(heavy_coords(res), pep_coords) < cut:
            pocket.append(i + 1)
    return sorted(set(pocket))


# --------------------------------------------------------------------------------------------
# selftest — pure-numpy core only (no gemmi required)
# --------------------------------------------------------------------------------------------
def _selftest() -> int:
    checks = {}
    # residue A heavy atoms at x=0, peptide at x=3 and x=12 -> min dist 3.0
    res = np.array([[0.0, 0.0, 0.0], [1.0, 0.0, 0.0]])
    pep = np.array([[3.0, 0.0, 0.0], [12.0, 0.0, 0.0]])
    checks["min dist = 2.0 (nearest pair 1->3)"] = abs(min_heavy_distance(res, pep) - 2.0) < 1e-9
    checks["empty residue -> inf"] = min_heavy_distance(np.zeros((0, 3)), pep) == float("inf")
    checks["empty peptide -> inf"] = min_heavy_distance(res, np.zeros((0, 3))) == float("inf")

    # pocket membership via min distance + a cutoff, emulating both callers' core
    far = np.array([[50.0, 0.0, 0.0]])
    near = np.array([[2.0, 0.0, 0.0]])
    cut = 5.0
    members = [min_heavy_distance(c, pep) < cut for c in (near, far)]
    checks["near in pocket, far out (cut 5A)"] = members == [True, False]

    for k, v in checks.items():
        print(f"  {'PASS' if v else 'FAIL'}  {k}")
    ok = all(checks.values())
    print("ALL_CHECKS_PASS=" + str(ok))
    return 0 if ok else 1


if __name__ == "__main__":
    import sys

    if "--selftest" in sys.argv:
        sys.exit(_selftest())
    print(__doc__)
