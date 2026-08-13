"""Gate-2 confounded: real pancreas cells, batch made CORRELATED with biology (90/10)."""
import numpy as np, anndata, harmonypy, pandas as pd, collections
from scipy import sparse
from sklearn.decomposition import PCA
from sklearn.neighbors import NearestNeighbors
from sklearn.cluster import KMeans

def lisi(labels,nn):
    labels=np.asarray(labels); o=np.empty(nn.shape[0])
    for i in range(nn.shape[0]):
        _,c=np.unique(labels[nn[i]],return_counts=True); p=c/c.sum(); o[i]=1.0/(p@p)
    return float(o.mean())
def kbet_accept(batch,nn,tol=0.15):
    batch=np.asarray(batch); B=np.unique(batch); g=np.array([(batch==b).mean() for b in B]); ok=0
    for i in range(nn.shape[0]):
        loc=np.array([(batch[nn[i]]==b).mean() for b in B])
        if np.abs(loc-g).max()<=tol: ok+=1
    return ok/nn.shape[0]
def ari(a,b):
    a=np.asarray(a);b=np.asarray(b);ua=np.unique(a);ub=np.unique(b)
    t=np.array([[((a==i)&(b==j)).sum() for j in ub] for i in ua],float)
    comb=lambda n:n*(n-1)/2; idx=comb(t).sum();ai=comb(t.sum(1)).sum();bj=comb(t.sum(0)).sum()
    n=len(a);exp=ai*bj/comb(n);mx=(ai+bj)/2
    return 0.0 if mx==exp else float((idx-exp)/(mx-exp))
def score(emb,batch,ct,k=30,sub=4000,seed=0):
    rng=np.random.RandomState(seed); idx=np.arange(emb.shape[0])
    if emb.shape[0]>sub: idx=rng.choice(idx,sub,replace=False)
    e=emb[idx]; b=np.asarray(batch)[idx]; c=np.asarray(ct)[idx]
    nn=NearestNeighbors(n_neighbors=k+1).fit(e).kneighbors(e,return_distance=False)[:,1:]
    lab=KMeans(n_clusters=len(np.unique(c)),n_init=10,random_state=0).fit_predict(e)
    return dict(iLISI=lisi(b,nn),cLISI=lisi(c,nn),kBET=kbet_accept(b,nn),ARI=ari(c,lab))

ad=anndata.read_h5ad("pancreas.h5ad")
tech=ad.obs["tech"].astype(str).values; ct=ad.obs["celltype"].astype(str).values
b1,b2="inDrop1","smartseq2"; t1,t2="alpha","beta"
rng=np.random.RandomState(0); keep=[]
for i in range(len(ct)):
    if ct[i] not in (t1,t2) or tech[i] not in (b1,b2): continue
    p=0.9 if ((tech[i]==b1 and ct[i]==t1) or (tech[i]==b2 and ct[i]==t2)) else 0.1
    if rng.rand()<p: keep.append(i)
keep=np.array(keep); sub=ad[keep].copy()
tb=sub.obs["tech"].astype(str).values; tc=sub.obs["celltype"].astype(str).values
print("[confound] n=",len(keep)," tech×type:",dict(collections.Counter(zip(tb,tc))))
X=sub.X; X=X.tocsr() if sparse.issparse(X) else np.asarray(X)
rs=np.asarray(X.sum(1)).ravel(); rs[rs==0]=1
if sparse.issparse(X): X=X.multiply(1e4/rs[:,None]).tocsr(); X.data=np.log1p(X.data); Xd=X.toarray()
else: Xd=np.log1p(X*(1e4/rs[:,None]))
var=Xd.var(0); hvg=np.argsort(var)[::-1][:2000]; Xd=Xd[:,hvg]
mu=Xd.mean(0);sd=Xd.std(0);sd[sd==0]=1; Xs=np.clip((Xd-mu)/sd,-10,10)
pca=PCA(n_components=30,random_state=0).fit_transform(Xs); n=pca.shape[0]
meta=pd.DataFrame({"tech":tb})
rows=[("uncorrected",None,score(pca,tb,tc))]
for th in [0,1,4,16,64]:
    ho=harmonypy.run_harmony(pca,meta,["tech"],theta=th,max_iter_harmony=20)
    Z=np.asarray(ho.Z_corr); emb=Z if Z.shape[0]==n else Z.T
    rows.append((f"theta_{th}",th,score(emb,tb,tc)))
best=max(r[2]["ARI"] for r in rows)
print(f"\n{'stage':14}{'iLISI↑':>8}{'cLISI↓':>8}{'kBET↑':>8}{'ARI↑':>8}{'bio_ok':>8}")
for s,th,m in rows:
    print(f"{s:14}{m['iLISI']:8.3f}{m['cLISI']:8.3f}{m['kBET']:8.3f}{m['ARI']:8.3f}{str(m['ARI']>=0.9*best):>8}")
over=[s for s,th,m in rows if th and m['iLISI']>=1.6 and m['ARI']<0.9*best]
print(f"\nOVER-CORRECTED (batch-mixed, biology erased): {over or 'none'}")
print("→ batch-only metric PASSES these; biology panel FLAGS them." if over else "→ none in range.")
