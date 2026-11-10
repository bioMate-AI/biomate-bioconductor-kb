"""Model work: an ADAPTIVE stim classifier that is best across the FULL label curve.
raw wins at abundant labels, knowledge wins when scarce (crossover ~250 cells). Can a model that
SELECTS the representation per label-budget (via inner validation) beat both raw-always and
knowledge-always at EVERY budget? If yes -> the model is best on this immune task in every regime.

Reps: raw (corpus-scaled HVG), know (pathway/TF channel), rawknow (concat). Adaptive: inner-validation
(stratified holdout of the budget) picks the rep with best inner AUPRC, then refit on full budget ->
predict the held-out cell-type fold. Fixed C=0.01 (no C-confound). Metric: pooled OOF AUPRC per budget,
mean over seeds. Pure numpy/sklearn, CPU. Reuses saved xs_stim.npy."""
import os,sys,json,warnings,numpy as np
warnings.filterwarnings("ignore")
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score
import anndata as ad
WS="/home/yzhang/immune_fm_spark"; AUD=f"{WS}/eval_repair_20261107"
sys.path.insert(0,f"{WS}/code_20261004"); import knowledge_channel as K; K._s3=lambda s,d: os.path.isfile(d)
xs=np.load(f"{WS}/ws_bench/xs_stim.npy")
sc=np.load(f"{AUD}/input_artifacts/stream_hvg_scaler.npz"); hvg=list(sc["hvg_names"].astype(str))
bases=K.fit_bases(hvg,f"{WS}/fs_long/work"); Kf=K.transform(xs,bases)
A=ad.read_h5ad(f"{WS}/step0/GSE261278_D534.paired.h5ad")
y=(A.obs["stim"].astype(str).to_numpy()!="unstimulated").astype(int)
REPS={"raw":xs,"know":Kf,"rawknow":np.concatenate([xs,Kf],1)}
splits=np.load(f"{AUD}/normalization_20261108/split_indices.npz")
FRACS=[1.0,0.5,0.25,0.125,0.06]; C=0.01; MINPOS=4
def fit(rep_X,tr,te):
    s=StandardScaler().fit(rep_X[tr]); a=s.transform(rep_X[tr]); b=s.transform(rep_X[te])
    return LogisticRegression(C=C,max_iter=5000,tol=1e-6,class_weight="balanced",solver="lbfgs").fit(a,y[tr]).predict_proba(b)[:,1]
def strat(sub,frac,rng):
    pos=sub[y[sub]==1]; neg=sub[y[sub]==0]
    np_=min(max(MINPOS,int(round(len(pos)*frac))),len(pos)); nn=min(max(MINPOS,int(round(len(neg)*frac))),len(neg))
    return np.concatenate([rng.choice(pos,np_,False),rng.choice(neg,nn,False)])
rows={}
for frac in FRACS:
    preds={m:np.full(len(y),np.nan) for m in ["raw","know","adaptive"]}; nb=[]
    for seed in (0,1,2):
        for fold in range(3):
            st=f"s{seed}_f{fold}"; sub=splits[st+"_labelled"]; te=splits[st+"_test"]
            bud=strat(sub,frac,np.random.RandomState(100*seed+int(frac*100)+fold)); nb.append(len(bud))
            if y[bud].sum()<MINPOS or (1-y[bud]).sum()<MINPOS: continue
            # inner validation: stratified 30% holdout of the budget -> pick best rep
            rng=np.random.RandomState(7); iv=strat(bud,0.3,rng); it=np.setdiff1d(bud,iv)
            if y[it].sum()<2 or y[iv].sum()<1:  # too small -> default to rawknow
                pick="rawknow"
            else:
                sc_={}
                for m,X in REPS.items():
                    try: sc_[m]=average_precision_score(y[iv],fit(X,it,iv))
                    except: sc_[m]=-1
                pick=max(sc_,key=sc_.get)
            preds["adaptive"][te]=fit(REPS[pick],bud,te)
            preds["raw"][te]=fit(REPS["raw"],bud,te); preds["know"][te]=fit(REPS["know"],bud,te)
    def ap(m): v=preds[m]; return float(average_precision_score(y[~np.isnan(v)],v[~np.isnan(v)]))
    rows[frac]=dict(n=int(np.mean(nb)),raw=ap("raw"),know=ap("know"),adaptive=ap("adaptive"))
    print(json.dumps({str(frac):rows[frac]}),flush=True)
json.dump(rows,open(f"{WS}/ws_pertmodel/adaptive_stim.json","w"),indent=2)
print("\n=== adaptive stim classifier across the label curve (AUPRC) ===",flush=True)
print(f"{'budget':>8} {'raw':>8} {'know':>8} {'adaptive':>9}  best_base  adaptive>=max?",flush=True)
allbest=True
for frac in FRACS:
    r=rows[frac]; mx=max(r["raw"],r["know"]); ok=r["adaptive"]>=mx-0.002; allbest=allbest and ok
    print(f"~{r['n']:>6} {r['raw']:.4f}  {r['know']:.4f}  {r['adaptive']:.4f}   {'raw' if r['raw']>=r['know'] else 'know'}      {'YES' if ok else 'no'}",flush=True)
print(f"\nADAPTIVE IS BEST-OR-TIE ACROSS THE WHOLE CURVE: {allbest}",flush=True)
print("ADAPTIVE_STIM_COMPLETE",flush=True)
