"""Learned-model headroom gate: does LEARNED weighting over the knowledge graph beat the uniform
neighbor-mean on KO-specific perturbation effects? Exact leave-one-out kernel ridge (hat-matrix form)
with a gene-set-sharing (Jaccard) kernel vs the uniform neighbor-mean and random baselines.
If learned > uniform-mean, a GEARS-style learned model has headroom on this knowledge graph. CPU-only."""
import json, os, sys, gzip, time
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr
WS=os.environ.get("WS","/workspace"); OUT=Path(os.environ.get("AUD","/audit"))/"perturb_leaveKOout_20261108"
t0=time.time()
D=np.load(f"{WS}/fs_long/work/czi_tcell_deltas.npz",allow_pickle=True)
delta=D["delta"].astype(np.float64); ko=D["genes"].astype(str); nko=len(ko)
Y=delta-delta.mean(0,keepdims=True)                      # KO-specific residual target
def read_gmt(p):
    op=gzip.open(p,"rt") if p.endswith(".gz") else open(p); out=[]
    for ln in op:
        q=ln.rstrip("\n").split("\t")
        if len(q)>=3: out.append(set(q[2:]))
    return out
gmt=[]
for nm in ("reactome.gmt","kegg.gmt","go_bp.gmt"):
    p=f"{WS}/fs_long/work/{nm}"
    if os.path.exists(p): gmt+=read_gmt(p)
ko_sets=[set(j for j,s in enumerate(gmt) if g in s) for g in ko]
# Jaccard kernel over gene-set membership (diag=1); count-shared for neighbor defn
K=np.eye(nko); shared=np.zeros((nko,nko),int)
for i in range(nko):
    for j in range(i+1,nko):
        inter=len(ko_sets[i]&ko_sets[j])
        if inter:
            shared[i,j]=shared[j,i]=inter
            uni=len(ko_sets[i]|ko_sets[j]); jac=inter/uni if uni else 0.0
            K[i,j]=K[j,i]=jac
TOPK=50
def topr(pred):   # mean Pearson over KOs on each KO's true top-50 residual-DE genes
    rs=[]
    for g in range(nko):
        top=np.argsort(-np.abs(Y[g]))[:TOPK]; pt=pred[g,top]; tt=Y[g,top]
        if np.std(pt)>1e-12 and np.std(tt)>1e-12: rs.append(pearsonr(pt,tt)[0])
    return float(np.mean(rs)), len(rs)
# --- uniform neighbor-mean (know) and random, LOO ---
rng=np.random.RandomState(0); pk=np.zeros_like(Y); pr=np.zeros_like(Y); has=np.zeros(nko,bool)
for g in range(nko):
    nb=np.where(shared[g]>0)[0]
    if len(nb)>0:
        has[g]=True; w=shared[g,nb].astype(float)
        pk[g]=(Y[nb]*w[:,None]).sum(0)/w.sum()
        pr[g]=Y[rng.choice(np.setdiff1d(np.arange(nko),[g]),len(nb),replace=False)].mean(0)
# --- exact LOO kernel ridge (hat-matrix), sweep lambda ---
def loo_kr(lam):
    H=K@np.linalg.inv(K+lam*np.eye(nko)); h=np.diag(H)
    Yhat=H@Y
    return (Yhat-h[:,None]*Y)/((1-h)[:,None]+1e-12)
res={"know_uniform":topr(pk), "rand":topr(pr)}
best=None
for lam in [0.1,0.3,1.0,3.0,10.0]:
    r=topr(loo_kr(lam))
    res[f"kridge_lam{lam}"]=r
    if best is None or r[0]>best[1]: best=(lam,r[0])
# restrict all to KOs with neighbors for a fair paired compare
nb_mask=has
def topr_masked(pred):
    rs=[pearsonr(pred[g,np.argsort(-np.abs(Y[g]))[:TOPK]],Y[g,np.argsort(-np.abs(Y[g]))[:TOPK]])[0]
        for g in range(nko) if nb_mask[g]]
    return float(np.mean(rs))
klr=loo_kr(best[0])
import numpy as _np
paired=_np.asarray([pearsonr(klr[g,np.argsort(-np.abs(Y[g]))[:TOPK]],Y[g,np.argsort(-np.abs(Y[g]))[:TOPK]])[0]
        - pearsonr(pk[g,np.argsort(-np.abs(Y[g]))[:TOPK]],Y[g,np.argsort(-np.abs(Y[g]))[:TOPK]])[0]
        for g in range(nko) if nb_mask[g]])
tt=float(paired.mean()/(paired.std(ddof=1)/_np.sqrt(len(paired))))
json.dump({"res":res,"best_lambda":best[0],"kridge_minus_knowuniform":{"mean":float(paired.mean()),"t":tt,"n":len(paired),"frac_pos":float((paired>0).mean())}},open(OUT/"learned_headroom.json","w"),indent=2)
print(f"KOs={nko}, sets={len(gmt)}, with-neighbor={int(has.sum())}  ({time.time()-t0:.0f}s)")
print(f"  know (uniform neighbor-mean) top-{TOPK} resid-r = {res['know_uniform'][0]:+.4f}")
print(f"  rand                                           = {res['rand'][0]:+.4f}")
for lam in [0.1,0.3,1.0,3.0,10.0]:
    print(f"  kernel-ridge lam={lam:<4}                         = {res[f'kridge_lam{lam}'][0]:+.4f}")
print(f"  BEST kernel-ridge (lam={best[0]}) vs know-uniform: Δr={paired.mean():+.4f} t={tt:+.1f} frac>0={float((paired>0).mean()):.2f} n={len(paired)}")
print("LEARNED_HEADROOM_COMPLETE")
