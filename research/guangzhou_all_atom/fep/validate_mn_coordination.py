#!/usr/bin/env python3
"""validate_mn_coordination.py -- does each CaDA-Mn actually sit in a metal site?

WHY THIS EXISTS (2026-10-25). The 2026-10-21 equilibration acceptance ("JUNCTION HOLDS ... dynamically
validated") checked only the peptide's head-to-tail amide geometry. It never measured the metal. When we
did, all three CaDA-Mn in the production complex leg were 31-36 A from the receptor and 62-70 A from the
peptide (free, hexa-aquo, in bulk water) in em/nvt/npt alike: build_fep_setup.sh ran `editconf -c`
(rigid translation of receptor+peptide, 161 A) and THEN appended Mn at their un-translated input
coordinates. So the control-edge ddG (-0.18 kcal/mol) was computed on a metal-free binding site. See
docs/20261025_CADA_MN_METAL_MODEL_VALIDATION.md.

This script is the missing measurement and the guard that closes the class. It works on any GROMACS .gro
(em / nvt / npt / a trajectory frame) with full triclinic minimum-image handling.

Per Mn centre it reports the protein/ligand oxygens within --site-cutoff and classifies:
  UNBOUND  fewer than --min-o protein/ligand O within --site-cutoff  (frame bug / metal lost / ion escaped)  -> FAIL
  CLASH    nearest protein/ligand O closer than --clash                (pose artifact; stiff CaDA will blow up) -> FAIL in
                                                                         --mode post, WARN in --mode pre
  OK       >= --min-o O within cutoff and none closer than --clash
Exit code: 0 = no FAIL, 2 = at least one FAIL.

Usage:
  python3 validate_mn_coordination.py npt.gro --mode post --ligand-resids 1070-1078
"""
import argparse, itertools, json, sys
import numpy as np

WAT = {"SOL", "HOH", "WAT", "TIP3"}


def read_gro(fn):
    L = open(fn).read().splitlines()
    n = int(L[1])
    rows = []
    for ln in L[2:2 + n]:
        rows.append((int(ln[0:5]), ln[5:10].strip(), ln[10:15].strip(),
                     np.array([float(ln[20:28]), float(ln[28:36]), float(ln[36:44])]) * 10.0))  # nm -> A
    b = [float(x) for x in L[2 + n].split()]
    if len(b) == 3:
        M = np.diag(b)
    else:  # triclinic: v1x v2y v3z v1y v1z v2x v2z v3x v3y
        v1x, v2y, v3z, v1y, v1z, v2x, v2z, v3x, v3y = b
        M = np.array([[v1x, v1y, v1z], [v2x, v2y, v2z], [v3x, v3y, v3z]])
    return rows, M * 10.0  # box rows in A


def wrap(X, M):
    f = X @ np.linalg.inv(M)
    return (f - np.floor(f)) @ M


def check(rows, M, site_cutoff=3.0, min_o=2, clash=1.8, ligand=None, mode="post"):
    xyz = wrap(np.array([r[3] for r in rows]), M)
    shifts = [np.array(s) @ M for s in itertools.product((-1, 0, 1), repeat=3)]
    is_mn_res = np.array([r[1].upper().startswith("MN") for r in rows])
    is_water = np.array([r[1] in WAT for r in rows])
    is_cent = np.array([r[1].upper().startswith("MN") and r[2].upper() == "MN" for r in rows])
    # coordinating candidates: heavy O of protein/peptide (not water, not the CaDA cage itself)
    cand = np.array([r[2].startswith("O") and not r[1] in WAT and not r[1].upper().startswith("MN") for r in rows])
    ci = np.where(cand)[0]
    out = []
    for i in np.where(is_cent)[0]:
        q = xyz[i]
        d = np.min([np.linalg.norm(xyz[ci] - (q + s), axis=1) for s in shifts], axis=0)
        order = np.argsort(d)
        near = [(float(d[k]), f"{rows[ci[k]][1]}{rows[ci[k]][0]}:{rows[ci[k]][2]}", rows[ci[k]][0]) for k in order[:6]]
        n_site = int((d < site_cutoff).sum())
        dmin = float(d[order[0]])
        dw = np.min([np.linalg.norm(xyz[is_water & np.array([r[2] == "OW" for r in rows])] - (q + s), axis=1)
                     for s in shifts], axis=0)
        n_wat = int((dw < 2.8).sum())
        lig = bool(ligand and any(ligand[0] <= r <= ligand[1] for dist, nm, r in near if dist < site_cutoff))
        if n_site < min_o:
            status = "UNBOUND"
        elif dmin < clash:
            status = "CLASH"
        else:
            status = "OK"
        fail = status == "UNBOUND" or (status == "CLASH" and mode == "post")
        out.append(dict(residue=rows[i][0], status=status, fail=fail, n_O_within_cutoff=n_site,
                        n_water_O_within_2p8A=n_wat, nearest_protein_O=[(round(x, 2), n) for x, n, _ in near[:4]],
                        min_O_dist=round(dmin, 2), ligand_contact=lig))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("gro")
    ap.add_argument("--mode", choices=("pre", "post"), default="post")
    ap.add_argument("--site-cutoff", type=float, default=3.0)
    ap.add_argument("--min-o", type=int, default=2)
    ap.add_argument("--clash", type=float, default=1.8)
    ap.add_argument("--ligand-resids", default=None, help="e.g. 1070-1078 (reports MIDAS-ligand contact)")
    ap.add_argument("--json", default=None)
    a = ap.parse_args()
    lig = tuple(int(x) for x in a.ligand_resids.split("-")) if a.ligand_resids else None
    rows, M = read_gro(a.gro)
    res = check(rows, M, a.site_cutoff, a.min_o, a.clash, lig, a.mode)
    if not res:
        print(f"{a.gro}: NO Mn centres found (resname MN*, atom MN)"); sys.exit(2)
    print(f"{a.gro}  mode={a.mode}  (cutoff {a.site_cutoff} A, min {a.min_o} protein/ligand O, clash <{a.clash} A)")
    for r in res:
        print(f"  Mn res {r['residue']}: {r['status']:8s} nO<{a.site_cutoff}A={r['n_O_within_cutoff']} "
              f"minO={r['min_O_dist']} A  waterO<2.8A={r['n_water_O_within_2p8A']}  ligand_contact={r['ligand_contact']}  "
              f"nearest={r['nearest_protein_O'][:3]}")
    nfail = sum(r["fail"] for r in res)
    print(f"  => {'FAIL' if nfail else 'PASS'} ({nfail}/{len(res)} Mn failing)")
    if a.json:
        json.dump(res, open(a.json, "w"), indent=1)
    sys.exit(2 if nfail else 0)


if __name__ == "__main__":
    main()
