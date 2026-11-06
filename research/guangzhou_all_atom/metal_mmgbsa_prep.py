#!/usr/bin/env python3
"""metal_mmgbsa_prep.py — Mn-retaining prep + control-anchoring gate for metal-aware MM-GBSA.

The existing pocket MM-GBSA runner (peptide_mmgbsa_pocket_run.sh) keeps only
`is_amino_acid()` residues in split_design() — it DROPS the MIDAS Mn ions, which
is why metal-free avb6 MM-GBSA gave weak/positive dG (integrin RGD binding is
MIDAS-metal-mediated). This module is the structural half of the metal-aware fix,
and the part that needs NO force field / OpenMM:

  1. parse a metal-aware cofold pose (Boltz-2 output with Mn CCD ligands),
  2. split receptor(+Mn) / peptide so the Mn sits on the RECEPTOR side
     (ΔG = E_complex − E_receptor(+Mn) − E_ligand then captures the
     peptide-Asp→MIDAS-Mn bridge the metal-free run missed),
  3. ASSERT the Mn ions are retained on the receptor side (the "proves Mn is
     retained" dry-run), and
  4. run the A2 control-anchoring GEOMETRIC gate: known binders (Trivehexin /
     avebehexin) must place their RGD Asp carboxylate in direct MIDAS-Mn
     coordination (inner-sphere ~2.0-2.4 Å). If the controls don't, the
     metal-aware setup is INADMISSIBLE and no candidate number is trusted.

Honest limits: coordination distances are cofold-approximate (Boltz places the
metal with no explicit vdW repulsion, so very short O-Mn separations are a model
artifact); the conclusion is RELATIVE/qualitative (does the ligand engage the
metal site), never an affinity. The energy half (OpenMM GBn2 with a validated
Mn²⁺ non-bonded parameter — Li & Merz JCTC 2013, 12-6 TIP3P) is launch-ready in
peptide_mmgbsa_metal_run.sh but must pass this gate on controls first.
"""
import sys, math, json, os

CARBOXYL = {'OD1', 'OD2', 'OE1', 'OE2'}  # Asp/Glu side-chain carboxylate O
INNER_SPHERE_MAX = 2.6   # Å — generous inner-sphere coordination cutoff
ENGAGE_MAX = 3.5         # Å — beyond this the ligand does not engage the metal


def parse_atoms(cif):
    """Dependency-free parse of mmCIF _atom_site rows.
    Boltz column order: group id type atom alt comp seqid authseq ins asym x y z occ entity."""
    atoms = []
    with open(cif) as fh:
        for ln in fh:
            if ln.startswith('ATOM ') or ln.startswith('HETATM '):
                p = ln.split()
                try:
                    atoms.append(dict(group=p[0], el=p[2], atom=p[3], comp=p[5],
                                      chain=p[9], x=float(p[10]), y=float(p[11]), z=float(p[12])))
                except (IndexError, ValueError):
                    pass
    return atoms


def dist(a, b):
    return math.sqrt((a['x'] - b['x'])**2 + (a['y'] - b['y'])**2 + (a['z'] - b['z'])**2)


def split_sides(atoms):
    """Return (receptor_atoms_incl_Mn, ligand_atoms, mn_atoms, ligand_chain).
    Ligand = chain 'P' (Boltz peptide) else the smallest non-Mn chain by atom count.
    Mn ions are assigned to the RECEPTOR side (they are the β6 MIDAS cofactor)."""
    mn = [a for a in atoms if a['comp'] == 'MN']
    counts = {}
    for a in atoms:
        if a['comp'] == 'MN':
            continue
        counts[a['chain']] = counts.get(a['chain'], 0) + 1
    ligch = 'P' if 'P' in counts else (min(counts, key=counts.get) if counts else None)
    lig = [a for a in atoms if a['chain'] == ligch]
    rec = [a for a in atoms if a['chain'] != ligch and a['comp'] != 'MN']
    receptor = rec + mn  # Mn rides with the receptor
    return receptor, lig, mn, ligch


def coordination(lig, mn):
    """Min distance from a ligand carboxylate O to any Mn; which residue/atom."""
    best = (1e9, None, None)
    for a in lig:
        if a['atom'] in CARBOXYL:
            for m in mn:
                d = dist(a, m)
                if d < best[0]:
                    best = (d, a['comp'], a['atom'])
    return best


def prep_and_gate(poses):
    """poses: {name: cif}. Controls are names containing 'CTRL'. Returns verdict dict."""
    rows = {}
    for name, cif in poses.items():
        atoms = parse_atoms(cif)
        receptor, lig, mn, ligch = split_sides(atoms)
        # DRY-RUN ASSERTION: Mn retained on receptor side.
        n_mn_rec = sum(1 for a in receptor if a['comp'] == 'MN')
        assert n_mn_rec == len(mn) and len(mn) >= 1, \
            f"{name}: Mn not retained on receptor ({n_mn_rec}/{len(mn)})"
        d, res, atom = coordination(lig, mn)
        rows[name] = dict(lig_chain=ligch, n_mn=len(mn), n_rec_atoms=len(receptor),
                          n_lig_atoms=len(lig), min_ligO_Mn=round(d, 2),
                          coord_res=res, coord_atom=atom,
                          engages_metal=bool(d <= ENGAGE_MAX),
                          inner_sphere=bool(d <= INNER_SPHERE_MAX))
    # A2 control-anchoring: every control must engage the MIDAS Mn via Asp/Glu.
    controls = {k: v for k, v in rows.items() if 'CTRL' in k.upper()}
    ctrl_ok = bool(controls) and all(v['engages_metal'] and v['coord_res'] in ('ASP', 'GLU')
                                     for v in controls.values())
    verdict = dict(
        admissible=ctrl_ok,
        reason=('controls recover RGD-Asp->MIDAS-Mn coordination (setup admissible)'
                if ctrl_ok else
                'controls do NOT engage the MIDAS Mn via Asp/Glu — metal-aware setup INADMISSIBLE'),
        controls=controls,
        candidates={k: v for k, v in rows.items() if 'CTRL' not in k.upper()},
        note=('Geometric site-fidelity gate only. Mn retained on receptor side for the energy '
              'step. Coordination distances are cofold-approximate; RELATIVE/qualitative, not '
              'affinity. Candidate dG ranking (OpenMM GBn2 + Li-Merz Mn²⁺) is valid ONLY if '
              'admissible=true.'))
    return verdict


if __name__ == '__main__':
    base = os.path.dirname(os.path.abspath(__file__))
    poses = {
        'CTRL-TRIVEHEXIN': 'results/poses/CTRL-TRIVEHEXIN_metal.cif',
        'CTRL-AVEBEHEXIN': 'results/poses/CTRL-AVEBEHEXIN_metal.cif',
        'AVB6-SH-M7-01': 'results/poses/AVB6-SH-M7-01_sh.cif',
        'AVB6-SH-M11-01': 'results/poses/AVB6-SH-M11-01_sh.cif',
    }
    if len(sys.argv) > 1:  # allow explicit pose list: name=path ...
        poses = dict(kv.split('=', 1) for kv in sys.argv[1:])
    poses = {k: (v if os.path.isabs(v) else os.path.join(base, v)) for k, v in poses.items()}
    v = prep_and_gate(poses)
    out = os.path.join(base, 'results/avb6_metal_mmgbsa_gate.json')
    json.dump(v, open(out, 'w'), indent=2)
    print(f"ADMISSIBLE: {v['admissible']} — {v['reason']}\n")
    print(f"{'pose':<18}{'res':>5}{'O-Mn(Å)':>9}{'inner':>7}{'engage':>8}")
    for grp in ('controls', 'candidates'):
        for name, r in v[grp].items():
            print(f"{name:<18}{str(r['coord_res']):>5}{r['min_ligO_Mn']:>9}"
                  f"{str(r['inner_sphere']):>7}{str(r['engages_metal']):>8}")
    print(f"\nwrote {out}")
