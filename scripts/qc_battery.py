"""Replication battery for the preprocessing-QC paper. Non-circular ground truth:
an INDEPENDENT downstream outcome (cross-validated condition classification on the CLEANED
data) defines 'over-corrected' (biology recoverable before cleaning, lost after). Test whether
the biology-conservation GATE predicts downstream failure while the batch-mixing metric does not.
Arms: bulk + real ComBat, single-cell-like + real Harmony. Confound sweep x seeds."""
import numpy as np, pandas as pd, json
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import cross_val_score
from combat.pycombat import pycombat
import harmonypy

def sep(emb, labels):
    return float(silhouette_score(emb, labels)) if len(np.unique(labels)) > 1 else 0.0
def downstream(emb, cond):                      # independent outcome: can we recover biology?
    try: return float(cross_val_score(LogisticRegression(max_iter=500), emb, cond, cv=5).mean())
    except Exception: return 0.5

def sim_bulk(confound, seed, N=80, G=500, cond_eff=1.0, batch_eff=2.0):
    rng = np.random.RandomState(seed)
    cond = np.array([0]*(N//2)+[1]*(N//2))
    batch = np.array([c if rng.rand() < 0.5+confound/2 else 1-c for c in cond])
    X = rng.normal(0,1,(G,N))
    X[0:100] += cond_eff*(2*cond-1); X[100:200] += batch_eff*(2*batch-1)
    return pd.DataFrame(X), cond, batch
def sim_sc(confound, seed, ncell=1200, G=400, cond_eff=1.2, batch_eff=2.5):
    rng = np.random.RandomState(seed)
    cond = rng.randint(0,2,ncell)                # 2 cell states
    batch = np.array([c if rng.rand() < 0.5+confound/2 else 1-c for c in cond])
    X = rng.normal(0,1,(ncell,G))
    X[:,0:80] += cond_eff*(2*cond-1)[:,None]; X[:,80:160] += batch_eff*(2*batch-1)[:,None]
    return X, cond, batch

def run(arm, confound, seed):
    if arm=="bulk_combat":
        Xdf,cond,batch = sim_bulk(confound,seed)
        emb_b = PCA(10,random_state=0).fit_transform(Xdf.T.values)
        Xc = pycombat(Xdf, list(batch)); emb_a = PCA(10,random_state=0).fit_transform(Xc.T.values)
    else:  # sc_harmony
        X,cond,batch = sim_sc(confound,seed)
        emb_b = PCA(20,random_state=0).fit_transform(X)
        meta = pd.DataFrame({"b":batch.astype(str)})
        ho = harmonypy.run_harmony(emb_b, meta, ["b"], theta=6, max_iter_harmony=20)
        Z=np.asarray(ho.Z_corr); emb_a = Z if Z.shape[0]==len(cond) else Z.T
    d_before, d_after = downstream(emb_b,cond), downstream(emb_a,cond)
    cs_b, cs_a = sep(emb_b,cond), sep(emb_a,cond)
    bs_b, bs_a = sep(emb_b,batch), sep(emb_a,batch)
    gate_metric = cs_a/ (cs_b+1e-9)                 # biology-conservation retention (the GATE)
    batch_metric = bs_b - bs_a                      # batch removed (what practice optimizes)
    overcorrected = (d_before>0.75) and (d_after<0.62)   # INDEPENDENT ground truth
    return dict(arm=arm,confound=confound,seed=seed,d_before=d_before,d_after=d_after,
                cs_b=cs_b,cs_a=cs_a,bs_b=bs_b,bs_a=bs_a,gate=gate_metric,batch=batch_metric,
                overcorrected=overcorrected)

rows=[]
for arm in ["bulk_combat","sc_harmony"]:
    seeds = range(10) if arm=="bulk_combat" else range(6)
    for cf in [0.0,0.25,0.5,0.75,0.95]:
        for s in seeds:
            try: rows.append(run(arm,cf,s))
            except Exception as e: print("ERR",arm,cf,s,e)
    print(f"[done] {arm}")
json.dump(rows, open("qc_battery_results.json","w"), indent=2)

def corr(a,b):
    a=np.array(a);b=np.array(b)
    return float(np.corrcoef(a,b)[0,1]) if a.std()>0 and b.std()>0 else float('nan')
def auc(score, label):  # does `score` separate overcorrected(True) from ok(False)? oriented
    pos=[s for s,l in zip(score,label) if l]; neg=[s for s,l in zip(score,label) if not l]
    if not pos or not neg: return float('nan')
    a=np.mean([1.0 if p>n else 0.5 if p==n else 0.0 for p in pos for n in neg]); return max(a,1-a)

print("\n================= BATTERY SUMMARY =================")
for arm in ["bulk_combat","sc_harmony"]:
    R=[r for r in rows if r["arm"]==arm]; oc=[r["overcorrected"] for r in R]
    print(f"\n--- {arm}: n={len(R)}, over-corrected(ground truth)={sum(oc)} ---")
    print(f"  corr(GATE metric, downstream)  = {corr([r['gate'] for r in R],[r['d_after'] for r in R]):+.3f}  (want HIGH: gate tracks biology)")
    print(f"  corr(BATCH metric, downstream) = {corr([r['batch'] for r in R],[r['d_after'] for r in R]):+.3f}  (want ~0/neg: batch blind to biology)")
    print(f"  GATE detects over-correction  |AUC|={auc([-r['gate'] for r in R],oc):.3f}")
    print(f"  BATCH detects over-correction |AUC|={auc([r['batch'] for r in R],oc):.3f}")
    # "standard practice": accept whenever batch was removed (batch_metric>0.3). false-accept of over-corrected:
    acc = [r for r in R if r['batch']>0.3]
    fa = sum(1 for r in acc if r['overcorrected'])/max(1,len(acc))
    gate_fa = sum(1 for r in R if r['gate']>0.7 and r['overcorrected'])/max(1,sum(1 for r in R if r['gate']>0.7))
    print(f"  STANDARD-PRACTICE false-accept of over-corrected = {fa:.2f}  vs  GATE false-accept = {gate_fa:.2f}")
print("\nwrote qc_battery_results.json")
