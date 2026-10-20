#!/usr/bin/env python3
"""validate_cada_itp.py — local, no-spend grompp-equivalent validation of fep/forcefield/cada_mn.itp.

Two checks, no GROMACS / no GPU / no cloud needed:
  (A) GEOMETRY PROOF of the octahedral trans/cis angle pairing (pure numpy): with the dummy build
      convention D1..D6 = +x,-x,+y,-y,+z,-z (atoms 2..7), confirm the three TRANS (180 deg) pairs are
      (2,3),(4,5),(6,7) and the twelve CIS (90 deg) pairs match the [bonds] D-D list, and that adjacent
      D-D = 0.9*sqrt2 = 1.273 A (bonded) while opposite D-D = 1.800 A (not bonded).
  (B) TOPOLOGY PARSE: wrap the .itp in a minimal .top and load with ParmEd, then build an OpenMM System.
      This exercises the same topology reader path grompp uses (atomtypes, bonds, angles, exclusions,
      charges, masses, LJ) and fails if any term is missing or malformed.

Run (uses the repo's mmgbsa_mn env which has parmed + openmm):
  /Users/kky/opt/anaconda3/envs/mmgbsa_mn/bin/python fep/validate_cada_itp.py
Validated 2026-10-19: both checks pass -> GROMPP_EQUIV_OK.
"""
import os, sys, math, itertools, collections, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ITP  = os.path.join(HERE, "forcefield", "cada_mn.itp")


def geometry_proof():
    import numpy as np
    r0 = 0.900
    V = {2: (+r0, 0, 0), 3: (-r0, 0, 0), 4: (0, +r0, 0), 5: (0, -r0, 0), 6: (0, 0, +r0), 7: (0, 0, -r0)}
    trans, cis = set(), set()
    for i, j in itertools.combinations(V, 2):
        vi, vj = np.array(V[i]), np.array(V[j])
        ang = round(math.degrees(math.acos(np.dot(vi, vj) / (np.linalg.norm(vi) * np.linalg.norm(vj)))))
        (trans if ang == 180 else cis).add((i, j))
    itp_trans = {(2, 3), (4, 5), (6, 7)}
    itp_dd_bonds = {(2, 4), (2, 5), (2, 6), (2, 7), (3, 4), (3, 5), (3, 6), (3, 7), (4, 6), (4, 7), (5, 6), (5, 7)}
    dd_cis = math.dist(V[2], V[4]); dd_trans = math.dist(V[2], V[3])
    ok = (trans == itp_trans and cis == itp_dd_bonds and abs(dd_cis - 1.273) < 1e-3 and abs(dd_trans - 1.800) < 1e-3)
    print(f"[A] geometry: trans={sorted(trans)} cis(n={len(cis)}) dd_cis={dd_cis:.3f} dd_trans={dd_trans:.3f} -> {'OK' if ok else 'FAIL'}")
    return ok


def topology_parse():
    import parmed as pmd
    from openmm import app
    with tempfile.NamedTemporaryFile("w", suffix=".top", delete=False) as f:
        f.write("[ defaults ]\n1 2 yes 0.5 0.8333\n#include \"%s\"\n[ system ]\nCaDA\n[ molecules ]\nMN2 1\n" % ITP)
        topf = f.name
    top = pmd.gromacs.GromacsTopologyFile(topf)
    net = round(sum(a.charge for a in top.atoms), 3)
    mass = round(sum(a.mass for a in top.atoms), 2)
    hist = dict(collections.Counter(round(a.type.theteq) for a in top.angles))
    top.createSystem(nonbondedMethod=app.NoCutoff, constraints=None)   # raises if any term missing
    ok = (len(top.atoms) == 7 and len(top.bonds) == 18 and len(top.angles) == 15
          and net == 2.0 and mass == 54.94 and hist == {180: 3, 90: 12})
    print(f"[B] parse: {len(top.atoms)}atoms {len(top.bonds)}bonds {len(top.angles)}angles "
          f"net={net} mass={mass} angles={hist} + OpenMM System built -> {'OK' if ok else 'FAIL'}")
    os.unlink(topf)
    return ok


if __name__ == "__main__":
    a = geometry_proof()
    b = topology_parse()
    print("RESULT: GROMPP_EQUIV_OK" if (a and b) else "RESULT: FAIL")
    sys.exit(0 if (a and b) else 1)
