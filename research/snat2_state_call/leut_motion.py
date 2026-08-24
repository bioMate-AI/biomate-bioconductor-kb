import numpy as np, mdtraj as md
inw = md.load("3TT3.pdb"); out = md.load("3TT1.pdb")
# take chain A protein CA only, common residue set
def caidx(t):
    top=t.topology
    return {a.residue.resSeq:a.index for a in top.atoms if a.name=="CA" and a.residue.chain.index==0 and a.residue.is_protein}
ci, co = caidx(inw), caidx(out)
common = sorted(set(ci)&set(co))
print(f"3TT3(inward) CAs={len(ci)}  3TT1(outward) CAs={len(co)}  common residues={len(common)}")
if len(common) < 30:
    print("too few common residues (numbering/chains differ) — inspecting..."); 
    print("3TT3 resSeq range:", min(ci), max(ci), " 3TT1:", min(co), max(co)); raise SystemExit
Xi = inw.xyz[0][[ci[r] for r in common]]*10
Xo = out.xyz[0][[co[r] for r in common]]*10
# global Kabsch superpose inward onto outward, per-residue displacement
def kabsch(P,Q):
    Pc,Qc=P-P.mean(0),Q-Q.mean(0)
    V,_,Wt=np.linalg.svd(Pc.T@Qc); d=np.sign(np.linalg.det(V@Wt)); D=np.diag([1,1,d]); R=V@D@Wt
    return Pc@R+Q.mean(0)
Xi_al=kabsch(Xi,Xo)
disp=np.linalg.norm(Xi_al-Xo,axis=1)
print(f"global CA RMSD inward vs outward = {np.sqrt((disp**2).mean()):.2f} A")
print(f"per-residue displacement: median={np.median(disp):.1f}  90th pct={np.percentile(disp,90):.1f}  max={disp.max():.1f} A")
# which residues move most (bundle vs scaffold signature of rocking-bundle)
order=np.argsort(disp)[::-1][:15]
print("top-moving residues (resSeq:displacement A):", ", ".join(f"{common[i]}:{disp[i]:.0f}" for i in order))
mob=[common[i] for i in range(len(common)) if disp[i]>disp.mean()+disp.std()]
print(f"# residues moving >mean+1sd = {len(mob)} of {len(common)} (localized motion => two-domain/rocking signature)")
