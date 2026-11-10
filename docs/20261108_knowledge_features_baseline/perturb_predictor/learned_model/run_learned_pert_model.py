"""Immune-LLM model work: does a LEARNED map from a KO's knowledge-graph features beat the
neighbor-mean baseline on unseen-perturbation prediction? (the GEARS direction, tested cleanly.)

Per context (full DE_stats, ~6-7k KOs): KO feature = random projection of its GO/KEGG/Reactome gene-set
membership (a fixed, non-leaky 'which pathways is this KO in' embedding). Learn a ridge map
features->residual-effect, leave-KO-out (5-fold), predict held-out KO's effect. Compare to the
shared-set-weighted neighbor-mean (bar=+0.078 Rest) and random. Metric: top-50 residual-DE Pearson.
Pure numpy (ridge closed-form, numpy Pearson) -- no scipy (Spark torch is broken). CPU.
"""
import os,sys,gzip,json,time
import numpy as np,h5py
WS=os.environ.get("WS","/workspace"); H5=f"{WS}/perturb_full/GWCD4i.DE_stats.h5ad"
OUT=f"{WS}/ws_pertmodel"; os.makedirs(OUT,exist_ok=True); t0=time.time()
def pear(a,b):
    a=a-a.mean(); b=b-b.mean(); d=np.sqrt((a*a).sum()*(b*b).sum()); return float((a*b).sum()/d) if d>1e-12 else 0.0
def topr(P,Y,idx,K=50):
    return np.array([pear(P[i,o],Y[i,o]) for i in idx for o in [np.argsort(-np.abs(Y[i]))[:K]]])
def read_cat(g):
    c=g["categories"][:]; k=g["codes"][:]; c=np.array([x.decode() if isinstance(x,(bytes,bytearray)) else str(x) for x in c])
    return np.where(k<0,"NA",c[np.clip(k,0,len(c)-1)])
f=h5py.File(H5,"r"); Y=f["layers"]["log_fc"][:].astype(np.float32)
ko=read_cat(f["obs"]["target_contrast_gene_name"]).astype(str); cond=read_cat(f["obs"]["culture_condition"]).astype(str)
mask=f["obs"]["ontarget_significant"][:].astype(bool)&(~f["obs"]["low_target_gex"][:].astype(bool)); f.close()
gmt=[]
for nm in ("reactome.gmt","kegg.gmt","go_bp.gmt"):
    p=f"{WS}/fs_long/work/{nm}"
    if os.path.exists(p):
        op=open(p)
        for ln in op:
            q=ln.rstrip("\n").split("\t")
            if len(q)>=3: gmt.append(set(q[2:]))
set_of={}
for j,s in enumerate(gmt):
    for g in s: set_of.setdefault(g,[]).append(j)
RP_DIM=256; rpR=np.random.RandomState(1).randn(len(gmt),RP_DIM).astype(np.float32)/np.sqrt(RP_DIM)
def ridge_loo(X,Yr,lam,folds=5):
    n=len(X); idx=np.random.RandomState(0).permutation(n); P=np.zeros_like(Yr)
    for k in range(folds):
        te=np.sort(idx[k::folds]); tr=np.setdiff1d(np.arange(n),te)
        A=X[tr]; W=np.linalg.solve(A.T@A+lam*np.eye(X.shape[1]), A.T@Yr[tr]); P[te]=X[te]@W
    return P
summary={}
for c in ["Rest","Stim8hr","Stim48hr"]:
    sel=np.where(mask&(cond==c))[0]; seen={}; rows=[]
    for r in sel:
        if ko[r] not in seen: seen[ko[r]]=1; rows.append(r)
    rows=np.array(rows); kos=ko[rows]; n=len(rows)
    Yc=Y[rows].astype(np.float32); Yc-=Yc.mean(0,keepdims=True)
    # KO knowledge feature = random projection of gene-set membership (which pathways the KO is in)
    Xko=np.zeros((n,RP_DIM),np.float32)
    for a,g in enumerate(kos):
        js=set_of.get(g,[])
        if js: Xko[a]=rpR[js].sum(0)
    Xko=(Xko-Xko.mean(0))/(Xko.std(0)+1e-6)
    # neighbor-mean baseline (shared-set weighted), LOO
    cnt={}
    for g in kos:
        for j in set_of.get(g,[]): cnt[j]=cnt.get(j,0)+1
    keep={j:i for i,j in enumerate(j for j,v in cnt.items() if v>=2)}
    Mb=np.zeros((n,max(1,len(keep))),np.float32)
    for a,g in enumerate(kos):
        for j in set_of.get(g,[]):
            kk=keep.get(j)
            if kk is not None: Mb[a,kk]=1.0
    S=Mb@Mb.T; np.fill_diagonal(S,0.0)
    pk=np.zeros_like(Yc); has=np.zeros(n,bool); rng=np.random.RandomState(0); pr=np.zeros_like(Yc)
    for g in range(n):
        nb=np.where(S[g]>0)[0]
        if len(nb)>0:
            has[g]=True; w=S[g,nb]; pk[g]=(Yc[nb]*w[:,None]).sum(0)/w.sum()
            pr[g]=Yc[rng.choice(np.setdiff1d(np.arange(n),[g]),len(nb),replace=False)].mean(0)
    idx=np.where(has)[0]
    # learned ridge from KO features -> residual effect (pick best lam)
    best=None
    for lam in (1.0,10.0,100.0):
        P=ridge_loo(Xko,Yc,lam); r=topr(P,Yc,idx).mean()
        if best is None or r>best[1]: best=(lam,r,P)
    rk=topr(pk,Yc,idx).mean(); rr=topr(pr,Yc,idx).mean()
    # paired learned vs neighbor-mean
    dl=topr(best[2],Yc,idx)-topr(pk,Yc,idx); t=float(dl.mean()/(dl.std(ddof=1)/np.sqrt(len(dl)))) if dl.std()>0 else 0.0
    summary[c]=dict(n=int(n),neighbor_mean=float(rk),random=float(rr),learned_ridge=float(best[1]),
                    best_lam=best[0],learned_minus_neighbor_t=t,learned_minus_neighbor_mean=float(dl.mean()))
    print(json.dumps({c:summary[c]}),flush=True)
json.dump(summary,open(f"{OUT}/results.json","w"),indent=2)
print(f"\n=== learned KO-feature model vs neighbor-mean (top-50 residual-DE Pearson) t={time.time()-t0:.0f}s ===",flush=True)
for c,s in summary.items():
    print(f" {c:9s} neighbor_mean={s['neighbor_mean']:+.4f}  learned_ridge={s['learned_ridge']:+.4f}  random={s['random']:+.4f}  (learned-neighbor Δ={s['learned_minus_neighbor_mean']:+.4f} t={s['learned_minus_neighbor_t']:+.1f})",flush=True)
print("LEARNED_PERT_MODEL_COMPLETE",flush=True)
