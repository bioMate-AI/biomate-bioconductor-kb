#!/usr/bin/env python3
"""Permeability-driven generation v3 — score an OVERSAMPLED BoltzGen pool by binding x permeability-headroom,
and test whether the permeability-aware Pareto finds good binders with far more headroom than BoltzGen's
default (permeability-blind) top-ranked designs.

Inputs (env or argv): RUN_DIR with cif/*.cif (oversampled complexes) and metrics.csv (all_designs_metrics.csv,
providing design_to_target_iptm + final_rank). Reuses v1's structure-grounded headroom (backbone Ns not
H-bonding the receptor are N-methylatable => removable donors = permeability headroom at fixed binding).
"""
import csv, glob, json, os, re
from collections import defaultdict
import numpy as np
from rdkit import Chem, RDLogger
from rdkit.Chem import Descriptors, Lipinski, rdMolDescriptors
RDLogger.DisableLog('rdApp.*')

RUN_DIR = os.environ.get('RUN_DIR', '.')
CIF_GLOB = os.path.join(RUN_DIR, 'cif', '*.cif')
METRICS = os.environ.get('METRICS', os.path.join(RUN_DIR, 'metrics.csv'))
IFACE_CUT, HB_CUT = 4.5, 3.5
AA3to1 = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLN':'Q','GLU':'E','GLY':'G','HIS':'H','ILE':'I',
          'LEU':'L','LYS':'K','MET':'M','PHE':'F','PRO':'P','SER':'S','THR':'T','TRP':'W','TYR':'Y','VAL':'V'}

def cyclic_mol(seq):
    """Head-to-tail cyclize (committee fix: v3 previously scored the LINEAR peptide, off by ~+18 Da / +1-2
    donors). Removes the SINGLE-bonded (hydroxyl) O to form the amide, not the carbonyl. Returns None on failure."""
    m=Chem.MolFromSequence(seq)
    if m is None: return None
    rw=Chem.RWMol(m)
    n_term=next((a.GetIdx() for a in rw.GetAtoms() if a.GetSymbol()=='N'
                 and a.GetPDBResidueInfo() and a.GetPDBResidueInfo().GetResidueNumber()==1), None)
    c_term=None
    for a in rw.GetAtoms():
        if a.GetSymbol()=='C' and len([nb for nb in a.GetNeighbors() if nb.GetSymbol()=='O'])>=2:
            c_term=a.GetIdx()
    if n_term is None or c_term is None: return None
    try:
        rw.AddBond(c_term,n_term,Chem.BondType.SINGLE)
        removed=False
        for nb in rw.GetAtomWithIdx(c_term).GetNeighbors():
            if nb.GetSymbol()=='O' and rw.GetBondBetweenAtoms(c_term,nb.GetIdx()).GetBondType()==Chem.BondType.SINGLE:
                rw.RemoveAtom(nb.GetIdx()); removed=True; break
        if not removed: return None
        mm=rw.GetMol(); Chem.SanitizeMol(mm); return mm
    except Exception:
        return None

def parse_cif(path):
    atoms=[]
    for ln in open(path):
        if ln.startswith(('ATOM','HETATM')):
            p=ln.split()
            try: atoms.append(dict(elem=p[2],atom=p[3],resn=p[5],chain=p[6],res=int(p[8]),
                                   xyz=(float(p[10]),float(p[11]),float(p[12]))))
            except (ValueError,IndexError): pass
    return atoms

def analyze(cif):
    atoms=parse_cif(cif)
    by=defaultdict(set)
    for a in atoms: by[a['chain']].add(a['res'])
    if len(by)<2: return None
    pep=min(by,key=lambda c:len(by[c]))
    pepA=[a for a in atoms if a['chain']==pep and a['elem']!='H']
    rec=np.array([a['xyz'] for a in atoms if a['chain']!=pep and a['elem']!='H'])
    rec_acc=np.array([a['xyz'] for a in atoms if a['chain']!=pep and a['elem'] in ('O','N')])
    per=defaultdict(list); bbN={}
    for a in pepA:
        per[a['res']].append((a['resn'],a['xyz']))
        if a['atom']=='N': bbN[a['res']]=a['xyz']
    resn={}; methylatable=[]
    for r,lst in sorted(per.items()):
        resn[r]=lst[0][0]
        if r in bbN and len(rec_acc):
            dN=np.sqrt(((np.array(bbN[r])[None,:]-rec_acc)**2).sum(-1)).min()
            if dN>HB_CUT and resn[r]!='PRO': methylatable.append(r)
    seq=''.join(AA3to1.get(resn[r],'X') for r in sorted(resn))
    m=cyclic_mol(seq)                       # committee fix: score the CYCLIC macrocycle, not the linear peptide
    if m is None: return None
    hbd=Lipinski.NumHDonors(m); mw=Descriptors.MolWt(m); tpsa=rdMolDescriptors.CalcTPSA(m)
    return dict(seq=seq, n=len(seq), MW=round(mw,1), TPSA=round(tpsa,1),
                HBD=hbd, dHBD=len(methylatable), HBD_redesign=max(0,hbd-len(methylatable)), methylate=methylatable)

# metrics: id like '1yf4_3', design_to_target_iptm, final_rank
met={}
if os.path.exists(METRICS):
    for row in csv.DictReader(open(METRICS)):
        did=row.get('id') or row.get('design') or ''
        try: met[did]=dict(iptm=float(row.get('design_to_target_iptm','nan')), rank=int(float(row.get('final_rank','999'))))
        except ValueError: met[did]=dict(iptm=float('nan'), rank=999)

rows=[]
for cif in sorted(glob.glob(CIF_GLOB)):
    name=os.path.basename(cif).replace('.cif','')
    did=re.sub(r'^rank\d+_','',name)          # rankN_1yf4_3 -> 1yf4_3
    a=analyze(cif)
    if not a: continue
    mm=met.get(did, {})
    a.update(design=name, id=did, iptm=round(mm.get('iptm',float('nan')),3), bg_rank=mm.get('rank',999))
    rows.append(a)
if not rows:
    print('no designs parsed; check RUN_DIR/cif and METRICS'); raise SystemExit(1)

# permeability-aware score: reward binding (iptm) and target the END STATE permeability after N-methyl redesign
# -- LOW remaining donors (HBD_redesign) and LOW MW. (Rewarding raw dHBD is wrong: it favors big donor-rich
# peptides. What matters post-redesign is the achievable donor count and size.) z-scored.
def z(vals):
    v=np.array(vals,float); mu,sd=np.nanmean(v), (np.nanstd(v) or 1.0); return mu,sd
mI,sI=z([r['iptm'] for r in rows]); mR,sR=z([r['HBD_redesign'] for r in rows]); mW,sW=z([r['MW'] for r in rows])
for r in rows:
    zi=0 if np.isnan(r['iptm']) else (r['iptm']-mI)/sI
    r['perm_score']=round(0.5*zi - 0.4*((r['HBD_redesign']-mR)/sR) - 0.3*((r['MW']-mW)/sW),3)

K=min(8,len(rows))
bg_top=sorted(rows, key=lambda r:r['bg_rank'])[:K]           # BoltzGen default (permeability-blind)
pa_top=sorted(rows, key=lambda r:-r['perm_score'])[:K]       # permeability-aware (end-state)
def summ(s):
    return dict(mean_iptm=round(float(np.nanmean([r['iptm'] for r in s])),3),
                mean_HBD_redesign=round(float(np.mean([r['HBD_redesign'] for r in s])),2),
                mean_dHBD=round(float(np.mean([r['dHBD'] for r in s])),2),
                mean_MW=round(float(np.mean([r['MW'] for r in s])),0))
out=dict(run_dir=RUN_DIR, n_designs=len(rows), K=K,
         boltzgen_default_topK=summ(bg_top), perm_aware_topK=summ(pa_top),
         hypothesis='perm-aware topK should retain iptm while raising mean dHBD headroom vs BoltzGen default',
         designs=sorted(rows, key=lambda r:-r['perm_score']))
json.dump(out, open(os.path.join(RUN_DIR,'perm_generation_v3_result.json'),'w'), indent=2)

print(f"n={len(rows)} oversampled designs")
print(f"{'rank':4} {'design':16} {'seq':18} {'iptm':>5} {'bgR':>4} {'MW':>6} {'HBD':>3}->{'':2} {'dHBD':>4} {'pScore':>6}")
for i,r in enumerate(sorted(rows,key=lambda r:-r['perm_score'])[:15],1):
    print(f"{i:4} {r['design']:16} {r['seq']:18} {r['iptm']:>5} {r['bg_rank']:>4} {r['MW']:>6.0f} {r['HBD']:>3}->{r['HBD_redesign']:<2} {r['dHBD']:>4} {r['perm_score']:>6}")
print("\nBoltzGen default top-K :", summ(bg_top))
print("Permeability-aware topK:", summ(pa_top))
