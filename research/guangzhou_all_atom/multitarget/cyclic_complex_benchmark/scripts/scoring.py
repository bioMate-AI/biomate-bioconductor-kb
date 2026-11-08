"""Scoring (needs ground truth) and ground-truth-free feature extraction for co-folded cyclic-peptide/receptor samples.

Conventions (see prep_inputs.py): receptor chains A,B,.. ; peptide chain Z ; residues numbered by entity position (label_seq_id) in both
the ground truth (native.pdb) and the predictions, so DockQ needs no chain/residue mapping search.

GT-dependent: dockq_metrics()                      -> DockQ, iRMSD, LRMSD, fnat of the peptide interface (primary = most native contacts)
GT-free     : sample_features()                    -> confidences, ring geometry, clash, contact density, interface pLDDT/PAE
              consensus_features()                 -> pose centrality / pose-cluster density across the samples of one complex
"""
import json, math, os, tempfile
import numpy as np
import gemmi
from scipy.spatial import cKDTree

IDEAL_BOND = {frozenset(("S", "S")): 2.03, frozenset(("C", "N")): 1.33, frozenset(("C", "S")): 1.82, frozenset(("C", "C")): 1.54,
              frozenset(("C", "O")): 1.36, frozenset(("N", "N")): 1.40}
RING_TOL = 0.30            # A; ring "valid" if every closure bond is within +/-0.3 A of ideal (PREREG s9)
CLASH_D = 2.2              # A; peptide-receptor heavy atom pairs closer than this are clashes
CONTACT_D = 5.0
CLUSTER_RMSD = 4.0         # A; pose-cluster radius on peptide residue representatives after receptor superposition


# ----------------------------------------------------------------------------- structure IO
def normalize_to_pdb(path_in, path_out):
    """Read a model (cif/pdb), drop H, mark every residue as ATOM (so NCAA are not skipped as HETATM by Bio.PDB), write PDB."""
    st = gemmi.read_structure(path_in)
    st.remove_hydrogens()
    st.remove_alternative_conformations()
    for ch in st[0]:
        for r in ch:
            r.het_flag = "A"
    buf = st.make_pdb_string()
    open(path_out, "w").write("".join(l for l in buf.splitlines(True) if not l.startswith(("ANISOU", "CRYST1"))))
    return path_out


def load_atoms(path):
    """-> dict chain -> list of (resnum, resname, atomname, element, xyz, bfac)"""
    st = gemmi.read_structure(path)
    st.remove_hydrogens()
    out = {}
    for ch in st[0]:
        L = []
        for r in ch:
            for a in r:
                L.append((r.seqid.num, r.name, a.name, a.element.name, np.array([a.pos.x, a.pos.y, a.pos.z]), a.b_iso))
        out[ch.name] = L
    return out


# ----------------------------------------------------------------------------- DockQ
def dockq_metrics(model_pdb, native_pdb, chain_ids, capri_peptide=False):
    """DockQ v2 for the peptide (chain Z, 'ligand') against each receptor chain; returns primary-interface dict + per-interface list.
    Primary = interface with the most native contacts. Returns None on failure (reason in 'error')."""
    from DockQ.DockQ import load_PDB, run_on_all_native_interfaces
    try:
        model = load_PDB(model_pdb)
        native = load_PDB(native_pdb)
        cmap = {c: c for c in chain_ids}
        res, _ = run_on_all_native_interfaces(model, native, chain_map=cmap, capri_peptide=capri_peptide)
    except Exception as e:  # noqa
        return {"error": f"{type(e).__name__}: {e}"[:300]}
    rows = [dict(iface=k, **{x: v[x] for x in ("DockQ", "iRMSD", "LRMSD", "fnat", "nat_total", "fnonnat", "clashes")}) for k, v in res.items()
            if "Z" in k]
    if not rows:
        return {"error": "no peptide interface found in native/model"}
    prim = max(rows, key=lambda r: r["nat_total"])
    return dict(primary=prim, interfaces=rows)


# ----------------------------------------------------------------------------- ring geometry
def _atom(atoms, resnum, name):
    for a in atoms:
        if a[0] == resnum and a[2] == name:
            return a[4], a[3]
    return None, None


def _angle(a, b, c):
    v1, v2 = a - b, c - b
    return math.degrees(math.acos(np.clip(v1 @ v2 / (np.linalg.norm(v1) * np.linalg.norm(v2) + 1e-9), -1, 1)))


def _dihedral(p0, p1, p2, p3):
    b0, b1, b2 = p0 - p1, p2 - p1, p3 - p2
    b1n = b1 / np.linalg.norm(b1)
    v, w = b0 - (b0 @ b1n) * b1n, b2 - (b2 @ b1n) * b1n
    return math.degrees(math.atan2(np.cross(b1n, v) @ w, v @ w))


def ring_geometry(pep_atoms, closures, plen):
    """Ground-truth-free ring-closure geometry of the peptide chain.
    Per closure: |d(atom1,atom2) - ideal|, bond-angle deviations at the two closure atoms (to bonded heavy neighbours within 1.9 A),
    and for head-to-tail closures the planarity deviation of the closing peptide bond (omega, from 180 or 0 deg)."""
    out = dict(n_closures=len(closures), bond_dev=[], angle_dev=[], omega_dev=[], valid=True, missing=False)
    for c in closures:
        p1, x1 = _atom(pep_atoms, c["pos1"], c["atom1"])
        p2, x2 = _atom(pep_atoms, c["pos2"], c["atom2"])
        if p1 is None or p2 is None:
            out["missing"] = True
            out["valid"] = False
            continue
        ideal = IDEAL_BOND.get(frozenset((x1[0], x2[0])), 1.5)
        d = float(np.linalg.norm(p1 - p2))
        dev = abs(d - ideal)
        out["bond_dev"].append(dev)
        if dev > RING_TOL:
            out["valid"] = False
        for (pos, nm, pa, el, pb) in ((c["pos1"], c["atom1"], p1, x1, p2), (c["pos2"], c["atom2"], p2, x2, p1)):
            ideal_ang = 104.0 if el == "S" else (121.0 if el == "N" else (116.0 if any(a[0] == pos and a[3] == "O" and np.linalg.norm(a[4] - pa) < 1.4 for a in pep_atoms) else 109.5))
            for a in pep_atoms:
                if a[0] == pos and a[2] != nm and np.linalg.norm(a[4] - pa) < 1.9 and a[3] != "H":
                    out["angle_dev"].append(abs(_angle(a[4], pa, pb) - ideal_ang))
        if {(c["pos1"], c["atom1"]), (c["pos2"], c["atom2"])} == {(1, "N"), (plen, "C")}:
            ca_l, _ = _atom(pep_atoms, plen, "CA")
            ca_f, _ = _atom(pep_atoms, 1, "CA")
            if ca_l is not None and ca_f is not None:
                w = abs(_dihedral(ca_l, p2 if c["atom2"] == "C" else p1, p1 if c["atom1"] == "N" else p2, ca_f))
                out["omega_dev"].append(min(w, abs(180 - w)))
    return out


def ring_strain(rg):
    """A-priori scalar (lower = better closed): sum bond deviation (A) + (sum angle dev + sum omega dev)(deg)/60; +10 if a closure atom is missing."""
    if rg["n_closures"] == 0:
        return 0.0
    return float(sum(rg["bond_dev"]) + (sum(rg["angle_dev"]) + sum(rg["omega_dev"])) / 60.0 + (10.0 if rg["missing"] else 0.0))


# ----------------------------------------------------------------------------- per-sample features (GT-free)
def sample_features(model_pdb, conf_json, meta, pae_if=None):
    atoms = load_atoms(model_pdb)
    pep = atoms.get("Z", [])
    rec = [a for ch, L in atoms.items() if ch != "Z" for a in L]
    P = np.array([a[4] for a in pep])
    R = np.array([a[4] for a in rec])
    plen = len(meta["peptide_ccds"])
    f = {}
    conf = json.load(open(conf_json))
    for k in ("confidence_score", "ptm", "iptm", "protein_iptm", "ligand_iptm", "complex_plddt", "complex_iplddt", "complex_pde", "complex_ipde"):
        f[k] = conf.get(k)
    pc = conf.get("pair_chains_iptm") or {}
    chains = meta["receptor_chains"] + ["Z"]
    zi = str(len(chains) - 1)
    vals = []
    for i in range(len(chains) - 1):
        a = pc.get(str(i), {}).get(zi)
        b = pc.get(zi, {}).get(str(i))
        if a is not None and b is not None:
            vals.append(max(a, b))
    f["iptm_pep_rec"] = float(max(vals)) if vals else conf.get("iptm")
    tree = cKDTree(R)
    d, _ = tree.query(P, k=1)
    pairs = tree.query_ball_point(P, CONTACT_D)
    n_contact = sum(len(x) for x in pairs)
    f["contact_density"] = n_contact / max(plen, 1)
    f["n_contact_pairs"] = n_contact
    f["clash_count"] = int(sum(len(x) for x in tree.query_ball_point(P, CLASH_D)))
    f["min_pep_rec_dist"] = float(d.min())
    iface_rec_idx = sorted({j for x in pairs for j in x})
    rec_b = np.array([a[5] for a in rec])
    pep_b = np.array([a[5] for a in pep])
    f["pep_plddt"] = float(pep_b.mean())
    f["if_plddt"] = float(np.concatenate([pep_b, rec_b[iface_rec_idx]]).mean()) if iface_rec_idx else float(pep_b.mean())
    if pae_if:
        f["pae_if"] = pae_if["pae_if_mean"]
        f["pae_pep_to_rec"] = pae_if["pae_pep_to_rec"]
    rg = ring_geometry(pep, meta["closures"], plen)
    f["ring_bond_dev_max"] = max(rg["bond_dev"]) if rg["bond_dev"] else 0.0
    f["ring_bond_dev_sum"] = float(sum(rg["bond_dev"]))
    f["ring_angle_dev_sum"] = float(sum(rg["angle_dev"]))
    f["ring_omega_dev"] = float(sum(rg["omega_dev"]))
    f["ring_strain"] = ring_strain(rg)
    f["ring_valid"] = bool(rg["valid"])
    return f


# ----------------------------------------------------------------------------- consensus features (GT-free)
def kabsch(P, Q):
    """rotation R, translation t minimising |R P + t - Q|"""
    pc, qc = P.mean(0), Q.mean(0)
    H = (P - pc).T @ (Q - qc)
    U, S, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(Vt.T @ U.T))
    D = np.diag([1, 1, d])
    R = Vt.T @ D @ U.T
    return R, qc - R @ pc


def pep_rec_coords(model_pdb):
    """receptor CA coordinates (all receptor chains) and per-residue peptide representatives (CA, else residue centroid)"""
    atoms = load_atoms(model_pdb)
    rca = np.array([a[4] for ch, L in atoms.items() if ch != "Z" for a in L if a[2] == "CA"])
    by = {}
    for a in atoms["Z"]:
        by.setdefault(a[0], []).append(a)
    rep = []
    for n in sorted(by):
        ca = [a[4] for a in by[n] if a[2] == "CA"]
        rep.append(ca[0] if ca else np.mean([a[4] for a in by[n]], axis=0))
    return rca, np.array(rep)


def consensus_features(coords):
    """coords: list of (receptor_CA[Nr,3], peptide_rep[L,3]) per sample. Superpose all on sample 0 receptor CA (all receptor chains),
    compute pairwise peptide-representative RMSD. Returns per-sample dict list + RMSD matrix."""
    n = len(coords)
    ref = coords[0][0]
    pep = []
    for rca, rep in coords:
        if len(rca) != len(ref):
            raise ValueError("receptor CA count differs between samples")
        R, t = kabsch(rca, ref)
        pep.append(rep @ R.T + t)
    M = np.zeros((n, n))
    for i in range(n):
        for j in range(i + 1, n):
            M[i, j] = M[j, i] = float(np.sqrt(((pep[i] - pep[j]) ** 2).sum(1).mean()))
    out = []
    for i in range(n):
        others = np.delete(M[i], i)
        out.append(dict(cons_mean_rmsd=float(others.mean()), cons_nbr=int((others < CLUSTER_RMSD).sum())))
    biggest = int(max(o["cons_nbr"] for o in out) + 1)
    return out, M, biggest
