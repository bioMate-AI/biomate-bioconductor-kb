import numpy as np, mdtraj as md
t = md.load("snat2.pdb"); top=t.topology; xyz=t.xyz[0]*10.0
def ca(rs):
    for a in top.atoms:
        if a.residue.resSeq==rs and a.name=="CA": return xyz[a.index]
site=np.mean([ca(82),ca(384)],0)
P=xyz[np.array([a.index for a in top.atoms if a.element.symbol!="H"])]
c=P-P.mean(0); _,_,Vt=np.linalg.svd(c,full_matrices=False); ax=Vt[2]  # PA3 = membrane normal (from pore analysis)
# positive-inside rule: project charged-residue CAs onto membrane normal; cytoplasmic face has excess K+R
pos=neg=0.0; proj_pos=[]; proj_neg=[]
for a in top.atoms:
    if a.name!="CA": continue
    r=a.residue.name; s=np.dot(xyz[a.index]-site, ax)  # signed offset along normal (+ = open side)
    if r in ("LYS","ARG"): (proj_pos if s>0 else proj_neg).append(1)
    if r in ("ASP","GLU"): (proj_pos if s>0 else proj_neg).append(-1)
netp=sum(proj_pos); netn=sum(proj_neg)
print(f"membrane normal = PA3; +side = the OPEN gate (from pore profile)")
print(f"net charge (K+R minus D+E):  +side(open)= {netp:+d}   -side(closed)= {netn:+d}")
cyto = "+side (OPEN gate)" if netp>netn else "-side (CLOSED gate)"
print(f"positive-inside rule -> cytoplasmic face = {cyto}")
if netp>netn:
    print("\n==> OPEN gate faces the CYTOPLASM  =>  INWARD-OPEN state")
else:
    print("\n==> OPEN gate faces EXTRACELLULAR/lumen  =>  OUTWARD-OPEN state")
print("(caveat: modeled region 67-470 only; positive-inside is a heuristic — confirm vs OPM/6C08 superposition.)")
