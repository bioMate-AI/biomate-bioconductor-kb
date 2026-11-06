#!/usr/bin/env python3
"""Self-consistency scRMSD: Cα-RMSD between a DESIGNED peptide pose and an INDEPENDENT re-fold of the
same sequence, after optimal superposition (Kabsch). Used by the self-consistency re-ranker: low scRMSD
= the generator's pose agrees with an independent folder = designable (RFpeptides metric).

Two modes:
  * peptide-frame (default): superpose on the peptide Cα only -> intrinsic fold self-consistency.
  * receptor-frame (--on receptor): superpose on receptor Cα, then RMSD on peptide Cα -> bound-pose
    self-consistency (stricter; needs matched receptor numbering in both files).

Pure numpy + a tiny PDB Cα parser (no biotite/gemmi dependency, so it runs in any env on-instance).
Testable locally: identical coords -> 0; a known rotation+translation -> recovered to ~0.
"""
import argparse, json, sys
import numpy as np

def read_ca(path, chain=None):
    """Return {chain: [(resnum, (x,y,z)), ...]} for CA atoms, in file order."""
    out = {}
    for ln in open(path):
        if not ln.startswith(("ATOM", "HETATM")): continue
        if ln[12:16].strip() != "CA": continue
        ch = ln[21]
        if chain and ch != chain: continue
        try:
            resnum = int(ln[22:26])
            xyz = (float(ln[30:38]), float(ln[38:46]), float(ln[46:54]))
        except ValueError:
            continue
        out.setdefault(ch, []).append((resnum, xyz))
    return out

def kabsch_rmsd(P, Q):
    """RMSD between P,Q (N x 3) after optimal rotation+translation of P onto Q."""
    P = np.asarray(P, float); Q = np.asarray(Q, float)
    assert P.shape == Q.shape and P.shape[0] >= 1
    Pc, Qc = P - P.mean(0), Q - Q.mean(0)
    H = Pc.T @ Qc
    U, _, Vt = np.linalg.svd(H)
    d = np.sign(np.linalg.det(Vt.T @ U.T))
    D = np.diag([1, 1, d])
    R = Vt.T @ D @ U.T
    Pr = Pc @ R.T
    return float(np.sqrt(((Pr - Qc) ** 2).sum() / P.shape[0]))

def _shortest_chain(ca):
    return min(ca, key=lambda c: len(ca[c])) if ca else None

def scrmsd(designed_pdb, refold_pdb, pep_chain=None, on="peptide", rec_chain=None):
    dca, rca = read_ca(designed_pdb), read_ca(refold_pdb)
    pc_d = pep_chain or _shortest_chain(dca)
    pc_r = pep_chain or _shortest_chain(rca)
    if pc_d is None or pc_r is None: raise ValueError("no CA atoms parsed")
    dp = [xyz for _, xyz in dca[pc_d]]
    rp = [xyz for _, xyz in rca[pc_r]]
    n = min(len(dp), len(rp))
    if n == 0: raise ValueError("empty peptide")
    if on == "receptor":
        if not rec_chain: raise ValueError("--on receptor needs --rec_chain")
        drec = {rn: xyz for rn, xyz in dca.get(rec_chain, [])}
        rrec = {rn: xyz for rn, xyz in rca.get(rec_chain, [])}
        common = sorted(set(drec) & set(rrec))
        if len(common) < 3: raise ValueError("too few common receptor CA for superposition")
        P = np.array([drec[i] for i in common]); Q = np.array([rrec[i] for i in common])
        # rotation from receptor, applied to peptide, then peptide RMSD
        Pc, Qc = P - P.mean(0), Q - Q.mean(0)
        U, _, Vt = np.linalg.svd(Pc.T @ Qc)
        d = np.sign(np.linalg.det(Vt.T @ U.T)); R = Vt.T @ np.diag([1, 1, d]) @ U.T
        dpep = (np.array(dp[:n]) - P.mean(0)) @ R.T
        rpep = np.array(rp[:n]) - Q.mean(0)
        return float(np.sqrt(((dpep - rpep) ** 2).sum() / n))
    return kabsch_rmsd(dp[:n], rp[:n])   # peptide-frame

def _selftest():
    import tempfile, os
    def write_pdb(coords, chain="A", start=1):
        lines = []
        for i, (x, y, z) in enumerate(coords):
            lines.append(f"ATOM  {i+1:5d}  CA  ALA {chain}{start+i:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C")
        f = tempfile.NamedTemporaryFile("w", suffix=".pdb", delete=False); f.write("\n".join(lines) + "\n"); f.close()
        return f.name
    rng = np.random.default_rng(0)
    base = rng.normal(size=(10, 3)) * 5
    # identical -> 0
    a = write_pdb(base); b = write_pdb(base)
    r0 = scrmsd(a, b)
    # rotate+translate -> Kabsch recovers ~0
    theta = 0.7; R = np.array([[np.cos(theta), -np.sin(theta), 0], [np.sin(theta), np.cos(theta), 0], [0, 0, 1]])
    moved = base @ R.T + np.array([10, -4, 3])
    c = write_pdb(moved)
    r_rot = scrmsd(a, c)
    # add noise -> finite positive
    noisy = base + rng.normal(size=base.shape) * 0.5
    d = write_pdb(noisy)
    r_noisy = scrmsd(a, d)
    for p in (a, b, c, d): os.unlink(p)
    checks = {
        "identical -> ~0": r0 < 1e-6,
        "rigid rotation+translation recovered -> ~0 (limited by PDB 3-decimal precision)": r_rot < 1e-2,
        "noise -> positive, small (<1.5A for 0.5 jitter)": 0 < r_noisy < 1.5,
    }
    for k, v in checks.items(): print(f"  {'PASS' if v else 'FAIL'}  {k}  (r0={r0:.2e} r_rot={r_rot:.2e} r_noisy={r_noisy:.3f})")
    ok = all(checks.values()); print("ALL_CHECKS_PASS=" + str(ok)); return 0 if ok else 1

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--designed"); ap.add_argument("--refold")
    ap.add_argument("--pep_chain"); ap.add_argument("--on", default="peptide", choices=["peptide", "receptor"])
    ap.add_argument("--rec_chain"); ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest: sys.exit(_selftest())
    if not (a.designed and a.refold): ap.error("need --designed --refold (or --selftest)")
    print(json.dumps({"scrmsd": round(scrmsd(a.designed, a.refold, a.pep_chain, a.on, a.rec_chain), 4)}))
