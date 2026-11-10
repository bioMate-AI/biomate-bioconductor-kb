"""AUDIT FIX: re-measure cell-type annotation with (1) PROPER convergence on the easy split and
(2) group-disjoint leave-one-TISSUE-out. All 4 reps {raw, pca50, knowledge, fm_z} on the same cells.
Reuses the agent's saved embeddings (xs_stim.npy, z_fm_stim.npy) so fm_z needs no envpin2."""
import os,sys,numpy as np,anndata as ad,warnings,json
warnings.filterwarnings("ignore")
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import f1_score
WS="/home/yzhang/immune_fm_spark"; WB=f"{WS}/ws_bench"
sys.path.insert(0,f"{WS}/code_20261004"); import knowledge_channel as K; K._s3=lambda s,d: os.path.isfile(d)
xs=np.load(f"{WB}/xs_stim.npy"); zfm=np.load(f"{WB}/z_fm_stim.npy")
A=ad.read_h5ad(f"{WS}/step0/GSE261278_D534.paired.h5ad")
ct=A.obs["cell_type"].astype(str).to_numpy(); tis=A.obs["tissue"].astype(str).to_numpy()
classes=sorted(set(ct)); y=np.array([classes.index(c) for c in ct])
sc=np.load(f"{WS}/eval_repair_20261107/input_artifacts/stream_hvg_scaler.npz"); hvg=list(sc["hvg_names"].astype(str))
bases=K.fit_bases(hvg,f"{WS}/fs_long/work"); know=K.transform(xs,bases)
pca=PCA(50,random_state=0).fit_transform(StandardScaler().fit_transform(xs))
REPS={"raw":xs,"pca50":pca,"know":know,"fm_z":zfm}
def probe(Xtr,ytr,Xte,yte,mi=2000,tol=1e-3):
    s=StandardScaler().fit(Xtr); a=s.transform(Xtr); b=s.transform(Xte)
    clf=LogisticRegression(C=1.0,max_iter=mi,solver="saga",tol=tol,n_jobs=-1).fit(a,ytr)
    return f1_score(yte,clf.predict(b),average="macro"), int(np.max(clf.n_iter_))
# subsample for tractable PROPER-convergence compute; same cells for all reps
rng=np.random.RandomState(0); idx=rng.choice(len(y),8000,replace=False)
print(f"cells={len(idx)} classes={len(classes)} | agent(loose,random): raw=0.490 fm_z=0.536",flush=True)
# (1) easy random split, PROPER convergence
print("\n=== (1) random split, PROPER convergence (saga 2000, tol1e-3) ===",flush=True)
r1={}
for r,X in REPS.items():
    Xi=X[idx]; skf=StratifiedKFold(3,shuffle=True,random_state=0); fs=[];it=[]
    for tr,te in skf.split(Xi,y[idx]):
        f,i=probe(Xi[tr],y[idx][tr],Xi[te],y[idx][te]); fs.append(f);it.append(i)
    r1[r]=float(np.mean(fs)); print(f"  {r:6s} macroF1={np.mean(fs):.4f}  iters={it} capped={[i>=2000 for i in it]}",flush=True)
# (2) leave-one-tissue-out (group-disjoint); score only classes present in held-out tissue
print("\n=== (2) leave-one-TISSUE-out (group-disjoint generalization) ===",flush=True)
r2={r:[] for r in REPS}
for T in sorted(set(tis)):
    te=np.where(tis==T)[0]; tr=np.where(tis!=T)[0]
    if len(set(y[te]))<2: continue
    for r,X in REPS.items():
        f,_=probe(X[tr],y[tr],X[te],y[te]); r2[r].append(f)
    print(f"  held-out {T:16s} "+" ".join(f"{r}={r2[r][-1]:.3f}" for r in REPS),flush=True)
print("\n  mean over tissues: "+" ".join(f"{r}={np.mean(v):.4f}" for r,v in r2.items()),flush=True)
out=dict(random_proper={r:r1[r] for r in REPS}, tissue_holdout={r:float(np.mean(v)) for r,v in r2.items()})
json.dump(out,open(f"{WB}/annot_fix_results.json","w"),indent=2)
print("\nVERDICT raw-vs-fmz: random_proper Δ(fm_z-raw)=%+.4f | tissue_holdout Δ=%+.4f"%(r1["fm_z"]-r1["raw"], np.mean(r2["fm_z"])-np.mean(r2["raw"])),flush=True)
print("ANNOT_FIX_COMPLETE",flush=True)
