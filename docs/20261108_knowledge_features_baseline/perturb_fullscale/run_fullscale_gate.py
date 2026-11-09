"""Full-scale perturbation knowledge-transfer gate (33,983-contrast DE_stats, ~11k KOs/context).
Reads the h5ad DIRECTLY with h5py (no loader, no scipy — this python's torch is broken and poisons
scipy's array-api probe). Pure h5py + numpy.

Per culture_condition (Rest/Stim8hr/Stim48hr) separately:
  residual = per-context-centered KO effect (removes context generic response)
  know : shared-set-count-weighted neighbor-mean over GO/KEGG/Reactome set-sharing  (external knowledge)
  rand : size-matched random neighbor-mean (content control)
  kernel-ridge (LOO hat-matrix, Jaccard kernel, capped) : learned weighting (headroom test)
Metric: numpy Pearson on each KO's top-50 residual-DE genes.
Decisive: know>rand (signal at scale) AND kernel-ridge > neighbor-mean with POSITIVE absolute r.
"""
import json, os, sys, gzip, time
from pathlib import Path
import numpy as np, h5py
WS=os.environ.get("WS","/workspace"); H5=os.environ.get("H5", f"{WS}/perturb_full/GWCD4i.DE_stats.h5ad")
OUT=Path(os.environ.get("AUD","/audit"))/"perturb_fullscale_20261108"; OUT.mkdir(exist_ok=True)
t0=time.time()

def pear(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float); a=a-a.mean(); b=b-b.mean()
    d=np.sqrt((a*a).sum()*(b*b).sum()); return float((a*b).sum()/d) if d>1e-12 else 0.0
def topr(pred,Yr,idx,TOPK=50):
    rs=[]
    for i in idx:
        top=np.argsort(-np.abs(Yr[i]))[:TOPK]; pt=pred[i,top]; tt=Yr[i,top]
        if pt.std()>1e-9 and tt.std()>1e-9: rs.append(pear(pt,tt))
    return np.asarray(rs)
def read_cat(g):
    cats=g["categories"][:]; codes=g["codes"][:]
    cats=np.array([x.decode() if isinstance(x,(bytes,bytearray)) else str(x) for x in cats])
    return np.where(codes<0,"NA",cats[np.clip(codes,0,len(cats)-1)])

f=h5py.File(H5,"r")
Y=f["layers"]["log_fc"][:].astype(np.float32)          # [33983, 10282]
ko=read_cat(f["obs"]["target_contrast_gene_name"]).astype(str)
cond=read_cat(f["obs"]["culture_condition"]).astype(str)
ont=f["obs"]["ontarget_significant"][:].astype(bool); lowg=f["obs"]["low_target_gex"][:].astype(bool)
mask=ont & (~lowg)
f.close()
print(f"loaded Y={Y.shape} KOunique={len(set(ko))} conds={sorted(set(cond))} QC-kept={int(mask.sum())}/{len(ko)} ({time.time()-t0:.0f}s)",flush=True)

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
set_of={}
for j,s in enumerate(gmt):
    for g in s: set_of.setdefault(g,[]).append(j)
print(f"gene-sets={len(gmt)}",flush=True)

CAP=5000; summary={}; rng=np.random.RandomState(0)
for c in sorted(set(cond)):
    sel=np.where(mask&(cond==c))[0]
    seen={}; rows=[]
    for r in sel:
        if ko[r] not in seen: seen[ko[r]]=1; rows.append(r)
    rows=np.asarray(rows); kos=ko[rows]; n=len(rows)
    Yc=Y[rows].astype(np.float32); Yc-=Yc.mean(0,keepdims=True)
    cnt={}
    for g in kos:
        for j in set_of.get(g,[]): cnt[j]=cnt.get(j,0)+1
    keep={j:k for k,j in enumerate(j for j,v in cnt.items() if v>=2)}
    Mb=np.zeros((n,max(1,len(keep))),np.float32)
    for a,g in enumerate(kos):
        for j in set_of.get(g,[]):
            k=keep.get(j)
            if k is not None: Mb[a,k]=1.0
    S=Mb@Mb.T; np.fill_diagonal(S,0.0)
    deg=np.array([len(set_of.get(g,[])) for g in kos],np.float32)
    pk=np.zeros_like(Yc); pr=np.zeros_like(Yc); has=np.zeros(n,bool)
    for g in range(n):
        nb=np.where(S[g]>0)[0]
        if len(nb)>0:
            has[g]=True; w=S[g,nb]
            pk[g]=(Yc[nb]*w[:,None]).sum(0)/w.sum()
            pr[g]=Yc[rng.choice(np.setdiff1d(np.arange(n),[g]),len(nb),replace=False)].mean(0)
    idx=np.where(has)[0]
    rk=topr(pk,Yc,idx); rr=topr(pr,Yc,idx)
    dkr=rk-rr; tkr=float(dkr.mean()/(dkr.std(ddof=1)/np.sqrt(len(dkr)))) if len(dkr)>1 and dkr.std()>0 else float("nan")
    cap=np.sort(rng.choice(idx,size=min(CAP,len(idx)),replace=False))
    Sc=S[np.ix_(cap,cap)].astype(np.float64); dc=deg[cap].astype(np.float64)
    with np.errstate(divide="ignore",invalid="ignore"):
        J=Sc/(dc[:,None]+dc[None,:]-Sc); J[~np.isfinite(J)]=0.0
    np.fill_diagonal(J,1.0); Ycap=Yc[cap]
    best=None
    for lam in (0.3,1.0,3.0):
        Hh=J@np.linalg.inv(J+lam*np.eye(len(cap))); h=np.diag(Hh)
        loo=(Hh@Ycap - h[:,None]*Ycap)/((1-h)[:,None]+1e-12)
        r=topr(loo,Ycap,np.arange(len(cap)))
        if best is None or r.mean()>best[1]: best=(lam,float(r.mean()),r)
    rk_cap=topr(pk[cap],Ycap,np.arange(len(cap)))
    dp=best[2]-rk_cap; tp=float(dp.mean()/(dp.std(ddof=1)/np.sqrt(len(dp)))) if len(dp)>1 and dp.std()>0 else float("nan")
    summary[c]=dict(n_ko=int(n),n_with_nb=int(has.sum()),cap=int(len(cap)),
        know_r=float(rk.mean()),rand_r=float(rr.mean()),know_minus_rand_t=tkr,
        kridge_lam=best[0],kridge_r=best[1],kridge_minus_knowmean_mean=float(dp.mean()),
        kridge_minus_knowmean_t=tp,kridge_frac_pos=float((dp>0).mean()))
    print(json.dumps({c:summary[c]}),flush=True)
json.dump(summary,open(OUT/"results.json","w"),indent=2)
print(f"\n=== FULL-SCALE gate (per context) time {time.time()-t0:.0f}s ===",flush=True)
for c,s in summary.items():
    print(f" {c:9s} n={s['n_ko']:5d} | know={s['know_r']:+.4f} rand={s['rand_r']:+.4f} (know-rand t={s['know_minus_rand_t']:+.1f}) | "
          f"kridge={s['kridge_r']:+.4f} (vs nbr-mean Δ={s['kridge_minus_knowmean_mean']:+.4f} t={s['kridge_minus_knowmean_t']:+.1f} pos={s['kridge_frac_pos']:.2f})",flush=True)
print("FULLSCALE_GATE_COMPLETE",flush=True)
