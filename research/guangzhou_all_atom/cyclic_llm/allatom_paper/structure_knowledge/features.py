"""Per-complex structural features for protein-cyclic-peptide complexes (workstream K3).

Pure gemmi + numpy + scipy. Input: one mmCIF path, the peptide chain id and the receptor chain ids (the conventions of
data/bound_cyclic/v2/bound_cyclic_manifest.jsonl: gemmi chain names = auth_asym_id). Output: a JSON-serialisable dict.

Design rules (owner: no unverifiable claims):
  * cyclisation is RE-DETECTED here from coordinates, independently of the manifest label; the caller compares the two.
  * D residues are detected geometrically (sign of the CA chirality volume against the receptor's L-amino-acid majority);
    N-methyl by geometry (a carbon on the backbone N with no other heavy neighbour); no CCD-code tables are assumed.
  * turn / Ramachandran classes use fixed textbook windows (declared in TURN_WINDOWS); they are descriptive classes, not fits.
"""
from __future__ import annotations

import math
from typing import Dict, List, Optional, Tuple

import gemmi
import numpy as np
from scipy.spatial import cKDTree

STD3 = {"ALA": "A", "ARG": "R", "ASN": "N", "ASP": "D", "CYS": "C", "GLN": "Q", "GLU": "E", "GLY": "G", "HIS": "H",
        "ILE": "I", "LEU": "L", "LYS": "K", "MET": "M", "PHE": "F", "PRO": "P", "SER": "S", "THR": "T", "TRP": "W",
        "TYR": "Y", "VAL": "V"}
RADII = {"C": 1.70, "N": 1.55, "O": 1.52, "S": 1.80, "P": 1.80, "SE": 1.90}
PROBE = 1.4
METALS = {"MG", "MN", "ZN", "CA", "FE", "CU", "NI", "CO", "CD", "NA", "K", "FE2"}
CHG_POS_ATOMS = {("LYS", "NZ"), ("ARG", "NH1"), ("ARG", "NH2"), ("ARG", "NE")}
CHG_NEG_ATOMS = {("ASP", "OD1"), ("ASP", "OD2"), ("GLU", "OE1"), ("GLU", "OE2")}
# beta-turn windows: (phi_i+1, psi_i+1, phi_i+2, psi_i+2) centres, tolerance 30 deg (textbook values; descriptive classes)
TURN_WINDOWS = {"I": (-60, -30, -90, 0), "I'": (60, 30, 90, 0), "II": (-60, 120, 80, 0), "II'": (60, -120, -80, 0)}
TURN_TOL = 30.0
GAMMA = {"gamma_classic": (75.0, -65.0), "gamma_inverse": (-75.0, 65.0)}
GAMMA_TOL = 40.0


def _deg(x: float) -> float:
    return math.degrees(x)


def _angdiff(a: float, b: float) -> float:
    d = (a - b + 180.0) % 360.0 - 180.0
    return abs(d)


def _atom(res: gemmi.Residue, name: str) -> Optional[gemmi.Atom]:
    a = res.find_atom(name, "*")
    return a


def _xyz(a: gemmi.Atom) -> np.ndarray:
    return np.array([a.pos.x, a.pos.y, a.pos.z], float)


def _chir_volume(res: gemmi.Residue) -> Optional[float]:
    n, ca, c, cb = _atom(res, "N"), _atom(res, "CA"), _atom(res, "C"), _atom(res, "CB")
    if None in (n, ca, c, cb):
        return None
    v1, v2, v3 = _xyz(n) - _xyz(ca), _xyz(c) - _xyz(ca), _xyz(cb) - _xyz(ca)
    return float(np.dot(v1, np.cross(v2, v3)))


def _receptor_l_sign(model: gemmi.Model, rec_chains: List[str]) -> Optional[int]:
    pos = neg = 0
    for ch in model:
        if ch.name not in rec_chains:
            continue
        for r in ch:
            if r.name in STD3 and r.name != "GLY":
                v = _chir_volume(r)
                if v is not None and abs(v) > 0.5:
                    pos += v > 0
                    neg += v < 0
    if pos + neg < 20:
        return None
    return 1 if pos >= neg else -1


def _connected(a: gemmi.Residue, b: gemmi.Residue) -> bool:
    c, n = _atom(a, "C"), _atom(b, "N")
    return bool(c and n and c.pos.dist(n.pos) < 1.7)


def _is_nmethyl(res: gemmi.Residue, prev: Optional[gemmi.Residue], tree: cKDTree, pts: np.ndarray, names: List[Tuple[str, str, int]],
                elems: List[str]) -> bool:
    n = _atom(res, "N")
    if n is None:
        return False
    idx = tree.query_ball_point(_xyz(n), 1.65)
    for k in idx:
        nm, rn, ri = names[k]
        if elems[k] != "C" or (nm == "CA" and ri == res_index(res)):
            continue
        if nm == "CA":
            continue
        if prev is not None and nm == "C" and ri == res_index(prev):
            continue
        # carbon bonded to N: N-methyl iff it has exactly one heavy neighbour (the N)
        nb = tree.query_ball_point(pts[k], 1.7)
        if len([j for j in nb if j != k]) == 1:
            return True
    return False


_RES_INDEX: Dict[int, int] = {}


def res_index(res: gemmi.Residue) -> int:
    return _RES_INDEX.get(id(res), -1)


def shrake_rupley(coords: np.ndarray, radii: np.ndarray, occ_coords: np.ndarray, occ_radii: np.ndarray, n_points: int = 96) -> np.ndarray:
    """Per-atom SASA of `coords` in the presence of `occ_coords` (which include the atoms themselves)."""
    golden = math.pi * (3.0 - math.sqrt(5.0))
    k = np.arange(n_points)
    y = 1.0 - 2.0 * (k + 0.5) / n_points
    rad = np.sqrt(1.0 - y * y)
    th = golden * k
    sphere = np.stack([np.cos(th) * rad, y, np.sin(th) * rad], axis=1)
    tree = cKDTree(occ_coords)
    rmax = float(occ_radii.max()) + PROBE
    out = np.zeros(len(coords))
    for i in range(len(coords)):
        ri = radii[i] + PROBE
        pts = coords[i] + sphere * ri
        cand = tree.query_ball_point(coords[i], ri + rmax)
        if not cand:
            out[i] = 4.0 * math.pi * ri * ri
            continue
        cc, cr = occ_coords[cand], occ_radii[cand] + PROBE
        d2 = ((pts[:, None, :] - cc[None, :, :]) ** 2).sum(-1)
        free = (d2 >= (cr[None, :] ** 2) - 1e-9).all(axis=1)
        out[i] = 4.0 * math.pi * ri * ri * free.mean()
    return out


def featurize_complex(path: str, pep_chain: str, rec_chains: List[str], cutoff: float = 4.5) -> Dict:
    st = gemmi.read_structure(path)
    st.setup_entities()
    st.remove_hydrogens()
    st.remove_waters()
    st.remove_alternative_conformations()
    model = st[0]
    out: Dict = {"ok": False}
    pep_ch = next((c for c in model if c.name == pep_chain), None)
    if pep_ch is None:
        out["error"] = "peptide chain not found"
        return out
    pres = [r for r in pep_ch if r.het_flag != "H" or r.name in STD3 or _atom(r, "CA") is not None]
    pres = [r for r in pres if _atom(r, "CA") is not None or _atom(r, "N") is not None]
    n = len(pres)
    out["n_res"] = n
    if n < 3:
        out["error"] = "peptide has < 3 residues with backbone atoms"
        return out
    if n > 40:
        out["error"] = "peptide chain longer than 40 residues (not a short-peptide ligand)"
        return out
    _RES_INDEX.clear()
    for i, r in enumerate(pres):
        _RES_INDEX[id(r)] = i
    # peptide atom arrays
    P_xyz, P_el, P_name, P_res = [], [], [], []
    for i, r in enumerate(pres):
        for a in r:
            P_xyz.append(_xyz(a)); P_el.append(a.element.name.upper()); P_name.append((a.name, r.name, i)); P_res.append(i)
    P_xyz = np.array(P_xyz)
    Ptree = cKDTree(P_xyz)
    # receptor atoms
    R_xyz, R_el, R_info = [], [], []
    for ch in model:
        if ch.name not in rec_chains:
            continue
        for r in ch:
            for a in r:
                R_xyz.append(_xyz(a)); R_el.append(a.element.name.upper()); R_info.append((ch.name, r.seqid.num, r.name, a.name))
    if not R_xyz:
        out["error"] = "receptor chains empty"
        return out
    R_xyz = np.array(R_xyz)
    Rtree = cKDTree(R_xyz)

    # sequence & residue flags
    seq = "".join(STD3.get(r.name, "X") for r in pres)
    ref_sign = _receptor_l_sign(model, rec_chains)
    is_d = []
    for r in pres:
        v = _chir_volume(r)
        is_d.append(bool(ref_sign is not None and v is not None and abs(v) > 0.5 and (1 if v > 0 else -1) != ref_sign))
    is_nme = []
    for i, r in enumerate(pres):
        prev = pres[i - 1] if i > 0 and _connected(pres[i - 1], r) else None
        is_nme.append(_is_nmethyl(r, prev, Ptree, P_xyz, P_name, P_el))
    nonstd = sorted({r.name for r in pres if r.name not in STD3})

    # --- cyclisation re-detection ---
    closures = []
    for a, b in Ptree.query_pairs(2.3):
        ia, ib = P_res[a], P_res[b]
        if abs(ia - ib) < 2:
            continue
        ea, eb = P_el[a], P_el[b]
        d = float(np.linalg.norm(P_xyz[a] - P_xyz[b]))
        na, nb_ = P_name[a][0], P_name[b][0]
        pair = tuple(sorted([ea, eb]))
        kind = None
        if pair == ("S", "S") and d < 2.3:
            kind = "disulfide"
        elif pair == ("C", "N") and d < 1.6:
            kind = "amide_like"
        elif pair == ("C", "S") and d < 2.0:
            kind = "thioether"
        elif pair == ("C", "O") and d < 1.6:
            kind = "ester_like"
        elif pair == ("C", "C") and d < 1.7:
            kind = "c_c_link"
        if kind:
            lo, hi = min(ia, ib), max(ia, ib)
            closures.append({"kind": kind, "i": lo, "j": hi, "span_res": hi - lo + 1, "atoms": [na, nb_], "dist": round(d, 2)})
    n0, c_last = _atom(pres[0], "N"), _atom(pres[-1], "C")
    if n0 is not None and c_last is not None and n0.pos.dist(c_last.pos) < 1.6:
        closures.append({"kind": "head_to_tail", "i": 0, "j": n - 1, "span_res": n, "atoms": ["N", "C"], "dist": round(n0.pos.dist(c_last.pos), 2)})
    kinds = sorted({c["kind"] for c in closures})
    if "head_to_tail" in kinds:
        primary = "head_to_tail"
    else:
        nondis = [c for c in closures if c["kind"] != "disulfide"]
        primary = (max(nondis, key=lambda c: c["span_res"])["kind"] if nondis else ("disulfide" if closures else "none"))
    ring = max((c["span_res"] for c in closures), default=0)

    # --- backbone dihedrals ---
    phi = [None] * n; psi = [None] * n; omega = [None] * n
    for i, r in enumerate(pres):
        prev = pres[i - 1] if i > 0 and _connected(pres[i - 1], r) else None
        nxt = pres[i + 1] if i < n - 1 and _connected(r, pres[i + 1]) else None
        N, CA, C = _atom(r, "N"), _atom(r, "CA"), _atom(r, "C")
        if prev is not None and None not in (N, CA, C) and _atom(prev, "C") is not None:
            phi[i] = _deg(gemmi.calculate_dihedral(_atom(prev, "C").pos, N.pos, CA.pos, C.pos))
        if nxt is not None and None not in (N, CA, C) and _atom(nxt, "N") is not None:
            psi[i] = _deg(gemmi.calculate_dihedral(N.pos, CA.pos, C.pos, _atom(nxt, "N").pos))
            if _atom(nxt, "CA") is not None:
                omega[i] = _deg(gemmi.calculate_dihedral(CA.pos, C.pos, _atom(nxt, "N").pos, _atom(nxt, "CA").pos))
    n_cis = sum(1 for o in omega if o is not None and abs(o) < 30.0)
    rama = {"alphaR": 0, "beta": 0, "alphaL": 0, "other": 0}
    for p, s, r in zip(phi, psi, pres):
        if p is None or s is None or r.name == "GLY":
            continue
        if -160 <= p <= -20 and -120 <= s <= 50:
            rama["alphaR"] += 1
        elif -180 <= p <= -45 and (s >= 90 or s <= -150):
            rama["beta"] += 1
        elif 20 <= p <= 120 and -30 <= s <= 90:
            rama["alphaL"] += 1
        else:
            rama["other"] += 1
    turns = []
    ca_xyz = [(_xyz(_atom(r, "CA")) if _atom(r, "CA") is not None else None) for r in pres]
    for i in range(n - 3):
        if not all(_connected(pres[k], pres[k + 1]) for k in range(i, i + 3)):
            continue
        if ca_xyz[i] is None or ca_xyz[i + 3] is None or np.linalg.norm(ca_xyz[i] - ca_xyz[i + 3]) > 7.0:
            continue
        a1, a2, a3, a4 = phi[i + 1], psi[i + 1], phi[i + 2], psi[i + 2]
        if None in (a1, a2, a3, a4):
            continue
        for tname, (p1, s1, p2, s2) in TURN_WINDOWS.items():
            if all(_angdiff(x, y) <= TURN_TOL for x, y in ((a1, p1), (a2, s1), (a3, p2), (a4, s2))):
                turns.append({"type": tname, "start": i, "res": seq[i:i + 4], "d_at_i1_i2": [is_d[i + 1], is_d[i + 2]]})
                break
    gammas = []
    for i in range(1, n - 1):
        if phi[i] is None or psi[i] is None or pres[i].name == "GLY":
            continue
        for gname, (gp, gs) in GAMMA.items():
            if _angdiff(phi[i], gp) <= GAMMA_TOL and _angdiff(psi[i], gs) <= GAMMA_TOL:
                gammas.append({"type": gname, "pos": i, "res": seq[i]})
                break

    # --- interface ---
    contact_pairs = Ptree.query_ball_tree(Rtree, cutoff)
    n_contacts = [0] * n; n_hb = [0] * n; n_salt = [0] * n; n_hyd = [0] * n
    pocket: Dict[Tuple, int] = {}
    R_apolar = np.zeros(len(R_xyz), bool)
    allxyz = np.vstack([P_xyz, R_xyz]); allel = P_el + R_el
    alltree = cKDTree(allxyz)
    def _apolar_c(global_idx: int) -> bool:
        if allel[global_idx] != "C":
            return False
        return not any(allel[j] in ("N", "O", "S") for j in alltree.query_ball_point(allxyz[global_idx], 1.7) if j != global_idx)
    for a, rl in enumerate(contact_pairs):
        i = P_res[a]
        for b in rl:
            d = float(np.linalg.norm(P_xyz[a] - R_xyz[b]))
            n_contacts[i] += 1
            key = (R_info[b][0], R_info[b][1], R_info[b][2])
            pocket[key] = pocket.get(key, 0) + 1
            ea, eb = P_el[a], R_el[b]
            if ea in ("N", "O") and eb in ("N", "O") and d <= 3.5:
                n_hb[i] += 1
            pa = (pres[i].name, P_name[a][0]); rb = (R_info[b][2], R_info[b][3])
            if ((pa in CHG_POS_ATOMS and rb in CHG_NEG_ATOMS) or (pa in CHG_NEG_ATOMS and rb in CHG_POS_ATOMS)) and d <= 4.0:
                n_salt[i] += 1
            if ea == "C" and eb == "C" and d <= 4.5 and _apolar_c(a) and _apolar_c(len(P_xyz) + b):
                n_hyd[i] += 1
    # covalent links between the 'peptide' and the 'receptor' (e.g. an insulin A chain disulfide-bonded to its B chain, or a
    # chain broken in the numbering) mean the chain is not an independent peptide ligand: flag it so the library can exclude it.
    n_cov = 0
    for a, rl in enumerate(contact_pairs):
        for b in rl:
            d = float(np.linalg.norm(P_xyz[a] - R_xyz[b]))
            pair = tuple(sorted([P_el[a], R_el[b]]))
            if (pair == ("S", "S") and d < 2.3) or (pair in (("C", "N"), ("C", "O"), ("C", "C"), ("C", "S")) and d < 1.85):
                n_cov += 1
    metal_contacts = 0
    for ch in model:
        for r in ch:
            for at in r:
                if at.element.name.upper() in METALS and len(r) <= 2:
                    ds = Ptree.query_ball_point(_xyz(at), 3.0)
                    metal_contacts += sum(1 for k in ds if P_el[k] in ("N", "O", "S"))
    iface_res = [i for i in range(n) if n_contacts[i] > 0]

    # --- SASA (isolated vs in complex) ---
    P_rad = np.array([RADII.get(e, 1.7) for e in P_el])
    near = Rtree.query_ball_point(P_xyz.mean(axis=0), float(np.max(np.linalg.norm(P_xyz - P_xyz.mean(axis=0), axis=1))) + 14.0)
    R_rad_all = np.array([RADII.get(e, 1.7) for e in R_el])
    occ_xyz = np.vstack([P_xyz, R_xyz[near]]) if near else P_xyz
    occ_rad = np.concatenate([P_rad, R_rad_all[near]]) if near else P_rad
    sasa_iso = shrake_rupley(P_xyz, P_rad, P_xyz, P_rad)
    sasa_cpx = shrake_rupley(P_xyz, P_rad, occ_xyz, occ_rad)
    buried_atom = np.clip(sasa_iso - sasa_cpx, 0.0, None)
    polar = np.array([e in ("N", "O") for e in P_el])
    res_iso = np.zeros(n); res_cpx = np.zeros(n)
    for k in range(len(P_xyz)):
        res_iso[P_res[k]] += sasa_iso[k]; res_cpx[P_res[k]] += sasa_cpx[k]
    buried_frac = [round(float(1.0 - res_cpx[i] / res_iso[i]), 3) if res_iso[i] > 1e-6 else 0.0 for i in range(n)]

    # --- backbone NH accounting ---
    nh_idx = [i for i, r in enumerate(pres) if r.name != "PRO" and not is_nme[i] and _atom(r, "N") is not None
              and not (i == 0 and "head_to_tail" not in kinds)]
    O_atoms = [(i, _atom(r, "O")) for i, r in enumerate(pres) if _atom(r, "O") is not None]
    n_nh_intra = n_nh_rec = n_nh_free = 0
    for i in nh_idx:
        Na = _atom(pres[i], "N")
        intra = any(abs(j - i) >= 2 and Na.pos.dist(Oa.pos) <= 3.3 for j, Oa in O_atoms)
        recep = any(eb in ("N", "O") and np.linalg.norm(_xyz(Na) - R_xyz[b]) <= 3.5 for b in Rtree.query_ball_point(_xyz(Na), 3.5) for eb in [R_el[b]])
        n_nh_intra += intra; n_nh_rec += (recep and not intra); n_nh_free += (not intra and not recep)

    pocket_list = sorted(pocket.items(), key=lambda kv: -kv[1])
    cs = P_xyz[[k for k, nm in enumerate(P_name) if nm[0] == "CA"]]
    rg = float(np.sqrt(((cs - cs.mean(axis=0)) ** 2).sum(axis=1).mean())) if len(cs) else None
    out.update({
        "ok": True, "n_res": n, "seq": seq, "nonstd_resnames": nonstd,
        "is_d": is_d, "is_nme": is_nme, "n_d": int(sum(is_d)), "n_nme": int(sum(is_nme)),
        "closures": closures, "closure_kinds": kinds, "primary_cyclisation": primary, "ring_residues": int(ring),
        "n_disulfide": sum(c["kind"] == "disulfide" for c in closures),
        "n_cis_amide": int(n_cis), "rama": rama, "beta_turns": turns, "gamma_turns": gammas,
        "n_contacts": n_contacts, "n_hbond_rec": n_hb, "n_salt": n_salt, "n_hydrophobic": n_hyd,
        "buried_frac": buried_frac, "iface_res": iface_res,
        "n_iface_res": len(iface_res), "contacts_total": int(sum(n_contacts)), "hbond_rec_total": int(sum(n_hb)),
        "salt_total": int(sum(n_salt)), "hydrophobic_total": int(sum(n_hyd)), "metal_contacts": int(metal_contacts),
        "buried_sasa_total": round(float(buried_atom.sum()), 1), "buried_sasa_polar": round(float(buried_atom[polar].sum()), 1),
        "buried_sasa_apolar": round(float(buried_atom[~polar].sum()), 1), "sasa_isolated": round(float(sasa_iso.sum()), 1),
        "n_backbone_nh": len(nh_idx), "n_nh_intra_hbond": int(n_nh_intra), "n_nh_receptor_hbond": int(n_nh_rec), "n_nh_free": int(n_nh_free),
        "n_pocket_res": len(pocket_list), "pocket": [list(k) + [v] for k, v in pocket_list[:60]],
        "hotspots": [list(k) + [v] for k, v in pocket_list[:8]], "rg_ca": None if rg is None else round(rg, 2),
        "d_sign_ref_found": ref_sign is not None, "n_covalent_to_receptor": int(n_cov),
    })
    return out
