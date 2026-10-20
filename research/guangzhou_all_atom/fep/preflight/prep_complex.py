#!/usr/bin/env python3
"""prep_complex.py — split the metal-complete control pose into GROMACS-ready components.

Reads a CTRL-*_metal.cif (receptor chains A,B + 3 Mn centers M1/M2/M3 + cyclic peptide chain P)
and writes, into the CWD:
  receptor.pdb  — chains A,B (protein only), for pdb2gmx (CHARMM36m)
  peptide.pdb   — chain P (the 9-residue head-to-tail cyclic peptide; the FEP-mutated molecule)
  mn_cada.pdb   — the 3 Mn as full CaDA MN2 residues: each = center MN + 6 octahedral dummies
                  D1..D6 placed at +x,-x,+y,-y,+z,-z offset 0.900 A from the center (matching
                  fep/forcefield/cada_mn.itp). Geometry is approximate (grompp preflight only; em relaxes).

Usage: python prep_complex.py <pose.cif>
"""
import sys
import gemmi

OFFS = [(+0.9, 0, 0), (-0.9, 0, 0), (0, +0.9, 0), (0, -0.9, 0), (0, 0, +0.9), (0, 0, -0.9)]  # D1..D6
DUM = ["D1", "D2", "D3", "D4", "D5", "D6"]
AA = set("ALA ARG ASN ASP CYS GLN GLU GLY HIS ILE LEU LYS MET PHE PRO SER THR TRP TYR VAL "
         "HID HIE HIP HSD HSE HSP CYX".split())


def write_pdb(path, chains_atoms):
    """chains_atoms: list of (chain_id, gemmi.Residue list). Minimal PDB writer via gemmi."""
    st = gemmi.Structure()
    mdl = gemmi.Model("1")
    for cid, residues in chains_atoms:
        ch = gemmi.Chain(cid)
        for r in residues:
            ch.add_residue(r)
        mdl.add_chain(ch)
    st.add_model(mdl)
    st.setup_entities()
    doc = st.make_pdb_string()
    open(path, "w").write(doc)


def main(cif):
    st = gemmi.read_structure(cif)
    st.setup_entities()
    m = st[0]
    prot_chains, pep_chain, mn_centers = [], None, []
    for ch in m:
        names = [r.name for r in ch]
        if ch.name in ("A", "B"):
            prot_chains.append((ch.name, [r for r in ch if r.name in AA]))
        elif ch.name == "P":
            pep_chain = (ch.name, [r for r in ch])
        else:  # Mn centers M1/M2/M3 (single-atom chains) or any MN residue
            for r in ch:
                for a in r:
                    if a.element == gemmi.Element("Mn") or r.name in ("MN", "MN2"):
                        mn_centers.append(a.pos)
    # also catch MN present inside receptor chains
    for ch in m:
        for r in ch:
            if r.name in ("MN", "MN2"):
                for a in r:
                    if a.pos not in mn_centers:
                        mn_centers.append(a.pos)

    write_pdb("receptor.pdb", prot_chains)
    write_pdb("peptide.pdb", [pep_chain])

    # build mn_cada.pdb by hand (7 atoms/residue)
    lines = []
    serial = 1
    for i, c in enumerate(mn_centers, 1):
        atoms = [("MN", c.x, c.y, c.z)]
        for nm, (dx, dy, dz) in zip(DUM, OFFS):
            atoms.append((nm, c.x + dx, c.y + dy, c.z + dz))
        for nm, x, y, z in atoms:
            el = "Mn" if nm == "MN" else "C"
            lines.append(f"HETATM{serial:5d} {nm:<4s} MN2 Z{i:4d}    "
                         f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00          {el:>2s}")
            serial += 1
    lines.append("END")
    open("mn_cada.pdb", "w").write("\n".join(lines) + "\n")

    npep = len(pep_chain[1]) if pep_chain else 0
    nrec = sum(len(r) for _, r in prot_chains)
    print(f"PREP_OK receptor_chains={[c for c,_ in prot_chains]} receptor_res={nrec} "
          f"peptide_res={npep} n_Mn={len(mn_centers)} (each -> 7 CaDA particles)")


if __name__ == "__main__":
    main(sys.argv[1])
