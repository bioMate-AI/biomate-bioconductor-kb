"""Dependency-free geometric featurizer for a DESIGNED cyclic-peptide backbone (mmCIF).

Extracts the peptide-chain CA trace from a BoltzGen designed-pose .cif (the intermediate_designs/
<target>_<NNN>.cif files) and computes intrinsic backbone-geometry features that relate to
DESIGNABILITY (whether the sequence will refold to this backbone) — radius of gyration, contact
order, long-range contact density, compactness, etc. These are available from the designed pose
BEFORE the independent refold, so using them to predict refold scRMSD is not circular.

No external parser: mmCIF `_atom_site` loop is parsed directly (robust for Boltz/AF-style output).
"""
from __future__ import annotations

import math
from pathlib import Path
from typing import Dict, List, Optional, Tuple

Coord = Tuple[float, float, float]


def parse_ca_by_chain(cif_path: str) -> Dict[str, List[Tuple[int, Coord]]]:
    """Return {chain -> [(label_seq_id, (x,y,z)), ...]} for CA atoms, in file order."""
    lines = Path(cif_path).read_text().splitlines()
    i = 0
    out: Dict[str, List[Tuple[int, Coord]]] = {}
    while i < len(lines):
        if lines[i].strip() == "loop_":
            # collect the column names of this loop
            cols = []
            j = i + 1
            while j < len(lines) and lines[j].lstrip().startswith("_"):
                cols.append(lines[j].strip())
                j += 1
            if any(c.startswith("_atom_site.") for c in cols):
                idx = {c: k for k, c in enumerate(cols)}
                ci_atom = idx.get("_atom_site.label_atom_id")
                ci_chain = idx.get("_atom_site.label_asym_id")
                ci_seq = idx.get("_atom_site.label_seq_id")
                ci_x = idx.get("_atom_site.Cartn_x")
                ci_y = idx.get("_atom_site.Cartn_y")
                ci_z = idx.get("_atom_site.Cartn_z")
                if None in (ci_atom, ci_chain, ci_x, ci_y, ci_z):
                    i = j
                    continue
                k = j
                while k < len(lines):
                    ln = lines[k]
                    s = ln.strip()
                    if s == "" or s == "#" or s == "loop_" or s.startswith("_") or s.startswith("data_"):
                        break
                    parts = ln.split()
                    if len(parts) < len(cols):
                        k += 1
                        continue
                    if parts[ci_atom] == "CA":
                        try:
                            xyz = (float(parts[ci_x]), float(parts[ci_y]), float(parts[ci_z]))
                            seq = int(parts[ci_seq]) if ci_seq is not None and parts[ci_seq].lstrip("-").isdigit() else len(out.get(parts[ci_chain], []))
                            out.setdefault(parts[ci_chain], []).append((seq, xyz))
                        except (ValueError, IndexError):
                            pass
                    k += 1
                i = k
                continue
        i += 1
    return out


def peptide_chain(ca_by_chain: Dict[str, List[Tuple[int, Coord]]],
                  expected_len: Optional[int] = None) -> Optional[List[Coord]]:
    """Pick the peptide (design) chain: the one matching expected_len if given, else the shortest
    non-trivial chain (the receptor is much larger)."""
    if not ca_by_chain:
        return None
    chains = {c: [xyz for _, xyz in v] for c, v in ca_by_chain.items() if len(v) >= 4}
    if not chains:
        return None
    if expected_len:
        best = min(chains.items(), key=lambda kv: abs(len(kv[1]) - expected_len))
        return best[1]
    return min(chains.values(), key=len)


def _dist(a: Coord, b: Coord) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


POSE_FEATURE_NAMES = ["pose_n", "pose_rg", "pose_rg_over_n13", "pose_end2end",
                      "pose_end2end_over_rg", "pose_bond_mean", "pose_bond_std",
                      "pose_contact_order", "pose_lr_contacts_per_res", "pose_frac_in_contact",
                      "pose_span_max"]


def geom_features(ca: List[Coord], contact_cut=8.0, lr_sep=3) -> Dict[str, float]:
    """Intrinsic backbone geometry of the CA trace."""
    n = len(ca)
    if n < 4:
        return {k: 0.0 for k in POSE_FEATURE_NAMES}
    cx = sum(p[0] for p in ca) / n
    cy = sum(p[1] for p in ca) / n
    cz = sum(p[2] for p in ca) / n
    rg = math.sqrt(sum((p[0]-cx)**2 + (p[1]-cy)**2 + (p[2]-cz)**2 for p in ca) / n)
    bonds = [_dist(ca[i], ca[i+1]) for i in range(n-1)]
    bmean = sum(bonds) / len(bonds)
    bstd = math.sqrt(sum((b-bmean)**2 for b in bonds) / len(bonds))
    e2e = _dist(ca[0], ca[-1])
    # contact order + long-range contact density
    contacts = 0
    seps = []
    lr = 0
    in_contact = set()
    maxspan = 0.0
    for i in range(n):
        for j in range(i+1, n):
            d = _dist(ca[i], ca[j])
            maxspan = max(maxspan, d)
            if d < contact_cut:
                contacts += 1
                seps.append(j - i)
                in_contact.add(i); in_contact.add(j)
                if (j - i) > lr_sep:
                    lr += 1
    co = (sum(seps) / (len(seps) * n)) if seps else 0.0  # relative contact order
    return {
        "pose_n": float(n),
        "pose_rg": rg,
        "pose_rg_over_n13": rg / (n ** (1/3)),
        "pose_end2end": e2e,
        "pose_end2end_over_rg": e2e / rg if rg else 0.0,
        "pose_bond_mean": bmean,
        "pose_bond_std": bstd,
        "pose_contact_order": co,
        "pose_lr_contacts_per_res": lr / n,
        "pose_frac_in_contact": len(in_contact) / n,
        "pose_span_max": maxspan,
    }


def features_for_cif(cif_path: str, expected_len: Optional[int] = None) -> Optional[Dict[str, float]]:
    ca_by = parse_ca_by_chain(cif_path)
    ca = peptide_chain(ca_by, expected_len)
    if ca is None:
        return None
    return geom_features(ca)


if __name__ == "__main__":
    import argparse, json
    ap = argparse.ArgumentParser()
    ap.add_argument("cif")
    ap.add_argument("--len", type=int, default=None)
    a = ap.parse_args()
    print(json.dumps(features_for_cif(a.cif, a.len), indent=2))
