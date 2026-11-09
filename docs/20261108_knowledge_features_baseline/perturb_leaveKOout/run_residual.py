import json, time, os, sys, gzip
from pathlib import Path
import numpy as np
from scipy.stats import pearsonr
WS=os.environ.get("WS","/workspace"); OUT=Path(os.environ.get("AUD","/audit"))/"perturb_leaveKOout_20261108"
D=np.load(f"{WS}/fs_long/work/czi_tcell_deltas.npz",allow_pickle=True)
delta=D["delta"].astype(np.float32); ko=D["genes"].astype(str); nko=len(ko)
# CENTER: remove the across-KO generic response -> KO-specific residual
resid = delta - delta.mean(0, keepdims=True)
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
shared=np.zeros((nko,nko),np.int32)
for i in range(nko):
    for j in range(i+1,nko):
        c=len(ko_sets[i]&ko_sets[j])
        if c: shared[i,j]=shared[j,i]=c
TOPK=50; rng=np.random.RandomState(0); rows=[]
for g in range(nko):
    tr=np.setdiff1d(np.arange(nko),[g]); true=resid[g]
    top=np.argsort(-np.abs(true))[:TOPK]; tt=true[top]
    nb=np.where(shared[g]>0)[0]
    rec={"n_nb":int(len(nb))}
    if len(nb)>0:
        w=shared[g,nb].astype(np.float32)
        pk=(resid[nb]*w[:,None]).sum(0)/w.sum()
        ridx=rng.choice(tr,size=len(nb),replace=False); pr=resid[ridx].mean(0)
        for m,p in (("know",pk),("rand",pr)):
            pt=p[top]
            rec[f"{m}_r"]=float(pearsonr(pt,tt)[0]) if np.std(pt)>1e-9 else 0.0
    rows.append(rec)
def paired(a,b):
    d=np.asarray([r[a]-r[b] for r in rows if a in r and b in r])
    t=float(d.mean()/(d.std(ddof=1)/np.sqrt(len(d)))) if len(d)>1 and d.std()>0 else float("nan")
    return dict(mean=float(d.mean()),t=t,n=len(d),frac_pos=float((d>0).mean()))
def agg(k):
    v=np.asarray([r[k] for r in rows if k in r]); return float(v.mean()),float(v.std(ddof=1)),len(v)
know=agg("know_r"); rand=agg("rand_r"); pv=paired("know_r","rand_r")
print(f"RESIDUAL (KO-specific) Pearson on true top-{TOPK} residual-DE genes, n={know[2]}:")
print(f"  know={know[0]:+.4f}±{know[1]:.3f}   rand={rand[0]:+.4f}±{rand[1]:.3f}")
print(f"  PAIRED know-rand: Δr={pv['mean']:+.4f} t={pv['t']:+.1f} frac>0={pv['frac_pos']:.2f} n={pv['n']}")
json.dump(dict(know=know,rand=rand,paired_know_vs_rand=pv),open(OUT/"residual_results.json","w"),indent=2)
print("RESID_COMPLETE")
