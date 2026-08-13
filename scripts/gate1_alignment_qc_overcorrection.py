"""Gate-1: do integration-QC metrics RELIABLY separate over-correction from correct
integration on data where we KNOW the answer? Controlled simulation (best case).

Sweep t: 0..0.5 removes batch (under->correct), 0.5..1 also collapses cell types
(correct->over-corrected). Known truth at every t. Question: does a batch-only metric
get FOOLED by over-correction while the bio-conservation metric catches it — and is the
combined verdict a RELIABLE separator across seeds?
"""
import numpy as np

def knn_idx(X, k):
    # pairwise sq dists, return k nearest (excluding self)
    sq = ((X[:, None, :] - X[None, :, :]) ** 2).sum(-1)
    np.fill_diagonal(sq, np.inf)
    return np.argsort(sq, axis=1)[:, :k]

def lisi(labels, nn):
    # mean inverse-Simpson of `labels` among k-NN. batch: high=well mixed; celltype: low=pure
    labels = np.asarray(labels); out = []
    for i in range(nn.shape[0]):
        _, cnt = np.unique(labels[nn[i]], return_counts=True)
        p = cnt / cnt.sum()
        out.append(1.0 / (p @ p))
    return float(np.mean(out))

def kbet_accept(batch, nn, tol=0.15):
    # frac of cells whose local batch composition ~ global (well-mixed test)
    batch = np.asarray(batch); B = np.unique(batch)
    g = np.array([(batch == b).mean() for b in B]); ok = 0
    for i in range(nn.shape[0]):
        loc = np.array([(batch[nn[i]] == b).mean() for b in B])
        if np.abs(loc - g).max() <= tol: ok += 1
    return ok / nn.shape[0]

def kmeans(X, K, iters=50, inits=5, rng=None):
    rng = rng or np.random.RandomState(0); best=None
    for _ in range(inits):
        c = X[rng.choice(len(X), K, replace=False)]
        for _ in range(iters):
            d = ((X[:,None,:]-c[None,:,:])**2).sum(-1); lab = d.argmin(1)
            nc = np.array([X[lab==j].mean(0) if (lab==j).any() else c[j] for j in range(K)])
            if np.allclose(nc,c): c=nc; break
            c=nc
        inertia = ((X-c[lab])**2).sum()
        if best is None or inertia<best[0]: best=(inertia,lab)
    return best[1]

def ari(a, b):
    a=np.asarray(a); b=np.asarray(b); ua=np.unique(a); ub=np.unique(b)
    tab=np.array([[((a==i)&(b==j)).sum() for j in ub] for i in ua])
    comb=lambda n: n*(n-1)/2
    idx=comb(tab).sum(); ai=comb(tab.sum(1)).sum(); bj=comb(tab.sum(0)).sum()
    n=len(a); exp=ai*bj/comb(n); mx=(ai+bj)/2
    return 0.0 if mx==exp else (idx-exp)/(mx-exp)

def simulate_and_score(seed, N=600, K=4, B=2, D=10, sep=3.0, batch_str=2.5, sigma=1.0,
                       k=30, ts=None, confound=0.0):
    rng=np.random.RandomState(seed)
    mu = rng.randn(K,D); mu = mu/np.linalg.norm(mu,axis=1,keepdims=True)*sep
    beta = rng.randn(B,D); beta = beta/np.linalg.norm(beta,axis=1,keepdims=True)*batch_str
    ct = rng.randint(0,K,N)
    # batch assignment: independent (confound=0) or partially confounded with cell type
    pb = np.full((K,B), 1.0/B)
    if confound>0:
        for kk in range(K):
            fav = kk % B; pb[kk,:] = (1-confound)/B; pb[kk,fav]+=confound
    batch = np.array([rng.choice(B, p=pb[ct[i]]) for i in range(N)])
    noise = rng.randn(N,D)*sigma
    rows=[]
    for t in ts:
        c = min(1.0, 2*t)          # batch removal fraction
        o = max(0.0, 2*t-1)        # over-correction: shrink cell-type separation
        X = (1-o)*mu[ct] + noise + (1-c)*beta[batch]
        nn = knn_idx(X,k)
        iL = lisi(batch,nn); cL = lisi(ct,nn); kb = kbet_accept(batch,nn)
        lab = kmeans(X,K,rng=rng); ar = ari(ct,lab)
        rows.append(dict(t=t,iLISI=iL,cLISI=cL,kBET=kb,ARI=ar))
    return rows

if __name__=="__main__":
    ts=[0.0,0.25,0.5,0.75,1.0]; seeds=range(20)
    for confound,tag in [(0.0,"SEPARABLE batch"),(0.6,"CONFOUNDED batch (60%)")]:
        agg={t:{m:[] for m in ("iLISI","cLISI","kBET","ARI")} for t in ts}
        for s in seeds:
            for r in simulate_and_score(s, ts=ts, confound=confound):
                for m in ("iLISI","cLISI","kBET","ARI"): agg[r['t']][m].append(r[m])
        print(f"\n===== {tag} — mean±sd over {len(list(seeds))} seeds (iLISI↑=mixed[1..2], cLISI↓=pure[1..4], kBET↑=mixed, ARI↑=bio kept) =====")
        print(f"{'t':>5} {'regime':>14} {'iLISI':>12} {'cLISI':>12} {'kBET':>12} {'ARI':>12}")
        regime={0.0:'under-corr',0.25:'under->ok',0.5:'CORRECT',0.75:'ok->over',1.0:'OVER-corr'}
        for t in ts:
            f=lambda m:(np.mean(agg[t][m]),np.std(agg[t][m]))
            print(f"{t:>5} {regime[t]:>14} "+" ".join(f"{f(m)[0]:6.3f}±{f(m)[1]:4.2f}" for m in ("iLISI","cLISI","kBET","ARI")))
        # THE test: can a metric separate CORRECT (t=.5) from OVER-corrected (t=1)?
        for m,better in (("kBET","batch-only"),("iLISI","batch-only"),("ARI","bio"),("cLISI","bio")):
            corr=np.array(agg[0.5][m]); over=np.array(agg[1.0][m])
            # rank-AUC: how separable are the two regimes on this metric
            auc=np.mean([1.0 if c>o else (0.5 if c==o else 0.0) for c in corr for o in over])
            auc=max(auc,1-auc)
            print(f"  separate CORRECT vs OVER on {m:6s} ({better:10s}): |AUC|={auc:.3f}"
                  + ("   <-- FOOLED (can't tell)" if auc<0.75 else "   <-- discriminates"))
