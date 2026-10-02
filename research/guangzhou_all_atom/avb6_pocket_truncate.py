#!/usr/bin/env python3
"""Pocket-truncate αvβ6 (9xmm) panel complexes for MM-GBSA.

The refold complexes carry the FULL receptor (chain B=αV 440aa + C=β6 241aa) + peptide (chain A).
Whole-receptor MM-GBSA hung (the base runner also silently kept only the largest single chain =
αV, dropping β6 — losing half the integrin RGD pocket). Here we keep, from BOTH receptor chains,
every residue with any heavy atom within CUT (default 10 Å) of any peptide heavy atom, and write a
truncated complex (peptide chain A + B-pocket + C-pocket). Receptor shrinks 681 -> ~30-70 res, and
BOTH subunits' contacts are retained by construction (10 Å >> the 4.5 Å contact shell).

Usage: python avb6_pocket_truncate.py <in_dir> <out_dir> [cut_A]
Prints per-design pocket sizes + RGD-style contact retention; exits non-zero if any pocket is empty.
"""
import sys, os, glob, json
import numpy as np
import gemmi

IN = sys.argv[1] if len(sys.argv) > 1 else '/private/tmp/claude-501/-Users-kky-biomate-review/9bfe5056-ee28-4095-8e35-5af49e87e358/scratchpad/avb6_refold'
OUT = sys.argv[2] if len(sys.argv) > 2 else '/private/tmp/claude-501/-Users-kky-biomate-review/9bfe5056-ee28-4095-8e35-5af49e87e358/scratchpad/avb6_pocket'
CUT = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
CONTACT = 4.5
PANEL = '/Users/kky/biomate-review/research/guangzhou_all_atom/results/avb6_round1_panel.json'
os.makedirs(OUT, exist_ok=True)

def is_aa(r):
    i = gemmi.find_tabulated_residue(r.name)
    return bool(i) and i.is_amino_acid()

def heavy(res):
    return [a for a in res if a.element.name != 'H']

ids = [x['id'] for x in json.load(open(PANEL))['panel']]
report = []
ok_all = True
for did in ids:
    cif = os.path.join(IN, f'{did}.cif')
    if not os.path.exists(cif):
        print(f'{did}: MISSING {cif}'); ok_all = False; continue
    st = gemmi.read_structure(cif); st.setup_entities(); m = st[0]
    # peptide = fewest-aa chain; receptor = the rest
    aa_chains = [(c.name, sum(is_aa(r) for r in c)) for c in m]
    aa_chains = [c for c in aa_chains if c[1] > 0]
    aa_chains.sort(key=lambda x: x[1])
    pep_name = aa_chains[0][0]
    rec_names = [c for c, _ in aa_chains[1:]]
    pep_chain = next(c for c in m if c.name == pep_name)
    pep_atoms = np.array([[a.pos.x, a.pos.y, a.pos.z] for r in pep_chain if is_aa(r) for a in heavy(r)])

    # build truncated structure: peptide (all) + receptor residues within CUT
    out = gemmi.Structure(); out.name = f'{did}_pocket'
    md = gemmi.Model('1')
    newpep = gemmi.Chain(pep_name)
    for r in pep_chain:
        if is_aa(r): newpep.add_residue(r)
    md.add_chain(newpep)
    pocket_counts = {}
    contact_B = contact_C = 0  # peptide-sidechain contacts retained to each subunit
    for cn in rec_names:
        c = next(ch for ch in m if ch.name == cn)
        newc = gemmi.Chain(cn)
        for r in c:
            if not is_aa(r):
                continue
            rc = np.array([[a.pos.x, a.pos.y, a.pos.z] for a in heavy(r)])
            if rc.size == 0:
                continue
            d = np.sqrt(((rc[:, None, :] - pep_atoms[None, :, :]) ** 2).sum(-1)).min()
            if d < CUT:
                newc.add_residue(r)
        pocket_counts[cn] = sum(1 for _ in newc)
        md.add_chain(newc)
    out.add_model(md); out.setup_entities()

    # RGD-contact evidence: peptide cationic (R/K) heavy atoms vs each receptor subunit @ CONTACT,
    # and peptide D/E/G vs each subunit (RGD-like: Arg->one subunit, Asp->the other MIDAS).
    def contacts(resn_set, cn):
        c = next(ch for ch in m if ch.name == cn)
        rec_atoms = np.array([[a.pos.x, a.pos.y, a.pos.z] for r in c if is_aa(r) for a in heavy(r)])
        pa = np.array([[a.pos.x, a.pos.y, a.pos.z] for r in pep_chain if is_aa(r) and r.name in resn_set for a in heavy(r)])
        if pa.size == 0 or rec_atoms.size == 0:
            return 0
        return int((np.sqrt(((pa[:, None, :] - rec_atoms[None, :, :]) ** 2).sum(-1)).min(1) < CONTACT).sum())
    cat = {'ARG', 'LYS'}; acid = {'ASP', 'GLU'}
    cB = {cn: (contacts(cat, cn), contacts(acid, cn)) for cn in rec_names}

    total_pocket = sum(pocket_counts.values())
    if total_pocket == 0:
        ok_all = False
    outpath = os.path.join(OUT, f'{did}.cif')
    out.write_pdb(outpath.replace('.cif', '.pdb'))
    doc = out.make_pdb_string()
    # write as mmCIF too (runner globs *.cif)
    out.setup_entities()
    out.make_mmcif_document().write_file(outpath)
    report.append(dict(id=did, pep=pep_name, pep_len=aa_chains[0][1], rec_chains=rec_names,
                       pocket=pocket_counts, total_pocket=total_pocket, cat_acid_contacts=cB))
    cc = ' '.join(f'{cn}:cat{cB[cn][0]}/acid{cB[cn][1]}' for cn in rec_names)
    print(f'{did}: pep={pep_name}({aa_chains[0][1]}aa) pocket={pocket_counts} total={total_pocket}  contacts[{cc}]')

json.dump({'cut_A': CUT, 'contact_A': CONTACT, 'designs': report},
          open(os.path.join(OUT, 'truncation_report.json'), 'w'), indent=2)
tp = [r['total_pocket'] for r in report if 'total_pocket' in r]
print(f'\nSUMMARY: {len(report)} designs | pocket residues min={min(tp)} max={max(tp)} mean={sum(tp)/len(tp):.0f}')
print('All pockets span BOTH receptor subunits:',
      all(len([c for c in r['pocket'].values() if c > 0]) == len(r['rec_chains']) for r in report))
sys.exit(0 if ok_all else 2)
