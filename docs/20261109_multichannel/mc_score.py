# system py: score stim AUPRC for 5 reps across label budgets. KEY: does FM learned fusion (fm_multi)
# beat naive concat(RNA,protein)? does protein help at all?
import numpy as np,json,warnings; warnings.filterwarnings("ignore")
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score
WS="/home/yzhang/immune_fm_spark"; OUT=f"{WS}/ws_mc"; AUD=f"{WS}/eval_repair_20261107"
xs=np.load(f"{WS}/ws_bench/xs_stim.npy"); Xp=np.load(f"{OUT}/Xp144.npy")
fm_rna=np.load(f"{OUT}/fm_rna.npy"); fm_multi=np.load(f"{OUT}/fm_multi.npy"); y=np.load(f"{OUT}/y.npy")
REPS={"rna_raw":xs,"prot_raw":Xp,"concat_raw":np.concatenate([xs,Xp],1),"fm_rna":fm_rna,"fm_multi":fm_multi}
splits=np.load(f"{AUD}/normalization_20261108/split_indices.npz"); C=0.01; MINPOS=4
def strat(sub,frac,rng):
    pos=sub[y[sub]==1]; neg=sub[y[sub]==0]
    np_=min(max(MINPOS,int(round(len(pos)*frac))),len(pos)); nn=min(max(MINPOS,int(round(len(neg)*frac))),len(neg))
    return np.concatenate([rng.choice(pos,np_,False),rng.choice(neg,nn,False)])
def fit(X,tr,te):
    s=StandardScaler().fit(X[tr]); a=s.transform(X[tr]); b=s.transform(X[te])
    return LogisticRegression(C=C,max_iter=5000,tol=1e-6,class_weight="balanced",solver="lbfgs").fit(a,y[tr]).predict_proba(b)[:,1]
rows={}
for frac in [1.0,0.25,0.06]:
    rep_ap={m:[] for m in REPS}; nb=[]
    for seed in (0,1,2):
        oof={m:np.full(len(y),np.nan) for m in REPS}
        for fold in range(3):
            st=f"s{seed}_f{fold}"; sub=splits[st+"_labelled"]; te=splits[st+"_test"]
            bud=strat(sub,frac,np.random.RandomState(100*seed+int(frac*100)+fold)); nb.append(len(bud))
            if y[bud].sum()<MINPOS or (1-y[bud]).sum()<MINPOS: continue
            for m,X in REPS.items(): oof[m][te]=fit(X,bud,te)
        for m in REPS:
            v=oof[m]; rep_ap[m].append(average_precision_score(y[~np.isnan(v)],v[~np.isnan(v)]))
    rows[frac]=dict(n=int(np.mean(nb)),**{m:float(np.mean(rep_ap[m])) for m in REPS})
    print(json.dumps({str(frac):rows[frac]}),flush=True)
json.dump(rows,open(f"{OUT}/mc_results.json","w"),indent=2)
print("\n=== multi-channel stim AUPRC (mean/3 seeds) ===",flush=True)
print(f"{'budget':>7} {'rna_raw':>8} {'prot_raw':>8} {'concat':>8} {'fm_rna':>8} {'fm_multi':>8}  | fusion>concat? prot_helps?",flush=True)
for frac in [1.0,0.25,0.06]:
    r=rows[frac]
    fuse=r["fm_multi"]>max(r["concat_raw"],r["fm_rna"]); ph=r["concat_raw"]>r["rna_raw"]
    print(f"~{r['n']:>5} {r['rna_raw']:.4f}  {r['prot_raw']:.4f}  {r['concat_raw']:.4f}  {r['fm_rna']:.4f}  {r['fm_multi']:.4f}   {'YES' if fuse else 'no':>3}         {'yes' if ph else 'no'}",flush=True)
print("MC_SCORE_COMPLETE",flush=True)
