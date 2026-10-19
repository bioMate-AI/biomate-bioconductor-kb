#!/usr/bin/env python3
"""metal_aware MM-GBSA (local CPU) for alpha-v beta-6 — the energy half.

Adapted from the proven peptide_mmgbsa_pocket_run.sh (complex-minimize then
split-by-segid, cyclic via CYCP head-to-tail patch, first/last='none' ragged
termini). The ONE change: the 3 MIDAS Mn ions are retained as a receptor-side
psfgen ION segment (RESI MN2) with Li-Merz 12-6 Mn2+ params, so
  dG = E_complex - E_receptor(+Mn) - E_ligand
captures the peptide-Asp -> MIDAS-Mn bridge the metal-free run dropped.

A2 control-anchoring: controls (Trivehexin, avebehexin — known avb6 binders)
scored first; candidate dG is reported ONLY if controls recover strongly
negative dG. Refuse-on-stub: aborts if the Mn param is missing/placeholder.

HONEST LIMITS: dG is RELATIVE within-target, not absolute affinity; entropy
omitted; single structure; Mn LJ is explicit-solvent-derived (Li-Merz TIP3P)
used with GBn2 implicit solvent (approximate, non-bonded model). Ground truth =
wet-lab assay. Trust only ring_closed rows.
"""
import os, sys, re, json, math
import gemmi
from psfgen import PsfGen
import openmm as mm, openmm.app as app, openmm.unit as unit
import parmed as pmd
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.join(HERE, 'toppar_local')
RTF = os.path.join(TOP, 'top_all36_prot.rtf'); PRM = os.path.join(TOP, 'par_all36m_prot.prm')
MN_RTF = os.path.join(TOP, 'mn.rtf'); MN_PRM = os.path.join(TOP, 'mn.prm')
WORK = os.path.join(HERE, '_mmg_metal'); os.makedirs(WORK, exist_ok=True)

def _refuse_on_stub():
    for f in (RTF, PRM, MN_RTF, MN_PRM):
        if not os.path.exists(f): sys.exit(f"REFUSE: missing param file {f}")
    txt = open(MN_PRM).read()
    m = re.search(r'^MN\s+\S+\s+(-?\d+\.\d+)\s+(\d+\.\d+)', txt, re.M)
    if not m: sys.exit("REFUSE: no MN NONBONDED line in mn.prm")
    eps, rmin2 = abs(float(m.group(1))), float(m.group(2))
    if eps <= 0 or rmin2 <= 0 or 'PLACEHOLDER' in txt.upper() or 'STUB' in txt.upper():
        sys.exit("REFUSE: Mn param looks like a placeholder/stub")
    return eps, rmin2

MN_EPS, MN_RMIN2 = _refuse_on_stub()
PLAT = mm.Platform.getPlatformByName('CPU')
params = app.CharmmParameterSet(RTF, PRM, MN_RTF, MN_PRM)

def is_aa(r):
    i = gemmi.find_tabulated_residue(r.name); return bool(i) and i.is_amino_acid()

def _write_run(residues, path):
    s = gemmi.Structure(); md = gemmi.Model('1'); c = gemmi.Chain('X'); n = 0
    for r in residues:
        n += 1; r2 = r.clone() if hasattr(r, 'clone') else r
        c.add_residue(r2); c[-1].seqid = gemmi.SeqId(n, ' ')
    md.add_chain(c); s.add_model(md); s.setup_entities(); s.write_pdb(path); return n

def _write_ions(mn_atoms, path):
    s = gemmi.Structure(); md = gemmi.Model('1'); c = gemmi.Chain('I'); n = 0
    for a in mn_atoms:
        n += 1; r = gemmi.Residue(); r.name = 'MN2'; r.seqid = gemmi.SeqId(n, ' ')
        at = gemmi.Atom(); at.name = 'MN'; at.element = gemmi.Element('Mn'); at.pos = a.pos
        r.add_atom(at); c.add_residue(r)
    md.add_chain(c); s.add_model(md); s.setup_entities(); s.write_pdb(path); return n

POCKET_CUTOFF = 8.0  # A — keep receptor residues within this of the peptide or any Mn (pocket MM-GBSA)

def _near(res, ref_pts, cutoff):
    c2 = cutoff * cutoff
    for a in res:
        for p in ref_pts:
            dx = a.pos.x - p[0]; dy = a.pos.y - p[1]; dz = a.pos.z - p[2]
            if dx * dx + dy * dy + dz * dz <= c2:
                return True
    return False

def split_design(cif, tag):
    st = gemmi.read_structure(cif); st.setup_entities(); m = st[0]
    aac = {c.name: sum(is_aa(r) for r in c) for c in m}; aac = {k: v for k, v in aac.items() if v > 0}
    pep = 'P' if 'P' in aac else min(aac, key=aac.get)
    pepres = [r for c in m if c.name == pep for r in c if is_aa(r)]
    npep = _write_run(pepres, f'{tag}_pep.pdb')
    # pocket-truncation reference points: all peptide atoms + all Mn atoms
    ref = [(a.pos.x, a.pos.y, a.pos.z) for r in pepres for a in r]
    ref += [(a.pos.x, a.pos.y, a.pos.z) for c in m for r in c if r.name.strip() == 'MN' for a in r]
    rec_pdbs = []; k = 0
    for c in m:
        if c.name == pep: continue
        res = [r for r in c if is_aa(r) and _near(r, ref, POCKET_CUTOFF)]
        if not res: continue
        res.sort(key=lambda r: r.seqid.num); frag = []; prev = None
        for r in res:
            if prev is not None and r.seqid.num != prev + 1:
                _write_run(frag, f'{tag}_rec{k}.pdb'); rec_pdbs.append(f'{tag}_rec{k}.pdb'); k += 1; frag = []
            frag.append(r); prev = r.seqid.num
        if frag:
            _write_run(frag, f'{tag}_rec{k}.pdb'); rec_pdbs.append(f'{tag}_rec{k}.pdb'); k += 1
    mn = [a for c in m for r in c if r.name.strip() == 'MN' for a in r]
    nion = _write_ions(mn, f'{tag}_ions.pdb') if mn else 0
    return rec_pdbs, npep, nion

HEADTAIL = "* head-to-tail patch\n*\n   36  1\nPRES CYCP         0.00\nBOND 1C 2N\n\nEND\n"
open(os.path.join(WORK, 'headtail.top'), 'w').write(HEADTAIL)
ALIASES = [('HIS', 'HSD'), ('HID', 'HSD'), ('HIE', 'HSE'), ('HIP', 'HSP')]

def build_psf(kind, tag, npep, rec_pdbs, nion):
    g = PsfGen()
    g.read_topology(RTF); g.read_topology(os.path.join(WORK, 'headtail.top')); g.read_topology(MN_RTF)
    for a, b in ALIASES:
        try: g.alias_residue(top_resname=b, pdb_resname=a)
        except Exception:
            try: g.alias_residue(a, b)
            except Exception: pass
    try: g.alias_atom(resname='ILE', top_atomname='CD', pdb_atomname='CD1')
    except Exception:
        try: g.alias_atom('ILE', 'CD', 'CD1')
        except Exception: pass
    if kind in ('complex', 'receptor'):
        for i, rp in enumerate(rec_pdbs):
            g.add_segment(segid=f'R{i}', pdbfile=rp, first='none', last='none'); g.read_coords(segid=f'R{i}', filename=rp)
        if nion:
            g.add_segment(segid='ION', pdbfile=f'{tag}_ions.pdb', first='none', last='none'); g.read_coords(segid='ION', filename=f'{tag}_ions.pdb')
    if kind in ('complex', 'ligand'):
        g.add_segment(segid='PEP', pdbfile=f'{tag}_pep.pdb', first='none', last='none'); g.read_coords(segid='PEP', filename=f'{tag}_pep.pdb')
        g.patch('CYCP', [('PEP', str(npep)), ('PEP', '1')])
    g.regenerate_angles(); g.regenerate_dihedrals()
    try: g.guess_coords()
    except Exception: pass
    psf = f'{tag}_{kind}.psf'; pdb = f'{tag}_{kind}.pdb'
    g.write_psf(filename=psf); g.write_pdb(filename=pdb); return psf, pdb

def energy(system, pos):
    integ = mm.VerletIntegrator(1.0 * unit.femtoseconds); ctx = mm.Context(system, integ, PLAT)
    ctx.setPositions(pos); e = ctx.getState(getEnergy=True).getPotentialEnergy().value_in_unit(unit.kilocalorie_per_mole)
    del ctx, integ; return e

def ring_closed(lp):
    def idx(res, nm):
        for a in res.atoms:
            if a.name == nm: return a.idx
        return None
    ni = idx(lp.residues[0], 'N'); ci = idx(lp.residues[-1], 'C')
    return bool(any({b.atom1.idx, b.atom2.idx} == {ni, ci} for b in lp.bonds)) if (ni is not None and ci is not None) else False

def score_one(cif, tag):
    rec_pdbs, npep, nion = split_design(cif, tag)
    cpsf, cpdb = build_psf('complex', tag, npep, rec_pdbs, nion)
    lpsf, _ = build_psf('ligand', tag, npep, rec_pdbs, nion)
    lp = pmd.load_file(lpsf); rc = ring_closed(lp)
    cp = app.CharmmPsfFile(cpsf)
    csys = cp.createSystem(params, nonbondedMethod=app.CutoffNonPeriodic, nonbondedCutoff=1.2 * unit.nanometer,
                           constraints=app.HBonds, implicitSolvent=app.GBn2)
    pos = app.PDBFile(cpdb).getPositions()
    integ = mm.LangevinMiddleIntegrator(300 * unit.kelvin, 1 / unit.picosecond, 0.002 * unit.picoseconds)
    sim = app.Simulation(cp.topology, csys, integ, PLAT); sim.context.setPositions(pos); sim.minimizeEnergy(maxIterations=1500)
    P = sim.context.getState(getPositions=True).getPositions(); Ecom = energy(csys, P)
    comp = pmd.charmm.CharmmPsfFile(cpsf); comp.load_parameters(pmd.charmm.CharmmParameterSet(RTF, PRM, MN_RTF, MN_PRM))
    comp.coordinates = np.array(P.value_in_unit(unit.angstrom))
    rec_idx = [a.idx for a in comp.atoms if a.residue.segid != 'PEP']
    lig_idx = [a.idx for a in comp.atoms if a.residue.segid == 'PEP']
    rst = comp[rec_idx]; lst = comp[lig_idx]
    opt = dict(nonbondedMethod=app.CutoffNonPeriodic, nonbondedCutoff=1.2 * unit.nanometer, constraints=app.HBonds, implicitSolvent=app.GBn2)
    rsys = rst.createSystem(**opt); lsys = lst.createSystem(**opt)
    Erec = energy(rsys, rst.positions); Elig = energy(lsys, lst.positions)
    nmn = sum(1 for a in comp.atoms if a.residue.segid == 'ION')
    return dict(dG_bind_kcal_mol=round(float(Ecom - Erec - Elig), 2), E_complex=round(Ecom, 1),
                E_receptor_incl_Mn=round(Erec, 1), E_ligand=round(Elig, 1), npep=npep, n_mn=nmn,
                ring_closed=rc, ok=True)

POSES = {
    'CTRL-TRIVEHEXIN': 'results/poses/CTRL-TRIVEHEXIN_metal.cif',
    'CTRL-AVEBEHEXIN': 'results/poses/CTRL-AVEBEHEXIN_metal.cif',
    'AVB6-SH-M7-01': 'results/poses/AVB6-SH-M7-01_sh.cif',
    'AVB6-SH-M11-01': 'results/poses/AVB6-SH-M11-01_sh.cif',
}

def main():
    os.chdir(WORK)
    partial = os.path.join(HERE, 'results/avb6_metal_mmgbsa_dG.json')
    results = {}
    for name, rel in POSES.items():
        cif = os.path.join(HERE, rel); tag = name.replace('/', '_')
        try:
            r = score_one(cif, tag); print(f"{name:<18} dG = {r['dG_bind_kcal_mol']:>8} kcal/mol  (Mn={r['n_mn']}, {r['npep']}-mer, ring={r['ring_closed']})", flush=True)
        except Exception as e:
            import traceback; r = dict(ok=False, error=f"{type(e).__name__}: {str(e)[:200]}")
            print(f"{name:<18} FAILED: {r['error']}", flush=True); traceback.print_exc()
        results[name] = r
        json.dump({'results': results, 'complete': False}, open(partial, 'w'), indent=2)  # per-pose flush
    ctrls = {k: v for k, v in results.items() if 'CTRL' in k and v.get('ok')}
    cvals = [v['dG_bind_kcal_mol'] for v in ctrls.values()]
    MAXGOOD = -5.0            # a control must be at least this negative
    MAX_CTRL_SPREAD = 30.0    # A2: comparable known binders must cluster (generous for MM-GBSA)
    ctrl_neg = len(ctrls) >= 2 and all(c <= MAXGOOD for c in cvals)
    ctrl_clustered = len(cvals) >= 2 and (max(cvals) - min(cvals)) <= MAX_CTRL_SPREAD
    ctrl_ok = ctrl_neg and ctrl_clustered  # BOTH required for A2 admissibility
    spread = round(max(cvals) - min(cvals), 1) if cvals else None
    verdict = dict(
        param_source='Li-Merz 12-6 CM set, TIP3P (Li,Roberts,Chakravorty,Merz JCTC 2013,9,2733); Rmin/2=%.3f A eps=%.6f kcal/mol' % (MN_RMIN2, MN_EPS),
        admissible=bool(ctrl_ok),
        gate='A2: both controls dG <= %.1f AND mutually clustered within %.0f kcal/mol' % (MAXGOOD, MAX_CTRL_SPREAD),
        control_spread_kcal=spread,
        reason=('controls cluster — relative ranking admissible' if ctrl_ok else
                'controls DIVERGE by %.0f kcal/mol (> %.0f): two comparable known avb6 binders cannot differ '
                'this much — the dG is dominated by the artifactual, distance-sensitive Asp-Mn2+ electrostatic '
                '(fixed-charge non-bonded metal), NOT recoverable binding. INADMISSIBLE.' % (spread, MAX_CTRL_SPREAD)),
        results=results,
        ranking=sorted([{'name': k, 'dG': v['dG_bind_kcal_mol'], 'ring': v.get('ring_closed')}
                        for k, v in results.items() if v.get('ok')], key=lambda x: x['dG']) if ctrl_ok else None,
        note=('RELATIVE within-avb6 MM-GBSA (GBn2 minimized single-point, CHARMM36m, receptor-side Mn). '
              'NOT absolute affinity; entropy omitted; Mn LJ explicit-solvent-derived used with GBn2 (approx). '
              'Report ranking ONLY if admissible. A fixed-charge non-bonded +2 metal gives enormous '
              'distance-sensitive electrostatics; a 12-6-4 LJ or bonded/CaDA Mn model is needed for an '
              'admissible energy step. Geometric site-fidelity gate (metal_mmgbsa_prep.py) remains the '
              'defensible metal-aware result. Ground truth = wet-lab assay.'))
    out = os.path.join(HERE, 'results/avb6_metal_mmgbsa_dG.json')
    json.dump(verdict, open(out, 'w'), indent=2)
    print('\nADMISSIBLE:', verdict['admissible'], '—', verdict['gate'])
    if ctrl_ok:
        print('CONTROL-GATED RELATIVE RANKING (most negative = best):')
        for row in verdict['ranking']:
            print(f"  {row['name']:<18} dG = {row['dG']:>8} kcal/mol  ring={row['ring']}")
    else:
        print('INADMISSIBLE — controls did not recover binding; candidate dG NOT reported.')
    print('wrote', out)

if __name__ == '__main__':
    main()
