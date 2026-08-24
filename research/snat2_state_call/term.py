import numpy as np, mdtraj as md
t=md.load("snat2.pdb"); top=t.topology; xyz=t.xyz[0]*10.0
def ca(rs):
    for a in top.atoms:
        if a.residue.resSeq==rs and a.name=="CA": return xyz[a.index]
site=np.mean([ca(82),ca(384)],0)
P=xyz[np.array([a.index for a in top.atoms if a.element.symbol!="H"])]
c=P-P.mean(0); _,_,Vt=np.linalg.svd(c,full_matrices=False); ax=Vt[2]
rs=sorted({a.residue.resSeq for a in top.atoms})
first,last=rs[0],rs[-1]
print(f"modeled residues {first}..{last}  (SLC38: both termini cytoplasmic)")
def off(r):
    p=ca(r); return np.dot(p-site,ax) if p is not None else None
for label,r in [("N-term",first),("N+3",first+3),("C-term",last),("C-3",last-3)]:
    o=off(r); print(f"  {label} (res {r}): offset along membrane-normal = {o:+.1f} A  -> {'+side(OPEN gate)' if o>0 else '-side(CLOSED gate)'}")
# consensus
offs=[off(r) for r in [first,first+3,last,last-3] if off(r) is not None]
side="+ (OPEN)" if np.mean(offs)>0 else "- (CLOSED)"
print(f"\ntermini mean offset = {np.mean(offs):+.1f} -> cytoplasmic face = {side} side")
if np.mean(offs)>0: print("==> OPEN gate is on the CYTOPLASMIC side  =>  INWARD-OPEN")
else: print("==> OPEN gate is on the EXTRACELLULAR side  =>  OUTWARD-OPEN")
