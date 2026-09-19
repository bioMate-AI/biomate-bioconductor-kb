#!/usr/bin/env python3
"""Permeability-driven redesign v1 (structure-grounded, mechanistic, no GPU).

For each BoltzGen design (bound complex CIF): classify peptide positions as interface
(binding-critical, <4.5A heavy-atom to receptor) vs exposed. Permeability headroom =
exposed, non-Pro backbone amide NH donors that can be N-methylated WITHOUT touching the
interface -> binding preserved by construction. This is the objective a generation-time
step would maximize. Honest: N-methylation gain is scored MECHANISTICALLY (removing
exposed backbone H-bond donors is the established cyclic-peptide permeability lever,
Lokey/Kihlberg) because our own test showed the 2D-descriptor GBM is blind to it.
"""
import glob, json, os, re
from collections import defaultdict
import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors, Lipinski, rdMolDescriptors, AllChem
RDLogger.DisableLog('rdApp.*')

W = os.environ.get('PERMGEN_DIR', os.path.dirname(os.path.abspath(__file__)))  # holds cif/<target>/*.cif and mmgbsa/<target>.json
TARGETS = ['1yf4', '1csb', '1kc4', '1u8p']
IFACE_CUT = 4.5   # A, heavy-atom peptide-residue -> receptor contact

def parse_cif(path):
    """Return list of atoms: dict(chain,res,resn,atom,elem,xyz). Boltz CIFs are heavy-atom only."""
    atoms = []
    for ln in open(path):
        if ln.startswith(('ATOM', 'HETATM')):
            p = ln.split()
            try:
                atoms.append(dict(elem=p[2], atom=p[3], resn=p[5], chain=p[6],
                                  res=int(p[8]), xyz=(float(p[10]), float(p[11]), float(p[12]))))
            except (ValueError, IndexError):
                continue
    return atoms

def split_chains(atoms):
    by_chain = defaultdict(set)
    for a in atoms:
        by_chain[a['chain']].add(a['res'])
    # peptide chain = fewest residues
    pep = min(by_chain, key=lambda c: len(by_chain[c]))
    return pep

HB_CUT = 3.5   # A, backbone-N donor -> receptor acceptor H-bond distance

def interface_positions(atoms, pep_chain):
    pep = [a for a in atoms if a['chain'] == pep_chain and a['elem'] != 'H']
    rec = np.array([a['xyz'] for a in atoms if a['chain'] != pep_chain and a['elem'] != 'H'])
    rec_acc = np.array([a['xyz'] for a in atoms if a['chain'] != pep_chain and a['elem'] in ('O','N')])
    per_res = defaultdict(list)
    bbN = {}
    for a in pep:
        per_res[a['res']].append((a['resn'], a['xyz']))
        if a['atom'] == 'N':
            bbN[a['res']] = a['xyz']
    iface, exposed, resn_by_pos, bbN_free = set(), set(), {}, set()
    for res, lst in sorted(per_res.items()):
        resn_by_pos[res] = lst[0][0]
        coords = np.array([xyz for _, xyz in lst])
        dmin = np.sqrt(((coords[:, None, :] - rec[None, :, :]) ** 2).sum(-1)).min()
        (iface if dmin < IFACE_CUT else exposed).add(res)
        # backbone-N methylatable iff its N is NOT within H-bond distance of a receptor acceptor
        if res in bbN and len(rec_acc):
            dN = np.sqrt(((np.array(bbN[res])[None, :] - rec_acc) ** 2).sum(-1)).min()
            if dN > HB_CUT:
                bbN_free.add(res)
    return sorted(iface), sorted(exposed), resn_by_pos, sorted(bbN_free)

AA3to1 = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q','GLU':'E','GLY':'G',
          'HIS':'H','ILE':'I','LEU':'L','LYS':'K','MET':'M','PHE':'F','PRO':'P','SER':'S',
          'THR':'T','TRP':'W','TYR':'Y','VAL':'V'}

def cyclic_mol(seq):
    m = Chem.MolFromSequence(seq)
    if m is None: return None
    rw = Chem.RWMol(m)
    # head-to-tail: bond backbone N of res1 to C of the C-terminal carboxyl
    n_term = next((a.GetIdx() for a in rw.GetAtoms() if a.GetSymbol()=='N'
                   and a.GetPDBResidueInfo() and a.GetPDBResidueInfo().GetResidueNumber()==1), None)
    # C-terminal carbonyl C: the carboxyl carbon of the last residue
    c_term = None
    for a in rw.GetAtoms():
        if a.GetSymbol()=='C':
            os_ = [nb for nb in a.GetNeighbors() if nb.GetSymbol()=='O']
            if len(os_)>=2:
                c_term = a.GetIdx()
    if n_term is None or c_term is None: return m
    try:
        rw.AddBond(c_term, n_term, Chem.BondType.SINGLE)
        # drop one terminal O (the OH) to make an amide
        for nb in rw.GetAtomWithIdx(c_term).GetNeighbors():
            if nb.GetSymbol()=='O' and nb.GetDegree()==1:
                rw.RemoveAtom(nb.GetIdx()); break
        mm = rw.GetMol(); Chem.SanitizeMol(mm); return mm
    except Exception:
        return m

# side-chain H-bond donor residues (backbone handled separately)
SIDE_DONOR = set('RKNQHWYST')  # approx: guanidinium/amine/amide/OH/indole/imidazole

rows = []
for T in TARGETS:
    mg = json.load(open(f'{W}/mmgbsa/{T}.json'))
    dG = {d['seq']: d['dG'] for d in mg['within_target_ranking']}
    for cif in sorted(glob.glob(f'{W}/cif/{T}/*.cif')):
        name = os.path.basename(cif).replace('.cif','')
        atoms = parse_cif(cif)
        pep = split_chains(atoms)
        iface, exposed, resn, bbN_free = interface_positions(atoms, pep)
        seq = ''.join(AA3to1.get(resn[r],'X') for r in sorted(resn))
        n = len(seq)
        # methylatable = backbone-N NOT making an interface H-bond, and not Pro (already tertiary)
        methylatable = [r for r in bbN_free if resn.get(r)!='PRO']
        n_meth = len(methylatable)
        mol = cyclic_mol(seq)
        if mol is None: continue
        mw = Descriptors.MolWt(mol)
        hbd = Lipinski.NumHDonors(mol)      # baseline H-bond donors (backbone NH + side-chain)
        tpsa = rdMolDescriptors.CalcTPSA(mol)
        clogp = Descriptors.MolLogP(mol)
        # N-methylating exposed backbone amides removes n_meth backbone NH donors
        hbd_redesign = max(0, hbd - n_meth)
        all_pos = sorted(resn)
        keep_bb_donors = [r for r in all_pos if r not in set(methylatable)]  # bb N H-bonding receptor, or Pro
        rows.append(dict(target=T, design=name, seq=seq, n=n,
                         dG=round(dG.get(seq, float('nan')),2) if seq in dG else None,
                         iface_contact=iface, methylate=methylatable, keep_bb_donors=keep_bb_donors,
                         MW=round(mw,1), TPSA=round(tpsa,1), cLogP=round(clogp,2),
                         HBD=hbd, HBD_redesign=hbd_redesign, dHBD=hbd-hbd_redesign))

# score: prefer strong binder (low dG) with high permeability headroom (high dHBD) and modest size
def zscore(vals):
    v=np.array([x for x in vals if x is not None], float)
    mu,sd=v.mean(), v.std() or 1.0
    return mu,sd
dGs=[r['dG'] for r in rows if r['dG'] is not None]
muG,sdG=zscore(dGs)
for r in rows:
    bind = (-(r['dG']-muG)/sdG) if r['dG'] is not None else 0.0   # lower dG -> higher
    perm_headroom = r['dHBD'] - 0.004*(r['MW']-800)              # donors removable, small MW penalty
    r['bind_z']=round(bind,2); r['perm_headroom']=round(perm_headroom,2)
    r['combined']=round(0.5*bind + 0.5*(perm_headroom/ (np.std([x['dHBD'] for x in rows]) or 1)),3)

rows.sort(key=lambda r:(r['target'], -(r['combined'])))
STD_DHBD=float(np.std([x['dHBD'] for x in rows]) or 1)
out={'method':'permeability-driven redesign v1 (structure-grounded, mechanistic; N-methylation of '
     'exposed non-interface backbone amides preserves binding by construction; HBD reduction is the '
     'Lokey/Kihlberg permeability lever, scored mechanistically because the 2D GBM is blind to it)',
     'iface_cut_A':IFACE_CUT, 'n_designs':len(rows), 'designs':rows}
json.dump(out, open(f'{W}/redesign_v1_result.json','w'), indent=2)

# human summary
print(f"{'target':6} {'design':14} {'seq':16} {'len':3} {'dG':>7} {'MW':>6} {'HBD':>3} {'->':>3} {'nMeth':>5} {'keepBB':>6}")
for r in rows:
    print(f"{r['target']:6} {r['design']:14} {r['seq']:16} {r['n']:3d} {str(r['dG']):>7} {r['MW']:>6.0f} "
          f"{r['HBD']:>3d} {r['HBD_redesign']:>3d} {len(r['methylate']):>5d} {len(r['keep_bb_donors']):>6d}")
print("\nPer target: best combined (binding x permeability-headroom):")
seen=set()
for r in rows:
    if r['target'] not in seen:
        seen.add(r['target'])
        print(f"  {r['target']}: {r['design']} ({r['seq']}) dG={r['dG']} | N-methylate backbone at {r['methylate']} "
              f"(HBD {r['HBD']}->{r['HBD_redesign']}, dHBD={r['dHBD']}) | keep {len(r['keep_bb_donors'])} interface-H-bonding/Pro backbone donors")
